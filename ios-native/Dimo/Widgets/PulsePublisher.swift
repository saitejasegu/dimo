import Foundation
import OSLog

enum PulsePublisher {
  /// Serial, so snapshot writes land in order and `clear` on sign-out cannot be
  /// overtaken by a write still in flight for the previous account.
  private static let queue = DispatchQueue(label: "app.dimo.widget-pulse", qos: .utility)

  /// Builds and writes the widget snapshot off the main actor: a full scan, FX
  /// conversion, JSON encode and file write used to run inside every hydrate.
  static func publishInBackground(transactions: [Transaction], currency: String, rates: RateTable?) {
    queue.async {
      publish(transactions: transactions, currency: currency, rates: rates)
    }
  }

  static func activate(owner: String) {
    queue.sync { PulseStorage.activate(owner: owner) }
  }

  static func clear() {
    queue.sync { PulseStorage.clear() }
  }

  static func publish(transactions: [Transaction], currency: String, rates: RateTable?, now: Date = Date()) {
    let snapshot = makeSnapshot(transactions: transactions, currency: currency, rates: rates, now: now)
    do {
      try PulseStorage.write(snapshot)
    } catch {
      Logger(subsystem: "app.dimo.ios", category: "Widgets").error("Unable to publish widget snapshot: \(error.localizedDescription, privacy: .public)")
    }
  }

  static func makeSnapshot(transactions: [Transaction], currency: String, rates: RateTable?, now: Date) -> PulseSnapshot {
    let cutoff = Calendar.current.date(byAdding: .day, value: -21, to: now)!
    var missingRates = false
    let expenses: [PulseSnapshot.Expense] = transactions.compactMap { transaction in
      guard let occurredAt = transaction.occurredAt else { return nil }
      let date = Date(timeIntervalSince1970: Double(occurredAt) / 1000)
      guard date >= cutoff else { return nil }
      let source = transaction.currency ?? currency
      let minor = transaction.amountMinor ?? ExchangeRates.toMinorUnits(transaction.amount, source)
      guard let converted = ExchangeRates.convertMinor(minor, from: source, to: currency, rates: rates) else {
        missingRates = true
        return nil
      }
      return .init(date: date, amountMinor: converted,
                   categoryID: transaction.categoryId ?? transaction.category,
                   categoryName: transaction.category)
    }
    return PulseSnapshot(updatedAt: now, currency: currency,
      minorUnitDigits: CurrencyMeta.minorUnitDigits(currency), expenses: expenses, missingRates: missingRates)
  }
}
