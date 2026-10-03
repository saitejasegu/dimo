import Foundation

/// How an expense divides between the user and other people.
enum SplitMode: String, CaseIterable, Hashable, Sendable {
  case equal
  case exact
  case percent

  var label: String {
    switch self {
    case .equal: return "Equally"
    case .exact: return "By amount"
    case .percent: return "By percent"
    }
  }
}

struct SplitShareInput: Hashable, Sendable {
  var contactId: String
  /// Minor units for `.exact`, a percentage for `.percent`; ignored for `.equal`.
  var value: Double
}

struct SplitShares: Equatable, Sendable {
  struct Share: Equatable, Sendable {
    var contactId: String
    var share: Int
  }

  /// The user's own share, recorded as the expense.
  var mine: Int
  var others: [Share]

  func share(for contactId: String) -> Int? {
    others.first { $0.contactId == contactId }?.share
  }
}

/// Splitting one expense between the user and other people. All amounts are
/// integer minor units of the currency the expense was entered in; the user's
/// share is whatever is left, so shares always add up to the total exactly.
/// Keep aligned with `app/features/transactions/split.ts`.
enum SplitSelectors {
  /// Shares of `totalMinor`, or `nil` when the split doesn't add up (more than
  /// the total, over 100%, or nobody to split with). An equal split gives any
  /// leftover minor units to the user first.
  static func shares(totalMinor: Int, mode: SplitMode, people: [SplitShareInput]) -> SplitShares? {
    guard totalMinor > 0, !people.isEmpty else { return nil }

    if mode == .equal {
      let count = people.count + 1
      let base = totalMinor / count
      let remainder = totalMinor - base * count
      return SplitShares(
        mine: base + (remainder > 0 ? 1 : 0),
        others: people.enumerated().map { index, person in
          SplitShares.Share(contactId: person.contactId, share: base + (index + 1 < remainder ? 1 : 0))
        }
      )
    }

    guard people.allSatisfy({ $0.value.isFinite && $0.value >= 0 }) else { return nil }
    if mode == .percent, people.reduce(0, { $0 + $1.value }) > 100 + 1e-9 { return nil }
    let others = people.map { person in
      // Rounding down leaves any fraction of a minor unit with the user.
      SplitShares.Share(
        contactId: person.contactId,
        share: mode == .exact
          ? Int(person.value.rounded())
          : Int((Double(totalMinor) * person.value / 100 + 1e-9).rounded(.down))
      )
    }
    let mine = totalMinor - others.reduce(0) { $0 + $1.share }
    return mine < 0 ? nil : SplitShares(mine: mine, others: others)
  }
}

/// Splitting one purchase across several categories, e.g. a grocery order that
/// also covers household items. The extra categories get the typed amounts and
/// the main category keeps whatever is left, so the parts always add up to the
/// purchase exactly. All amounts are integer minor units.
enum CategorySplitSelectors {
  /// What's left for the main category, or `nil` when a part isn't positive or
  /// the parts leave nothing for the main category.
  static func remainder(totalMinor: Int, partsMinor: [Int]) -> Int? {
    guard totalMinor > 0, !partsMinor.isEmpty, partsMinor.allSatisfy({ $0 > 0 }) else { return nil }
    let rest = totalMinor - partsMinor.reduce(0, +)
    return rest > 0 ? rest : nil
  }

  /// Keeps a typed part amount to what the expense keypad allows: digits, one
  /// decimal point, at most two decimals and seven whole digits. That keeps the
  /// value exact in minor units and far from `Int` overflow. A comma only
  /// counts as the decimal point where the keyboard's locale uses one.
  static func sanitizedAmount(
    _ text: String,
    decimalSeparator: String = Locale.current.decimalSeparator ?? "."
  ) -> String {
    var whole = ""
    var fraction: String?
    for character in text {
      if character == "." || String(character) == decimalSeparator {
        if fraction == nil { fraction = "" }
      } else if character.isASCII, character.isNumber {
        if fraction == nil {
          if whole.count < 7 { whole.append(character) }
        } else if fraction!.count < 2 {
          fraction!.append(character)
        }
      }
    }
    guard let fraction else { return whole }
    return (whole.isEmpty ? "0" : whole) + "." + fraction
  }
}
