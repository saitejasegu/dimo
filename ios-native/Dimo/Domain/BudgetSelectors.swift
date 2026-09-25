import Foundation

struct CategoryBudget: Equatable, Identifiable, Sendable {
  var id: String { category }
  var category: String
  var spent: Double
  var limit: Double?
  var hasLimit: Bool
  var pct: Int
  var over: Bool
}

struct BudgetTotals: Equatable, Sendable {
  var totalSpent: Double
  var totalLimit: Double
  var pct: Int
  var left: Double
  var over: Bool
  /// Transactions in the current local calendar month (same filter as spent).
  var transactionCount: Int
}

struct DailyBudgetAllowance: Equatable, Sendable {
  var amount: Double
  var daysRemaining: Int
}

struct CategoryLookbackSpend: Equatable, Sendable {
  var total: Double
  var monthlyAverage: Double
  var monthCount: Int
}

struct SuggestedCategoryBudgetUpdate: Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var suggestedLimit: Double
  var currentLimit: Double?
}

struct GlobalBudgetCategoryInput: Equatable, Sendable {
  var id: String
  var name: String
  var sortOrder: Int
  var monthlyBudgetMinor: Int?
}

struct GlobalBudgetLookbackWindow: Equatable, Sendable {
  var start: Int
  var end: Int
  var monthCount: Int
}

struct GlobalBudgetCategoryAllocation: Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var sortOrder: Int
  var sixMonthSpend: Double
  var monthlyAverage: Double
  var share: Int
  /// Whole major currency units. Only categories without history receive nil.
  var allocatedLimit: Int?
  var currentLimit: Double?
  var changed: Bool
}

struct GlobalBudgetLimitUpdate: Equatable, Sendable {
  var id: String
  var allocatedLimit: Int?
}

enum GlobalBudgetAllocationIssue: Equatable, Sendable {
  case invalidTotal
  case noCategories
  case noHistory
}

struct GlobalBudgetAllocation: Equatable, Sendable {
  var window: GlobalBudgetLookbackWindow
  var totalBudget: Int
  var totalAllocated: Int
  var sixMonthSpend: Double
  var monthlyAverage: Double
  var allocations: [GlobalBudgetCategoryAllocation]
  var issue: GlobalBudgetAllocationIssue?

  var canApply: Bool { issue == nil }
}

struct TopCategory: Equatable, Identifiable, Sendable {
  var id: String { category }
  var category: String
  var amount: Double
  var share: Int
  var relative: Int
}

enum BudgetSelectors {
  /// Epoch-millisecond bounds of the local calendar month containing `now`, computed
  /// once per selector call. Membership then costs two integer comparisons instead of
  /// four `Calendar.component` lookups per transaction.
  private static func currentMonthBounds(
    now: Date,
    calendar: Calendar
  ) -> (start: Int, end: Int) {
    let parts = calendar.dateComponents([.year, .month], from: now)
    guard let start = calendar.date(from: parts),
          let end = calendar.date(byAdding: .month, value: 1, to: start) else {
      return (Int.min, Int.max)
    }
    return (
      Int(start.timeIntervalSince1970 * 1000),
      Int(end.timeIntervalSince1970 * 1000)
    )
  }

  private static func isInMonth(_ timestamp: Int?, bounds: (start: Int, end: Int)) -> Bool {
    guard let timestamp else { return false }
    return timestamp >= bounds.start && timestamp < bounds.end
  }

