import Foundation

enum StatsConstants {
  static let ranges: [StatsRange] = [.oneWeek, .month, .threeMonths, .sixMonths, .oneYear, .twoYears]

  static let rangeLabel: [StatsRange: String] = [
    .oneWeek: "1 week",
    .month: "1 month",
    .threeMonths: "3 months",
    .sixMonths: "6 months",
    .oneYear: "1 year",
    .twoYears: "2 years",
  ]

  static let rangeMonths: [StatsRange: Int] = [
    .month: 1,
    .threeMonths: 3,
    .sixMonths: 6,
    .oneYear: 12,
    .twoYears: 24,
  ]

  static func isDayStatsRange(_ range: StatsRange) -> Bool {
    range == .oneWeek || range == .month
  }

  static func hydratedRange(
    current: StatsRange,
    previousDefault: StatsRange,
    nextDefault: StatsRange,
    dataReady: Bool
  ) -> StatsRange {
    !dataReady || current == previousDefault ? nextDefault : current
  }
}

struct StatsScope: Equatable, Sendable {
  var rangeMonths: Int
  var scopeTotal: Double
  var scopePast: Double
  var spentLabel: String
  var averageLabel: String
  var transactions: [Transaction]
}

struct MonthBar: Equatable, Identifiable, Sendable {
  var id: String { key }
  var key: String
  var label: String
  var amount: Double
  var display: String
  var selected: Bool
  var heightRatio: Double
  var wide: Bool
}

struct MonthBars: Equatable, Sendable {
  var visible: Bool
  var title: String
  var caption: String
  var bars: [MonthBar]
}

struct StatCategory: Equatable, Identifiable, Sendable {
  var id: String { category }
  var category: String
  var amount: Double
  var caption: String
  var relative: Int
  var primary: Bool
}

struct MerchantStat: Equatable, Identifiable, Sendable {
  var id: String { name }
  var name: String
  var count: Int
  var amount: Double
  var green: Bool
  var emoji: String?
  var sub: String
  var relative: Int
}

enum StatsSelectors {
  /// Cached: `DateFormatter` allocation dominates label building, and bars are rebuilt
  /// on every range change and every hydrate. Locked because the hydrator queue and
  /// the UI can both format at once.
  private static let formatterLock = NSLock()

