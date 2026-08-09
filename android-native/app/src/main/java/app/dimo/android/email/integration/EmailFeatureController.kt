package app.dimo.android.email.integration

import android.content.Context
import android.util.Log
import app.dimo.android.app.AppConfig
import app.dimo.android.data.EmailRepository
import app.dimo.android.data.SeedData
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EmailAccountSyncState
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailAnalysisRetryState
import app.dimo.android.data.model.EmailAnalysisSettings
import app.dimo.android.data.model.EmailAnalyzerKind
import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailMessageRecordModel
import app.dimo.android.data.model.EmailRepositoryException
import app.dimo.android.data.model.EmailSuggestionState
import app.dimo.android.data.model.EmailSyncWindow
import app.dimo.android.data.model.OpenRouterAccessMode
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.Transaction
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.EmailPurchaseGroupingSelector
import app.dimo.android.domain.EmailRefundEvidence
import app.dimo.android.domain.EmailSuggestionSelectors
import app.dimo.android.email.analysis.EmailAnalysisCoordinator
import app.dimo.android.email.analysis.EmailAnalysisStartThrottle
import app.dimo.android.email.analysis.ConvexFreeOpenRouterEmailAnalyzer
import app.dimo.android.email.analysis.OpenRouterEmailAnalyzer
import app.dimo.android.email.domain.EmailAnalysisEnvelope
import app.dimo.android.email.domain.EmailAnalysisProviding
import app.dimo.android.email.domain.EmailAnalysisRequest
import app.dimo.android.email.domain.EmailAnalysisResult
import app.dimo.android.email.domain.EmailAnalyzerType
import app.dimo.android.email.domain.EmailCategoryOption
import app.dimo.android.email.domain.EmailMerchantCategoryHint
import app.dimo.android.email.domain.EmailPaymentMethodHint
import app.dimo.android.email.gmail.EmailSyncCoordinator
import app.dimo.android.email.gmail.GmailAccessTokenManager
import app.dimo.android.email.gmail.GmailCredentialVault
import app.dimo.android.email.gmail.GmailOAuthClient
import app.dimo.android.email.gmail.GmailOAuthConfiguration
import app.dimo.android.email.gmail.GmailRESTClient
import app.dimo.android.email.openrouter.OpenRouterClient
import app.dimo.android.email.openrouter.OpenRouterClientException
import app.dimo.android.email.openrouter.OpenRouterConvexTransportException
import app.dimo.android.email.openrouter.OpenRouterConvexTransporting
import app.dimo.android.email.openrouter.OpenRouterCredentialVault
import app.dimo.android.email.openrouter.OpenRouterModel
import app.dimo.android.email.work.EmailBackgroundWork
import app.dimo.android.email.work.EmailBackgroundWorkProviding
import app.dimo.android.features.email.EmailFeatureActions
import app.dimo.android.features.email.EmailFeatureStore
import app.dimo.android.features.email.EmailUIAccount
import app.dimo.android.features.email.EmailUIAccountSyncState
import app.dimo.android.features.email.EmailUIAnalyzer
import app.dimo.android.features.email.EmailUIEmailDetail
import app.dimo.android.features.email.EmailUILatePurchaseMatch
import app.dimo.android.features.email.EmailUIMessage
import app.dimo.android.features.email.EmailUIMessageAnalysisState
import app.dimo.android.features.email.EmailUIPurchaseReviewDraft
import app.dimo.android.features.email.EmailUIRefundCandidate
import app.dimo.android.features.email.EmailUISourceSummary
import app.dimo.android.features.email.EmailUISuggestion
import app.dimo.android.features.email.EmailUISuggestionKind
import app.dimo.android.features.email.EmailUISuggestionStatus
import app.dimo.android.features.email.OpenRouterUIConnectionState
import java.math.BigDecimal
import java.math.RoundingMode
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlin.coroutines.coroutineContext

/** Port of `EmailFeatureControllerError` in the Swift controller. */
sealed class EmailFeatureControllerException(message: String) : Exception(message) {
  object GmailNotConfigured :
    EmailFeatureControllerException("Gmail OAuth is not configured for this build.")

  object InvalidSuggestion : EmailFeatureControllerException(
    "The email suggestion is missing a valid amount, date, or category.",
  )

  object AnalysisNotConfigured :
    EmailFeatureControllerException(EmailFeatureStore.UNCONFIGURED_STATUS)

  object OpenRouterNotConfigured :
    EmailFeatureControllerException("Configure OpenRouter in Email settings before analyzing.")

  object NonZDRConsentRequired : EmailFeatureControllerException(
    "This model has no zero-data-retention route. Confirm non-ZDR use before selecting it.",
  )
}

private enum class AnalysisAttemptOutcome { PROCESSED, PAUSED }

/**
 * Port of `ios-native/Dimo/Email/Integration/EmailFeatureController.swift`.
 *
 * Owns the account-scoped Email feature for one signed-in Dimo user. Gmail
 * credentials stay on this device. Reviewed suggestions (including the full
 * normalized body) are dual-written into the synced `emailMessage` entity/outbox
 * path; acceptance and refunds also write normal transaction entities.
 */
