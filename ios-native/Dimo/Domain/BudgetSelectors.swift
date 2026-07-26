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

struct TopCategory: Equatable, Identifiable, Sendable {
  var id: String { category }
  var category: String
  var amount: Double
  var share: Int
  var relative: Int
}

enum BudgetSelectors {
  private static func isCurrentMonth(_ timestamp: Int?, now: Date, calendar: Calendar) -> Bool {
    guard let timestamp else { return false }
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    return calendar.component(.year, from: date) == calendar.component(.year, from: now)
      && calendar.component(.month, from: date) == calendar.component(.month, from: now)
  }

  static func categoryBudgets(
    _ transactions: [Transaction],
    limits: CategoryLimits,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [CategoryBudget] {
    var spentByCategory: [String: Double] = [:]
    for transaction in transactions where isCurrentMonth(transaction.occurredAt, now: now, calendar: calendar) {
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
        over: pct >= 90
      )
    }
    .sorted { $0.spent > $1.spent }
  }

  static func budgetTotals(
    _ transactions: [Transaction],
    limits: CategoryLimits,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> BudgetTotals {
    var totalSpent = 0.0
    var transactionCount = 0
    for transaction in transactions where isCurrentMonth(transaction.occurredAt, now: now, calendar: calendar) {
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
      over: totalLimit > 0 && totalSpent / totalLimit >= 0.9,
      transactionCount: transactionCount
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
    let current = transactions.filter { isCurrentMonth($0.occurredAt, now: now, calendar: calendar) }
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
