import Foundation

struct LendContactSummary: Hashable, Sendable, Identifiable {
  var contactName: String
  /// Address-book identifier of the contact this group belongs to.
  var contactId: String
  /// Net outstanding (lent minus repaid). Only contacts with a positive balance
  /// appear in the summary list.
  var total: Double
  var count: Int
  var lastOccurredAt: Int

  var id: String { contactId }
}

struct LendDayGroup: Equatable, Sendable {
  var label: String
  var total: Double
  var items: [Lend]
}

struct LendContactSuggestion: Hashable, Sendable, Identifiable {
  var contactName: String
  var contactId: String

  var id: String { contactId }
}

enum LendSelectors {
  /// Net amount still out: money lent minus money got back.
  static func totalLent(_ lends: [Lend]) -> Double {
    lends.reduce(0) { $0 + $1.signedAmount }
  }

  /// Amount that can still be recorded as repaid for a contact. When editing a
  /// repayment, exclude it so its current amount remains eligible.
  static func outstandingAmount(
    for contactId: String,
    in lends: [Lend],
    excludingLendId: String? = nil
  ) -> Double {
    max(0, lends.reduce(0) { total, lend in
      guard lend.contactId == contactId, lend.id != excludingLendId else { return total }
      return total + lend.signedAmount
    })
  }

  /// Chronological transactions in the contact's current unsettled cycle.
  /// Entries before the most recent zero balance belong to an earlier,
  /// completed settlement and are omitted.
  static func unsettledTransactions(for contactId: String, in lends: [Lend]) -> [Lend] {
    let contactLends = lends
      .filter { $0.contactId == contactId }
      .sorted {
        if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
        return $0.id < $1.id
      }

    var balance = 0.0
    var unsettledStartIndex = 0
    for (index, lend) in contactLends.enumerated() {
      balance += lend.signedAmount
      if abs(balance) < 0.0001 {
        unsettledStartIndex = index + 1
      }
    }
    return Array(contactLends.dropFirst(unsettledStartIndex))
  }

  /// Groups lends per person by address-book identifier, keeping the name
  /// casing of the most recent entry, sorted by highest outstanding total;
  /// settled contacts are omitted.
  static func contactSummaries(_ lends: [Lend]) -> [LendContactSummary] {
    var byContact: [String: LendContactSummary] = [:]
    for lend in lends.sorted(by: { $0.occurredAt > $1.occurredAt }) {
      if var existing = byContact[lend.contactId] {
        existing.total += lend.signedAmount
        existing.count += 1
        existing.lastOccurredAt = max(existing.lastOccurredAt, lend.occurredAt)
        byContact[lend.contactId] = existing
      } else {
        byContact[lend.contactId] = LendContactSummary(
          contactName: lend.contactName,
          contactId: lend.contactId,
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

  /// Most recently used contacts across lend history, deduped per person,
  /// for the suggestion chips on the add-lend sheet.
  static func recentContacts(_ lends: [Lend], limit: Int = 6) -> [LendContactSuggestion] {
    var seen: Set<String> = []
    var result: [LendContactSuggestion] = []
    for lend in lends.sorted(by: { $0.occurredAt > $1.occurredAt }) {
      guard seen.insert(lend.contactId).inserted else { continue }
      result.append(LendContactSuggestion(contactName: lend.contactName, contactId: lend.contactId))
      if result.count == limit { break }
    }
    return result
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
