package app.dimo.android.data.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EmailAccountSyncState
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailAnalysisRetryState
import app.dimo.android.data.model.EmailAnalysisSettings
import app.dimo.android.data.model.EmailAnalyzerKind
import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailMessageRecordModel
import app.dimo.android.data.model.EmailMessageSummaryModel
import app.dimo.android.data.model.EmailRepositoryException
import app.dimo.android.data.model.EmailSuggestionState
import app.dimo.android.data.model.EmailSyncWindow
import app.dimo.android.data.model.OpenRouterAccessMode
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.data.model.PendingEmailMessage

/**
 * Room rows for the device-local email tables, mirroring the GRDB records in
 * `ios-native/Dimo/Data/EmailLocalRecords.swift`.
 *
 * Enum-valued columns are stored as their wire strings rather than Room type
 * converters, so a row written by a future build with an unknown value decodes to
 * the same error the iOS records raise instead of silently coercing.
 */

@Entity(
  tableName = "emailAccounts",
  indices = [Index("emailAddress")],
)
data class EmailAccountRecord(
  @PrimaryKey val id: String,
  val emailAddress: String,
  val historyId: String?,
  val backfillPageToken: String?,
  val backfillCompletedAt: Long?,
  val lastAttemptAt: Long?,
  val lastSuccessfulSyncAt: Long?,
  val syncState: String,
  val lastError: String?,
  val createdAt: Long,
  val updatedAt: Long,
) {
  fun toModel(): EmailAccountRecordModel {
    val state = EmailAccountSyncState.fromWire(syncState)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_ACCOUNT)
    return EmailAccountRecordModel(
      id = id,
      emailAddress = emailAddress,
      historyId = historyId,
      backfillPageToken = backfillPageToken,
      backfillCompletedAt = backfillCompletedAt,
      lastAttemptAt = lastAttemptAt,
      lastSuccessfulSyncAt = lastSuccessfulSyncAt,
      syncState = state,
      lastError = lastError,
      createdAt = createdAt,
      updatedAt = updatedAt,
    )
  }

  companion object {
    fun from(account: EmailAccountRecordModel) = EmailAccountRecord(
      id = account.id,
      emailAddress = account.emailAddress,
      historyId = account.historyId,
      backfillPageToken = account.backfillPageToken,
      backfillCompletedAt = account.backfillCompletedAt,
      lastAttemptAt = account.lastAttemptAt,
      lastSuccessfulSyncAt = account.lastSuccessfulSyncAt,
      syncState = account.syncState.wire,
      lastError = account.lastError,
      createdAt = account.createdAt,
      updatedAt = account.updatedAt,
    )
  }
}

