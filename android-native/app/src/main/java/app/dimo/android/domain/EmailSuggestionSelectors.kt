package app.dimo.android.domain

import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.Transaction
import java.text.Normalizer
import kotlin.math.abs

/**
 * Port of `ios-native/Dimo/Domain/EmailSuggestionSelectors.swift`.
 *
 * Everything here is deterministic and model-independent: refund matching, the
 * partial-refund blocklist, and duplicate detection all have to agree with the
 * repository's atomic checks, so no analyzer output is trusted at this layer.
 */

data class EmailRefundEvidence(
  val merchant: String? = null,
  val amountMinor: Long? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
)

data class EmailRefundRankedMatch(
  val transactionId: String,
  val score: Int,
  val reasons: List<String>,
)

data class EmailRefundMatchResult(
  val candidates: List<EmailRefundRankedMatch>,
  val preselectedTransactionId: String?,
  val isFullRefund: Boolean,
)

data class EmailDuplicateTransactionMatch(
  val transactionId: String,
  val name: String,
  val categoryName: String,
  val paymentMethodLabel: String?,
)

object EmailSuggestionSelectors {
  private const val REFUND_WINDOW_MS = 120L * 24 * 60 * 60 * 1000

  /**
   * Refund removal is intentionally conservative: currency and exact amount are
   * hard gates, and a candidate must predate the refund by no more than 120 days.
   * The score only ranks rows that already pass those gates.
   */
  fun refundMatches(
    evidence: EmailRefundEvidence,
    activeCurrency: Currency,
    transactions: List<Transaction>,
    paymentMethods: List<PaymentMethodOption>,
    isExplicitlyPartial: Boolean = false,
    limit: Int = 3,
  ): EmailRefundMatchResult {
    if (isExplicitlyPartial) {
      return EmailRefundMatchResult(emptyList(), null, isFullRefund = false)
    }
    val amountMinor = evidence.amountMinor
    val refundAt = evidence.occurredAt
    if (evidence.currency != activeCurrency || amountMinor == null || amountMinor <= 0 ||
      refundAt == null
    ) {
      return EmailRefundMatchResult(emptyList(), null, isFullRefund = true)
    }

    val methodsById = paymentMethods.associateBy { it.id }
    val ranked = transactions.mapNotNull { transaction ->
      val transactionAt = transaction.occurredAt ?: return@mapNotNull null
      if (transaction.amountMinor != amountMinor) return@mapNotNull null
      if (transactionAt > refundAt) return@mapNotNull null
      if (refundAt - transactionAt > REFUND_WINDOW_MS) return@mapNotNull null

      // Exact amount is the strongest deterministic signal.
      var score = 50
      val reasons = mutableListOf("Exact amount")

      val merchantSimilarity = stringSimilarity(evidence.merchant, transaction.name)
      if (merchantSimilarity >= 0.85) {
        score += 30
        reasons.add("Merchant match")
      } else if (merchantSimilarity >= 0.55) {
        score += 18
        reasons.add("Similar merchant")
      }

      val expectedLastFour = normalizedLastFour(evidence.paymentLastFour)
      val method = transaction.paymentMethodId?.let { methodsById[it] }
      if (expectedLastFour != null && method != null &&
        paymentMethodContains(expectedLastFour, method)
      ) {
        score += 18
        reasons.add("Payment method match")
      }

      val ageDays = (refundAt - transactionAt).toDouble() / 86_400_000
      if (ageDays <= 7) {
        score += 12
        reasons.add("Within 7 days")
      } else if (ageDays <= 30) {
        score += 8
        reasons.add("Within 30 days")
      } else if (ageDays <= 60) {
        score += 4
      }

      // Transactions do not persist an email reference. A reference can only add
      // weight when the merchant text itself contains it; it never gates a
      // deletion or enters the synced transaction contract.
      val reference = evidence.reference?.trim()
      if (reference != null && reference.length >= 4 &&
        transaction.name.contains(reference, ignoreCase = true)
      ) {
        score += 8
        reasons.add("Reference match")
      }

      EmailRefundRankedMatch(transaction.id, score, reasons)
    }.sortedWith(
      compareByDescending<EmailRefundRankedMatch> { it.score }.thenBy { it.transactionId },
    )

    val candidates = ranked.take(maxOf(0, limit))
    val first = candidates.firstOrNull()
    val runnerUp = candidates.getOrNull(1)
    // Only preselect a clear winner: high absolute score and a real gap to second.
    val preselected = if (first != null && first.score >= 68 &&
      (runnerUp == null || first.score - runnerUp.score >= 12)
    ) {
      first.transactionId
    } else {
      null
    }

    return EmailRefundMatchResult(candidates, preselected, isFullRefund = true)
  }

  /**
   * Conservative, deterministic blocklist for refund language that signals a
   * credit smaller than the original purchase. This same check is repeated inside
   * the atomic repository deletion path.
   */
  fun isExplicitlyPartialRefund(body: String?): Boolean {
    if (body == null) return false
    return PARTIAL_REFUND_PATTERNS.any { it.containsMatchIn(body) }
  }

