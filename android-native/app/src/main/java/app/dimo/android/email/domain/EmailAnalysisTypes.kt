package app.dimo.android.email.domain

import app.dimo.android.data.model.Currency
import java.math.BigDecimal

/** Port of `ios-native/Dimo/Email/Domain/EmailAnalysisTypes.swift`. */

enum class EmailAnalysisKind(val wire: String) {
  PURCHASE("purchase"),
  DEBIT("debit"),
  REFUND("refund"),
  IRRELEVANT("irrelevant");

  companion object {
    fun fromWire(value: String?): EmailAnalysisKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class EmailAnalyzerType(val wire: String) {
  GEMMA("gemma"),
  OPEN_ROUTER("openRouter"),
}

enum class EmailAnalysisConfidence(val wire: String) {
  HIGH("high"),
  MEDIUM("medium"),
  LOW("low");

  companion object {
    fun fromWire(value: String?): EmailAnalysisConfidence? =
      entries.firstOrNull { it.wire == value }
  }
}

data class EmailCategoryOption(val id: String, val name: String)

data class EmailPaymentMethodHint(
  val id: String,
  val label: String,
  val lastFour: String? = null,
  val archived: Boolean = false,
)

data class EmailMerchantCategoryHint(val merchant: String, val categoryId: String)

data class EmailAnalysisRequest(
  val messageId: String,
  val accountSubject: String,
  val senderName: String? = null,
  val senderAddress: String,
  val subject: String,
  val receivedAt: Long,
  val normalizedBody: String,
  val categories: List<EmailCategoryOption>,
  val paymentMethods: List<EmailPaymentMethodHint>,
  val merchantHistory: List<EmailMerchantCategoryHint>,
  val activeCurrency: Currency,
)

data class EmailAnalysisResult(
  val kind: EmailAnalysisKind,
  val merchant: String? = null,
  val amount: BigDecimal? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
  val analyzer: EmailAnalyzerType,
  val confidence: EmailAnalysisConfidence,
) {
  companion object {
    const val SCHEMA_VERSION = 1

    fun irrelevant(analyzer: EmailAnalyzerType) = EmailAnalysisResult(
      kind = EmailAnalysisKind.IRRELEVANT,
      analyzer = analyzer,
      confidence = EmailAnalysisConfidence.HIGH,
    )
  }
}

data class EmailAnalysisEnvelope(
  val result: EmailAnalysisResult,
  val analyzer: EmailAnalyzerType,
  val modelId: String,
  val requestId: String? = null,
)

interface EmailAnalysisProviding {
  suspend fun analyze(request: EmailAnalysisRequest): EmailAnalysisEnvelope
}

/**
 * Amounts and identifiers the deterministic scan found in the raw email. The
 * validator uses these to reject model output that is not present in the source.
 */
data class EmailDeterministicEvidence(
  val amounts: List<Amount>,
  val paymentLastFour: String? = null,
  val reference: String? = null,
) {
  data class Amount(val value: BigDecimal, val currency: Currency, val source: String)
}

class EmailStructuredOutputException(message: String) :
  Exception("Invalid analysis output: $message")
