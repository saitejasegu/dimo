import Foundation

struct EmailRefundEvidence: Hashable, Sendable {
  var merchant: String?
  var amountMinor: Int?
  var currency: Currency?
  var occurredAt: Int?
  var paymentLastFour: String?
  var reference: String?
}

struct EmailRefundRankedMatch: Hashable, Sendable, Identifiable {
  var transactionId: String
  var score: Int
  var reasons: [String]

  var id: String { transactionId }
}

struct EmailRefundMatchResult: Hashable, Sendable {
  var candidates: [EmailRefundRankedMatch]
  var preselectedTransactionId: String?
  var isFullRefund: Bool
}

struct EmailDuplicateTransactionMatch: Hashable, Sendable, Identifiable {
  var transactionId: String
  var name: String
  var categoryName: String
  var paymentMethodLabel: String?

  var id: String { transactionId }
}

enum EmailSuggestionSelectors {
  private static let refundWindowMilliseconds = 120 * 24 * 60 * 60 * 1_000

  /// Refund removal is intentionally conservative: currency and exact amount
  /// are hard gates, and a candidate must predate the refund by no more than
  /// 120 days. The score only ranks rows that already pass those gates.
  static func refundMatches(
    evidence: EmailRefundEvidence,
    activeCurrency: Currency,
    transactions: [Transaction],
    paymentMethods: [PaymentMethodOption],
    isExplicitlyPartial: Bool = false,
    limit: Int = 3
  ) -> EmailRefundMatchResult {
    guard !isExplicitlyPartial else {
      return EmailRefundMatchResult(candidates: [], preselectedTransactionId: nil, isFullRefund: false)
    }
    guard evidence.currency == activeCurrency,
          let amountMinor = evidence.amountMinor,
          amountMinor > 0,
          let refundAt = evidence.occurredAt else {
      return EmailRefundMatchResult(candidates: [], preselectedTransactionId: nil, isFullRefund: true)
    }

    let methodsById = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })
    let ranked = transactions.compactMap { transaction -> EmailRefundRankedMatch? in
      guard transaction.amountMinor == amountMinor,
            let transactionAt = transaction.occurredAt,
            transactionAt <= refundAt,
            refundAt - transactionAt <= refundWindowMilliseconds else { return nil }

      var score = 50 // Exact amount is the strongest deterministic signal.
      var reasons = ["Exact amount"]

      let merchantSimilarity = stringSimilarity(evidence.merchant, transaction.name)
      if merchantSimilarity >= 0.85 {
        score += 30
        reasons.append("Merchant match")
      } else if merchantSimilarity >= 0.55 {
        score += 18
        reasons.append("Similar merchant")
      }

      if let expectedLastFour = normalizedLastFour(evidence.paymentLastFour),
         let methodId = transaction.paymentMethodId,
         let method = methodsById[methodId],
         paymentMethodContains(lastFour: expectedLastFour, method: method) {
        score += 18
        reasons.append("Payment method match")
      }

      let ageDays = Double(refundAt - transactionAt) / 86_400_000
      if ageDays <= 7 {
        score += 12
        reasons.append("Within 7 days")
      } else if ageDays <= 30 {
        score += 8
        reasons.append("Within 30 days")
      } else if ageDays <= 60 {
        score += 4
      }

      // Transactions do not persist an email reference. A reference can only
      // add weight when the merchant text itself contains it; it never gates a
      // deletion or enters the synced transaction contract.
      if let reference = evidence.reference?.trimmingCharacters(in: .whitespacesAndNewlines),
         reference.count >= 4,
         transaction.name.localizedCaseInsensitiveContains(reference) {
        score += 8
        reasons.append("Reference match")
      }

      return EmailRefundRankedMatch(
        transactionId: transaction.id,
        score: score,
        reasons: reasons
      )
    }
    .sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      return $0.transactionId < $1.transactionId
    }

    let candidates = Array(ranked.prefix(max(0, limit)))
    let preselected: String?
    if let first = candidates.first,
       first.score >= 68,
       candidates.dropFirst().first.map({ first.score - $0.score >= 12 }) ?? true {
      preselected = first.transactionId
    } else {
      preselected = nil
    }

    return EmailRefundMatchResult(
      candidates: candidates,
      preselectedTransactionId: preselected,
      isFullRefund: true
    )
  }

  /// Conservative, deterministic blocklist for refund language that signals
  /// a credit smaller than the original purchase. This same check is repeated
  /// inside the atomic repository deletion path.
  static func isExplicitlyPartialRefund(_ body: String?) -> Bool {
    guard let body else { return false }
    let patterns = [
      #"(?i)\bpartial(?:ly)?\s+(?:refund|refunded|credit|credited)\b"#,
      #"(?i)\b(?:refund|credit)(?:ed)?\s+(?:for\s+)?(?:part|a portion|some)\s+of\b"#,
      #"(?i)\b(?:refund|credit)(?:ed)?\s+(?:for\s+)?(?:one|some)\s+items?\b"#,
      #"(?i)\bpro[ -]?rated\s+(?:refund|credit)\b"#,
      #"(?i)\badjusted\s+(?:refund|credit)\b"#,
      #"(?i)\bremaining\s+(?:refund|credit|balance)\b"#,
    ]
    return patterns.contains {
      body.range(of: $0, options: .regularExpression) != nil
    }
  }

  /// Same amount on the same local calendar day is the user-facing definition
  /// of a duplicate: an email receipt and the matching manual entry rarely
  /// agree on the time of day, so only the day is compared. Merchant never
  /// gates a match here because the same purchase is often named differently
  /// by the sender and the user; it only ranks the candidates.
  ///
  /// `dayKey` is a `DateHelpers.localDateKey`. Candidates are compared through
  /// their timestamp rather than `Transaction.day`, which holds display text
  /// such as "Today".
  static func duplicateTransactionMatches(
    amountMinor: Int?,
    dayKey: String,
    merchant: String?,
    transactions: [Transaction],
    calendar: Calendar = .current,
    limit: Int = 3
  ) -> [EmailDuplicateTransactionMatch] {
    guard let amountMinor, amountMinor > 0, !dayKey.isEmpty else { return [] }
    return transactions.compactMap { transaction -> (EmailDuplicateTransactionMatch, Double)? in
      guard transaction.amountMinor == amountMinor,
            let occurredAt = transaction.occurredAt,
            DateHelpers.localDateKey(
              Date(timeIntervalSince1970: TimeInterval(occurredAt) / 1_000),
              calendar: calendar
            ) == dayKey else { return nil }
      let match = EmailDuplicateTransactionMatch(
        transactionId: transaction.id,
        name: transaction.name,
        categoryName: transaction.category,
        paymentMethodLabel: transaction.paymentMethod
      )
      return (match, stringSimilarity(merchant, transaction.name))
    }
    .sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      return $0.0.transactionId < $1.0.transactionId
    }
    .prefix(max(0, limit))
    .map(\.0)
  }

  static func likelyDuplicateDescriptions(
    merchant: String?,
    amountMinor: Int?,
    occurredAt: Int?,
    transactions: [Transaction],
    limit: Int = 3
  ) -> [String] {
    guard let amountMinor, let occurredAt else { return [] }
    let dayWindow = 36 * 60 * 60 * 1_000
    return transactions.compactMap { transaction -> (String, Double)? in
      guard transaction.amountMinor == amountMinor,
            let transactionAt = transaction.occurredAt,
            abs(transactionAt - occurredAt) <= dayWindow else { return nil }
      let similarity = stringSimilarity(merchant, transaction.name)
      guard similarity >= 0.55 else { return nil }
      let description = "\(transaction.name) · \(transaction.day)"
      return (description, similarity)
    }
    .sorted { $0.1 > $1.1 }
    .prefix(max(0, limit))
    .map(\.0)
  }

  private static func paymentMethodContains(
    lastFour: String,
    method: PaymentMethodOption
  ) -> Bool {
    let digits = (method.detail + method.name).filter(\.isNumber)
    return digits.hasSuffix(lastFour)
  }

  private static func normalizedLastFour(_ value: String?) -> String? {
    guard let value else { return nil }
    let digits = value.filter(\.isNumber)
    guard digits.count >= 4 else { return nil }
    return String(digits.suffix(4))
  }

  private static func stringSimilarity(_ lhs: String?, _ rhs: String?) -> Double {
    guard let lhs, let rhs else { return 0 }
    let a = normalizedTokens(lhs)
    let b = normalizedTokens(rhs)
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    let intersection = a.intersection(b).count
    let union = a.union(b).count
    let tokenScore = union == 0 ? 0 : Double(intersection) / Double(union)
    let containment = a.isSubset(of: b) || b.isSubset(of: a) ? 0.85 : 0
    return max(tokenScore, containment)
  }

  private static func normalizedTokens(_ value: String) -> Set<String> {
    let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    return Set(
      folded
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter {
          $0.count >= 2
            && !["the", "payment", "purchase", "pvt", "ltd", "private", "limited"].contains($0)
        }
    )
  }
}