  /**
   * Same amount on the same local calendar day is the user-facing definition of a
   * duplicate: an email receipt and the matching manual entry rarely agree on the
   * time of day, so only the day is compared. Merchant never gates a match here
   * because the same purchase is often named differently by the sender and the
   * user; it only ranks the candidates.
   *
   * [dayKey] is a [DateHelpers.localDateKey]. Candidates are compared through their
   * timestamp rather than `Transaction.day`, which holds display text like "Today".
   */
  fun duplicateTransactionMatches(
    amountMinor: Long?,
    dayKey: String,
    merchant: String?,
    transactions: List<Transaction>,
    limit: Int = 3,
  ): List<EmailDuplicateTransactionMatch> {
    if (amountMinor == null || amountMinor <= 0 || dayKey.isEmpty()) return emptyList()
    return transactions.mapNotNull { transaction ->
      val occurredAt = transaction.occurredAt ?: return@mapNotNull null
      if (transaction.amountMinor != amountMinor) return@mapNotNull null
      if (DateHelpers.localDateKey(occurredAt) != dayKey) return@mapNotNull null
      EmailDuplicateTransactionMatch(
        transactionId = transaction.id,
        name = transaction.name,
        categoryName = transaction.category,
        paymentMethodLabel = transaction.paymentMethod,
      ) to stringSimilarity(merchant, transaction.name)
    }.sortedWith(
      compareByDescending<Pair<EmailDuplicateTransactionMatch, Double>> { it.second }
        .thenBy { it.first.transactionId },
    ).take(maxOf(0, limit)).map { it.first }
  }

  fun likelyDuplicateDescriptions(
    merchant: String?,
    amountMinor: Long?,
    occurredAt: Long?,
    transactions: List<Transaction>,
    limit: Int = 3,
  ): List<String> {
    if (amountMinor == null || occurredAt == null) return emptyList()
    val dayWindow = 36L * 60 * 60 * 1000
    return transactions.mapNotNull { transaction ->
      val transactionAt = transaction.occurredAt ?: return@mapNotNull null
      if (transaction.amountMinor != amountMinor) return@mapNotNull null
      if (abs(transactionAt - occurredAt) > dayWindow) return@mapNotNull null
      val similarity = stringSimilarity(merchant, transaction.name)
      if (similarity < 0.55) return@mapNotNull null
      "${transaction.name} · ${transaction.day}" to similarity
    }.sortedByDescending { it.second }.take(maxOf(0, limit)).map { it.first }
  }

  fun merchantSimilarity(lhs: String?, rhs: String?): Double = stringSimilarity(lhs, rhs)

  private fun paymentMethodContains(lastFour: String, method: PaymentMethodOption): Boolean {
    val digits = (method.detail + method.name).filter { it.isDigit() }
    return digits.endsWith(lastFour)
  }

  internal fun normalizedLastFour(value: String?): String? {
    val digits = value?.filter { it.isDigit() } ?: return null
    return if (digits.length >= 4) digits.takeLast(4) else null
  }

  private fun stringSimilarity(lhs: String?, rhs: String?): Double {
    if (lhs == null || rhs == null) return 0.0
    val a = normalizedTokens(lhs)
    val b = normalizedTokens(rhs)
    if (a.isEmpty() || b.isEmpty()) return 0.0
    val union = a.union(b).size
    val tokenScore = if (union == 0) 0.0 else a.intersect(b).size.toDouble() / union
    // One name being a strict subset of the other ("Swiggy" vs "Swiggy Instamart")
    // is strong evidence even when the token overlap ratio is low.
    val containment = if (a.containsAll(b) || b.containsAll(a)) 0.85 else 0.0
    return maxOf(tokenScore, containment)
  }

  private fun normalizedTokens(value: String): Set<String> =
    fold(value)
      .split(NON_ALPHANUMERIC)
      .map { it.trim() }
      .filter { it.length >= 2 && it !in IGNORED_MERCHANT_TOKENS }
      .toSet()

  /** Case- and diacritic-insensitive folding, the equivalent of Swift's `folding`. */
  internal fun fold(value: String): String =
    Normalizer.normalize(value, Normalizer.Form.NFD)
      .replace(COMBINING_MARKS, "")
      .lowercase()

  private val NON_ALPHANUMERIC = Regex("[^\\p{Alnum}]+")
  private val COMBINING_MARKS = Regex("\\p{Mn}+")

  private val IGNORED_MERCHANT_TOKENS =
    setOf("the", "payment", "purchase", "pvt", "ltd", "private", "limited")

  private val PARTIAL_REFUND_PATTERNS = listOf(
    Regex("\\bpartial(?:ly)?\\s+(?:refund|refunded|credit|credited)\\b", RegexOption.IGNORE_CASE),
    Regex(
      "\\b(?:refund|credit)(?:ed)?\\s+(?:for\\s+)?(?:part|a portion|some)\\s+of\\b",
      RegexOption.IGNORE_CASE,
    ),
    Regex(
      "\\b(?:refund|credit)(?:ed)?\\s+(?:for\\s+)?(?:one|some)\\s+items?\\b",
      RegexOption.IGNORE_CASE,
    ),
    Regex("\\bpro[ -]?rated\\s+(?:refund|credit)\\b", RegexOption.IGNORE_CASE),
    Regex("\\badjusted\\s+(?:refund|credit)\\b", RegexOption.IGNORE_CASE),
    Regex("\\bremaining\\s+(?:refund|credit|balance)\\b", RegexOption.IGNORE_CASE),
  )
}
