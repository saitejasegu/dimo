import Foundation

enum RecurringOccurrenceSelection {
  case all, selected
}

enum DateHelpers {
  static let dayMS = 86_400_000

  static func localDateKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  static func parseLocalDate(_ value: String, calendar: Calendar = .current) -> Date {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return Date() }
    var components = DateComponents()
    components.year = parts[0]
    components.month = parts[1]
    components.day = parts[2]
    return calendar.date(from: components) ?? Date()
  }

  static func formatTransactionDay(_ timestamp: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let today = localDateKey(now, calendar: calendar)
    let key = localDateKey(date, calendar: calendar)
    if key == today { return "Today" }
    guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else {
      return key
    }
    if key == localDateKey(yesterday, calendar: calendar) { return "Yesterday" }

    let formatter = DateFormatter()
    formatter.locale = .current
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEE MMMd" : "EEEE MMMd yyyy")
    return formatter.string(from: date)
  }

  static func formatTransactionTime(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("jmm")
    return formatter.string(from: date)
  }

  static func daysInMonth(year: Int, monthIndex: Int, calendar: Calendar = .current) -> Int {
    var components = DateComponents()
    components.year = year
    components.month = monthIndex + 1
    components.day = 1
    guard let start = calendar.date(from: components),
          let range = calendar.range(of: .day, in: .month, for: start) else { return 30 }
    return range.count
  }

  static func nextOccurrence(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date {
    let anchor = parseLocalDate(anchorDate, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    if anchor >= today { return anchor }

    let anchorDay = calendar.component(.day, from: anchor)
    let anchorMonth = calendar.component(.month, from: anchor) - 1

    if frequency == .monthly {
      let year = calendar.component(.year, from: today)
      let month = calendar.component(.month, from: today) - 1
      func candidate(year: Int, month: Int) -> Date {
        let day = min(anchorDay, daysInMonth(year: year, monthIndex: month, calendar: calendar))
        var c = DateComponents()
        c.year = year
        c.month = month + 1
        c.day = day
        return calendar.date(from: c) ?? today
      }
      var result = candidate(year: year, month: month)
      if result < today {
        var nextMonth = month + 1
        var nextYear = year
        if nextMonth > 11 {
          nextMonth = 0
          nextYear += 1
        }
        result = candidate(year: nextYear, month: nextMonth)
      }
      return result
    }

    func candidate(year: Int) -> Date {
      let day = min(anchorDay, daysInMonth(year: year, monthIndex: anchorMonth, calendar: calendar))
      var c = DateComponents()
      c.year = year
      c.month = anchorMonth + 1
      c.day = day
      return calendar.date(from: c) ?? today
    }
    let year = calendar.component(.year, from: today)
    var result = candidate(year: year)
    if result < today {
      result = candidate(year: year + 1)
    }
    return result
  }

  static func occurrencesThrough(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Date] {
    let anchor = parseLocalDate(anchorDate, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    if anchor > today { return [] }

    let day = calendar.component(.day, from: anchor)
    var dates: [Date] = []

    if frequency == .monthly {
      var year = calendar.component(.year, from: anchor)
      var month = calendar.component(.month, from: anchor) - 1
      while dates.count < 1200 {
        let clamped = min(day, daysInMonth(year: year, monthIndex: month, calendar: calendar))
        var c = DateComponents()
        c.year = year
        c.month = month + 1
        c.day = clamped
        guard let date = calendar.date(from: c) else { break }
        if date > today { break }
        dates.append(date)
        month += 1
        if month > 11 {
          month = 0
          year += 1
        }
      }
      return dates
    }

    var year = calendar.component(.year, from: anchor)
    let month = calendar.component(.month, from: anchor) - 1
    while dates.count < 200 {
      let clamped = min(day, daysInMonth(year: year, monthIndex: month, calendar: calendar))
      var c = DateComponents()
      c.year = year
      c.month = month + 1
      c.day = clamped
      guard let date = calendar.date(from: c) else { break }
      if date > today { break }
      dates.append(date)
      year += 1
    }
    return dates
  }

  static func recurringTransactionDates(
    anchorDate: String,
    frequency: RecurringFrequency,
    selection: RecurringOccurrenceSelection,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [Date] {
    let anchor = parseLocalDate(anchorDate, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    guard anchor <= today else { return [] }
    return selection == .all
      ? occurrencesThrough(anchorDate: anchorDate, frequency: frequency, now: now, calendar: calendar)
      : [anchor]
  }

  static func occurrenceTimestamp(_ date: Date, calendar: Calendar = .current) -> Int {
    var c = calendar.dateComponents([.year, .month, .day], from: date)
    c.hour = 12
    c.minute = 0
    c.second = 0
    let noon = calendar.date(from: c) ?? date
    return Int(noon.timeIntervalSince1970 * 1000)
  }

  static func occurrenceTimestamp(
    _ date: Date,
    time: Date,
    calendar: Calendar = .current
  ) -> Int {
    var dateParts = calendar.dateComponents([.year, .month, .day], from: date)
    let timeParts = calendar.dateComponents([.hour, .minute], from: time)
    dateParts.hour = timeParts.hour
    dateParts.minute = timeParts.minute
    dateParts.second = 0
    let combined = calendar.date(from: dateParts) ?? date
    return Int(combined.timeIntervalSince1970 * 1000)
  }

  static func recurringDueLabel(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String {
    let due = nextOccurrence(anchorDate: anchorDate, frequency: frequency, now: now, calendar: calendar)
    let today = calendar.startOfDay(for: now)
    let days = Int(round(due.timeIntervalSince(today) / 86_400))
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    let date = formatter.string(from: due)
    let relative: String
    if days == 0 {
      relative = "today"
    } else if days == 1 {
      relative = "tomorrow"
    } else {
      relative = "in \(days) days"
    }
    return "Due \(date) · \(relative)"
  }
}