  static func categoryBudgets(
    _ transactions: [Transaction],
    limits: CategoryLimits,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [CategoryBudget] {
    let bounds = currentMonthBounds(now: now, calendar: calendar)
    var spentByCategory: [String: Double] = [:]
    for transaction in transactions where isInMonth(transaction.occurredAt, bounds: bounds) {
      spentByCategory[transaction.category, default: 0] += transaction.amount
    }
    return limits.keys.map { category in
      let limit = limits[category] ?? nil
      let hasLimit = (limit ?? 0) > 0
      let spent = spentByCategory[category] ?? 0
      let pct = hasLimit ? Formatting.percent(spent, total: limit ?? 0) : 0
      return CategoryBudget(
        category: category,
        spent: spent,
        limit: limit,
        hasLimit: hasLimit,
        pct: pct,
        over: hasLimit && spent > (limit ?? 0)
      )
    }
    // Highest usage first so near-limit categories surface at the top.
    .sorted {
      if $0.pct != $1.pct { return $0.pct > $1.pct }
      return $0.spent > $1.spent
    }
  }

  static func budgetTotals(
    _ transactions: [Transaction],
    limits: CategoryLimits,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> BudgetTotals {
    let bounds = currentMonthBounds(now: now, calendar: calendar)
    var totalSpent = 0.0
    var transactionCount = 0
    for transaction in transactions where isInMonth(transaction.occurredAt, bounds: bounds) {
      totalSpent += transaction.amount
      transactionCount += 1
    }
    let totalLimit = limits.values.reduce(0.0) { $0 + ($1 ?? 0) }
    let pct = Formatting.percent(totalSpent, total: totalLimit)
    return BudgetTotals(
      totalSpent: totalSpent,
      totalLimit: totalLimit,
      pct: pct,
      left: totalLimit - totalSpent,
      over: totalLimit > 0 && totalSpent > totalLimit,
      transactionCount: transactionCount
    )
  }

  /// Local calendar days left in the month, including today (never below 1).
  static func daysRemainingInMonth(now: Date = Date(), calendar: Calendar = .current) -> Int {
    let day = calendar.component(.day, from: now)
    let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? day
    return max(1, daysInMonth - day + 1)
  }

  /// Average available spend for each remaining local calendar day, including today.
  /// A missing budget or an already-exceeded budget has no useful daily allowance.
  static func dailyBudgetAllowance(
    _ totals: BudgetTotals,
    now: Date = Date(),
    calendar: Calendar = .current,
    upcomingTotal: Double = 0
  ) -> DailyBudgetAllowance? {
    guard totals.totalLimit > 0, totals.left >= 0 else { return nil }
    let daysRemaining = daysRemainingInMonth(now: now, calendar: calendar)
    return DailyBudgetAllowance(
      amount: max(0, totals.left - upcomingTotal) / Double(daysRemaining),
      daysRemaining: daysRemaining
    )
  }

  /// Splits one monthly total using spending from the six completed local calendar
  /// months. Largest-remainder rounding makes the whole-unit allocations sum exactly.
  static func globalBudgetAllocation(
    _ transactions: [Transaction],
    categories: [GlobalBudgetCategoryInput],
    totalBudget: Int,
    monthCount: Int = 6,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> GlobalBudgetAllocation {
    let safeMonthCount = monthCount > 0 ? monthCount : 6
    let currentStart = monthStart(now, calendar: calendar)
    let lookbackStart = calendar.date(
      byAdding: .month,
      value: -safeMonthCount,
      to: currentStart
    ) ?? currentStart
    let window = GlobalBudgetLookbackWindow(
      start: Int(lookbackStart.timeIntervalSince1970 * 1000),
      end: Int(currentStart.timeIntervalSince1970 * 1000),
      monthCount: safeMonthCount
    )

    var spendByCategoryId: [String: Double] = [:]
    for transaction in transactions {
      guard let categoryId = transaction.categoryId,
            let occurredAt = transaction.occurredAt,
            occurredAt >= window.start,
            occurredAt < window.end else { continue }
      spendByCategoryId[categoryId, default: 0] += transaction.amount
    }

    let eligibleSpend = categories.reduce(0.0) {
      $0 + max(0, spendByCategoryId[$1.id] ?? 0)
    }
    let validTotal = totalBudget > 0 && totalBudget <= Int.max / 100
    let issue: GlobalBudgetAllocationIssue? = if categories.isEmpty {
      .noCategories
    } else if eligibleSpend <= 0 {
      .noHistory
    } else if !validTotal {
      .invalidTotal
    } else {
      nil
    }

    struct Draft {
      var category: GlobalBudgetCategoryInput
      var spend: Double
      var raw: Double
      var allocation: Int?
    }

    var drafts = categories.map { category in
      let spend = max(0, spendByCategoryId[category.id] ?? 0)
      let raw = validTotal && eligibleSpend > 0
        ? Double(totalBudget) * spend / eligibleSpend
        : 0
      return Draft(
        category: category,
        spend: spend,
        raw: raw,
        allocation: spend > 0 && validTotal ? Int(floor(raw)) : nil
      )
    }

    if issue == nil {
      let floorTotal = drafts.reduce(0) { $0 + ($1.allocation ?? 0) }
      let remainderOrder = drafts.indices
        .filter { drafts[$0].spend > 0 }
        .sorted { left, right in
          let leftFraction = drafts[left].raw - floor(drafts[left].raw)
          let rightFraction = drafts[right].raw - floor(drafts[right].raw)
          if abs(leftFraction - rightFraction) > Double.ulpOfOne {
            return leftFraction > rightFraction
          }
          let lhs = drafts[left].category
          let rhs = drafts[right].category
          if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
          return lhs.id < rhs.id
        }
      let unitsLeft = totalBudget - floorTotal
      if !remainderOrder.isEmpty, unitsLeft > 0 {
        for position in 0..<unitsLeft {
          let index = remainderOrder[position % remainderOrder.count]
          drafts[index].allocation = (drafts[index].allocation ?? 0) + 1
        }
      }
    }

    let allocations = drafts.map { draft in
      let current = draft.category.monthlyBudgetMinor.map { Double($0) / 100 }
      return GlobalBudgetCategoryAllocation(
        id: draft.category.id,
        name: draft.category.name,
        sortOrder: draft.category.sortOrder,
        sixMonthSpend: draft.spend,
        monthlyAverage: draft.spend / Double(safeMonthCount),
        share: eligibleSpend > 0 ? Formatting.percent(draft.spend, total: eligibleSpend) : 0,
        allocatedLimit: draft.allocation,
        currentLimit: current,
        changed: current != draft.allocation.map(Double.init)
      )
    }

    return GlobalBudgetAllocation(
      window: window,
      totalBudget: totalBudget,
      totalAllocated: allocations.reduce(0) { $0 + ($1.allocatedLimit ?? 0) },
      sixMonthSpend: eligibleSpend,
      monthlyAverage: eligibleSpend / Double(safeMonthCount),
      allocations: allocations,
      issue: issue
    )
  }

  static func categoryLookbackSpend(
    _ transactions: [Transaction],
    categoryId: String,
    monthCount: Int = 6,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> CategoryLookbackSpend {
    let startDate = calendar.date(byAdding: .month, value: -(monthCount - 1), to: monthStart(now, calendar: calendar)) ?? now
    let start = startDate.timeIntervalSince1970 * 1000
    let end = now.timeIntervalSince1970 * 1000
    let total = transactions
      .filter {
        $0.categoryId == categoryId
          && Double($0.occurredAt ?? 0) >= start
          && Double($0.occurredAt ?? 0) <= end
      }
      .reduce(0.0) { $0 + $1.amount }
    return CategoryLookbackSpend(
      total: total,
      monthlyAverage: total / Double(monthCount),
      monthCount: monthCount
    )
  }

  static func suggestedCategoryBudgetUpdates(
    _ transactions: [Transaction],
    categories: [(id: String, name: String, monthlyBudgetMinor: Int?)],
    monthCount: Int = 6,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [SuggestedCategoryBudgetUpdate] {
    let startDate = calendar.date(
      byAdding: .month, value: -(monthCount - 1), to: monthStart(now, calendar: calendar)
    ) ?? now
    let start = startDate.timeIntervalSince1970 * 1000
    let end = now.timeIntervalSince1970 * 1000
    var spendByCategoryId: [String: Double] = [:]
    for transaction in transactions {
      guard let categoryId = transaction.categoryId else { continue }
      let occurred = Double(transaction.occurredAt ?? 0)
      guard occurred >= start, occurred <= end else { continue }
      spendByCategoryId[categoryId, default: 0] += transaction.amount
    }
    return categories.compactMap { category in
      let total = spendByCategoryId[category.id] ?? 0
      if total <= 0 { return nil }
      let suggestedLimit = (total / Double(monthCount)).rounded()
      let currentLimit = category.monthlyBudgetMinor.map { Double($0) / 100 }
      if currentLimit == suggestedLimit { return nil }
      return SuggestedCategoryBudgetUpdate(
        id: category.id,
        name: category.name,
        suggestedLimit: suggestedLimit,
        currentLimit: currentLimit
      )
    }
  }

  static func topCategories(
    _ transactions: [Transaction],
    limit: Int,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [TopCategory] {
    let bounds = currentMonthBounds(now: now, calendar: calendar)
    let current = transactions.filter { isInMonth($0.occurredAt, bounds: bounds) }
    var byCategory: [String: Double] = [:]
    var total = 0.0
    for t in current {
      byCategory[t.category, default: 0] += t.amount
      total += t.amount
    }
    let sorted = byCategory.sorted { $0.value > $1.value }
    let maxAmount = sorted.first?.value ?? 1
    return sorted.prefix(limit).map { category, amount in
      TopCategory(
        category: category,
        amount: amount,
        share: Formatting.percent(amount, total: total),
        relative: max(6, Int((amount / maxAmount * 100).rounded()))
      )
    }
  }

  private static func monthStart(_ date: Date, calendar: Calendar) -> Date {
    let comps = calendar.dateComponents([.year, .month], from: date)
    return calendar.date(from: comps) ?? date
  }
}
