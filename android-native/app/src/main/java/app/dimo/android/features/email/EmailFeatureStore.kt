package app.dimo.android.features.email

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailSyncWindow
import app.dimo.android.data.model.OpenRouterAccessMode
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.email.gmail.GmailOAuthException
import app.dimo.android.email.openrouter.OpenRouterModel
import java.math.BigDecimal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Port of `ios-native/Dimo/Features/Email/EmailFeatureStore.swift`.
 *
 * UI-facing state for the Email feature. Gmail, database and model services
 * inject [EmailFeatureActions] and publish presentation values without being
 * imported here, so the Compose layer never touches OAuth or Room directly.
 */

enum class EmailSuggestionFilter(val title: String) {
  PURCHASES("Purchases"),
  REFUNDS("Refunds"),
  AWAITING_ANALYSIS("Awaiting analysis"),
  ERRORS("Errors"),
  REVIEWED("Reviewed"),
  ALL("All");

  val displaysMessages: Boolean
    get() = this == AWAITING_ANALYSIS || this == ERRORS || this == ALL
}

enum class EmailUIMessageAnalysisState(val title: String) {
  PENDING("Awaiting analysis"),
  FAILED("Analysis failed"),
  NEEDS_REVIEW("Needs review"),
  ANALYZED("Analyzed"),
  ADDED("Added"),
  REFUND_APPLIED("Refund applied"),
  DISMISSED("Dismissed"),
  EXPIRED("Expired"),
}

enum class EmailUISuggestionKind(val title: String) {
  PURCHASE("Purchase"),
  DEBIT("Debit"),
  REFUND("Refund"),
  IRRELEVANT("Not a transaction"),
}

enum class EmailUIAnalyzer(val title: String) {
  GEMMA("Gemma"),
  OPEN_ROUTER("OpenRouter");

  /** "OpenRouter · gpt-oss-20b" — the model name only, not the full slug. */
  fun provenanceTitle(modelVersion: String?): String {
    if (this != OPEN_ROUTER) return title
    val trimmed = modelVersion?.trim().orEmpty()
    if (trimmed.isEmpty()) return title
    return "OpenRouter · ${trimmed.substringAfterLast('/')}"
  }
}

enum class EmailUISuggestionStatus(val title: String) {
  PENDING_PURCHASE("Needs review"),
  PENDING_REFUND("Needs review"),
  ADDED("Added"),
  REFUND_APPLIED("Refund applied"),
  DISMISSED("Dismissed"),
  UNACTIONABLE("Informational"),
  EXPIRED("Expired");

  val isReviewed: Boolean
    get() = this == ADDED || this == REFUND_APPLIED || this == DISMISSED
}

enum class EmailUIAccountSyncState(val title: String) {
  IDLE("Up to date"),
  SYNCING("Syncing"),
  RATE_LIMITED("Waiting"),
  OFFLINE("Offline"),
  FAILED("Needs attention"),
  NEEDS_RECONNECT("Reconnect"),
  DISCONNECTED("Disconnected"),
}

enum class OpenRouterModelFilter(val title: String) {
  ALL("ALL"),
  FREE("FREE"),
  ZDR("ZDR"),
}

sealed interface OpenRouterUIConnectionState {
  data object Disconnected : OpenRouterUIConnectionState
  data object Validating : OpenRouterUIConnectionState
  data class Connected(
    val label: String,
    val creditLimit: Double?,
    val limitRemaining: Double?,
  ) : OpenRouterUIConnectionState

  data class Failed(val message: String) : OpenRouterUIConnectionState
}

data class EmailUIMessage(
  val id: String,
  val accountEmail: String,
  val sender: String,
  val subject: String,
  val snippet: String,
  val receivedAt: Long,
  val analyzer: EmailUIAnalyzer? = null,
  val modelVersion: String? = null,
  val classification: EmailUISuggestionKind? = null,
  val analysisState: EmailUIMessageAnalysisState,
  val analyzedAt: Long? = null,
  val reviewedAt: Long? = null,
)

data class EmailUIEmailDetail(
  val id: String,
  val accountEmail: String,
  val sender: String,
  val senderAddress: String,
  val subject: String,
  val bodyText: String,
  val receivedAt: Long,
  val analyzer: EmailUIAnalyzer? = null,
  val modelVersion: String? = null,
  val classification: EmailUISuggestionKind? = null,
  val analysisState: EmailUIMessageAnalysisState,
  val isBodyRetained: Boolean,
)

