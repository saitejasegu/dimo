import Foundation

enum RecurringSelectors {
  static func activeRecurring(_ recs: [Recurring]) -> [Recurring] {
    recs.filter { !$0.paused }
  }

  /// Sum active bills in a single currency. Foreign-currency callers provide
  /// `amountOf` to convert each bill before it is added to the total.
  static func monthlyRecurringTotal(
    _ recs: [Recurring],
    amountOf: (Recurring) -> Double = { $0.amount }
  ) -> Double {
    activeRecurring(recs).reduce(0) { sum, r in
      let amount = amountOf(r)
      return sum + (r.frequency == .yearly ? amount / 12 : amount)
    }
  }

  /// The bill's next due date that hasn't already been charged. The backend cron
  /// materializes each occurrence as a transaction keyed `recurring:<id>:<dateKey>`
  /// on its due day, so an occurrence whose transaction already exists is skipped —
  /// otherwise a bill charged today would linger in "upcoming" until day's end.
  private static func nextDueUnrecorded(
    _ rec: Recurring,
    anchor: String,
    frequency: RecurringFrequency,
    recordedIDs: Set<String>,
    now: Date,
    calendar: Calendar
  ) -> Date {
    var due = DateHelpers.nextOccurrence(
      anchorDate: anchor, frequency: frequency, now: now, calendar: calendar
    )
    for _ in 0..<24 {
      let key = DateHelpers.localDateKey(due, calendar: calendar)
      if !recordedIDs.contains("recurring:\(rec.id):\(key)") { break }
      // Advance past the recorded occurrence to the following one.
      let dayAfter = calendar.date(byAdding: .day, value: 1, to: due) ?? due
      due = DateHelpers.nextOccurrence(
        anchorDate: anchor, frequency: frequency, now: dayAfter, calendar: calendar
      )
    }
    return due
  }

  private static func withNextDue(
    _ recs: [Recurring],
    transactions: [Transaction],
    now: Date,
    calendar: Calendar,
    includePaused: Bool = false
  ) -> [(Recurring, Date)] {
    let recordedIDs = Set(transactions.map(\.id))
    return (includePaused ? recs : activeRecurring(recs))
      .compactMap { rec -> (Recurring, Date)? in
        guard let anchor = rec.anchorDate, let frequency = rec.frequency else { return nil }
        let due = nextDueUnrecorded(
          rec,
          anchor: anchor,
          frequency: frequency,
          recordedIDs: recordedIDs,
          now: now,
          calendar: calendar
        )
        return (rec, due)
      }
      .sorted { $0.1 < $1.1 }
  }

  static func upcomingBills(
    _ recs: [Recurring],
    transactions: [Transaction],
    limit: Int? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    let dueThisMonth = withNextDue(recs, transactions: transactions, now: now, calendar: calendar)
      .filter { pair in
        let due = pair.1
        let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
        let sameMonth = calendar.component(.month, from: due) == calendar.component(.month, from: now)
        return sameYear && sameMonth
      }
      .map(\.0)

    guard let limit else { return dueThisMonth }
    return Array(dueThisMonth.prefix(limit))
  }

  /// All bills, including paused bills, sorted by next unpaid due date (any month).
  static func allUpcomingBills(
    _ recs: [Recurring],
    transactions: [Transaction],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    withNextDue(recs, transactions: transactions, now: now, calendar: calendar, includePaused: true).map(\.0)
  }

  static func recurringSubtitle(_ rec: Recurring) -> String {
    let prefix = rec.category.isEmpty ? "" : "\(rec.category) · "
    return prefix + (rec.paused ? "Paused" : rec.due)
  }
}
