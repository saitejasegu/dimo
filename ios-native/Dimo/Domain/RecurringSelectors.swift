import Foundation

enum RecurringSelectors {
  static func activeRecurring(_ recs: [Recurring]) -> [Recurring] {
    recs.filter { !$0.paused }
  }

  static func monthlyRecurringTotal(_ recs: [Recurring]) -> Double {
    activeRecurring(recs).reduce(0) { sum, r in
      sum + (r.frequency == .yearly ? r.amount / 12 : r.amount)
    }
  }

  private static func withNextDue(
    _ recs: [Recurring],
    now: Date,
    calendar: Calendar,
    includePaused: Bool = false
  ) -> [(Recurring, Date)] {
    (includePaused ? recs : activeRecurring(recs))
      .compactMap { rec -> (Recurring, Date)? in
        guard let anchor = rec.anchorDate, let frequency = rec.frequency else { return nil }
        let due = DateHelpers.nextOccurrence(
          anchorDate: anchor,
          frequency: frequency,
          now: now,
          calendar: calendar
        )
        return (rec, due)
      }
      .sorted { $0.1 < $1.1 }
  }

  static func upcomingBills(
    _ recs: [Recurring],
    limit: Int? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    let dueThisMonth = withNextDue(recs, now: now, calendar: calendar)
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

  /// All bills, including paused bills, sorted by next due date (any month).
  static func allUpcomingBills(
    _ recs: [Recurring],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    withNextDue(recs, now: now, calendar: calendar, includePaused: true).map(\.0)
  }

  static func recurringSubtitle(_ rec: Recurring) -> String {
    let prefix = rec.category.isEmpty ? "" : "\(rec.category) · "
    return prefix + (rec.paused ? "Paused" : rec.due)
  }
}