data class EmailUIAccount(
  val id: String,
  val emailAddress: String,
  val syncState: EmailUIAccountSyncState = EmailUIAccountSyncState.IDLE,
  val statusDetail: String? = null,
  val lastSuccessfulSyncAt: Long? = null,
  val lastError: String? = null,
  val initialScanComplete: Boolean = false,
)

data class EmailUIRefundCandidate(
  val id: String,
  val merchant: String,
  val amount: BigDecimal,
  val currency: Currency,
  val occurredAt: Long,
  val categoryName: String,
  val paymentMethodLabel: String? = null,
  val matchReason: String? = null,
)

data class EmailUISourceSummary(
  val id: String,
  val sender: String,
  val subject: String,
)

data class EmailUILatePurchaseMatch(
  val reviewedSourceMessageId: String,
  val transactionId: String,
  val transactionName: String,
)

data class EmailUISuggestion(
  val id: String,
  val accountId: String,
  val accountEmail: String,
  val kind: EmailUISuggestionKind,
  val status: EmailUISuggestionStatus,
  val sender: String,
  val subject: String,
  val snippet: String,
  val receivedAt: Long,
  val merchant: String? = null,
  val amount: BigDecimal? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val categoryName: String? = null,
  val paymentMethodId: String? = null,
  val paymentMethodLabel: String? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
  val analyzer: EmailUIAnalyzer,
  val modelVersion: String? = null,
  val currencyWarning: String? = null,
  val possibleDuplicateDescriptions: List<String> = emptyList(),
  val isFullRefund: Boolean = true,
  val refundCandidates: List<EmailUIRefundCandidate> = emptyList(),
  val preselectedRefundTransactionId: String? = null,
  val groupId: String? = null,
  val sourceMessageIds: List<String> = emptyList(),
  val sourceSenders: List<String> = emptyList(),
  val sources: List<EmailUISourceSummary> = emptyList(),
  val lateMatch: EmailUILatePurchaseMatch? = null,
) {
  /** A grouped pair acts as one unit; a lone suggestion acts on itself. */
  val actionMessageIds: List<String>
    get() = sourceMessageIds.ifEmpty { listOf(id) }
}

data class EmailUISourceEmailsPresentation(
  val suggestion: EmailUISuggestion,
  val emails: List<EmailUIEmailDetail>,
) {
  val canSeparate: Boolean
    get() = suggestion.actionMessageIds.size > 1 && !suggestion.status.isReviewed
}

data class EmailUIPurchaseReviewDraft(
  val suggestionId: String,
  val groupId: String? = null,
  val sourceMessageIds: List<String> = emptyList(),
  val merchant: String,
  val amount: String,
  val occurredAt: Long,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val isRecurring: Boolean = false,
  val recurringFrequency: RecurringFrequency = RecurringFrequency.MONTHLY,
  val accountEmail: String,
  val analyzer: EmailUIAnalyzer,
  val currency: Currency? = null,
  val currencyWarning: String? = null,
  val possibleDuplicateDescriptions: List<String> = emptyList(),
)

data class EmailUIRefundReview(
  val suggestionId: String,
  val merchant: String,
  val amount: BigDecimal? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val accountEmail: String,
  val analyzer: EmailUIAnalyzer,
  val isFullRefund: Boolean,
  val candidates: List<EmailUIRefundCandidate>,
  val selectedTransactionId: String? = null,
)