@Entity(
  tableName = "emailMessages",
  indices = [
    Index("accountId"),
    Index("state", "internalDate"),
    Index("linkedTransactionId"),
    Index("purchaseGroupId"),
  ],
)
data class EmailMessageRecord(
  @PrimaryKey val key: String,
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
  val analysisProviderOverride: String?,
  val analyzerType: String?,
  val modelVersion: String?,
  val promptVersion: Int?,
  val classification: String?,
  val merchant: String?,
  val amount: String?,
  val currency: String?,
  val occurredAt: Long?,
  val categoryId: String?,
  val paymentMethodId: String?,
  val paymentLastFour: String?,
  val reference: String?,
  val state: String,
  val purchaseGroupId: String?,
  val linkedTransactionId: String?,
  val analyzedAt: Long?,
  val reviewedAt: Long?,
  val createdAt: Long,
  val updatedAt: Long,
) {
  fun toModel(): EmailMessageRecordModel {
    val decodedState = EmailSuggestionState.fromWire(state)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_SUGGESTION_STATE)
    return EmailMessageRecordModel(
      key = key,
      accountId = accountId,
      gmailMessageId = gmailMessageId,
      threadId = threadId,
      rfcMessageId = rfcMessageId,
      senderName = senderName,
      senderAddress = senderAddress,
      subject = subject,
      snippet = snippet,
      internalDate = internalDate,
      normalizedBodyText = normalizedBodyText,
      analysisProviderOverride = analysisProviderOverride?.let {
        EmailAnalysisProvider.fromWire(it) ?: throwInvalidAnalysis()
      },
      analyzerType = analyzerType?.let {
        EmailAnalyzerKind.fromWire(it) ?: throwInvalidAnalysis()
      },
      modelVersion = modelVersion,
      promptVersion = promptVersion,
      classification = classification?.let {
        EmailMessageClassification.fromWire(it) ?: throwInvalidAnalysis()
      },
      merchant = merchant,
      amount = amount,
      currency = currency?.let {
        Currency.entries.firstOrNull { candidate -> candidate.wire == it } ?: throwInvalidAnalysis()
      },
      occurredAt = occurredAt,
      categoryId = categoryId,
      paymentMethodId = paymentMethodId,
      paymentLastFour = paymentLastFour,
      reference = reference,
      state = decodedState,
      purchaseGroupId = purchaseGroupId,
      linkedTransactionId = linkedTransactionId,
      analyzedAt = analyzedAt,
      reviewedAt = reviewedAt,
      createdAt = createdAt,
      updatedAt = updatedAt,
    )
  }

  companion object {
    fun pending(message: PendingEmailMessage, now: Long) = EmailMessageRecord(
      key = message.key,
      accountId = message.accountId,
      gmailMessageId = message.gmailMessageId,
      threadId = message.threadId,
      rfcMessageId = message.rfcMessageId,
      senderName = message.senderName,
      senderAddress = message.senderAddress,
      subject = message.subject,
      snippet = message.snippet,
      internalDate = message.internalDate,
      normalizedBodyText = message.normalizedBodyText,
      analysisProviderOverride = null,
      analyzerType = null,
      modelVersion = null,
      promptVersion = null,
      classification = null,
      merchant = null,
      amount = null,
      currency = null,
      occurredAt = null,
      categoryId = null,
      paymentMethodId = null,
      paymentLastFour = null,
      reference = null,
      state = EmailSuggestionState.PENDING_ANALYSIS.wire,
      purchaseGroupId = null,
      linkedTransactionId = null,
      analyzedAt = null,
      reviewedAt = null,
      createdAt = now,
      updatedAt = now,
    )

    fun from(model: EmailMessageRecordModel) = EmailMessageRecord(
      key = model.key,
      accountId = model.accountId,
      gmailMessageId = model.gmailMessageId,
      threadId = model.threadId,
      rfcMessageId = model.rfcMessageId,
      senderName = model.senderName,
      senderAddress = model.senderAddress,
      subject = model.subject,
      snippet = model.snippet,
      internalDate = model.internalDate,
      normalizedBodyText = model.normalizedBodyText,
      analysisProviderOverride = model.analysisProviderOverride?.wire,
      analyzerType = model.analyzerType?.wire,
      modelVersion = model.modelVersion,
      promptVersion = model.promptVersion,
      classification = model.classification?.wire,
      merchant = model.merchant,
      amount = model.amount,
      currency = model.currency?.wire,
      occurredAt = model.occurredAt,
      categoryId = model.categoryId,
      paymentMethodId = model.paymentMethodId,
      paymentLastFour = model.paymentLastFour,
      reference = model.reference,
      state = model.state.wire,
      purchaseGroupId = model.purchaseGroupId,
      linkedTransactionId = model.linkedTransactionId,
      analyzedAt = model.analyzedAt,
      reviewedAt = model.reviewedAt,
      createdAt = model.createdAt,
      updatedAt = model.updatedAt,
    )
  }
}

