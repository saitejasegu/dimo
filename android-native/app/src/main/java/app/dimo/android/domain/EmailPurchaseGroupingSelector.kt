package app.dimo.android.domain

import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailMessageRecordModel
import app.dimo.android.data.model.EmailSuggestionState
import java.math.BigDecimal
import java.security.MessageDigest
import kotlin.math.abs

/**
 * Port of `ios-native/Dimo/Domain/EmailPurchaseGroupingSelector.swift`.
 *
 * One purchase often produces two emails — a merchant receipt and a bank debit
 * alert. Grouping them prevents double-counting, but a wrong pairing silently
 * hides a real expense, so every rule here is reciprocal and unambiguous: a pair
 * forms only when each side's *only* candidate is the other.
 */
data class EmailPurchaseGroupingPair(
  val groupId: String,
  val purchaseMessageId: String,
  val debitMessageId: String,
) {
  val messageIds: List<String> get() = listOf(purchaseMessageId, debitMessageId)
}

object EmailPurchaseGroupingSelector {
  private const val CLOSE_WINDOW_MS = 15L * 60 * 1000
  private const val CORROBORATED_WINDOW_MS = 2L * 60 * 60 * 1000

  /**
   * Returns a pair only when both messages have exactly one eligible counterpart.
   * This deliberately leaves ambiguous same-price purchases separate for the user
   * to review.
   */
  fun reciprocalPendingPair(
    messageId: String,
    messages: List<EmailMessageRecordModel>,
  ): EmailPurchaseGroupingPair? {
    val pending = messages.filter {
      it.state == EmailSuggestionState.PENDING_PURCHASE &&
        it.reviewedAt == null &&
        it.purchaseGroupId == null &&
        (
          it.classification == EmailMessageClassification.PURCHASE ||
            it.classification == EmailMessageClassification.DEBIT
          )
    }
    val message = pending.firstOrNull { it.key == messageId } ?: return null
    val matches = pending.filter { isEligiblePair(message, it) }
    val counterpart = matches.singleOrNull() ?: return null
    val reverse = pending.filter { isEligiblePair(counterpart, it) }
    if (reverse.singleOrNull()?.key != message.key) return null
    return pair(message, counterpart)
  }

  /**
   * Finds a unique reviewed source for a late-arriving counterpart. The caller
   * must still ask the user before linking it to the existing expense.
   */
  fun uniqueReviewedMatch(
    pending: EmailMessageRecordModel,
    reviewed: List<EmailMessageRecordModel>,
  ): EmailMessageRecordModel? {
    if (pending.state != EmailSuggestionState.PENDING_PURCHASE ||
      pending.reviewedAt != null ||
      pending.purchaseGroupId != null
    ) {
      return null
    }
    return reviewed.filter {
      it.state == EmailSuggestionState.ADDED &&
        it.linkedTransactionId != null &&
        isEligiblePair(pending, it)
    }.singleOrNull()
  }

  fun isEligiblePair(lhs: EmailMessageRecordModel, rhs: EmailMessageRecordModel): Boolean {
    if (lhs.key == rhs.key) return false
    if (lhs.accountId != rhs.accountId) return false
    if (!classificationsComplement(lhs.classification, rhs.classification)) return false
    val lhsAmount = decimalAmount(lhs.amount) ?: return false
    if (lhsAmount.signum() <= 0) return false
    if (lhsAmount.compareTo(decimalAmount(rhs.amount) ?: return false) != 0) return false
    val lhsCurrency = lhs.currency ?: return false
    if (lhsCurrency != rhs.currency) return false
    if (lhs.purchaseGroupId != null || rhs.purchaseGroupId != null) return false

    val arrivalGap = abs(lhs.internalDate - rhs.internalDate)
    if (arrivalGap <= CLOSE_WINDOW_MS) return true
    if (arrivalGap > CORROBORATED_WINDOW_MS) return false
    return hasCorroboratingSignal(lhs, rhs)
  }