/** Everything the UI can ask the controller to do. Defaults are no-ops for previews. */
data class EmailFeatureActions(
  val connectAccount: suspend () -> Unit = {},
  val reconnectAccount: suspend (String) -> Unit = {},
  val disconnectAccount: suspend (String) -> Unit = {},
  val refresh: suspend (String?) -> Unit = {},
  val dismissSuggestion: suspend (String) -> Unit = {},
  val dismissSuggestions: suspend (List<String>) -> Unit = {},
  val restoreSuggestion: suspend (String) -> Unit = {},
  val restoreSuggestions: suspend (List<String>) -> Unit = {},
  val separateSuggestions: suspend (List<String>) -> Unit = {},
  val linkLateSuggestion: suspend (String, String) -> Unit = { _, _ -> },
  val keepLateSuggestionSeparate: suspend (String) -> Unit = {},
  val acceptPurchase: suspend (EmailUIPurchaseReviewDraft) -> Unit = {},
  val linkPurchaseToTransaction: suspend (String, String) -> Unit = { _, _ -> },
  val applyFullRefund: suspend (String, String) -> Unit = { _, _ -> },
  val reanalyzeAllEmails: suspend () -> Unit = {},
  val saveOpenRouterKey: suspend (String) -> Unit = {},
  val removeOpenRouterKey: suspend () -> Unit = {},
  val refreshOpenRouterModels: suspend () -> Unit = {},
  val selectOpenRouterModel: suspend (String, Boolean) -> Unit = { _, _ -> },
  val selectOpenRouterAccessMode: suspend (OpenRouterAccessMode) -> Unit = {},
  val selectProvider: suspend (EmailAnalysisProvider?) -> Unit = {},
  val selectSyncWindow: suspend (EmailSyncWindow) -> Unit = {},
  val retryAnalysis: suspend (String) -> Unit = {},
  val retryOpenRouterConnection: suspend () -> Unit = {},
  val retryOpenRouterAnalysis: suspend () -> Unit = {},
  val loadEmailDetail: suspend (String) -> EmailUIEmailDetail = {
    throw EmailFeatureStoreException("The email no longer exists on this device.")
  },
)