class EmailFeatureController(
  private val context: Context,
  private val userId: String,
  private val repository: EmailRepository,
  val store: EmailFeatureStore,
  private val scope: CoroutineScope,
) : EmailBackgroundWorkProviding {
  private val vault = GmailCredentialVault(context)
  private val openRouterVault = OpenRouterCredentialVault(context)
  private val openRouterClient = OpenRouterClient()
  private val analysisCoordinator = EmailAnalysisCoordinator()

  private val oauthClient: GmailOAuthClient?
  private val tokenManager: GmailAccessTokenManager?
  private val syncCoordinator: EmailSyncCoordinator?

  private var analysisSettings = EmailAnalysisSettings.defaults()
  private var openRouterModels: List<OpenRouterModel> = emptyList()
  private var openRouterConvexTransport: OpenRouterConvexTransporting? = null

  private var accountsJob: Job? = null
  private var suggestionsJob: Job? = null
  private var summariesJob: Job? = null
  private var foregroundWork: Job? = null
  private var analysisWork: Job? = null
  private var pendingAnalysis: Deferred<Int>? = null

  private var accountRecords: List<EmailAccountRecordModel> = emptyList()
  private var suggestionRecords: List<EmailMessageRecordModel> = emptyList()
  private var messageSummaries = emptyList<app.dimo.android.data.model.EmailMessageSummaryModel>()
  private var categories: List<CategoryEntity> = emptyList()
  private var paymentMethods: List<PaymentMethodOption> = emptyList()
  private var transactions: List<Transaction> = emptyList()
  private var currency: Currency = Currency.INR

  @Volatile
  private var stopped = false

  @Volatile
  private var uiScrolling = false

  private var resumeAfterScrollJob: Job? = null
  private var publishJob: Job? = null
  private var pendingPublishAccounts = false
  private var pendingPublishSuggestions = false
  private var pendingPublishEmails = false

  init {
    val configuration = runCatching { GmailOAuthConfiguration.fromAppConfig() }.getOrNull()
    if (configuration == null) {
      oauthClient = null
      tokenManager = null
      syncCoordinator = null
    } else {
      val tokens = GmailAccessTokenManager(configuration, vault)
      oauthClient = GmailOAuthClient(configuration, vault)
      tokenManager = tokens
      syncCoordinator = EmailSyncCoordinator(
        api = GmailRESTClient(tokens),
        persistence = EmailRepositorySyncAdapter(repository),
        scope = scope,
      )
    }
  }

  val isGmailConfigured: Boolean get() = AppConfig.isGmailConfigured && oauthClient != null

  suspend fun start(
    categories: List<CategoryEntity>,
    paymentMethods: List<PaymentMethodOption>,
    transactions: List<Transaction>,
    currency: Currency,
  ) {
    stopped = false
    updateDomain(categories, paymentMethods, transactions, currency)
    configureActions()
    analysisSettings = runCatching { repository.analysisSettings() }.getOrNull()
      ?: EmailAnalysisSettings.defaults()
    publishAnalysisSettings()
    startObservations()
    EmailBackgroundWork.provider = this
    EmailBackgroundWork.schedule(
      context,
      requiresAnalysisNetwork = analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER,
    )

    runCatching { enforceRetention() }.onFailure {
      store.lastActionError = "Email retention cleanup failed: ${it.message}"
    }

    scope.launch {
      if (!stopped) restoreOpenRouterConfiguration()
    }

    if (hasConnectedAccounts()) {
      foregroundWork = scope.launch {
        runCatching { refresh(null) }
        foregroundWork = null
      }
    }
  }

  fun updateDomain(
    categories: List<CategoryEntity>,
    paymentMethods: List<PaymentMethodOption>,
    transactions: List<Transaction>,
    currency: Currency,
  ) {
    this.categories = categories
    this.paymentMethods = paymentMethods
    this.transactions = transactions
    this.currency = currency
    store.categories = categories
    store.paymentMethods = paymentMethods
    store.activeCurrency = currency
    publishSuggestions()
  }

  /** Soft-pauses analysis while the user is actively scrolling. */
  fun setUIScrolling(scrolling: Boolean) {
    uiScrolling = scrolling
    resumeAfterScrollJob?.cancel()
    if (scrolling) return
    resumeAfterScrollJob = scope.launch {
      delay(300)
      if (!stopped && !uiScrolling) resumeAnalysisIfNeeded()
    }
  }

  private suspend fun waitWhileUIScrolling() {
    while (uiScrolling) {
      coroutineContext.ensureActive()
      delay(50)
    }
  }

  suspend fun tearDown() {
    stopped = true
    uiScrolling = false
    resumeAfterScrollJob?.cancel()
    publishJob?.cancel()
    pendingPublishAccounts = false
    pendingPublishSuggestions = false
    pendingPublishEmails = false
    foregroundWork?.cancel()
    analysisWork?.cancelAndJoinQuietly()
    analysisWork = null
    pendingAnalysis?.cancelAndJoinQuietly()
    pendingAnalysis = null
    accountsJob?.cancel()
    suggestionsJob?.cancel()
    summariesJob?.cancel()
    syncCoordinator?.stop()
    analysisCoordinator.removeAll()
    tokenManager?.clearAll()
    // Credentials are per Dimo user; a torn-down controller must not leave a
    // usable Gmail grant behind for the next signed-in account.
    runCatching { vault.removeAll(userId) }
    runCatching { openRouterVault.remove(userId) }
    if (EmailBackgroundWork.provider === this) EmailBackgroundWork.provider = null
    EmailBackgroundWork.cancel(context)
  }

  /** Called when the app returns to the foreground. */
  fun appBecameActive() {
    if (foregroundWork?.isActive == true) return
    val mostRecentAttempt = accountRecords.mapNotNull { it.lastAttemptAt }.maxOrNull() ?: 0
    val stale = System.currentTimeMillis() - mostRecentAttempt > STALE_REFRESH_MS
    if (!stale || !hasConnectedAccounts()) return
    foregroundWork = scope.launch {
      runCatching { refresh(null) }
      foregroundWork = null
    }
  }

  // MARK: - Background entry points (called by the WorkManager workers)

  override suspend fun performBackgroundRefresh(): Boolean {
    val coordinator = syncCoordinator ?: return !hasConnectedAccounts()
    return try {
      val incremental = repository.accounts().filter {
        it.syncState != EmailAccountSyncState.DISCONNECTED &&
          it.syncState != EmailAccountSyncState.NEEDS_RECONNECT &&
          it.backfillCompletedAt != null &&
          it.historyId != null
      }
      for (account in incremental) {
        coroutineContext.ensureActive()
        coordinator.refresh(userId, account.id, analysisSettings.syncWindow)
      }
      enforceRetention()
      true
    } catch (_: CancellationException) {
      throw CancellationException("Background refresh cancelled")
    } catch (_: Exception) {
      false
    }
  }

  override suspend fun performBackgroundAnalysis(): Boolean {
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) return true
    val retry = runCatching { repository.analysisRetryState() }.getOrNull()
    val notBefore = retry?.notBefore
    // Still inside the backoff window; a run now would only burn the retry.
    if (notBefore != null && notBefore > System.currentTimeMillis()) return true
    return try {
      enforceRetention()
      runPendingAnalysis()
      true
    } catch (_: CancellationException) {
      throw CancellationException("Background analysis cancelled")
    } catch (_: Exception) {
      false
    }
  }

  // MARK: - Actions

  private fun configureActions() {
    store.configure(
      EmailFeatureActions(
        connectAccount = { connectAccount() },
        reconnectAccount = { reconnectAccount(it) },
        disconnectAccount = { disconnectAccount(it) },
        refresh = { refresh(it) },
        dismissSuggestion = { repository.dismissSuggestion(it) },
        dismissSuggestions = { repository.dismissSuggestions(it) },
        restoreSuggestion = { repository.restoreDismissedSuggestion(it) },
        restoreSuggestions = { repository.restoreDismissedSuggestions(it) },
        separateSuggestions = { repository.separateSuggestions(it) },
        linkLateSuggestion = { id, source -> repository.linkLateSuggestion(id, source) },
        keepLateSuggestionSeparate = { repository.keepLateSuggestionSeparate(it) },
        acceptPurchase = { acceptPurchase(it) },
        linkPurchaseToTransaction = { id, transactionId ->
          repository.linkSuggestionToTransaction(id, transactionId)
        },
        applyFullRefund = { id, transactionId -> repository.applyFullRefund(id, transactionId) },
        reanalyzeAllEmails = { reanalyzeAllEmails() },
        saveOpenRouterKey = { saveOpenRouterKey(it) },
        removeOpenRouterKey = { removeOpenRouterKey() },
        refreshOpenRouterModels = { refreshOpenRouterModels() },
        selectOpenRouterModel = { id, allowNonZDR -> selectOpenRouterModel(id, allowNonZDR) },
        selectOpenRouterAccessMode = { selectOpenRouterAccessMode(it) },
        selectProvider = { switchProvider(it) },
        selectSyncWindow = { selectSyncWindow(it) },
        retryAnalysis = { retryAnalysis(it) },
        retryOpenRouterConnection = { retryOpenRouterConnection() },
        retryOpenRouterAnalysis = { retryOpenRouterAnalysis() },
        loadEmailDetail = { loadEmailDetail(it) },
      ),
    )
  }

  private fun startObservations() {
    scope.launch {
      runCatching { repository.reconcilePendingPurchaseGroups() }
      accountRecords = runCatching { repository.accounts() }.getOrDefault(emptyList())
      suggestionRecords = runCatching { repository.suggestions() }.getOrDefault(emptyList())
      messageSummaries = runCatching { repository.messageSummaries() }.getOrDefault(emptyList())
      publishAccounts()
      publishSuggestions()
      publishAllEmails()
    }
    accountsJob = scope.launch {
      repository.observeAccounts().collectLatest { accounts ->
        accountRecords = accounts
        schedulePublish(accounts = true, suggestions = false, emails = true)
      }
    }
    suggestionsJob = scope.launch {
      repository.observeSuggestions().collectLatest { suggestions ->
        suggestionRecords = suggestions
        schedulePublish(accounts = false, suggestions = true, emails = false)
      }
    }
    summariesJob = scope.launch {
      repository.observeMessageSummaries().collectLatest { messages ->
        messageSummaries = messages
        schedulePublish(accounts = false, suggestions = false, emails = true)
      }
    }
  }

  /** Coalesces bursts of database change notifications into one UI publish. */
  private fun schedulePublish(accounts: Boolean, suggestions: Boolean, emails: Boolean) {
    pendingPublishAccounts = pendingPublishAccounts || accounts
    pendingPublishSuggestions = pendingPublishSuggestions || suggestions
    pendingPublishEmails = pendingPublishEmails || emails
    publishJob?.cancel()
    publishJob = scope.launch {
      delay(32)
      val doAccounts = pendingPublishAccounts
      val doSuggestions = pendingPublishSuggestions
      val doEmails = pendingPublishEmails
      pendingPublishAccounts = false
      pendingPublishSuggestions = false
      pendingPublishEmails = false
      if (doAccounts) publishAccounts()
      if (doSuggestions) publishSuggestions()
      if (doEmails) publishAllEmails()
    }
  }

  private suspend fun connectAccount() {
    val client = oauthClient ?: throw EmailFeatureControllerException.GmailNotConfigured
    val account = client.connect(context, userId)
    if (stopped) {
      runCatching { vault.remove(account.subject, userId) }
      throw CancellationException("Email feature stopped")
    }
    try {
      val existing = repository.account(account.subject)
      repository.saveAccount(
        EmailAccountRecordModel(
          id = account.subject,
          emailAddress = account.emailAddress,
          historyId = existing?.historyId,
          backfillPageToken = existing?.backfillPageToken,
          backfillCompletedAt = existing?.backfillCompletedAt,
          lastAttemptAt = existing?.lastAttemptAt,
          lastSuccessfulSyncAt = existing?.lastSuccessfulSyncAt,
          syncState = EmailAccountSyncState.IDLE,
          createdAt = existing?.createdAt ?: account.connectedAt,
        ),
      )
      repository.materializeSyncedMessages(account.subject)
    } catch (error: Exception) {
      // Never leave a stored grant for an account the database rejected.
      runCatching { vault.remove(account.subject, userId) }
      throw error
    }
    refresh(account.subject)
  }

  /**
   * Replaces a dead Gmail refresh token in place. Local messages, reviewed
   * suggestions and sync cursors are preserved.
   */
  private suspend fun reconnectAccount(accountId: String) {
    val client = oauthClient ?: throw EmailFeatureControllerException.GmailNotConfigured
    val existing = repository.account(accountId)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.ACCOUNT_NOT_FOUND)
    val account = client.reauthorize(context, accountId, existing.emailAddress, userId)
    if (stopped) throw CancellationException("Email feature stopped")
    tokenManager?.invalidate(accountId)
    repository.updateAccount(accountId) {
      it.copy(
        emailAddress = account.emailAddress,
        syncState = EmailAccountSyncState.IDLE,
        lastError = null,
      )
    }
    refresh(accountId)
  }

  private suspend fun disconnectAccount(accountId: String) {
    if (oauthClient != null) {
      oauthClient.disconnect(accountId, userId)
    } else {
      vault.remove(accountId, userId)
    }
    tokenManager?.invalidate(accountId)
    repository.deleteAccount(accountId)
  }

  private suspend fun refresh(accountId: String?) {
    val coordinator = syncCoordinator
      ?: throw EmailFeatureControllerException.GmailNotConfigured
    coroutineContext.ensureActive()
    if (stopped) throw CancellationException("Email feature stopped")
    coordinator.refresh(userId, accountId, analysisSettings.syncWindow)
    coroutineContext.ensureActive()
    if (stopped) throw CancellationException("Email feature stopped")
    enforceRetention()
    runPendingAnalysis()
  }

  private suspend fun enforceRetention(now: Long = System.currentTimeMillis()) {
    val cutoff = analysisSettings.syncWindow.cutoff(now)
    repository.expireMessages(cutoff)
    repository.purgeMessages(cutoff)
    repository.purgeReviewedBodies()
  }

  // MARK: - Analysis queue

  private suspend fun runPendingAnalysis(maximumCount: Int? = null): Int {
    pendingAnalysis?.let { return runCatching { it.await() }.getOrDefault(0) }
    val task = scope.async { analyzePending(maximumCount) }
    pendingAnalysis = task
    return try {
      task.await()
    } finally {
      if (pendingAnalysis === task) pendingAnalysis = null
    }
  }

  /** Round-robins one message per account so a large inbox cannot starve others. */
  private suspend fun analyzePending(maximumCount: Int? = null): Int {
    val accountIds = repository.accounts().map { it.id }
    if (accountIds.isEmpty()) return 0
    if (maximumCount != null && maximumCount <= 0) return 0
    var analyzed = 0
    var madeProgress = true
    while (madeProgress && !stopped && coroutineContext.isActiveSafe()) {
      if (maximumCount != null && analyzed >= maximumCount) break
      madeProgress = false
      for (accountId in accountIds) {
        if (maximumCount != null && analyzed >= maximumCount) break
        coroutineContext.ensureActive()
        waitWhileUIScrolling()
        val message = repository.messagesPendingAnalysis(accountId, limit = 1).firstOrNull()
          ?: continue
        if (analyze(message) != AnalysisAttemptOutcome.PROCESSED) return analyzed
        analyzed += 1
        madeProgress = true
      }
    }
    return analyzed
  }

  private suspend fun analyze(message: EmailMessageRecordModel): AnalysisAttemptOutcome {
    val body = message.normalizedBodyText
    if (body == null) {
      repository.markSuggestionUnactionable(message.key)
      return AnalysisAttemptOutcome.PROCESSED
    }
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) {
      store.analysisStatusDetail = EmailFeatureControllerException.AnalysisNotConfigured.message!!
      return AnalysisAttemptOutcome.PAUSED
    }
    val request = makeAnalysisRequest(message, body)

    return try {
      val retry = repository.analysisRetryState()
      val notBefore = retry?.notBefore
      if (notBefore != null && notBefore > System.currentTimeMillis()) {
        store.analysisStatusDetail = retry.reason ?: "OpenRouter analysis is waiting to retry."
        return AnalysisAttemptOutcome.PAUSED
      }
      val analyzer = preparedOpenRouterAnalyzer()
      if (analyzer == null) {
        store.analysisStatusDetail =
          EmailFeatureControllerException.OpenRouterNotConfigured.message!!
        return AnalysisAttemptOutcome.PAUSED
      }
      EmailAnalysisStartThrottle.waitForNextStart()
      val envelope = analyzer.analyze(request)
      repository.clearAnalysisRetryState()
      coroutineContext.ensureActive()
      if (stopped) throw CancellationException("Email feature stopped")
      repository.saveAnalysis(message.key, persisted(envelope))
      store.analysisStatusDetail = "Analysis complete."
      AnalysisAttemptOutcome.PROCESSED
    } catch (error: CancellationException) {
      throw error
    } catch (error: OpenRouterClientException) {
      handleOpenRouterAnalysisFailure(message, error)
    } catch (error: Exception) {
      Log.e(TAG, "Email analysis failure; model=${analysisSettings.openRouterModelId}", error)
      repository.markAnalysisFailed(
        message.key,
        EmailAnalyzerKind.OPEN_ROUTER,
        analysisSettings.openRouterModelId,
      )
      store.analysisStatusDetail = "Analysis failed"
      AnalysisAttemptOutcome.PROCESSED
    }
  }

  private suspend fun handleOpenRouterAnalysisFailure(
    message: EmailMessageRecordModel,
    error: OpenRouterClientException,
  ): AnalysisAttemptOutcome {
    if (error.isTransient) {
      // A transient failure parks the whole queue on a backoff rather than
      // burning through every queued message against a failing provider.
      scheduleOpenRouterRetry(error)
      store.analysisStatusDetail = error.message.orEmpty()
      return AnalysisAttemptOutcome.PAUSED
    }
    return when (error) {
      is OpenRouterClientException.InvalidKey -> {
        store.analysisStatusDetail = error.message.orEmpty()
        store.openRouterConnectionState =
          OpenRouterUIConnectionState.Failed(error.message.orEmpty())
        AnalysisAttemptOutcome.PAUSED
      }

      is OpenRouterClientException.Forbidden,
      is OpenRouterClientException.InsufficientCredits,
      -> {
        store.analysisStatusDetail = error.message.orEmpty()
        AnalysisAttemptOutcome.PAUSED
      }

      is OpenRouterClientException.ModelUnavailable -> {
        repository.clearAnalysisRetryState()
        store.analysisStatusDetail =
          "The selected OpenRouter model is unavailable. Choose another model in Email settings."
        AnalysisAttemptOutcome.PAUSED
      }

      else -> {
        repository.markAnalysisFailed(
          message.key,
          EmailAnalyzerKind.OPEN_ROUTER,
          analysisSettings.openRouterModelId,
        )
        store.analysisStatusDetail = "Analysis failed"
        AnalysisAttemptOutcome.PROCESSED
      }
    }
  }

  private fun makeAnalysisRequest(
    message: EmailMessageRecordModel,
    body: String,
  ): EmailAnalysisRequest = EmailAnalysisRequest(
    messageId = message.gmailMessageId,
    accountSubject = message.accountId,
    senderName = message.senderName,
    senderAddress = message.senderAddress,
    subject = message.subject,
    receivedAt = message.internalDate,
    normalizedBody = body,
    categories = categories.map { EmailCategoryOption(it.id, it.name) },
    paymentMethods = paymentMethods.map {
      EmailPaymentMethodHint(
        id = it.id,
        label = it.label,
        lastFour = lastFour(it.detail + " " + it.name),
        archived = it.archived,
      )
    },
    merchantHistory = merchantHistory(),
    activeCurrency = currency,
  )

  /** Up to 40 distinct merchant→category pairs the user has already confirmed. */
  private fun merchantHistory(): List<EmailMerchantCategoryHint> {
    val seen = mutableSetOf<String>()
    val hints = mutableListOf<EmailMerchantCategoryHint>()
    for (transaction in transactions) {
      val key = EmailSuggestionSelectors.fold(transaction.name).trim()
      val categoryId = transaction.categoryId
      if (key.isEmpty() || categoryId == null || !seen.add(key)) continue
      hints.add(EmailMerchantCategoryHint(transaction.name, categoryId))
      if (hints.size == 40) break
    }
    return hints
  }

  private fun persisted(envelope: EmailAnalysisEnvelope) =
    app.dimo.android.data.model.PersistedEmailAnalysis(
      analyzerType = if (envelope.analyzer == EmailAnalyzerType.GEMMA) {
        EmailAnalyzerKind.GEMMA
      } else {
        EmailAnalyzerKind.OPEN_ROUTER
      },
      modelVersion = envelope.modelId,
      promptVersion = EmailAnalysisResult.SCHEMA_VERSION,
      classification = EmailMessageClassification.fromWire(envelope.result.kind.wire)
        ?: EmailMessageClassification.IRRELEVANT,
      merchant = envelope.result.merchant,
      amount = envelope.result.amount?.toPlainString(),
      currency = envelope.result.currency,
      occurredAt = envelope.result.occurredAt,
      categoryId = envelope.result.categoryId,
      paymentMethodId = envelope.result.paymentMethodId,
      paymentLastFour = envelope.result.paymentLastFour,
      reference = envelope.result.reference,
    )

  // MARK: - OpenRouter configuration

  /** Attach the authenticated Convex client once sync login succeeds. */
  fun attachOpenRouterConvexTransport(transport: OpenRouterConvexTransporting?) {
    openRouterConvexTransport = transport
    if (analysisSettings.openRouterAccessMode != OpenRouterAccessMode.FREE_SHARED) return
    scope.launch { restoreOpenRouterConfiguration() }
  }

  private suspend fun preparedOpenRouterAnalyzer(): EmailAnalysisProviding? {
    val modelId = analysisSettings.openRouterModelId ?: return null
    val model = openRouterModels.firstOrNull { it.id == modelId }
      ?: throw OpenRouterClientException.ModelUnavailable
    if (analysisSettings.openRouterPrivacyMode == OpenRouterPrivacyMode.ZDR_ONLY &&
      !model.hasZDREndpoint
    ) {
      throw OpenRouterClientException.ModelUnavailable
    }

    return when (analysisSettings.openRouterAccessMode) {
      OpenRouterAccessMode.FREE_SHARED -> {
        if (!model.isFree) throw OpenRouterClientException.ModelUnavailable
        val transport = openRouterConvexTransport
          ?: throw OpenRouterConvexTransportException.NotReady.asClientException()
        ConvexFreeOpenRouterEmailAnalyzer(
          transport,
          model,
          analysisSettings.openRouterPrivacyMode,
        ).also { analysisCoordinator.set(it, EmailAnalysisProvider.OPEN_ROUTER) }
      }

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> {
        val credential = openRouterVault.credential(userId) ?: return null
        OpenRouterEmailAnalyzer(
          openRouterClient,
          model,
          analysisSettings.openRouterPrivacyMode,
          credential.apiKey,
        ).also { analysisCoordinator.set(it, EmailAnalysisProvider.OPEN_ROUTER) }
      }
    }
  }

  private suspend fun restoreOpenRouterConfiguration() {
    when (analysisSettings.openRouterAccessMode) {
      OpenRouterAccessMode.FREE_SHARED -> restoreFreeOpenRouterConfiguration()
      OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> restoreBYOKOpenRouterConfiguration()
    }
  }

  private suspend fun restoreFreeOpenRouterConfiguration() {
    val transport = openRouterConvexTransport
    if (transport == null) {
      store.openRouterConnectionState = OpenRouterUIConnectionState.Disconnected
      if (analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
        store.analysisStatusDetail =
          OpenRouterConvexTransportException.NotReady.message.orEmpty()
      }
      return
    }
    store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
    try {
      val models = transport.listFreeModels()
      openRouterModels = models
      store.openRouterModels = models
      store.openRouterConnectionState =
        OpenRouterUIConnectionState.Connected("Free models", null, null)
      ensureDefaultFreeModelSelection(models)
      val selected = analysisSettings.openRouterModelId
      if (selected != null && models.none { it.id == selected }) {
        store.analysisStatusDetail = MODEL_GONE
      }
      publishAnalysisSettings()
    } catch (error: Exception) {
      val message = error.message ?: "OpenRouter is unavailable."
      store.openRouterConnectionState = OpenRouterUIConnectionState.Failed(message)
      if (analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
        store.analysisStatusDetail = message
      }
    }
  }

  private suspend fun restoreBYOKOpenRouterConfiguration() {
    try {
      val credential = openRouterVault.credential(userId)
      if (credential == null) {
        store.openRouterConnectionState = OpenRouterUIConnectionState.Disconnected
        return
      }
      store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
      val keyInfo = openRouterClient.validateKey(credential.apiKey)
      openRouterModels = openRouterClient.models(credential.apiKey)
      store.openRouterModels = openRouterModels
      store.openRouterConnectionState = OpenRouterUIConnectionState.Connected(
        keyInfo.label,
        keyInfo.limit,
        keyInfo.limitRemaining,
      )
      // A 404 backoff was recorded against a model that no longer exists; the
      // key works, so clear it and tell the user to pick another model.
      if (repository.analysisRetryState()?.lastHttpStatus == 404) {
        repository.clearAnalysisRetryState()
        store.analysisStatusDetail = MODEL_UNAVAILABLE
      }
      val selected = analysisSettings.openRouterModelId
      if (selected != null && openRouterModels.none { it.id == selected }) {
        store.analysisStatusDetail = MODEL_GONE
      }
    } catch (error: Exception) {
      val message = error.message ?: "OpenRouter is unavailable."
      store.openRouterConnectionState = OpenRouterUIConnectionState.Failed(message)
      if (analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
        store.analysisStatusDetail = message
      }
    }
  }

  private suspend fun ensureDefaultFreeModelSelection(models: List<OpenRouterModel>) {
    val selected = analysisSettings.openRouterModelId
    if (selected != null && models.any { it.id == selected && it.isFree }) {
      rememberModelSelection(selected, OpenRouterAccessMode.FREE_SHARED)
      saveAnalysisSettings()
      return
    }
    val remembered = analysisSettings.lastFreeOpenRouterModelId
    if (remembered != null && models.any { it.id == remembered && it.isFree }) {
      analysisSettings = analysisSettings.copy(openRouterModelId = remembered)
      saveAnalysisSettings()
      return
    }
    if (models.any { it.id == OpenRouterClient.DEFAULT_FREE_MODEL_ID }) {
      analysisSettings =
        analysisSettings.copy(openRouterModelId = OpenRouterClient.DEFAULT_FREE_MODEL_ID)
      rememberModelSelection(
        OpenRouterClient.DEFAULT_FREE_MODEL_ID,
        OpenRouterAccessMode.FREE_SHARED,
      )
      saveAnalysisSettings()
      return
    }
    models.firstOrNull { it.isFree }?.let { firstFree ->
      analysisSettings = analysisSettings.copy(openRouterModelId = firstFree.id)
      rememberModelSelection(firstFree.id, OpenRouterAccessMode.FREE_SHARED)
      saveAnalysisSettings()
    }
  }

  private fun rememberModelSelection(modelId: String?, mode: OpenRouterAccessMode) {
    if (modelId == null) return
    analysisSettings = when (mode) {
      OpenRouterAccessMode.FREE_SHARED ->
        analysisSettings.copy(lastFreeOpenRouterModelId = modelId)

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY ->
        analysisSettings.copy(lastBYOKOpenRouterModelId = modelId)
    }
  }

  private fun rememberPrivacySelection(
    privacyMode: OpenRouterPrivacyMode,
    consentVersion: Int?,
    mode: OpenRouterAccessMode,
  ) {
    analysisSettings = when (mode) {
      OpenRouterAccessMode.FREE_SHARED -> analysisSettings.copy(
        lastFreeOpenRouterPrivacyMode = privacyMode,
        lastFreeNonZDRConsentVersion = consentVersion,
      )

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> analysisSettings.copy(
        lastBYOKOpenRouterPrivacyMode = privacyMode,
        lastBYOKNonZDRConsentVersion = consentVersion,
      )
    }
  }

  private fun restorePrivacySelection(mode: OpenRouterAccessMode) {
    analysisSettings = when (mode) {
      OpenRouterAccessMode.FREE_SHARED -> analysisSettings.copy(
        openRouterPrivacyMode = analysisSettings.lastFreeOpenRouterPrivacyMode,
        nonZDRConsentVersion = analysisSettings.lastFreeNonZDRConsentVersion,
      )

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> analysisSettings.copy(
        openRouterPrivacyMode = analysisSettings.lastBYOKOpenRouterPrivacyMode,
        nonZDRConsentVersion = analysisSettings.lastBYOKNonZDRConsentVersion,
      )
    }
  }

  private suspend fun selectOpenRouterAccessMode(mode: OpenRouterAccessMode) {
    if (analysisSettings.openRouterAccessMode == mode) return
    cancelAnalysisWork()
    analysisCoordinator.set(null, EmailAnalysisProvider.OPEN_ROUTER)
    repository.clearAnalysisRetryState()

    val previousMode = analysisSettings.openRouterAccessMode
    // Remember model + ZDR preference for the mode being left.
    rememberModelSelection(analysisSettings.openRouterModelId, previousMode)
    rememberPrivacySelection(
      analysisSettings.openRouterPrivacyMode,
      analysisSettings.nonZDRConsentVersion,
      previousMode,
    )

    analysisSettings = analysisSettings.copy(openRouterAccessMode = mode)
    analysisSettings = analysisSettings.copy(
      openRouterModelId = when (mode) {
        OpenRouterAccessMode.FREE_SHARED -> analysisSettings.lastFreeOpenRouterModelId
        OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> analysisSettings.lastBYOKOpenRouterModelId
      },
    )
    restorePrivacySelection(mode)

    saveAnalysisSettings()
    publishAnalysisSettings()
    openRouterModels = emptyList()
    store.openRouterModels = emptyList()
    store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
    restoreOpenRouterConfiguration()
    activateRestoredOpenRouterModeIfPossible()
  }

  /**
   * After a Free/BYOK switch, keep analysis active when the restored model and
   * privacy settings are compatible with the new catalog — otherwise the user has
   * to tap "Use OpenRouter" again after every mode change.
   */
  private suspend fun activateRestoredOpenRouterModeIfPossible() {
    suspend fun deactivate(status: String? = null) {
      analysisSettings = analysisSettings.copy(selectedProvider = null)
      runCatching { saveAnalysisSettings() }
      publishAnalysisSettings()
      if (status != null) store.analysisStatusDetail = status
    }

    if (store.openRouterConnectionState !is OpenRouterUIConnectionState.Connected) {
      return deactivate()
    }
    val modelId = analysisSettings.openRouterModelId ?: return deactivate()
    val model = openRouterModels.firstOrNull { it.id == modelId } ?: return deactivate()
    if (analysisSettings.openRouterAccessMode == OpenRouterAccessMode.FREE_SHARED &&
      !model.isFree
    ) {
      return deactivate()
    }
    if (analysisSettings.openRouterPrivacyMode == OpenRouterPrivacyMode.ZDR_ONLY &&
      !model.hasZDREndpoint
    ) {
      return deactivate("Confirm non-ZDR use for this model, or choose a ZDR model.")
    }

    analysisSettings = analysisSettings.copy(
      selectedProvider = EmailAnalysisProvider.OPEN_ROUTER,
    )
    runCatching { saveAnalysisSettings() }
    publishAnalysisSettings()
    EmailBackgroundWork.scheduleAnalysis(context, requiresNetwork = true)
    startAnalysisWork()
  }

  private suspend fun saveOpenRouterKey(apiKey: String) {
    analysisSettings =
      analysisSettings.copy(openRouterAccessMode = OpenRouterAccessMode.BRING_YOUR_OWN_KEY)
    saveAnalysisSettings()
    val trimmed = apiKey.trim()
    store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
    try {
      val info = openRouterClient.validateKey(trimmed)
      val models = openRouterClient.models(trimmed)
      openRouterVault.save(trimmed, userId)
      openRouterModels = models
      store.openRouterModels = models
      store.openRouterConnectionState =
        OpenRouterUIConnectionState.Connected(info.label, info.limit, info.limitRemaining)
      if (analysisSettings.openRouterModelId == null) {
        val remembered = analysisSettings.lastBYOKOpenRouterModelId
        val fallback = when {
          remembered != null && models.any { it.id == remembered } -> remembered
          models.any { it.id == OpenRouterClient.DEFAULT_BYOK_MODEL_ID } ->
            OpenRouterClient.DEFAULT_BYOK_MODEL_ID

          else -> null
        }
        if (fallback != null) {
          analysisSettings = analysisSettings.copy(openRouterModelId = fallback)
          rememberModelSelection(fallback, OpenRouterAccessMode.BRING_YOUR_OWN_KEY)
          saveAnalysisSettings()
        }
      } else {
        rememberModelSelection(
          analysisSettings.openRouterModelId,
          OpenRouterAccessMode.BRING_YOUR_OWN_KEY,
        )
        saveAnalysisSettings()
      }
      publishAnalysisSettings()
    } catch (error: Exception) {
      store.openRouterConnectionState =
        OpenRouterUIConnectionState.Failed(error.message ?: "The OpenRouter key was rejected.")
      throw error
    }
  }

  private suspend fun removeOpenRouterKey() {
    val next = if (analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
      null
    } else {
      analysisSettings.selectedProvider
    }
    switchProvider(next)
    openRouterVault.remove(userId)
    if (analysisSettings.openRouterAccessMode == OpenRouterAccessMode.BRING_YOUR_OWN_KEY) {
      openRouterModels = emptyList()
      store.openRouterModels = emptyList()
      store.openRouterConnectionState = OpenRouterUIConnectionState.Disconnected
    }
    analysisCoordinator.set(null, EmailAnalysisProvider.OPEN_ROUTER)
  }

  private suspend fun refreshOpenRouterModels() {
    when (analysisSettings.openRouterAccessMode) {
      OpenRouterAccessMode.FREE_SHARED -> {
        val transport = openRouterConvexTransport
          ?: throw OpenRouterConvexTransportException.NotReady
        store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
        val models = transport.listFreeModels()
        openRouterModels = models
        store.openRouterModels = models
        store.openRouterConnectionState =
          OpenRouterUIConnectionState.Connected("Free models", null, null)
        ensureDefaultFreeModelSelection(models)
        publishAnalysisSettings()
        val selected = analysisSettings.openRouterModelId
        if (selected != null && models.none { it.id == selected }) {
          store.analysisStatusDetail = MODEL_GONE
        }
      }

      OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> {
        val credential = openRouterVault.credential(userId)
          ?: throw EmailFeatureControllerException.OpenRouterNotConfigured
        val info = openRouterClient.validateKey(credential.apiKey)
        openRouterModels = openRouterClient.models(credential.apiKey)
        store.openRouterModels = openRouterModels
        store.openRouterConnectionState =
          OpenRouterUIConnectionState.Connected(info.label, info.limit, info.limitRemaining)
        val selected = analysisSettings.openRouterModelId
        if (selected != null && openRouterModels.none { it.id == selected }) {
          store.analysisStatusDetail = MODEL_GONE
        }
      }
    }
  }

  private suspend fun selectOpenRouterModel(modelId: String, allowNonZDR: Boolean) {
    val model = openRouterModels.firstOrNull { it.id == modelId }
      ?: throw EmailFeatureControllerException.OpenRouterNotConfigured
    if (analysisSettings.openRouterAccessMode == OpenRouterAccessMode.FREE_SHARED &&
      !model.isFree
    ) {
      throw EmailFeatureControllerException.OpenRouterNotConfigured
    }
    if (!model.hasZDREndpoint && !allowNonZDR) {
      throw EmailFeatureControllerException.NonZDRConsentRequired
    }

    val privacyMode = if (model.hasZDREndpoint && !allowNonZDR) {
      OpenRouterPrivacyMode.ZDR_ONLY
    } else {
      OpenRouterPrivacyMode.ALLOW_NON_ZDR
    }
    val consentVersion = if (allowNonZDR) 1 else null
    val alreadyOnOpenRouter =
      analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER
    val unchanged = alreadyOnOpenRouter &&
      analysisSettings.openRouterModelId == model.id &&
      analysisSettings.openRouterPrivacyMode == privacyMode &&
      analysisSettings.nonZDRConsentVersion == consentVersion

    analysisSettings = analysisSettings.copy(
      openRouterModelId = model.id,
      openRouterPrivacyMode = privacyMode,
      nonZDRConsentVersion = consentVersion,
    )
    rememberModelSelection(model.id, analysisSettings.openRouterAccessMode)
    rememberPrivacySelection(
      privacyMode,
      consentVersion,
      analysisSettings.openRouterAccessMode,
    )

    if (unchanged) {
      runCatching { saveAnalysisSettings() }
      publishAnalysisSettings()
      return
    }
    if (alreadyOnOpenRouter) {
      saveAnalysisSettings()
      publishAnalysisSettings()
      // Force the next analysis to rebuild the analyzer against the new model.
      analysisCoordinator.set(null, EmailAnalysisProvider.OPEN_ROUTER)
      return
    }
    switchProvider(EmailAnalysisProvider.OPEN_ROUTER)
  }

  private suspend fun selectSyncWindow(window: EmailSyncWindow) {
    if (analysisSettings.syncWindow == window) return
    syncCoordinator?.stop()
    val previous = analysisSettings.syncWindow
    analysisSettings = analysisSettings.copy(syncWindow = window)
    try {
      saveAnalysisSettings()
      enforceRetention()

      // A different window means a different scan range, so every cursor resets.
      val accounts = repository.accounts()
      for (account in accounts) {
        repository.updateAccount(account.id) {
          it.copy(
            historyId = null,
            backfillPageToken = null,
            backfillCompletedAt = null,
            syncState = EmailAccountSyncState.BACKFILLING,
            lastError = null,
          )
        }
      }
      publishAnalysisSettings()
      if (accounts.isEmpty()) return
      refresh(null)
    } catch (error: Exception) {
      analysisSettings = analysisSettings.copy(syncWindow = previous)
      runCatching { saveAnalysisSettings() }
      publishAnalysisSettings()
      throw error
    }
  }

  private suspend fun switchProvider(provider: EmailAnalysisProvider?) {
    if (analysisSettings.selectedProvider == provider) return
    cancelAnalysisWork()
    analysisCoordinator.set(null, EmailAnalysisProvider.OPEN_ROUTER)
    repository.clearAnalysisRetryState()
    analysisSettings = analysisSettings.copy(selectedProvider = provider)
    saveAnalysisSettings()
    publishAnalysisSettings()
    EmailBackgroundWork.scheduleAnalysis(
      context,
      requiresNetwork = provider == EmailAnalysisProvider.OPEN_ROUTER,
    )
    if (provider == null) return
    startAnalysisWork()
  }

  private suspend fun retryAnalysis(messageId: String) {
    val message = repository.message(messageId)
    if (message == null || message.state != EmailSuggestionState.ANALYSIS_FAILED) {
      throw EmailRepositoryException(EmailRepositoryException.Kind.INVALID_SUGGESTION_STATE)
    }
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) {
      throw EmailFeatureControllerException.AnalysisNotConfigured
    }
    preparedOpenRouterAnalyzer() ?: throw EmailFeatureControllerException.OpenRouterNotConfigured
    repository.clearAnalysisRetryState()
    repository.retryAnalysis(messageId, EmailAnalysisProvider.OPEN_ROUTER)
    refreshEmailUIFromRepository()
    runPendingAnalysis(maximumCount = 1)
  }

  private suspend fun retryOpenRouterConnection() {
    store.openRouterConnectionState = OpenRouterUIConnectionState.Validating
    try {
      refreshOpenRouterModels()
      repository.clearAnalysisRetryState()
      publishAnalysisSettings()
      resumeOpenRouterAnalysisQueue()
    } catch (error: Exception) {
      val message = error.message ?: "OpenRouter is unavailable."
      store.openRouterConnectionState = OpenRouterUIConnectionState.Failed(message)
      if (analysisSettings.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
        store.analysisStatusDetail = message
      }
      throw error
    }
  }

  private suspend fun retryOpenRouterAnalysis() {
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) {
      throw EmailFeatureControllerException.OpenRouterNotConfigured
    }
    preparedOpenRouterAnalyzer() ?: throw EmailFeatureControllerException.OpenRouterNotConfigured
    repository.clearAnalysisRetryState()
    store.analysisStatusDetail = "Retrying OpenRouter analysis…"
    resumeOpenRouterAnalysisQueue()
  }

  private suspend fun resumeOpenRouterAnalysisQueue() {
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) return
    cancelAnalysisWork()
    runPendingAnalysis()
  }

  private suspend fun reanalyzeAllEmails() {
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) {
      throw EmailFeatureControllerException.AnalysisNotConfigured
    }
    preparedOpenRouterAnalyzer() ?: throw EmailFeatureControllerException.OpenRouterNotConfigured
    cancelAnalysisWork()
    repository.clearAnalysisRetryState()

    val resetCount = repository.resetMessagesForReanalysis()
    refreshEmailUIFromRepository()
    if (resetCount == 0) return
    runPendingAnalysis()
  }

  private suspend fun refreshEmailUIFromRepository() {
    suggestionRecords = repository.suggestions()
    messageSummaries = repository.messageSummaries()
    store.purchaseReview = null
    store.refundReview = null
    store.emailDetail = null
    publishSuggestions()
    publishAllEmails()
  }

  private fun resumeAnalysisIfNeeded() {
    if (stopped) return
    if (analysisSettings.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER) return
    if (analysisWork?.isActive == true || pendingAnalysis?.isActive == true) return
    startAnalysisWork()
  }

  private fun startAnalysisWork() {
    analysisWork = scope.launch {
      runCatching { runPendingAnalysis() }
      analysisWork = null
    }
  }

  private suspend fun cancelAnalysisWork() {
    analysisWork?.cancelAndJoinQuietly()
    analysisWork = null
    pendingAnalysis?.cancelAndJoinQuietly()
    pendingAnalysis = null
  }

  private suspend fun saveAnalysisSettings() {
    analysisSettings = analysisSettings.copy(updatedAt = System.currentTimeMillis())
    repository.saveAnalysisSettings(analysisSettings)
  }

  private fun publishAnalysisSettings() {
    store.selectedProvider = analysisSettings.selectedProvider
    store.openRouterAccessMode = analysisSettings.openRouterAccessMode
    store.selectedOpenRouterModelId = analysisSettings.openRouterModelId
    store.openRouterPrivacyMode = analysisSettings.openRouterPrivacyMode
    store.syncWindow = analysisSettings.syncWindow
    store.analysisStatusDetail = when (analysisSettings.selectedProvider) {
      EmailAnalysisProvider.OPEN_ROUTER -> {
        val modeLabel =
          if (analysisSettings.openRouterAccessMode == OpenRouterAccessMode.FREE_SHARED) {
            "OpenRouter Free"
          } else {
            "OpenRouter"
          }
        analysisSettings.openRouterModelId?.let { "$modeLabel · $it" }
          ?: "Choose an OpenRouter model."
      }

      null -> EmailFeatureStore.UNCONFIGURED_STATUS
    }
  }

  /** Exponential backoff, honouring a server-supplied Retry-After when present. */
  private suspend fun scheduleOpenRouterRetry(error: OpenRouterClientException) {
    val previous = repository.analysisRetryState()
    val attempt = minOf((previous?.attempt ?: 0) + 1, 6)
    val fallbackDelays = listOf(900.0, 1_800.0, 3_600.0, 7_200.0, 14_400.0, 21_600.0)
    val base = error.retryAfterHint ?: fallbackDelays[attempt - 1]
    val jitter = if (error.retryAfterHint == null) Random.nextDouble(0.0, base * 0.1) else 0.0
    val notBefore = System.currentTimeMillis() + ((base + jitter) * 1000).toLong()
    repository.saveAnalysisRetryState(
      EmailAnalysisRetryState(
        attempt = attempt,
        notBefore = notBefore,
        reason = error.message,
        lastHttpStatus = error.statusCode,
        updatedAt = System.currentTimeMillis(),
      ),
    )
    EmailBackgroundWork.scheduleAnalysis(
      context,
      requiresNetwork = true,
      earliestMillis = notBefore,
    )
  }

  private fun hasConnectedAccounts(): Boolean =
    accountRecords.any { it.syncState != EmailAccountSyncState.DISCONNECTED }

  private suspend fun acceptPurchase(draft: EmailUIPurchaseReviewDraft) {
    val amount = runCatching { BigDecimal(draft.amount.trim()) }.getOrNull()
    val amountMinor = amount?.let(::minorUnits)
    val categoryId = draft.categoryId
    val category = categories.firstOrNull { it.id == categoryId }
    if (amountMinor == null || amountMinor <= 0 || categoryId == null || category == null) {
      throw EmailFeatureControllerException.InvalidSuggestion
    }
    val merchant = draft.merchant.trim()
    val paymentMethodId = resolvedPaymentMethodId(draft.paymentMethodId, paymentMethods)
    val transaction = TransactionEntity(
      id = "tx_${UUID.randomUUID().toString().lowercase()}",
      name = merchant.ifEmpty { category.name },
      amountMinor = amountMinor,
      // An email can be dated slightly ahead of the device clock; never write a
      // future-dated expense.
      occurredAt = minOf(draft.occurredAt, System.currentTimeMillis()),
      categoryId = categoryId,
      paymentMethodId = paymentMethodId,
      currency = currency.wire,
    )
    val recurring = if (draft.isRecurring) {
      RecurringEntity(
        id = "rec_${UUID.randomUUID().toString().lowercase()}",
        name = transaction.name,
        amountMinor = amountMinor,
        categoryId = categoryId,
        paymentMethodId = paymentMethodId,
        frequency = draft.recurringFrequency,
        anchorDate = DateHelpers.localDateKey(draft.occurredAt),
        paused = false,
        currency = currency.wire,
      )
    } else {
      null
    }
    val sourceIds = draft.sourceMessageIds.ifEmpty { listOf(draft.suggestionId) }
    repository.acceptSuggestions(sourceIds, transaction, recurring)
  }

  // MARK: - Publishing

  private fun publishAccounts() {
    store.accounts = accountRecords.map { account ->
      EmailUIAccount(
        id = account.id,
        emailAddress = account.emailAddress,
        syncState = uiSyncState(account.syncState),
        statusDetail = accountStatusDetail(account),
        lastSuccessfulSyncAt = account.lastSuccessfulSyncAt,
        lastError = account.lastError,
        initialScanComplete = account.backfillCompletedAt != null,
      )
    }
  }

  private fun publishSuggestions() {
    val accountEmail = accountRecords.associate { it.id to it.emailAddress }
    val categoryNames = categories.associate { it.id to it.name }
    val methods = paymentMethods.associateBy { it.id }
    val individual = suggestionRecords.mapNotNull { message ->
      val analyzerKind = message.analyzerType
      val classification = message.classification
      val status = uiStatus(message.state)
      if (analyzerKind == null || analyzerKind == EmailAnalyzerKind.RULES) return@mapNotNull null
      if (classification == null || status == null) return@mapNotNull null
      val kind = uiKind(classification) ?: return@mapNotNull null
      val analyzer = if (analyzerKind == EmailAnalyzerKind.OPEN_ROUTER) {
        EmailUIAnalyzer.OPEN_ROUTER
      } else {
        EmailUIAnalyzer.GEMMA
      }
      val amount = message.amount?.let { runCatching { BigDecimal(it) }.getOrNull() }
      val amountMinor = amount?.let(::minorUnits)
      val occurredMilliseconds = message.occurredAt ?: message.internalDate
      val duplicateDescriptions = EmailSuggestionSelectors.likelyDuplicateDescriptions(
        merchant = message.merchant,
        amountMinor = amountMinor,
        occurredAt = message.occurredAt,
        transactions = transactions,
      )
      val partialSource = listOf(
        message.subject,
        message.snippet,
        message.normalizedBodyText.orEmpty(),
      ).joinToString("\n")
      val partial = EmailSuggestionSelectors.isExplicitlyPartialRefund(partialSource)
      val refundMatches = EmailSuggestionSelectors.refundMatches(
        evidence = EmailRefundEvidence(
          merchant = message.merchant,
          amountMinor = amountMinor,
          currency = message.currency,
          occurredAt = occurredMilliseconds,
          paymentLastFour = message.paymentLastFour,
          reference = message.reference,
        ),
        activeCurrency = currency,
        transactions = transactions,
        paymentMethods = paymentMethods,
        isExplicitlyPartial = partial,
      )
      val refundCandidates = refundMatches.candidates.mapNotNull { match ->
        val transaction = transactions.firstOrNull { it.id == match.transactionId }
          ?: return@mapNotNull null
        val transactionAmountMinor = transaction.amountMinor ?: return@mapNotNull null
        val occurredAt = transaction.occurredAt ?: return@mapNotNull null
        EmailUIRefundCandidate(
          id = transaction.id,
          merchant = transaction.name,
          amount = BigDecimal(transactionAmountMinor).divide(BigDecimal(100)),
          currency = currency,
          occurredAt = occurredAt,
          categoryName = transaction.category,
          paymentMethodLabel = transaction.paymentMethodId?.let { methods[it]?.label },
          matchReason = match.reasons.joinToString(" · "),
        )
      }
      EmailUISuggestion(
        id = message.key,
        accountId = message.accountId,
        accountEmail = accountEmail[message.accountId] ?: message.accountId,
        kind = kind,
        status = status,
        sender = message.senderName ?: message.senderAddress,
        subject = message.subject,
        snippet = message.snippet,
        receivedAt = message.internalDate,
        merchant = message.merchant,
        amount = amount,
        currency = message.currency,
        occurredAt = message.occurredAt,
        categoryId = message.categoryId,
        categoryName = message.categoryId?.let { categoryNames[it] },
        paymentMethodId = message.paymentMethodId,
        paymentMethodLabel = message.paymentMethodId?.let { methods[it]?.label },
        paymentLastFour = message.paymentLastFour,
        reference = message.reference,
        analyzer = analyzer,
        modelVersion = message.modelVersion,
        currencyWarning = message.currency?.takeIf { it != currency }?.let {
          "Email amount is ${it.wire}; Dimo is set to ${currency.wire}. " +
            "No conversion will be performed."
        },
        possibleDuplicateDescriptions = duplicateDescriptions,
        isFullRefund = refundMatches.isFullRefund,
        refundCandidates = refundCandidates,
        preselectedRefundTransactionId = refundMatches.preselectedTransactionId,
      )
    }
    store.publishSuggestions(groupedSuggestions(individual))
  }

  /** Folds a grouped purchase/debit pair into one card driven by the receipt. */
  private fun groupedSuggestions(suggestions: List<EmailUISuggestion>): List<EmailUISuggestion> {
    val recordById = suggestionRecords.associateBy { it.key }
    val reviewedRecords = reviewedPurchaseSourcesCache
    val grouped = suggestions.groupBy { suggestion ->
      recordById[suggestion.id]?.purchaseGroupId?.takeIf { it != suggestion.id } ?: suggestion.id
    }

    return grouped.values.mapNotNull { members ->
      val ordered = members.sortedWith(
        compareBy<EmailUISuggestion> { if (it.kind == EmailUISuggestionKind.PURCHASE) 0 else 1 }
          .thenByDescending { it.receivedAt },
      )
      var primary = ordered.firstOrNull() ?: return@mapNotNull null
      val isPurchaseGroup = ordered.size > 1 &&
        ordered.any { it.kind == EmailUISuggestionKind.PURCHASE } &&
        ordered.any { it.kind == EmailUISuggestionKind.DEBIT }
      primary = if (isPurchaseGroup) {
        val debit = ordered.firstOrNull { it.kind == EmailUISuggestionKind.DEBIT }
        primary.copy(
          groupId = recordById[primary.id]?.purchaseGroupId,
          sourceMessageIds = ordered.map { it.id },
          sourceSenders = ordered.map { it.sender },
          sources = ordered.map { EmailUISourceSummary(it.id, it.sender, it.subject) },
          // The bank debit is the authoritative payment method and settle time.
          paymentMethodId = debit?.paymentMethodId ?: primary.paymentMethodId,
          paymentMethodLabel = debit?.paymentMethodLabel ?: primary.paymentMethodLabel,
          paymentLastFour = debit?.paymentLastFour ?: primary.paymentLastFour,
          occurredAt = debit?.occurredAt ?: primary.occurredAt,
          possibleDuplicateDescriptions = ordered
            .flatMap { it.possibleDuplicateDescriptions }
            .distinct()
            .sorted(),
        )
      } else {
        primary.copy(
          sourceMessageIds = listOf(primary.id),
          sourceSenders = listOf(primary.sender),
          sources = listOf(EmailUISourceSummary(primary.id, primary.sender, primary.subject)),
        )
      }

      if (primary.status == EmailUISuggestionStatus.PENDING_PURCHASE &&
        primary.sourceMessageIds.size == 1
      ) {
        val pending = recordById[primary.id]
        val reviewed = pending?.let {
          EmailPurchaseGroupingSelector.uniqueReviewedMatch(it, reviewedRecords)
        }
        val transactionId = reviewed?.linkedTransactionId
        val transaction = transactionId?.let { id -> transactions.firstOrNull { it.id == id } }
        if (reviewed != null && transactionId != null && transaction != null) {
          primary = primary.copy(
            lateMatch = EmailUILatePurchaseMatch(
              reviewedSourceMessageId = reviewed.key,
              transactionId = transactionId,
              transactionName = transaction.name,
            ),
          )
        }
      }
      primary
    }.sortedByDescending { it.receivedAt }
  }

  /**
   * Reviewed purchase sources for late matching. Refreshed alongside the
   * suggestion observation rather than read synchronously during publish, which
   * runs on the main dispatcher.
   */
  private var reviewedPurchaseSourcesCache: List<EmailMessageRecordModel> = emptyList()

  private fun publishAllEmails() {
    val accountEmails = accountRecords.associate { it.id to it.emailAddress }
    store.publishAllEmails(
      messageSummaries.map { message ->
        EmailUIMessage(
          id = message.id,
          accountEmail = accountEmails[message.accountId] ?: message.accountId,
          sender = message.senderName ?: message.senderAddress,
          subject = message.subject,
          snippet = message.snippet,
          receivedAt = message.internalDate,
          analyzer = uiAnalyzer(message.analyzerType),
          modelVersion = message.modelVersion,
          classification = message.classification?.let(::uiKind),
          analysisState = uiAnalysisState(message.state),
          analyzedAt = message.analyzedAt,
          reviewedAt = message.reviewedAt,
        )
      },
    )
    scope.launch {
      reviewedPurchaseSourcesCache =
        runCatching { repository.reviewedPurchaseSources() }.getOrDefault(emptyList())
    }
  }

  suspend fun sourceEmailDetails(transactionId: String): List<EmailUIEmailDetail> =
    repository.messagesForTransaction(transactionId)
      .mapNotNull { runCatching { loadEmailDetail(it.key) }.getOrNull() }

  private suspend fun loadEmailDetail(messageId: String): EmailUIEmailDetail {
    val message = repository.message(messageId)
      ?: throw EmailRepositoryException(EmailRepositoryException.Kind.MESSAGE_NOT_FOUND)
    val accountEmail = accountRecords.firstOrNull { it.id == message.accountId }?.emailAddress
      ?: message.accountId
    val retainedBody = message.normalizedBodyText?.trim()
    val hasRetainedBody = !retainedBody.isNullOrEmpty()
    val fallback = message.snippet.trim()
    val senderName = message.senderName?.trim()?.takeIf { it.isNotEmpty() }
    return EmailUIEmailDetail(
      id = message.id,
      accountEmail = accountEmail,
      sender = senderName ?: message.senderAddress,
      senderAddress = message.senderAddress,
      subject = message.subject,
      bodyText = if (hasRetainedBody) retainedBody!! else fallback,
      receivedAt = message.internalDate,
      analyzer = uiAnalyzer(message.analyzerType),
      modelVersion = message.modelVersion,
      classification = message.classification?.let(::uiKind),
      analysisState = uiAnalysisState(message.state),
      isBodyRetained = hasRetainedBody,
    )
  }

  private fun accountStatusDetail(account: EmailAccountRecordModel): String? =
    when (account.syncState) {
      EmailAccountSyncState.BACKFILLING ->
        "Scanning the latest ${analysisSettings.syncWindow.title}"

      EmailAccountSyncState.SYNCING -> "Checking Gmail history"
      EmailAccountSyncState.RATE_LIMITED -> "Paused briefly · retrying automatically"
      EmailAccountSyncState.OFFLINE -> "Waiting for a network connection"
      EmailAccountSyncState.FAILED -> account.lastError
      EmailAccountSyncState.NEEDS_RECONNECT -> account.lastError
        ?: "Gmail access expired or was revoked. Reconnect this account to continue."

      EmailAccountSyncState.DISCONNECTED ->
        "Reconnect to sync new mail. Reviewed suggestions are kept."

      EmailAccountSyncState.IDLE -> null
    }

  companion object {
    private const val TAG = "EmailFeature"
    private const val STALE_REFRESH_MS = 15L * 60 * 1000
    private const val MODEL_GONE = "The selected OpenRouter model is no longer available."
    private const val MODEL_UNAVAILABLE =
      "The selected OpenRouter model is unavailable. Choose another model in Email settings."

    fun uiAnalysisState(state: EmailSuggestionState): EmailUIMessageAnalysisState = when (state) {
      EmailSuggestionState.PENDING_ANALYSIS -> EmailUIMessageAnalysisState.PENDING
      EmailSuggestionState.ANALYSIS_FAILED -> EmailUIMessageAnalysisState.FAILED
      EmailSuggestionState.PENDING_PURCHASE,
      EmailSuggestionState.PENDING_REFUND,
      -> EmailUIMessageAnalysisState.NEEDS_REVIEW

      EmailSuggestionState.UNACTIONABLE -> EmailUIMessageAnalysisState.ANALYZED
      EmailSuggestionState.ADDED -> EmailUIMessageAnalysisState.ADDED
      EmailSuggestionState.REFUND_APPLIED -> EmailUIMessageAnalysisState.REFUND_APPLIED
      EmailSuggestionState.DISMISSED -> EmailUIMessageAnalysisState.DISMISSED
      EmailSuggestionState.EXPIRED -> EmailUIMessageAnalysisState.EXPIRED
    }

    fun uiAnalyzer(analyzer: EmailAnalyzerKind?): EmailUIAnalyzer? = when (analyzer) {
      EmailAnalyzerKind.GEMMA -> EmailUIAnalyzer.GEMMA
      EmailAnalyzerKind.OPEN_ROUTER -> EmailUIAnalyzer.OPEN_ROUTER
      EmailAnalyzerKind.RULES, null -> null
    }

    fun uiSyncState(state: EmailAccountSyncState): EmailUIAccountSyncState = when (state) {
      EmailAccountSyncState.IDLE -> EmailUIAccountSyncState.IDLE
      EmailAccountSyncState.BACKFILLING,
      EmailAccountSyncState.SYNCING,
      -> EmailUIAccountSyncState.SYNCING

      EmailAccountSyncState.RATE_LIMITED -> EmailUIAccountSyncState.RATE_LIMITED
      EmailAccountSyncState.OFFLINE -> EmailUIAccountSyncState.OFFLINE
      EmailAccountSyncState.FAILED -> EmailUIAccountSyncState.FAILED
      EmailAccountSyncState.NEEDS_RECONNECT -> EmailUIAccountSyncState.NEEDS_RECONNECT
      EmailAccountSyncState.DISCONNECTED -> EmailUIAccountSyncState.DISCONNECTED
    }

    /** Queued and failed rows have no reviewable suggestion yet. */
    fun uiStatus(state: EmailSuggestionState): EmailUISuggestionStatus? = when (state) {
      EmailSuggestionState.PENDING_ANALYSIS, EmailSuggestionState.ANALYSIS_FAILED -> null
      EmailSuggestionState.PENDING_PURCHASE -> EmailUISuggestionStatus.PENDING_PURCHASE
      EmailSuggestionState.PENDING_REFUND -> EmailUISuggestionStatus.PENDING_REFUND
      EmailSuggestionState.ADDED -> EmailUISuggestionStatus.ADDED
      EmailSuggestionState.REFUND_APPLIED -> EmailUISuggestionStatus.REFUND_APPLIED
      EmailSuggestionState.DISMISSED -> EmailUISuggestionStatus.DISMISSED
      EmailSuggestionState.UNACTIONABLE -> EmailUISuggestionStatus.UNACTIONABLE
      EmailSuggestionState.EXPIRED -> EmailUISuggestionStatus.EXPIRED
    }

    fun uiKind(classification: EmailMessageClassification): EmailUISuggestionKind? =
      when (classification) {
        EmailMessageClassification.PURCHASE -> EmailUISuggestionKind.PURCHASE
        EmailMessageClassification.DEBIT -> EmailUISuggestionKind.DEBIT
        EmailMessageClassification.REFUND -> EmailUISuggestionKind.REFUND
        EmailMessageClassification.IRRELEVANT -> EmailUISuggestionKind.IRRELEVANT
      }

    fun resolvedPaymentMethodId(
      requested: String?,
      paymentMethods: List<PaymentMethodOption>,
    ): String {
      val trimmed = requested?.trim()
      if (!trimmed.isNullOrEmpty() && paymentMethods.any { it.id == trimmed }) return trimmed
      return paymentMethods.firstOrNull { it.isDefault && !it.archived }?.id
        ?: paymentMethods.firstOrNull { !it.archived }?.id
        ?: SeedData.CASH_PAYMENT_METHOD.id
    }

    fun minorUnits(amount: BigDecimal): Long? {
      if (amount.signum() <= 0) return null
      return runCatching {
        amount.setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact()
      }.getOrNull()
    }

    fun lastFour(value: String): String? {
      val digits = value.filter(Char::isDigit)
      return if (digits.length >= 4) digits.takeLast(4) else null
    }
  }
}

private suspend fun Job.cancelAndJoinQuietly() {
  cancel()
  runCatching { join() }
}

private suspend fun Deferred<*>.cancelAndJoinQuietly() {
  cancel()
  runCatching { join() }
}

private fun kotlin.coroutines.CoroutineContext.isActiveSafe(): Boolean =
  this[Job]?.isActive ?: true
