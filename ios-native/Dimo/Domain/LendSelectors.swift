import Foundation

struct LendContactSummary: Hashable, Sendable, Identifiable {
  var contactName: String
  /// Net outstanding (lent minus repaid). Only contacts with a positive balance
  /// appear in the summary list.
  var total: Double
  var count: Int
  var lastOccurredAt: Int

  var id: String { contactName }
}

struct LendDayGroup: Equatable, Sendable {
  var label: String
  var total: Double
  var items: [Lend]
}

enum LendSelectors {
  /// Net amount still out: money lent minus money got back.
  static func totalLent(_ lends: [Lend]) -> Double {
    lends.reduce(0) { $0 + $1.signedAmount }
  }

  /// Groups lends by contact (case-insensitive), keeping the casing of the most
  /// recent entry, sorted by highest outstanding total. Settled contacts
  /// (zero or negative outstanding) are omitted.
  static func contactSummaries(_ lends: [Lend]) -> [LendContactSummary] {
    var byContact: [String: LendContactSummary] = [:]
    for lend in lends.sorted(by: { $0.occurredAt > $1.occurredAt }) {
      let key = lend.contactName.lowercased()
      if var existing = byContact[key] {
        existing.total += lend.signedAmount
        existing.count += 1
        existing.lastOccurredAt = max(existing.lastOccurredAt, lend.occurredAt)
        byContact[key] = existing
      } else {
        byContact[key] = LendContactSummary(
          contactName: lend.contactName,
          total: lend.signedAmount,
          count: 1,
          lastOccurredAt: lend.occurredAt
        )
      }
    }
    return byContact.values
      .filter { $0.total > 0.0001 }
      .sorted {
        if $0.total != $1.total { return $0.total > $1.total }
        return $0.contactName < $1.contactName
      }
  }

  /// Groups lends by their day label, preserving newest-first order.
  static func groupByDay(_ lends: [Lend]) -> [LendDayGroup] {
    var order: [String] = []
    var byDay: [String: [Lend]] = [:]
    for lend in lends {
      if byDay[lend.day] == nil {
        byDay[lend.day] = []
        order.append(lend.day)
      }
      byDay[lend.day, default: []].append(lend)
    }
    return order.map { day in
      let items = byDay[day] ?? []
      return LendDayGroup(
        label: day,
        total: items.reduce(0) { $0 + $1.signedAmount },
        items: items
      )
    }
  }
}