@Entity(tableName = "emailAnalysisSettings")
data class EmailAnalysisSettingsRecord(
  @PrimaryKey val id: String,
  val selectedProvider: String?,
  val openRouterAccessMode: String?,
  val openRouterModelId: String?,
  val lastFreeOpenRouterModelId: String?,
  val lastBYOKOpenRouterModelId: String?,
  val openRouterPrivacyMode: String,
  val nonZDRConsentVersion: Int?,
  val lastFreeOpenRouterPrivacyMode: String?,
  val lastFreeNonZDRConsentVersion: Int?,
  val lastBYOKOpenRouterPrivacyMode: String?,
  val lastBYOKNonZDRConsentVersion: Int?,
  val syncWindow: String,
  val updatedAt: Long,
) {
  fun toModel(): EmailAnalysisSettings {
    val accessMode = OpenRouterAccessMode.fromWire(openRouterAccessMode)
      ?: OpenRouterAccessMode.BRING_YOUR_OWN_KEY
    val privacyMode = OpenRouterPrivacyMode.fromWire(openRouterPrivacyMode)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_ANALYSIS)
    val window = EmailSyncWindow.fromWire(syncWindow)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_ANALYSIS)
    return EmailAnalysisSettings(
      // A provider this build does not know becomes unconfigured rather than fatal,
      // matching how iOS drops former Local Gemma selections.
      selectedProvider = selectedProvider?.let(EmailAnalysisProvider::fromWire),
      openRouterAccessMode = accessMode,
      openRouterModelId = openRouterModelId,
      lastFreeOpenRouterModelId = lastFreeOpenRouterModelId,
      lastBYOKOpenRouterModelId = lastBYOKOpenRouterModelId,
      openRouterPrivacyMode = privacyMode,
      nonZDRConsentVersion = nonZDRConsentVersion,
      lastFreeOpenRouterPrivacyMode = OpenRouterPrivacyMode.fromWire(lastFreeOpenRouterPrivacyMode)
        ?: privacyMode,
      lastFreeNonZDRConsentVersion = lastFreeNonZDRConsentVersion
        ?: nonZDRConsentVersion.takeIf { accessMode == OpenRouterAccessMode.FREE_SHARED },
      lastBYOKOpenRouterPrivacyMode = OpenRouterPrivacyMode.fromWire(lastBYOKOpenRouterPrivacyMode)
        ?: privacyMode,
      lastBYOKNonZDRConsentVersion = lastBYOKNonZDRConsentVersion
        ?: nonZDRConsentVersion.takeIf { accessMode == OpenRouterAccessMode.BRING_YOUR_OWN_KEY },
      syncWindow = window,
      updatedAt = updatedAt,
    )
  }

  companion object {
    fun from(value: EmailAnalysisSettings) = EmailAnalysisSettingsRecord(
      id = EmailAnalysisSettings.SINGLETON_ID,
      selectedProvider = value.selectedProvider?.wire,
      openRouterAccessMode = value.openRouterAccessMode.wire,
      openRouterModelId = value.openRouterModelId,
      lastFreeOpenRouterModelId = value.lastFreeOpenRouterModelId,
      lastBYOKOpenRouterModelId = value.lastBYOKOpenRouterModelId,
      openRouterPrivacyMode = value.openRouterPrivacyMode.wire,
      nonZDRConsentVersion = value.nonZDRConsentVersion,
      lastFreeOpenRouterPrivacyMode = value.lastFreeOpenRouterPrivacyMode.wire,
      lastFreeNonZDRConsentVersion = value.lastFreeNonZDRConsentVersion,
      lastBYOKOpenRouterPrivacyMode = value.lastBYOKOpenRouterPrivacyMode.wire,
      lastBYOKNonZDRConsentVersion = value.lastBYOKNonZDRConsentVersion,
      syncWindow = value.syncWindow.wire,
      updatedAt = value.updatedAt,
    )
  }
}

@Entity(tableName = "emailAnalysisRetry")
data class EmailAnalysisRetryRecord(
  @PrimaryKey val id: String,
  val attempt: Int,
  val notBefore: Long?,
  val reason: String?,
  val lastHttpStatus: Int?,
  val updatedAt: Long,
) {
  fun toModel() = EmailAnalysisRetryState(
    attempt = attempt,
    notBefore = notBefore,
    reason = reason,
    lastHttpStatus = lastHttpStatus,
    updatedAt = updatedAt,
  )

  companion object {
    fun from(state: EmailAnalysisRetryState) = EmailAnalysisRetryRecord(
      id = EmailAnalysisRetryState.SINGLETON_ID,
      attempt = state.attempt,
      notBefore = state.notBefore,
      reason = state.reason,
      lastHttpStatus = state.lastHttpStatus,
      updatedAt = state.updatedAt,
    )
  }
}

/** Projection for the all-email status feed; see `EmailMessageSummaryRecord` on iOS. */
data class EmailMessageSummaryRecord(
  val key: String,
  val accountId: String,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val analyzerType: String?,
  val modelVersion: String?,
  val classification: String?,
  val state: String,
  val analyzedAt: Long?,
  val reviewedAt: Long?,
) {
  fun toModel(): EmailMessageSummaryModel {
    val decodedState = EmailSuggestionState.fromWire(state)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_SUGGESTION_STATE)
    return EmailMessageSummaryModel(
      id = key,
      accountId = accountId,
      senderName = senderName,
      senderAddress = senderAddress,
      subject = subject,
      snippet = snippet,
      internalDate = internalDate,
      analyzerType = analyzerType?.let {
        EmailAnalyzerKind.fromWire(it) ?: throwInvalidAnalysis()
      },
      modelVersion = modelVersion,
      classification = classification?.let {
        EmailMessageClassification.fromWire(it) ?: throwInvalidAnalysis()
      },
      state = decodedState,
      analyzedAt = analyzedAt,
      reviewedAt = reviewedAt,
    )
  }
}

private fun throwInvalidAnalysis(): Nothing =
  throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_ANALYSIS)
