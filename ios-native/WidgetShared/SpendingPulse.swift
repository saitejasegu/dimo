import Foundation

enum PulsePeriod: String, Codable, CaseIterable {
  case day, week
}

/// A disposable projection, never the authoritative database or an outbox.
struct PulseSnapshot: Codable, Equatable {
  struct Expense: Codable, Equatable {
    var date: Date
    var amountMinor: Int
    var categoryID: String
    var categoryName: String
  }
  var updatedAt: Date
  var currency: String
  var minorUnitDigits: Int
  var expenses: [Expense]
  var missingRates: Bool = false
}

struct PulseSummary {
  var totalMinor: Int
  var previousMinor: Int
  var bars: [Int]
  var topCategory: String?
  var period: PulsePeriod

  var comparison: String {
    let reference = period == .day ? "yesterday" : "last week"
    guard previousMinor > 0 else {
      return totalMinor == 0 ? "No spending yet" : "No spending \(reference)"
    }
    let percent = Int((abs(Double(totalMinor) - Double(previousMinor)) / Double(previousMinor) * 100).rounded())
    if percent == 0 { return "Same as \(reference)" }
    return "\(percent)% \(totalMinor < previousMinor ? "less" : "more") than \(reference)"
  }
}

enum PulseSelectors {
  /// Monday-based calendar weeks; comparisons stop at the same local weekday/time.
  static func summarize(_ snapshot: PulseSnapshot, period: PulsePeriod, now: Date, calendar: Calendar = .current) -> PulseSummary {
    var cal = calendar
    cal.firstWeekday = 2
    cal.minimumDaysInFirstWeek = 4
    let dayStart = cal.startOfDay(for: now)
    let start = period == .day ? dayStart : cal.dateInterval(of: .weekOfYear, for: now)!.start
    let days = period == .day ? 1 : 7
    let previousStart = cal.date(byAdding: .day, value: -days, to: start)!
    let previousEnd = cal.date(byAdding: .day, value: -days, to: now)!
    var bars = Array(repeating: 0, count: period == .day ? 8 : 7)
    var categories: [String: (name: String, amount: Int)] = [:]
    var total = 0
    var previous = 0
    for expense in snapshot.expenses where expense.amountMinor > 0 {
      if expense.date >= previousStart && expense.date <= previousEnd && expense.date < start {
        previous += expense.amountMinor
      }
      guard expense.date >= start && expense.date <= now else { continue }
      total += expense.amountMinor
      let index = period == .day
        ? cal.component(.hour, from: expense.date) / 3
        : cal.dateComponents([.day], from: start, to: cal.startOfDay(for: expense.date)).day!
      if bars.indices.contains(index) { bars[index] += expense.amountMinor }
      let old = categories[expense.categoryID]?.amount ?? 0
      categories[expense.categoryID] = (expense.categoryName, old + expense.amountMinor)
    }
    let top = categories.sorted {
      $0.value.amount == $1.value.amount ? $0.key < $1.key : $0.value.amount > $1.value.amount
    }.first?.value.name
    return PulseSummary(totalMinor: total, previousMinor: previous, bars: bars, topCategory: top, period: period)
  }
}