class EmailFeatureStore(
  private val scope: CoroutineScope,
  accounts: List<EmailUIAccount> = emptyList(),
  suggestions: List<EmailUISuggestion> = emptyList(),
  allEmails: List<EmailUIMessage> = emptyList(),
  selectedProvider: EmailAnalysisProvider? = null,
  activeCurrency: Currency = Currency.INR,
  categories: List<CategoryEntity> = emptyList(),
  paymentMethods: List<PaymentMethodOption> = emptyList(),
  private var actions: EmailFeatureActions = EmailFeatureActions(),
) {
  var accounts by mutableStateOf(accounts)

  var suggestions by mutableStateOf(suggestions)
    private set

  var allEmails by mutableStateOf(allEmails)
    private set

  var selectedProvider by mutableStateOf(selectedProvider)
  var openRouterAccessMode by mutableStateOf(OpenRouterAccessMode.BRING_YOUR_OWN_KEY)
  var openRouterConnectionState by mutableStateOf<OpenRouterUIConnectionState>(
    OpenRouterUIConnectionState.Disconnected,
  )
  var openRouterModels by mutableStateOf<List<OpenRouterModel>>(emptyList())
  var selectedOpenRouterModelId by mutableStateOf<String?>(null)
  var openRouterPrivacyMode by mutableStateOf(OpenRouterPrivacyMode.ZDR_ONLY)
  var syncWindow by mutableStateOf(EmailSyncWindow.DEFAULT)
  var openRouterApiKeyInput by mutableStateOf("")
  var isRefreshingOpenRouterModels by mutableStateOf(false)
  var isUpdatingSyncWindow by mutableStateOf(false)
  var analysisStatusDetail by mutableStateOf(UNCONFIGURED_STATUS)
  var activeCurrency by mutableStateOf(activeCurrency)
  var categories by mutableStateOf(categories)
  var paymentMethods by mutableStateOf(paymentMethods)

  var selectedFilter by mutableStateOf(EmailSuggestionFilter.PURCHASES)
    private set

  var purchaseReview by mutableStateOf<EmailUIPurchaseReviewDraft?>(null)
  var refundReview by mutableStateOf<EmailUIRefundReview?>(null)
  var emailDetail by mutableStateOf<EmailUIEmailDetail?>(null)
  var sourceEmailsPresentation by mutableStateOf<EmailUISourceEmailsPresentation?>(null)
  var isRefreshing by mutableStateOf(false)
    private set
  var isReanalyzing by mutableStateOf(false)
    private set
  /** Settable by the controller so start-up failures surface in the same alert. */
  var lastActionError by mutableStateOf<String?>(null)

  /** When set, the action-failed alert can offer an in-place Gmail reconnect. */
  var pendingReconnectAccountId by mutableStateOf<String?>(null)
    private set

  /**
   * Pending purchase/debit suggestions waiting for review. Used for the Email tab
   * badge and the Purchases filter count.
   */
  var pendingPurchaseCount by mutableStateOf(0)
    private set

  var analysisErrorCount by mutableStateOf(0)
    private set

  var filteredSuggestions by mutableStateOf<List<EmailUISuggestion>>(emptyList())
    private set

  var filteredEmails by mutableStateOf<List<EmailUIMessage>>(emptyList())
    private set

  init {
    rebuildSuggestionDerived()
    rebuildEmailDerived()
  }

  fun configure(actions: EmailFeatureActions) {
    this.actions = actions
  }

  // MARK: - Published inputs

  fun publishSuggestions(value: List<EmailUISuggestion>) {
    suggestions = value
    rebuildSuggestionDerived()
  }

  fun publishAllEmails(value: List<EmailUIMessage>) {
    allEmails = value
    rebuildEmailDerived()
  }

  fun setFilter(value: EmailSuggestionFilter) {
    selectedFilter = value
    rebuildFilteredSuggestions()
    rebuildFilteredEmails()
  }

  // MARK: - Derived

  val hasFailedAnalyses: Boolean get() = analysisErrorCount > 0

  val activeAnalyzerTitle: String
    get() = when (selectedProvider) {
      EmailAnalysisProvider.OPEN_ROUTER -> "OpenRouter"
      null -> "Analysis not configured"
    }

  val isOpenRouterReady: Boolean
    get() = selectedProvider == EmailAnalysisProvider.OPEN_ROUTER &&
      selectedOpenRouterModelId != null &&
      openRouterConnectionState is OpenRouterUIConnectionState.Connected

  val selectedOpenRouterModel: OpenRouterModel?
    get() = openRouterModels.firstOrNull { it.id == selectedOpenRouterModelId }

  private fun rebuildSuggestionDerived() {
    pendingPurchaseCount = suggestions.count {
      it.status == EmailUISuggestionStatus.PENDING_PURCHASE &&
        (it.kind == EmailUISuggestionKind.PURCHASE || it.kind == EmailUISuggestionKind.DEBIT)
    }
    rebuildFilteredSuggestions()
  }

  private fun rebuildEmailDerived() {
    analysisErrorCount = allEmails.count {
      it.analysisState == EmailUIMessageAnalysisState.FAILED
    }
    rebuildFilteredEmails()
  }

  private fun rebuildFilteredSuggestions() {
    filteredSuggestions = when (selectedFilter) {
      EmailSuggestionFilter.PURCHASES -> suggestions.filter {
        it.status == EmailUISuggestionStatus.PENDING_PURCHASE &&
          (it.kind == EmailUISuggestionKind.PURCHASE || it.kind == EmailUISuggestionKind.DEBIT)
      }

      EmailSuggestionFilter.REFUNDS -> suggestions.filter {
        it.status == EmailUISuggestionStatus.PENDING_REFUND &&
          it.kind == EmailUISuggestionKind.REFUND
      }

      EmailSuggestionFilter.REVIEWED -> suggestions.filter { it.status.isReviewed }
      // These tabs list raw messages instead of suggestions.
      EmailSuggestionFilter.AWAITING_ANALYSIS,
      EmailSuggestionFilter.ERRORS,
      EmailSuggestionFilter.ALL,
      -> emptyList()
    }
  }

  private fun rebuildFilteredEmails() {
    filteredEmails = when (selectedFilter) {
      EmailSuggestionFilter.AWAITING_ANALYSIS -> allEmails.filter {
        it.analysisState == EmailUIMessageAnalysisState.PENDING
      }

      EmailSuggestionFilter.ERRORS -> allEmails.filter {
        it.analysisState == EmailUIMessageAnalysisState.FAILED
      }

      EmailSuggestionFilter.ALL -> allEmails
      EmailSuggestionFilter.PURCHASES,
      EmailSuggestionFilter.REFUNDS,
      EmailSuggestionFilter.REVIEWED,
      -> emptyList()
    }
  }

  // MARK: - Presentation

  fun presentEmail(id: String) = run { emailDetail = actions.loadEmailDetail(id) }

  fun presentSources(suggestion: EmailUISuggestion) {
    if (suggestion.actionMessageIds.size == 1) {
      presentEmail(suggestion.id)
      return
    }
    run {
      val emails = suggestion.actionMessageIds.map { actions.loadEmailDetail(it) }
      sourceEmailsPresentation = EmailUISourceEmailsPresentation(suggestion, emails)
    }
  }

  fun dismissSourceEmails() {
    sourceEmailsPresentation = null
  }

  fun dismissEmailDetail() {
    emailDetail = null
  }

  fun review(suggestion: EmailUISuggestion) {
    when (suggestion.kind) {
      EmailUISuggestionKind.PURCHASE, EmailUISuggestionKind.DEBIT ->
        purchaseReview = EmailUIPurchaseReviewDraft(
          suggestionId = suggestion.id,
          groupId = suggestion.groupId,
          sourceMessageIds = suggestion.actionMessageIds,
          merchant = suggestion.merchant.orEmpty(),
          amount = suggestion.amount?.toPlainString().orEmpty(),
          occurredAt = suggestion.occurredAt ?: suggestion.receivedAt,
          categoryId = suggestion.categoryId,
          paymentMethodId = suggestion.paymentMethodId,
          accountEmail = suggestion.accountEmail,
          analyzer = suggestion.analyzer,
          currency = suggestion.currency,
          currencyWarning = suggestion.currencyWarning,
          possibleDuplicateDescriptions = suggestion.possibleDuplicateDescriptions,
        )

      EmailUISuggestionKind.REFUND ->
        refundReview = EmailUIRefundReview(
          suggestionId = suggestion.id,
          merchant = suggestion.merchant ?: "Refund",
          amount = suggestion.amount,
          currency = suggestion.currency,
          occurredAt = suggestion.occurredAt,
          accountEmail = suggestion.accountEmail,
          analyzer = suggestion.analyzer,
          isFullRefund = suggestion.isFullRefund,
          candidates = suggestion.refundCandidates,
          selectedTransactionId = suggestion.preselectedRefundTransactionId,
        )

      EmailUISuggestionKind.IRRELEVANT -> Unit
    }
  }

  // MARK: - Actions

  fun connectAccount() = run { actions.connectAccount() }

  fun reconnectAccount(accountId: String) {
    scope.launch {
      try {
        actions.reconnectAccount(accountId)
        pendingReconnectAccountId = null
        lastActionError = null
      } catch (error: Throwable) {
        presentActionError(error, reconnectAccountId = accountId)
      }
    }
  }

  fun disconnectAccount(accountId: String) = run { actions.disconnectAccount(accountId) }

  suspend fun refreshAll() {
    if (isRefreshing) return
    isRefreshing = true
    try {
      actions.refresh(null)
    } catch (error: Throwable) {
      presentActionError(error)
    } finally {
      isRefreshing = false
    }
  }

  fun refreshAccount(accountId: String) = run { actions.refresh(accountId) }

  fun dismissSuggestion(suggestionId: String) = run { actions.dismissSuggestion(suggestionId) }

  fun dismissSuggestion(suggestion: EmailUISuggestion) {
    if (suggestion.actionMessageIds.size == 1) {
      dismissSuggestion(suggestion.id)
    } else {
      run { actions.dismissSuggestions(suggestion.actionMessageIds) }
    }
  }

  fun restoreSuggestion(suggestionId: String) = run { actions.restoreSuggestion(suggestionId) }

  fun restoreSuggestion(suggestion: EmailUISuggestion) {
    if (suggestion.actionMessageIds.size == 1) {
      restoreSuggestion(suggestion.id)
    } else {
      run { actions.restoreSuggestions(suggestion.actionMessageIds) }
    }
  }

  fun separateSuggestion(suggestion: EmailUISuggestion) =
    run { actions.separateSuggestions(suggestion.actionMessageIds) }

  fun linkLateSuggestion(suggestion: EmailUISuggestion) {
    val match = suggestion.lateMatch ?: return
    run { actions.linkLateSuggestion(suggestion.id, match.reviewedSourceMessageId) }
  }

  fun keepLateSuggestionSeparate(suggestion: EmailUISuggestion) =
    run { actions.keepLateSuggestionSeparate(suggestion.id) }

  fun acceptPurchase(draft: EmailUIPurchaseReviewDraft) =
    run(onSuccess = { purchaseReview = null }) { actions.acceptPurchase(draft) }

  /**
   * Marks the suggestion reviewed against an expense the user already has,
   * instead of adding a second one for the same purchase.
   */
  fun linkPurchaseToTransaction(suggestionId: String, transactionId: String) =
    run(onSuccess = { purchaseReview = null }) {
      actions.linkPurchaseToTransaction(suggestionId, transactionId)
    }

  fun applyFullRefund(review: EmailUIRefundReview) {
    val transactionId = review.selectedTransactionId ?: return
    run(onSuccess = { refundReview = null }) {
      actions.applyFullRefund(review.suggestionId, transactionId)
    }
  }

  fun reanalyzeAllEmails() {
    if (isReanalyzing) return
    isReanalyzing = true
    lastActionError = null
    setFilter(EmailSuggestionFilter.ALL)
    scope.launch {
      try {
        actions.reanalyzeAllEmails()
      } catch (error: Throwable) {
        presentActionError(error)
      } finally {
        isReanalyzing = false
      }
    }
  }

  fun saveOpenRouterKey() {
    val key = openRouterApiKeyInput
    run(onSuccess = { openRouterApiKeyInput = "" }) { actions.saveOpenRouterKey(key) }
  }

  fun removeOpenRouterKey() = run { actions.removeOpenRouterKey() }

  fun refreshOpenRouterModels() {
    if (isRefreshingOpenRouterModels) return
    isRefreshingOpenRouterModels = true
    scope.launch {
      try {
        actions.refreshOpenRouterModels()
      } catch (error: Throwable) {
        presentActionError(error)
      } finally {
        isRefreshingOpenRouterModels = false
      }
    }
  }

  fun selectOpenRouterModel(modelId: String, allowNonZDR: Boolean) =
    run { actions.selectOpenRouterModel(modelId, allowNonZDR) }

  fun selectOpenRouterAccessMode(mode: OpenRouterAccessMode) =
    run { actions.selectOpenRouterAccessMode(mode) }

  fun selectProvider(provider: EmailAnalysisProvider?) = run { actions.selectProvider(provider) }

  fun selectSyncWindow(window: EmailSyncWindow) {
    if (window == syncWindow || isUpdatingSyncWindow) return
    val previous = syncWindow
    // Optimistic: the picker should not lag a network round trip.
    syncWindow = window
    isUpdatingSyncWindow = true
    scope.launch {
      try {
        actions.selectSyncWindow(window)
      } catch (error: Throwable) {
        syncWindow = previous
        presentActionError(error)
      } finally {
        isUpdatingSyncWindow = false
      }
    }
  }

  fun retryAnalysis(messageId: String) = run { actions.retryAnalysis(messageId) }

  fun retryOpenRouterConnection() = run { actions.retryOpenRouterConnection() }

  fun retryOpenRouterAnalysis() = run { actions.retryOpenRouterAnalysis() }

  fun clearError() {
    lastActionError = null
    pendingReconnectAccountId = null
  }

  // MARK: - Private

  private fun presentActionError(error: Throwable, reconnectAccountId: String? = null) {
    // Pull-to-refresh and overlapping work cancel in-flight jobs; that is not a
    // user-facing failure.
    if (error is CancellationException) return
    lastActionError = error.message ?: "Something went wrong."
    if (reconnectAccountId != null) {
      pendingReconnectAccountId = reconnectAccountId
      return
    }
    pendingReconnectAccountId = when (error) {
      is GmailOAuthException.RequiresReconnect,
      is GmailOAuthException.MissingRefreshToken,
      is GmailOAuthException.AccountMismatch,
      ->
        accounts.firstOrNull { it.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT }?.id
          ?: accounts.firstOrNull()?.id

      else -> null
    }
  }

  private fun run(
    onSuccess: () -> Unit = {},
    operation: suspend () -> Unit,
  ) {
    scope.launch {
      try {
        operation()
        onSuccess()
      } catch (error: Throwable) {
        presentActionError(error)
      }
    }
  }

  companion object {
    const val UNCONFIGURED_STATUS =
      "Email analysis is not configured. Choose Free models or Bring your own key in " +
        "Email settings."
  }
}

class EmailFeatureStoreException(message: String) : Exception(message)
