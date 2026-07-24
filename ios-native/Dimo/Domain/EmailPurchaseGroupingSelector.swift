import CryptoKit
import Foundation

struct EmailPurchaseGroupingPair: Hashable, Sendable {
  var groupId: String
  var purchaseMessageId: String
  var debitMessageId: String

  var messageIds: [String] {
    [purchaseMessageId, debitMessageId]
  }
}

enum EmailPurchaseGroupingSelector {
  private static let closeWindow = 15 * 60 * 1_000
  private static let corroboratedWindow = 2 * 60 * 60 * 1_000

  /// Returns a pair only when both messages have exactly one eligible
  /// counterpart. This deliberately leaves ambiguous same-price purchases
  /// separate for the user to review.
  static func reciprocalPendingPair(
    containing messageId: String,
    messages: [EmailMessageRecordModel]
  ) -> EmailPurchaseGroupingPair? {
    let pending = messages.filter {
      $0.state == .pendingPurchase
        && $0.reviewedAt == nil
        && $0.purchaseGroupId == nil
        && ($0.classification == .purchase || $0.classification == .debit)
    }
    guard let message = pending.first(where: { $0.key == messageId }) else { return nil }
    let matches = pending.filter { isEligiblePair(message, $0) }
    guard matches.count == 1, let counterpart = matches.first else { return nil }
    let reverse = pending.filter { isEligiblePair(counterpart, $0) }
    guard reverse.count == 1, reverse.first?.key == message.key else { return nil }
    return pair(message, counterpart)
  }

  /// Finds a unique reviewed source for a late-arriving counterpart. The
  /// caller must still ask the user before linking it to the existing expense.
  static func uniqueReviewedMatch(
    for pending: EmailMessageRecordModel,
    reviewed: [EmailMessageRecordModel]
  ) -> EmailMessageRecordModel? {
    guard pending.state == .pendingPurchase,
          pending.reviewedAt == nil,
          pending.purchaseGroupId == nil else { return nil }
    let matches = reviewed.filter {
      $0.state == .added
        && $0.linkedTransactionId != nil
        && isEligiblePair(pending, $0)
    }
    return matches.count == 1 ? matches[0] : nil
  }

  static func isEligiblePair(
    _ lhs: EmailMessageRecordModel,
    _ rhs: EmailMessageRecordModel
  ) -> Bool {
    guard lhs.key != rhs.key,
          lhs.accountId == rhs.accountId,
          classificationsComplement(lhs.classification, rhs.classification),
          let lhsAmount = decimalAmount(lhs.amount),
          lhsAmount > 0,
          lhsAmount == decimalAmount(rhs.amount),
          let lhsCurrency = lhs.currency,
          lhsCurrency == rhs.currency,
          lhs.purchaseGroupId == nil,
          rhs.purchaseGroupId == nil else { return false }

    let arrivalGap = abs(lhs.internalDate - rhs.internalDate)
    if arrivalGap <= closeWindow { return true }
    guard arrivalGap <= corroboratedWindow else { return false }
    return hasCorroboratingSignal(lhs, rhs)
  }

  static func groupId(_ lhsId: String, _ rhsId: String) -> String {
    let ids = [lhsId, rhsId].sorted()
    let input = ids.map { "\($0.utf8.count):\($0)" }.joined()
    let digest = SHA256.hash(data: Data(input.utf8))
    return "email-purchase-" + digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func pair(
    _ lhs: EmailMessageRecordModel,
    _ rhs: EmailMessageRecordModel
  ) -> EmailPurchaseGroupingPair? {
    let purchase: EmailMessageRecordModel
    let debit: EmailMessageRecordModel
    if lhs.classification == .purchase {
      purchase = lhs
      debit = rhs
    } else {
      purchase = rhs
      debit = lhs
    }
    guard purchase.classification == .purchase, debit.classification == .debit else {
      return nil
    }
    return EmailPurchaseGroupingPair(
      groupId: groupId(purchase.key, debit.key),
      purchaseMessageId: purchase.key,
      debitMessageId: debit.key
    )
  }

  private static func classificationsComplement(
    _ lhs: EmailMessageClassification?,
    _ rhs: EmailMessageClassification?
  ) -> Bool {
    (lhs == .purchase && rhs == .debit) || (lhs == .debit && rhs == .purchase)
  }

  private static func hasCorroboratingSignal(
    _ lhs: EmailMessageRecordModel,
    _ rhs: EmailMessageRecordModel
  ) -> Bool {
    if let left = nonempty(lhs.paymentMethodId),
       let right = nonempty(rhs.paymentMethodId),
       left == right {
      return true
    }
    if let left = normalizedLastFour(lhs.paymentLastFour),
       left == normalizedLastFour(rhs.paymentLastFour) {
      return true
    }
    if let left = normalizedReference(lhs.reference),
       left == normalizedReference(rhs.reference) {
      return true
    }
    return merchantEvidenceSimilarity(lhs, rhs) >= 0.55
  }

  /// Analyzer merchant fields often name different layers of the same
  /// purchase (for example, a restaurant versus the delivery platform).
  /// An exact distinctive token shared by the merchant/sender/subject evidence
  /// is a similarity of 1.0; generic transaction words never corroborate.
  private static func merchantEvidenceSimilarity(
    _ lhs: EmailMessageRecordModel,
    _ rhs: EmailMessageRecordModel
  ) -> Double {
    let canonical = EmailSuggestionSelectors.merchantSimilarity(lhs.merchant, rhs.merchant)
    let sharedTokens = merchantEvidenceTokens(lhs).intersection(merchantEvidenceTokens(rhs))
    return sharedTokens.isEmpty ? canonical : 1
  }

  private static func merchantEvidenceTokens(
    _ message: EmailMessageRecordModel
  ) -> Set<String> {
    let evidence = [message.merchant, message.senderName, message.subject]
      .compactMap { $0 }
      .joined(separator: " ")
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
    let ignored = Set([
      "account", "alert", "amount", "bank", "card", "confirmed", "credit",
      "debit", "email", "from", "made", "order", "paid", "payment", "purchase",
      "receipt", "successfully", "thank", "thanks", "transaction", "using", "your",
    ])
    return Set(
      evidence
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { $0.count >= 5 && !ignored.contains($0) }
    )
  }

  private static func decimalAmount(_ amount: String?) -> Decimal? {
    guard let amount else { return nil }
    return Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
  }

  private static func normalizedLastFour(_ value: String?) -> String? {
    let digits = value?.filter(\.isNumber) ?? ""
    return digits.count >= 4 ? String(digits.suffix(4)) : nil
  }

  private static func normalizedReference(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .filter { $0.isLetter || $0.isNumber }
    return normalized.count >= 6 ? normalized : nil
  }

  private static func nonempty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
  }
}