  /** Stable, order-independent identifier for the pair. */
  fun groupId(lhsId: String, rhsId: String): String {
    val ids = listOf(lhsId, rhsId).sorted()
    // Length-prefixing keeps the digest injective for ids containing separators.
    val input = ids.joinToString("") { "${it.toByteArray(Charsets.UTF_8).size}:$it" }
    val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
    return "email-purchase-" + digest.joinToString("") { "%02x".format(it) }
  }

  private fun pair(
    lhs: EmailMessageRecordModel,
    rhs: EmailMessageRecordModel,
  ): EmailPurchaseGroupingPair? {
    val purchase: EmailMessageRecordModel
    val debit: EmailMessageRecordModel
    if (lhs.classification == EmailMessageClassification.PURCHASE) {
      purchase = lhs
      debit = rhs
    } else {
      purchase = rhs
      debit = lhs
    }
    if (purchase.classification != EmailMessageClassification.PURCHASE ||
      debit.classification != EmailMessageClassification.DEBIT
    ) {
      return null
    }
    return EmailPurchaseGroupingPair(
      groupId = groupId(purchase.key, debit.key),
      purchaseMessageId = purchase.key,
      debitMessageId = debit.key,
    )
  }

  private fun classificationsComplement(
    lhs: EmailMessageClassification?,
    rhs: EmailMessageClassification?,
  ): Boolean =
    (
      lhs == EmailMessageClassification.PURCHASE && rhs == EmailMessageClassification.DEBIT
      ) ||
      (lhs == EmailMessageClassification.DEBIT && rhs == EmailMessageClassification.PURCHASE)

  private fun hasCorroboratingSignal(
    lhs: EmailMessageRecordModel,
    rhs: EmailMessageRecordModel,
  ): Boolean {
    val leftMethod = nonempty(lhs.paymentMethodId)
    if (leftMethod != null && leftMethod == nonempty(rhs.paymentMethodId)) return true
    val leftLastFour = EmailSuggestionSelectors.normalizedLastFour(lhs.paymentLastFour)
    if (leftLastFour != null &&
      leftLastFour == EmailSuggestionSelectors.normalizedLastFour(rhs.paymentLastFour)
    ) {
      return true
    }
    val leftReference = normalizedReference(lhs.reference)
    if (leftReference != null && leftReference == normalizedReference(rhs.reference)) return true
    return merchantEvidenceSimilarity(lhs, rhs) >= 0.55
  }

  /**
   * Analyzer merchant fields often name different layers of the same purchase (for
   * example, a restaurant versus the delivery platform). An exact distinctive
   * token shared by the merchant/sender/subject evidence is a similarity of 1.0;
   * generic transaction words never corroborate.
   */
  private fun merchantEvidenceSimilarity(
    lhs: EmailMessageRecordModel,
    rhs: EmailMessageRecordModel,
  ): Double {
    val canonical = EmailSuggestionSelectors.merchantSimilarity(lhs.merchant, rhs.merchant)
    val shared = merchantEvidenceTokens(lhs).intersect(merchantEvidenceTokens(rhs))
    return if (shared.isEmpty()) canonical else 1.0
  }

  private fun merchantEvidenceTokens(message: EmailMessageRecordModel): Set<String> {
    val evidence = listOfNotNull(message.merchant, message.senderName, message.subject)
      .joinToString(" ")
    return EmailSuggestionSelectors.fold(evidence)
      .split(NON_ALPHANUMERIC)
      .filter { it.length >= 5 && it !in IGNORED_EVIDENCE_TOKENS }
      .toSet()
  }

  private fun decimalAmount(amount: String?): BigDecimal? =
    amount?.let { runCatching { BigDecimal(it.trim()) }.getOrNull() }

  private fun normalizedReference(value: String?): String? {
    if (value == null) return null
    val normalized = EmailSuggestionSelectors.fold(value).filter { it.isLetterOrDigit() }
    return if (normalized.length >= 6) normalized else null
  }

  private fun nonempty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

  private val NON_ALPHANUMERIC = Regex("[^\\p{Alnum}]+")

  private val IGNORED_EVIDENCE_TOKENS = setOf(
    "account", "alert", "amount", "bank", "card", "confirmed", "credit",
    "debit", "email", "from", "made", "order", "paid", "payment", "purchase",
    "receipt", "successfully", "thank", "thanks", "transaction", "using", "your",
  )
}
