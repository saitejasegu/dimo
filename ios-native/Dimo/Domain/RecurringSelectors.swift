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
    limit: Int,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Recurring] {
    Array(
      activeRecurring(recs)
        .filter { rec in
          guard let anchor = rec.anchorDate, let frequency = rec.frequency else { return false }
          let due = DateHelpers.nextOccurrence(anchorDate: anchor, frequency: frequency, now: now, calendar: calendar)
          return calendar.component(.year, from: due) == calendar.component(.year, from: now)
            && calendar.component(.month, from: due) == calendar.component(.month, from: now)
        }
        .prefix(limit)
    )
  }

  static func recurringSubtitle(_ rec: Recurring) -> String {
    let prefix = rec.category.isEmpty ? "" : "\(rec.category) · "
    return prefix + (rec.paused ? "Paused" : rec.due)
  }
}
