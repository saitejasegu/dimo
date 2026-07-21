import Foundation

/// Currency conversion for foreign-currency expense entry. Mirrors the web port
/// in `app/features/currency/rates.ts`. Rates are ECB daily reference rates
/// stored in Convex and refreshed once per day by the `refreshRates` cron —
/// clients read `exchangeRates:latest` and never call Frankfurter themselves.

enum CurrencyMeta {
  struct Info {
    let symbol: String
    let label: String
    let minorUnitDigits: Int
  }

  /// Metadata for every currency a single expense may be entered in.
  static let all: [String: Info] = [
    "INR": Info(symbol: "₹", label: "INR", minorUnitDigits: 2),
    "USD": Info(symbol: "$", label: "USD", minorUnitDigits: 2),
    "EUR": Info(symbol: "€", label: "EUR", minorUnitDigits: 2),
    "GBP": Info(symbol: "£", label: "GBP", minorUnitDigits: 2),
    "JPY": Info(symbol: "¥", label: "JPY", minorUnitDigits: 0),
    "AUD": Info(symbol: "A$", label: "AUD", minorUnitDigits: 2),
    "CAD": Info(symbol: "C$", label: "CAD", minorUnitDigits: 2),
    "HKD": Info(symbol: "HK$", label: "HKD", minorUnitDigits: 2),
    "SGD": Info(symbol: "S$", label: "SGD", minorUnitDigits: 2),
    "CHF": Info(symbol: "CHF", label: "CHF", minorUnitDigits: 2),
    "CNY": Info(symbol: "¥", label: "CNY", minorUnitDigits: 2),
  ]

  /// Ordered list for pickers; default currencies first.
  static let enterable: [String] = [
    "INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "HKD", "SGD", "CHF", "CNY",
  ]

  static func minorUnitDigits(_ code: String) -> Int {
    all[code]?.minorUnitDigits ?? 2
  }

  static func symbol(_ code: String) -> String {
    all[code]?.symbol ?? code
  }

  static func label(_ code: String) -> String {
    all[code]?.label ?? code
  }
}

/// A snapshot of exchange rates for a single day, quoted against `base`.
struct RateTable: Codable, Equatable, Sendable {
  /// ECB rate date, `YYYY-MM-DD`.
  var date: String
  /// Base currency the raw rates were quoted against.
  var base: String
  /// Units of each currency per 1 unit of `base` (the base itself is implicitly 1).
  var rates: [String: Double]
}

enum ExchangeRates {
  private static func factor(_ currency: String) -> Double {
    pow(10.0, Double(CurrencyMeta.minorUnitDigits(currency)))
  }

  /// Major-unit ratio to convert 1 unit of `from` into `to`, or nil if unknown.
  static func rateBetween(_ from: String, _ to: String, _ rates: RateTable?) -> Double? {
    if from == to { return 1 }
    guard let rates else { return nil }
    let unit: (String) -> Double? = { code in code == rates.base ? 1 : rates.rates[code] }
    guard let fromRate = unit(from), let toRate = unit(to), fromRate > 0, toRate > 0 else {
      return nil
    }
    return toRate / fromRate
  }

  /// Convert an integer minor-unit amount between currencies, honoring each
  /// currency's minor-unit exponent. Returns nil when the rate is unavailable.
  static func convertMinor(_ amountMinor: Int, from: String, to: String, rates: RateTable?) -> Int? {
    guard let ratio = rateBetween(from, to, rates) else { return nil }
    let major = (Double(amountMinor) / factor(from)) * ratio
    return Int((major * factor(to)).rounded())
  }

  /// Convert a major-unit amount (what a user types) into minor units.
  static func toMinorUnits(_ amount: Double, _ currency: String) -> Int {
    Int((amount * factor(currency)).rounded())
  }

  /// Convert an integer minor-unit amount back into major units.
  static func toMajorUnits(_ amountMinor: Int, _ currency: String) -> Double {
    Double(amountMinor) / factor(currency)
  }

  /// Canonical recurring fields. New rows always name their denomination.
  static func recurringFields(_ amount: Double, currency: String) -> (amountMinor: Int, currency: String) {
    (max(1, toMinorUnits(amount, currency)), currency)
  }

  /// A recurring bill's amount in major units of `defaultCurrency` using today's
  /// rates. Default-currency bills (or unavailable rates) return the raw amount.
  static func recurringAmountInDefault(
    _ rec: Recurring,
    defaultCurrency: String,
    rates: RateTable?
  ) -> Double {
    guard let currency = rec.currency, currency != defaultCurrency else { return rec.amount }
    let sourceMinor = rec.amountMinor ?? toMinorUnits(rec.amount, currency)
    guard let converted = convertMinor(sourceMinor, from: currency, to: defaultCurrency, rates: rates)
    else { return rec.amount }
    return toMajorUnits(converted, defaultCurrency)
  }
}

/// Local cache for the Convex `exchangeRates:latest` snapshot.
enum RatesService {
  private static let cacheKey = "dimo.exchangeRates"

  static func loadCached() -> RateTable? {
    guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
    return try? JSONDecoder().decode(RateTable.self, from: data)
  }

  static func store(_ table: RateTable) {
    if let data = try? JSONEncoder().encode(table) {
      UserDefaults.standard.set(data, forKey: cacheKey)
    }
  }
}
