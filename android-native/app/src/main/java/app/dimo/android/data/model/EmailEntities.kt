package app.dimo.android.data.model

import java.util.Calendar

/**
 * Port of `ios-native/Dimo/Data/EmailLocalModels.swift`.
 *
 * Device-local Gmail metadata and the analysis pipeline's persisted shape. OAuth
 * tokens are deliberately absent from every model here: refresh tokens live in
 * EncryptedSharedPreferences and access tokens stay in memory.
 */

enum class EmailAccountSyncState(val wire: String) {
  IDLE("idle"),
  BACKFILLING("backfilling"),
  SYNCING("syncing"),
  RATE_LIMITED("rateLimited"),
  OFFLINE("offline"),
  FAILED("failed"),

  /** Refresh token is invalid; local mail is kept until the user reconnects Gmail. */
  NEEDS_RECONNECT("needsReconnect"),

  /** Stub row kept after disconnect or restored from Convex without OAuth credentials. */
  DISCONNECTED("disconnected");

  companion object {
    fun fromWire(value: String?): EmailAccountSyncState? = entries.firstOrNull { it.wire == value }
  }
}

enum class EmailAnalyzerKind(val wire: String) {
  GEMMA("gemma"),
  OPEN_ROUTER("openRouter"),

  /** Backwards decoding only. New analyses never use the rules analyzer. */
  RULES("rules");

  companion object {
    fun fromWire(value: String?): EmailAnalyzerKind? = entries.firstOrNull { it.wire == value }
  }
}

enum class EmailAnalysisProvider(val wire: String) {
  OPEN_ROUTER("openRouter");

  companion object {
    fun fromWire(value: String?): EmailAnalysisProvider? = entries.firstOrNull { it.wire == value }
  }
}

enum class OpenRouterAccessMode(val wire: String) {
  /** Shared OpenRouter key via authenticated Convex actions; free models only. */
  FREE_SHARED("freeShared"),

  /** User-supplied OpenRouter key stored in EncryptedSharedPreferences. */
  BRING_YOUR_OWN_KEY("bringYourOwnKey");

  companion object {
    fun fromWire(value: String?): OpenRouterAccessMode? = entries.firstOrNull { it.wire == value }
  }
}

enum class OpenRouterPrivacyMode(val wire: String) {
  ZDR_ONLY("zdrOnly"),
  ALLOW_NON_ZDR("allowNonZDR");

  companion object {
    fun fromWire(value: String?): OpenRouterPrivacyMode? = entries.firstOrNull { it.wire == value }
  }
}

enum class EmailSyncWindow(val wire: String, val title: String) {
  ONE_DAY("oneDay", "1 day"),
  ONE_WEEK("oneWeek", "1 week"),
  ONE_MONTH("oneMonth", "1 month"),
  THREE_MONTHS("threeMonths", "3 months");

  /** Oldest epoch-millis instant still inside this window, measured back from [now]. */
  fun cutoff(now: Long): Long {
    val calendar = Calendar.getInstance()
    calendar.timeInMillis = now
    when (this) {
      ONE_DAY -> calendar.add(Calendar.DAY_OF_YEAR, -1)
      ONE_WEEK -> calendar.add(Calendar.DAY_OF_YEAR, -7)
      ONE_MONTH -> calendar.add(Calendar.MONTH, -1)
      THREE_MONTHS -> calendar.add(Calendar.MONTH, -3)
    }
    return calendar.timeInMillis
  }

  fun contains(instant: Long, now: Long): Boolean = instant >= cutoff(now)

  companion object {
    val DEFAULT = ONE_WEEK

    fun fromWire(value: String?): EmailSyncWindow? = entries.firstOrNull { it.wire == value }
  }
}

