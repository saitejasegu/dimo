import Foundation

struct TransactionFilter: Equatable, Sendable {
  var categories: [String] = []
  var paymentMethod: String = "All"
  var query: String = ""
}

struct DayGroup: Equatable, Sendable {
  var label: String
  var total: Double
  var items: [Transaction]
}

struct TransactionsSummary: Equatable, Sendable {
  var total: Double
  var count: Int
  var largest: Double
  var topCategory: String?
}

struct MerchantSuggestion: Equatable, Sendable {
  var name: String
  var category: String
  var paymentMethod: String?
  var count: Int
}

enum TransactionSelectors {
  static let homePageSize = 50

  static func categoryNames(_ limits: CategoryLimits) -> [String] {
    Array(limits.keys)
  }

  static func filterOptions(_ limits: CategoryLimits) -> [String] {
    ["All"] + categoryNames(limits)
  }

  static func paymentMethodFilterOptions(_ transactions: [Transaction]) -> [String] {
    Array(Set(transactions.compactMap(\.paymentMethod))).sorted()
  }

  static func filterTransactions(_ transactions: [Transaction], filter: TransactionFilter) -> [Transaction] {
    let q = filter.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return transactions.filter { t in
      let matchesCategory = filter.categories.isEmpty || filter.categories.contains(t.category)
      let matchesPayment = filter.paymentMethod == "All" || t.paymentMethod == filter.paymentMethod
      let matchesQuery = q.isEmpty
        || t.name.lowercased().contains(q)
        || t.category.lowercased().contains(q)
      return matchesCategory && matchesPayment && matchesQuery
    }
  }

  static func groupByDay(_ transactions: [Transaction]) -> [DayGroup] {
    var order: [String] = []
    var byDay: [String: [Transaction]] = [:]
    for t in transactions {
      if byDay[t.day] == nil {
        byDay[t.day] = []
        order.append(t.day)
      }
      byDay[t.day, default: []].append(t)
    }
    return order.map { day in
      let items = byDay[day] ?? []
      return DayGroup(label: day, total: items.reduce(0) { $0 + $1.amount }, items: items)
    }
  }

  static func paginateTransactionsByDay(
    _ transactions: [Transaction],
    limit: Int
  ) -> (items: [Transaction], hasMore: Bool) {
    if limit <= 0 { return ([], !transactions.isEmpty) }
    if transactions.count <= limit { return (transactions, false) }
    var end = limit
    let oldestDay = transactions[limit - 1].day
    while end < transactions.count && transactions[end].day == oldestDay {
      end += 1
    }
    return (Array(transactions.prefix(end)), end < transactions.count)
  }

  static func summarize(_ transactions: [Transaction]) -> TransactionsSummary {
    var byCategory: [String: Double] = [:]
    var total = 0.0
    var largest = 0.0
    for t in transactions {
      total += t.amount
      largest = max(largest, t.amount)
      byCategory[t.category, default: 0] += t.amount
    }
    let top = byCategory.max(by: { $0.value < $1.value })?.key
    return TransactionsSummary(total: total, count: transactions.count, largest: largest, topCategory: top)
  }

  static func totalSpent(_ transactions: [Transaction]) -> Double {
    transactions.reduce(0) { $0 + $1.amount }
  }

  static func merchantSuggestions(
    _ transactions: [Transaction],
    query: String,
    limit: Int = 6
  ) -> [MerchantSuggestion] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty { return [] }

    struct Acc {
      var name: String
      var category: String
      var paymentMethod: String?
      var count: Int
      var occurredAt: Int
    }
    var byKey: [String: Acc] = [:]
    for t in transactions {
      let name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
      if name.isEmpty { continue }
      let key = name.lowercased()
      guard key.contains(q) else { continue }
      let occurredAt = t.occurredAt ?? 0
      if var existing = byKey[key] {
        existing.count += 1
        if occurredAt >= existing.occurredAt {
          existing.name = name
          existing.category = t.category
          existing.paymentMethod = t.paymentMethod
          existing.occurredAt = occurredAt
        }
        byKey[key] = existing
      } else {
        byKey[key] = Acc(
          name: name, category: t.category, paymentMethod: t.paymentMethod,
          count: 1, occurredAt: occurredAt
        )
      }
    }

    return byKey.values
    .sorted { a, b in
      let aPrefix = a.name.lowercased().hasPrefix(q) ? 1 : 0
      let bPrefix = b.name.lowercased().hasPrefix(q) ? 1 : 0
      if aPrefix != bPrefix { return aPrefix > bPrefix }
      if a.count != b.count { return a.count > b.count }
      return a.occurredAt > b.occurredAt
    }
      .prefix(limit)
      .map { MerchantSuggestion(name: $0.name, category: $0.category, paymentMethod: $0.paymentMethod, count: $0.count) }
  }
}
