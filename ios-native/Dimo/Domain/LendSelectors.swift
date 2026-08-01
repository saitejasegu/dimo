import Foundation

/// Which way an unsettled balance runs.
enum LendDirection: Hashable, Sendable {
  /// The contact still owes the user money.
  case owedToMe
  /// The user still owes the contact money.
  case iOwe

  /// The entry kind that settles a balance running this way.
  var settlementKind: LendKind {
    switch self {
    case .owedToMe: return .repaid
    case .iOwe: return .returned
    }
  }
}

struct LendContactSummary: Hashable, Sendable, Identifiable {
  var contactName: String
  /// Address-book identifier of the contact this group belongs to.
  var contactId: String
  /// Signed net balance: positive when the contact owes the user, negative
  /// when the user owes the contact. Only contacts with a non-zero balance
  /// appear in the summary list.
  var total: Double
  var count: Int
  var lastOccurredAt: Int

  var id: String { contactId }

  var direction: LendDirection { total > 0 ? .owedToMe : .iOwe }

  /// Balance without its sign, for display next to a direction label.
  var magnitude: Double { abs(total) }
}

/// Both sides of the ledger, netted per contact so someone the user has both
/// lent to and borrowed from lands on one side only.
struct LendTotals: Equatable, Sendable {
  var owedToMe: Double
  var iOwe: Double

  static let zero = LendTotals(owedToMe: 0, iOwe: 0)

  var net: Double { owedToMe - iOwe }
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
  static let historyPageSize = 50

  /// Both sides of the ledger. Takes already-netted contact summaries rather
  /// than raw entries, so a contact the user has both lent to and borrowed
  /// from is not counted on both sides.
  static func totals(from summaries: [LendContactSummary]) -> LendTotals {
    summaries.reduce(into: LendTotals.zero) { totals, summary in
      switch summary.direction {
      case .owedToMe: totals.owedToMe += summary.total
      case .iOwe: totals.iOwe += summary.magnitude
      }
    }
  }

  /// Signed balance with one contact: positive when they owe the user,
  /// negative when the user owes them. When editing an entry, exclude it so
  /// its current amount remains eligible.
  static func netBalance(
    for contactId: String,
    in lends: [Lend],
    excludingLendId: String? = nil
  ) -> Double {
    lends.reduce(0) { total, lend in
      guard lend.contactId == contactId, lend.id != excludingLendId else { return total }
      return total + lend.signedAmount
    }
  }

  /// Amount that can still be recorded as repaid by a contact.
  static func outstandingAmount(
    for contactId: String,
    in lends: [Lend],
    excludingLendId: String? = nil
  ) -> Double {
    max(0, netBalance(for: contactId, in: lends, excludingLendId: excludingLendId))
  }

  /// Amount the user can still record paying back to a contact they borrowed
  /// from — the mirror image of `outstandingAmount`.
  static func borrowedBalance(
    for contactId: String,
    in lends: [Lend],
    excludingLendId: String? = nil
  ) -> Double {
    max(0, -netBalance(for: contactId, in: lends, excludingLendId: excludingLendId))
  }

  /// How much a settlement of `kind` may be for without overshooting zero.
  /// Entries that open a balance rather than close one are uncapped.
  static func settlementLimit(
    for kind: LendKind,
    contactId: String,
    in lends: [Lend],
    excludingLendId: String? = nil
  ) -> Double? {
    switch kind {
    case .lent, .borrowed:
      return nil
    case .repaid:
      return outstandingAmount(for: contactId, in: lends, excludingLendId: excludingLendId)
    case .returned:
      return borrowedBalance(for: contactId, in: lends, excludingLendId: excludingLendId)
    }
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
  /// casing of the most recent entry, sorted by largest balance in either
  /// direction; contacts whose balance nets to zero are omitted.
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
      .filter { $0.magnitude > 0.0001 }
      .sorted {
        if $0.magnitude != $1.magnitude { return $0.magnitude > $1.magnitude }
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

  /// Newest-first pagination that keeps day groups intact (same rule as Home).
  static func paginateByDay(
    _ lends: [Lend],
    limit: Int
  ) -> (items: [Lend], hasMore: Bool) {
    if limit <= 0 { return ([], !lends.isEmpty) }
    if lends.count <= limit { return (lends, false) }
    var end = limit
    let oldestDay = lends[limit - 1].day
    while end < lends.count && lends[end].day == oldestDay {
      end += 1
    }
    return (Array(lends.prefix(end)), end < lends.count)
  }
}
