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

  static func upcomingBills(
    _ recs: [Recurring],
    limit: Int? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    let dueThisMonth = activeRecurring(recs)
      .compactMap { rec -> (Recurring, Date)? in
        guard let anchor = rec.anchorDate, let frequency = rec.frequency else { return nil }
        let due = DateHelpers.nextOccurrence(
          anchorDate: anchor,
          frequency: frequency,
          now: now,
          calendar: calendar
        )
        let sameYear = calendar.component(.year, from: due) == calendar.component(.year, from: now)
        let sameMonth = calendar.component(.month, from: due) == calendar.component(.month, from: now)
        guard sameYear && sameMonth else { return nil }
        return (rec, due)
      }
      .sorted { $0.1 < $1.1 }

    let upcoming = dueThisMonth.map(\.0)
    guard let limit else { return upcoming }
    return Array(upcoming.prefix(limit))
  }

  static func recurringSubtitle(_ rec: Recurring) -> String {
    let prefix = rec.category.isEmpty ? "" : "\(rec.category) · "
    return prefix + (rec.paused ? "Paused" : rec.due)
  }
}