  private static let monthLabelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMM")
    return formatter
  }()

  private static let weekdayLabelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("EEE")
    return formatter
  }()

  private static let monthDayLabelFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()

  private static func monthLabel(for date: Date) -> String {
    formatterLock.lock(); defer { formatterLock.unlock() }
    return monthLabelFormatter.string(from: date)
  }

  private static func weekdayLabel(for date: Date) -> String {
    formatterLock.lock(); defer { formatterLock.unlock() }
    return weekdayLabelFormatter.string(from: date)
  }

  private static func monthDayLabel(for date: Date) -> String {
    formatterLock.lock(); defer { formatterLock.unlock() }
    return monthDayLabelFormatter.string(from: date)
  }

  private static func monthStart(_ date: Date, offset: Int = 0, calendar: Calendar = .current) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    guard let base = calendar.date(from: comps) else { return date }
    return calendar.date(byAdding: .month, value: offset, to: base) ?? base
  }

  private static func startOfLocalDay(_ date: Date, calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: date)
  }

  static func rangeStart(_ range: StatsRange, now: Date = Date(), calendar: Calendar = .current) -> Date {
    if range == .oneWeek {
      return startOfLocalDay(calendar.date(byAdding: .day, value: -6, to: now) ?? now, calendar: calendar)
    }
    let months = StatsConstants.rangeMonths[range] ?? 1
    return monthStart(now, offset: -(months - 1), calendar: calendar)
  }

  private static func inRange(
    _ transactions: [Transaction],
    range: StatsRange,
    now: Date,
    calendar: Calendar
  ) -> [Transaction] {
    let start = rangeStart(range, now: now, calendar: calendar).timeIntervalSince1970 * 1000
    let end = now.timeIntervalSince1970 * 1000
    return transactions.filter { t in
      let at = Double(t.occurredAt ?? 0)
      return at >= start && at <= end
    }
  }

  static func statsScope(
    range: StatsRange,
    transactions: [Transaction],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> StatsScope {
    let scoped = inRange(transactions, range: range, now: now, calendar: calendar)
    let scopeTotal = scoped.reduce(0.0) { $0 + $1.amount }
    let oldestTimestamp = scoped.compactMap(\.occurredAt).min()
    let days: Int
    if let oldestTimestamp {
      let oldestDate = Date(timeIntervalSince1970: TimeInterval(oldestTimestamp) / 1000)
      let oldestDay = startOfLocalDay(oldestDate, calendar: calendar)
      let today = startOfLocalDay(now, calendar: calendar)
      days = max(1, (calendar.dateComponents([.day], from: oldestDay, to: today).day ?? 0) + 1)
    } else {
      days = 1
    }
    let spentLabel: String
    switch range {
    case .oneWeek: spentLabel = "Spent this week"
    case .month: spentLabel = "Spent this month"
    default:
      let months = StatsConstants.rangeMonths[range] ?? 1
      spentLabel = "Spent in the last \(months) months"
    }
    return StatsScope(
      rangeMonths: range == .oneWeek ? 0 : (StatsConstants.rangeMonths[range] ?? 0),
      scopeTotal: scopeTotal,
      scopePast: 0,
      spentLabel: spentLabel,
      averageLabel: "\(Formatting.money(scopeTotal / Double(days))) avg per day",
      transactions: scoped
    )
  }

  private static func buildBars(
    title: String,
    entries: [(key: String, label: String, captionLabel: String, amount: Double)],
    selectedKey: String?,
    wide: Bool
  ) -> MonthBars {
    guard !entries.isEmpty else {
      return MonthBars(visible: false, title: title, caption: "", bars: [])
    }
    let resolvedKey = entries.first(where: { $0.key == selectedKey })?.key ?? entries.last!.key
    let selected = entries.first(where: { $0.key == resolvedKey })!
    let maxAmount = max(1, entries.map(\.amount).max() ?? 1)
    return MonthBars(
      visible: true,
      title: title,
      caption: "\(selected.captionLabel): \(Formatting.money(selected.amount))",
      bars: entries.map { entry in
        MonthBar(
          key: entry.key,
          label: entry.label,
          amount: entry.amount,
          display: (!wide || entry.key == resolvedKey) ? Formatting.compactMoney(entry.amount) : "",
          selected: entry.key == resolvedKey,
          heightRatio: entry.amount / maxAmount,
          wide: wide
        )
      }
    )
  }

  static func dayBars(
    range: StatsRange,
    transactions: [Transaction],
    selectedDay: String?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> MonthBars {
    guard StatsConstants.isDayStatsRange(range) else {
      return MonthBars(visible: false, title: "By day", caption: "", bars: [])
    }
    let start = rangeStart(range, now: now, calendar: calendar)
    let end = startOfLocalDay(now, calendar: calendar)
    var amounts: [String: Double] = [:]
    for t in transactions {
      let key = DateHelpers.localDateKey(
        Date(timeIntervalSince1970: TimeInterval(t.occurredAt ?? 0) / 1000),
        calendar: calendar
      )
      amounts[key, default: 0] += t.amount
    }
    var entries: [(key: String, label: String, captionLabel: String, amount: Double)] = []
    var cursor = start
    while cursor.timeIntervalSince1970 <= end.timeIntervalSince1970 {
      let key = DateHelpers.localDateKey(cursor, calendar: calendar)
      let label = range == .oneWeek
        ? Self.weekdayLabel(for: cursor)
        : "\(calendar.component(.day, from: cursor))"
      entries.append((key, label, Self.monthDayLabel(for: cursor), amounts[key] ?? 0))
      cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(86_400)
    }
    return buildBars(title: "By day", entries: entries, selectedKey: selectedDay, wide: entries.count > 7)
  }

  static func monthBars(
    range: StatsRange,
    transactions: [Transaction],
    selectedMonth: String?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> MonthBars {
    guard !StatsConstants.isDayStatsRange(range) else {
      return MonthBars(visible: false, title: "By month", caption: "", bars: [])
    }
    let count = StatsConstants.rangeMonths[range] ?? 1
    // Single grouping pass. Filtering the whole list once per month made this
    // O(months × transactions) with two Calendar component lookups per transaction per
    // month — hundreds of thousands of Calendar calls on a two-year range.
    var amounts: [String: Double] = [:]
    for transaction in transactions {
      let date = Date(timeIntervalSince1970: TimeInterval(transaction.occurredAt ?? 0) / 1000)
      let parts = calendar.dateComponents([.year, .month], from: date)
      amounts[monthKey(parts), default: 0] += transaction.amount
    }
    let entries = (0..<count).map { index -> (key: String, label: String, captionLabel: String, amount: Double) in
      let date = monthStart(now, offset: index - count + 1, calendar: calendar)
      let key = monthKey(calendar.dateComponents([.year, .month], from: date))
      let label = Self.monthLabel(for: date)
      return (key, label, label, amounts[key] ?? 0)
    }
    return buildBars(title: "By month", entries: entries, selectedKey: selectedMonth, wide: count > 6)
  }

  private static func monthKey(_ parts: DateComponents) -> String {
    "\(parts.year ?? 0)-\((parts.month ?? 1) - 1)"
  }

  static func trendBars(
    range: StatsRange,
    transactions: [Transaction],
    selectedKey: String?,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> MonthBars {
    StatsConstants.isDayStatsRange(range)
      ? dayBars(range: range, transactions: transactions, selectedDay: selectedKey, now: now, calendar: calendar)
      : monthBars(range: range, transactions: transactions, selectedMonth: selectedKey, now: now, calendar: calendar)
  }

  static func statCategories(scope: StatsScope, limit: Int) -> (categories: [StatCategory], total: Int) {
    var totals: [String: Double] = [:]
    for t in scope.transactions {
      totals[t.category, default: 0] += t.amount
    }
    let entries = totals.sorted { $0.value > $1.value }
    let maxAmount = entries.first?.value ?? 1
    let sliced = limit == Int.max ? entries : Array(entries.prefix(limit))
    return (
      sliced.enumerated().map { index, pair in
        StatCategory(
          category: pair.key,
          amount: pair.value,
          caption: "\(Formatting.money(pair.value)) · \(Formatting.percent(pair.value, total: scope.scopeTotal))%",
          relative: max(4, Int((pair.value / maxAmount * 100).rounded())),
          primary: index == 0
        )
      },
      entries.count
    )
  }

  static func topMerchants(scope: StatsScope, limit: Int) -> (merchants: [MerchantStat], total: Int) {
    struct Acc {
      var amount: Double
      var count: Int
      var green: Bool
      var category: String
      var categoryEmoji: String?
      var mixedCategories: Bool
    }
    var totals: [String: Acc] = [:]
    for t in scope.transactions {
      var current = totals[t.name] ?? Acc(
        amount: 0, count: 0, green: false, category: t.category,
        categoryEmoji: t.emoji, mixedCategories: false
      )
      current.amount += t.amount
      current.count += 1
      current.green = current.green || (t.green ?? false)
      current.mixedCategories = current.mixedCategories || current.category != t.category
      if current.categoryEmoji == nil { current.categoryEmoji = t.emoji }
      totals[t.name] = current
    }
    let sorted = totals.sorted { $0.value.amount > $1.value.amount }
    let maxAmount = sorted.first?.value.amount ?? 1
    let sliced = limit == Int.max ? sorted : Array(sorted.prefix(limit))
    return (
      sliced.map { name, value in
        MerchantStat(
          name: name,
          count: value.count,
          amount: value.amount,
          green: value.green,
          emoji: value.mixedCategories ? nil : value.categoryEmoji,
          sub: "\(value.count) \(value.count == 1 ? "transaction" : "transactions") · \(Formatting.percent(value.amount, total: scope.scopeTotal))%",
          relative: max(6, Int((value.amount / maxAmount * 100).rounded()))
        )
      },
      sorted.count
    )
  }
}