data class EmailAnalysisSettings(
  val selectedProvider: EmailAnalysisProvider?,
  val openRouterAccessMode: OpenRouterAccessMode,
  val openRouterModelId: String?,
  /** Last Free-mode model, restored when switching back from BYOK. */
  val lastFreeOpenRouterModelId: String?,
  /** Last BYOK model, restored when switching back from Free. */
  val lastBYOKOpenRouterModelId: String?,
  /** Active privacy mode for the current access mode. */
  val openRouterPrivacyMode: OpenRouterPrivacyMode,
  val nonZDRConsentVersion: Int?,
  /** Free-mode ZDR preference, restored when switching back from BYOK. */
  val lastFreeOpenRouterPrivacyMode: OpenRouterPrivacyMode,
  val lastFreeNonZDRConsentVersion: Int?,
  /** BYOK ZDR preference, restored when switching back from Free. */
  val lastBYOKOpenRouterPrivacyMode: OpenRouterPrivacyMode,
  val lastBYOKNonZDRConsentVersion: Int?,
  val syncWindow: EmailSyncWindow,
  val updatedAt: Long,
) {
  companion object {
    const val SINGLETON_ID = "settings"

    fun defaults(now: Long = System.currentTimeMillis()) = EmailAnalysisSettings(
      selectedProvider = null,
      openRouterAccessMode = OpenRouterAccessMode.BRING_YOUR_OWN_KEY,
      openRouterModelId = null,
      lastFreeOpenRouterModelId = null,
      lastBYOKOpenRouterModelId = null,
      openRouterPrivacyMode = OpenRouterPrivacyMode.ZDR_ONLY,
      nonZDRConsentVersion = null,
      lastFreeOpenRouterPrivacyMode = OpenRouterPrivacyMode.ZDR_ONLY,
      lastFreeNonZDRConsentVersion = null,
      lastBYOKOpenRouterPrivacyMode = OpenRouterPrivacyMode.ZDR_ONLY,
      lastBYOKNonZDRConsentVersion = null,
      syncWindow = EmailSyncWindow.DEFAULT,
      updatedAt = now,
    )
  }
}

data class EmailAnalysisRetryState(
  val attempt: Int,
  val notBefore: Long?,
  val reason: String?,
  val lastHttpStatus: Int?,
  val updatedAt: Long,
) {
  companion object {
    const val SINGLETON_ID = "openrouter"
  }
}

enum class EmailMessageClassification(val wire: String) {
  PURCHASE("purchase"),
  DEBIT("debit"),
  REFUND("refund"),
  IRRELEVANT("irrelevant");

  companion object {
    fun fromWire(value: String?): EmailMessageClassification? =
      entries.firstOrNull { it.wire == value }
  }
}

enum class EmailSuggestionState(val wire: String) {
  /** The message has been fetched but has not yet completed local analysis. */
  PENDING_ANALYSIS("pendingAnalysis"),
  ANALYSIS_FAILED("analysisFailed"),
  PENDING_PURCHASE("pendingPurchase"),
  PENDING_REFUND("pendingRefund"),
  ADDED("added"),
  REFUND_APPLIED("refundApplied"),
  DISMISSED("dismissed"),
  UNACTIONABLE("unactionable"),
  EXPIRED("expired");

  val isPendingReview: Boolean
    get() = this == PENDING_PURCHASE || this == PENDING_REFUND

  val isReviewed: Boolean
    get() = when (this) {
      ADDED, REFUND_APPLIED, DISMISSED -> true
      PENDING_ANALYSIS, ANALYSIS_FAILED, PENDING_PURCHASE, PENDING_REFUND, UNACTIONABLE, EXPIRED ->
        false
    }

  companion object {
    fun fromWire(value: String?): EmailSuggestionState? = entries.firstOrNull { it.wire == value }
  }
}

enum class EmailLocalSuggestionFilter {
  PURCHASES,
  REFUNDS,
  REVIEWED,
}

/**
 * Device-local Gmail account metadata. OAuth tokens are intentionally absent;
 * refresh tokens belong in the encrypted credential vault and access tokens must
 * remain in memory.
 */
data class EmailAccountRecordModel(
  /** Stable Google OpenID subject identifier. */
  val id: String,
  val emailAddress: String,
  val historyId: String? = null,
  val backfillPageToken: String? = null,
  val backfillCompletedAt: Long? = null,
  val lastAttemptAt: Long? = null,
  val lastSuccessfulSyncAt: Long? = null,
  val syncState: EmailAccountSyncState = EmailAccountSyncState.IDLE,
  val lastError: String? = null,
  val createdAt: Long = System.currentTimeMillis(),
  val updatedAt: Long = System.currentTimeMillis(),
)

/**
 * Immutable Gmail envelope plus the normalized body that is eligible for analysis.
 * Raw MIME, HTML, attachments, images, prompts, and model output do not have fields
 * in the local schema.
 */
data class PendingEmailMessage(
  val accountId: String,
  val gmailMessageId: String,
  val threadId: String,
  val rfcMessageId: String? = null,
  val senderName: String? = null,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBodyText: String,
) {
  val key: String get() = emailMessageKey(accountId, gmailMessageId)
}

data class PersistedEmailAnalysis(
  val analyzerType: EmailAnalyzerKind,
  val modelVersion: String? = null,
  val promptVersion: Int,
  val classification: EmailMessageClassification,
  val merchant: String? = null,
  /** Canonical base-unit decimal text, such as `1234.50`. */
  val amount: String? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
)

data class EmailMessageRecordModel(
  val key: String,
  val accountId: String,
  val gmailMessageId: String,
  val threadId: String,
  val rfcMessageId: String?,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBodyText: String?,
  val analysisProviderOverride: EmailAnalysisProvider?,
  val analyzerType: EmailAnalyzerKind?,
  val modelVersion: String?,
  val promptVersion: Int?,
  val classification: EmailMessageClassification?,
  val merchant: String?,
  val amount: String?,
  val currency: Currency?,
  val occurredAt: Long?,
  val categoryId: String?,
  val paymentMethodId: String?,
  val paymentLastFour: String?,
  val reference: String?,
  val state: EmailSuggestionState,
  val purchaseGroupId: String?,
  val linkedTransactionId: String?,
  val analyzedAt: Long?,
  val reviewedAt: Long?,
  val createdAt: Long,
  val updatedAt: Long,
) {
  val id: String get() = key
}

/**
 * Lightweight UI projection that deliberately excludes retained body text and
 * extracted transaction fields not needed by the all-email status feed.
 */
data class EmailMessageSummaryModel(
  val id: String,
  val accountId: String,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val analyzerType: EmailAnalyzerKind?,
  val modelVersion: String?,
  val classification: EmailMessageClassification?,
  val state: EmailSuggestionState,
  val analyzedAt: Long?,
  val reviewedAt: Long?,
)

/** Synced reviewed Gmail suggestion, including the full normalized body text. */
data class EmailMessageEntity(
  val id: String,
  val accountId: String,
  val accountEmail: String,
  val gmailMessageId: String,
  val threadId: String,
  val rfcMessageId: String? = null,
  val senderName: String? = null,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBodyText: String? = null,
  val analyzerType: String? = null,
  val modelVersion: String? = null,
  val promptVersion: Int? = null,
  val classification: String? = null,
  val merchant: String? = null,
  val amount: String? = null,
  val currency: String? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
  /** Wire values: added, dismissed, refundApplied, pendingPurchase, pendingRefund. */
  val state: String,
  /**
   * Shared by purchase/debit emails representing one expense. When equal to this
   * email's [id], the user explicitly chose to keep it separate.
   */
  val purchaseGroupId: String? = null,
  val linkedTransactionId: String? = null,
  val analyzedAt: Long? = null,
  val reviewedAt: Long? = null,
  val createdAt: Long,
  val updatedAt: Long,
)

/** Thrown by the email repository surface; each case carries a user-facing message. */
class EmailRepositoryException(
  val kind: Kind,
) : Exception(kind.message) {
  enum class Kind(val message: String) {
    INVALID_ACCOUNT("The Gmail account details are invalid."),
    ACCOUNT_NOT_FOUND("The Gmail account is no longer connected."),
    MESSAGE_NOT_FOUND("The email suggestion no longer exists."),
    SUGGESTION_ALREADY_REVIEWED("This email suggestion has already been reviewed."),
    INVALID_SUGGESTION_STATE("This action is not available for the email suggestion."),
    INVALID_ANALYSIS("The email analysis is invalid."),
    INVALID_CATEGORY("Choose an existing category before saving."),
    INVALID_PAYMENT_METHOD("The selected payment method no longer exists."),
    DUPLICATE_TRANSACTION("A transaction with this identifier already exists."),
    TRANSACTION_NOT_FOUND("The matched transaction no longer exists."),
    CURRENCY_MISMATCH("The refund currency does not match Dimo's active currency."),
    AMOUNT_MISMATCH("Only an exact full refund can remove a transaction."),
    TRANSACTION_OUTSIDE_REFUND_WINDOW(
      "The matched transaction is outside the refund matching window.",
    ),
  }
}

/**
 * Length-prefixing the account ID avoids delimiter collisions while keeping the key
 * deterministic for paged and incremental Gmail sync.
 */
fun emailMessageKey(accountId: String, gmailMessageId: String): String {
  val byteLength = accountId.toByteArray(Charsets.UTF_8).size
  return "$byteLength:$accountId$gmailMessageId"
}
