import Foundation
import GRDB
import OSLog
import UIKit

private let emailAnalysisLogger = Logger(
  subsystem: "app.dimo.ios",
  category: "EmailAnalysis"
)

enum EmailFeatureControllerError: LocalizedError {
  case gmailNotConfigured
  case invalidSuggestion
  case analysisNotConfigured
  case openRouterNotConfigured
  case nonZDRConsentRequired

  var errorDescription: String? {
    switch self {
    case .gmailNotConfigured:
      return "Gmail OAuth is not configured for this build."
    case .invalidSuggestion:
      return "The email suggestion is missing a valid amount, date, or category."
    case .analysisNotConfigured:
      return "Email analysis is not configured. Choose Free models or Bring your own key in Email settings."
    case .openRouterNotConfigured:
      return "Configure OpenRouter in Email settings before analyzing."
    case .nonZDRConsentRequired:
      return "This model has no zero-data-retention route. Confirm non-ZDR use before selecting it."
    }
  }
}

private enum EmailAnalysisAttemptOutcome: Equatable {
  case processed
  case paused
}

/// Owns the account-scoped Email feature for one signed-in Dimo user. Gmail
/// credentials stay on this device. Reviewed suggestions (including the full
/// normalized body) are dual-written into the synced `emailMessage` entity/
/// outbox path; acceptance/refund also writes normal transaction entities.
@MainActor
final class EmailFeatureController: EmailBackgroundWorkProviding {
  let store: EmailFeatureStore

  private static let legacyGemmaModelsCleanupKey = "email.legacyGemmaModelsCleaned"

  private let userId: String
  private let repository: Repository
  private let vault: GmailCredentialVault
  private let oauthClient: GmailOAuthClient?
  private let tokenManager: GmailAccessTokenManager?
  private let syncCoordinator: EmailSyncCoordinator?
  private let openRouterThrottle = EmailAnalysisStartThrottle.openRouter
  private let openRouterVault = OpenRouterCredentialVault()
  private let openRouterClient = OpenRouterClient()
  private let analysisCoordinator = EmailAnalysisCoordinator()

  private var analysisSettings: EmailAnalysisSettings = .defaults
  private var openRouterModels: [OpenRouterModel] = []
  private var openRouterConvexTransport: (any OpenRouterConvexTransporting)?
  private var accountsObservation: DatabaseCancellable?
  private var suggestionsObservation: DatabaseCancellable?
  private var messageSummariesObservation: DatabaseCancellable?
  private var foregroundWork: Task<Void, Never>?
  private var analysisWork: Task<Void, Never>?
  private var pendingAnalysisTask: Task<Int, Error>?
  private var pendingAnalysisRunId: UUID?

  private var accountRecords: [EmailAccountRecordModel] = []
  private var suggestionRecords: [EmailMessageRecordModel] = []
  private var messageSummaries: [EmailMessageSummaryModel] = []
  private var categories: [CategoryEntity] = []
  private var paymentMethods: [PaymentMethodOption] = []
  private var transactions: [Transaction] = []
  private var currency: Currency = .INR
  private var stopped = false
  private var uiScrolling = false
  private var resumeAfterScrollTask: Task<Void, Never>?
  private var publishUITask: Task<Void, Never>?
  private var pendingPublishAccounts = false
  private var pendingPublishSuggestions = false
  private var pendingPublishEmails = false

  init(
    userId: String,
    repository: Repository,
    store: EmailFeatureStore
  ) {
    self.userId = userId
    self.repository = repository
    self.store = store

    let vault = GmailCredentialVault()
    self.vault = vault
    if let configuration = try? GmailOAuthConfiguration.fromAppConfig() {
      let oauth = GmailOAuthClient(configuration: configuration, vault: vault)
      let tokens = GmailAccessTokenManager(configuration: configuration, vault: vault)
      let api = GmailRESTClient(tokenProvider: tokens)
      let persistence = EmailRepositorySyncAdapter(repository: repository)
      oauthClient = oauth
      tokenManager = tokens
      syncCoordinator = EmailSyncCoordinator(api: api, persistence: persistence)
    } else {
      oauthClient = nil
      tokenManager = nil
      syncCoordinator = nil
    }
  }

  func start(
    categories: [CategoryEntity],
    paymentMethods: [PaymentMethodOption],
    transactions: [Transaction],
    currency: Currency
  ) async {
    stopped = false
    cleanupLegacyGemmaModelsIfNeeded()
    updateDomain(
      categories: categories,
      paymentMethods: paymentMethods,
      transactions: transactions,
      currency: currency
    )
    configureActions()
    analysisSettings = (try? repository.emailAnalysisSettings()) ?? .defaults
    publishAnalysisSettings()
    startObservations()
    EmailBackgroundWorkRegistry.provider = self
    EmailBackgroundTasks.schedule(
      requiresAnalysisNetworkConnectivity: analysisSettings.selectedProvider == .openRouter
    )

    do {
      try enforceRetention()
    } catch {
      store.lastActionError = "Email retention cleanup failed: \(error.localizedDescription)"
    }

    Task { [weak self] in
      guard let self, !self.stopped else { return }
      await self.restoreOpenRouterConfiguration()
    }

    if hasConnectedAccounts {
      foregroundWork = Task { [weak self] in
        try? await self?.refresh(accountId: nil)
        self?.foregroundWork = nil
      }
    }
  }

  func updateDomain(
    categories: [CategoryEntity],
    paymentMethods: [PaymentMethodOption],
    transactions: [Transaction],
    currency: Currency
  ) {
    self.categories = categories
    self.paymentMethods = paymentMethods
    self.transactions = transactions
    self.currency = currency
    store.categories = categories
    store.paymentMethods = paymentMethods
    store.activeCurrency = currency
    publishSuggestions()
  }

  /// Soft-pauses analysis while the user is actively scrolling.
  func setUIScrolling(_ scrolling: Bool) {
    uiScrolling = scrolling
    resumeAfterScrollTask?.cancel()
    guard !scrolling else { return }
    resumeAfterScrollTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard let self, !self.stopped, !self.uiScrolling else { return }
      await self.resumeAnalysisIfNeeded()
    }
  }

  private func waitWhileUIScrolling() async throws {
    while uiScrolling {
      try Task.checkCancellation()
      try await Task.sleep(nanoseconds: 50_000_000)
    }
  }

  func tearDown() async {
    stopped = true
    uiScrolling = false
    resumeAfterScrollTask?.cancel()
    resumeAfterScrollTask = nil
    publishUITask?.cancel()
    publishUITask = nil
    pendingPublishAccounts = false
    pendingPublishSuggestions = false
    pendingPublishEmails = false
    foregroundWork?.cancel()
    if let analysisWork {
      analysisWork.cancel()
      await analysisWork.value
      self.analysisWork = nil
    }
    if let pendingAnalysisTask {
      pendingAnalysisTask.cancel()
      _ = try? await pendingAnalysisTask.value
      self.pendingAnalysisTask = nil
      pendingAnalysisRunId = nil
    }
    accountsObservation?.cancel()
    suggestionsObservation?.cancel()
    messageSummariesObservation?.cancel()
    oauthClient?.cancel()
    await syncCoordinator?.stop()
    await analysisCoordinator.removeAll()
    await tokenManager?.clearAll()
    try? await vault.removeAll(dimoUserId: userId)
    try? await openRouterVault.remove(dimoUserId: userId)
    if EmailBackgroundWorkRegistry.provider === self {
      EmailBackgroundWorkRegistry.provider = nil
    }
    EmailBackgroundTasks.cancelScheduledTasks()
  }

  func sceneBecameActive() {
    guard foregroundWork == nil || foregroundWork?.isCancelled == true else { return }
    let mostRecentAttempt = accountRecords.compactMap(\.lastAttemptAt).max() ?? 0
    let stale = Int(Date().timeIntervalSince1970 * 1_000) - mostRecentAttempt > 15 * 60 * 1_000
    guard stale, hasConnectedAccounts else { return }
    foregroundWork = Task { [weak self] in
      try? await self?.refresh(accountId: nil)
      self?.foregroundWork = nil
    }
  }

  func performEmailBackgroundRefresh() async -> Bool {
    guard let syncCoordinator else { return !hasConnectedAccounts }
    do {
      let incrementalAccounts = try repository.emailAccounts().filter {
        $0.syncState != .disconnected
          && $0.syncState != .needsReconnect
          && $0.backfillCompletedAt != nil
          && $0.historyId != nil
      }
      for account in incrementalAccounts {
        try Task.checkCancellation()
        await syncCoordinator.refresh(
          dimoUserId: userId,
          accountSubject: account.id,
          syncWindow: analysisSettings.syncWindow
        )
      }
      try enforceRetention()
      return !Task.isCancelled
    } catch {
      return false
    }
  }

  func performEmailBackgroundAnalysis() async -> Bool {
    defer {
      EmailBackgroundTasks.scheduleAnalysis(
        requiresNetworkConnectivity: analysisSettings.selectedProvider == .openRouter
      )
    }
    guard analysisSettings.selectedProvider == .openRouter else { return true }
    if let retry = try? repository.emailAnalysisRetryState(),
       let notBefore = retry.notBefore,
       notBefore > Int(Date().timeIntervalSince1970 * 1_000) {
      return true
    }
    do {
      try enforceRetention()
      _ = try await runPendingAnalysis()
      return !Task.isCancelled
    } catch {
      return false
    }
  }

  func cancelEmailBackgroundWork() {
    foregroundWork?.cancel()
    analysisWork?.cancel()
    pendingAnalysisTask?.cancel()
    Task { [weak self] in
      await self?.syncCoordinator?.stop()
      await self?.analysisCoordinator.set(nil, for: .openRouter)
    }
  }

  private func configureActions() {
    store.configure(actions: EmailFeatureActions(
      connectAccount: { [weak self] in
        guard let self else {
          throw EmailFeatureControllerError.gmailNotConfigured
        }
        try await self.connectAccount()
      },
      reconnectAccount: { [weak self] accountId in
        guard let self else {
          throw EmailFeatureControllerError.gmailNotConfigured
        }
        try await self.reconnectAccount(accountId)
      },
      disconnectAccount: { [weak self] accountId in
        guard let self else { return }
        try await self.disconnectAccount(accountId)
      },
      refresh: { [weak self] accountId in
        guard let self else { return }
        try await self.refresh(accountId: accountId)
      },
      dismissSuggestion: { [weak self] suggestionId in
        try self?.repository.dismissEmailSuggestion(messageKey: suggestionId)
      },
      dismissSuggestions: { [weak self] suggestionIds in
        try self?.repository.dismissEmailSuggestions(messageKeys: suggestionIds)
      },
      restoreSuggestion: { [weak self] suggestionId in
        try self?.repository.restoreDismissedEmailSuggestion(messageKey: suggestionId)
      },
      restoreSuggestions: { [weak self] suggestionIds in
        try self?.repository.restoreDismissedEmailSuggestions(messageKeys: suggestionIds)
      },
      separateSuggestions: { [weak self] suggestionIds in
        try self?.repository.separateEmailSuggestions(messageKeys: suggestionIds)
      },
      linkLateSuggestion: { [weak self] suggestionId, sourceId in
        try self?.repository.linkLateEmailSuggestion(
          messageKey: suggestionId,
          reviewedSourceKey: sourceId
        )
      },
      keepLateSuggestionSeparate: { [weak self] suggestionId in
        try self?.repository.keepLateEmailSuggestionSeparate(messageKey: suggestionId)
      },
      acceptPurchase: { [weak self] draft in
        guard let self else { return }
        try await self.acceptPurchase(draft)
      },
      linkPurchaseToTransaction: { [weak self] suggestionId, transactionId in
        let sourceIds = self?.store.purchaseReview?.sourceMessageIDs ?? []
        try self?.repository.linkEmailSuggestionsToTransaction(
          messageKeys: sourceIds.isEmpty ? [suggestionId] : sourceIds,
          transactionId: transactionId
        )
      },
      applyFullRefund: { [weak self] suggestionId, transactionId in
        try self?.repository.applyFullEmailRefund(
          messageKey: suggestionId,
          transactionId: transactionId
        )
      },
      reanalyzeAllEmails: { [weak self] in
        guard let self else { return }
        try await self.reanalyzeAllEmails()
      },
      saveOpenRouterKey: { [weak self] key in
        guard let self else { return }
        try await self.saveOpenRouterKey(key)
      },
      removeOpenRouterKey: { [weak self] in
        guard let self else { return }
        try await self.removeOpenRouterKey()
      },
      refreshOpenRouterModels: { [weak self] in
        guard let self else { return }
        try await self.refreshOpenRouterModels()
      },
      selectOpenRouterModel: { [weak self] modelID, allowNonZDR in
        guard let self else { return }
        try await self.selectOpenRouterModel(modelID, allowNonZDR: allowNonZDR)
      },
      selectOpenRouterAccessMode: { [weak self] mode in
        guard let self else { return }
        try await self.selectOpenRouterAccessMode(mode)
      },
      selectProvider: { [weak self] provider in
        guard let self else { return }
        try await self.switchProvider(to: provider)
      },
      selectSyncWindow: { [weak self] window in
        guard let self else { return }
        try await self.selectSyncWindow(window)
      },
      retryAnalysis: { [weak self] messageID in
        guard let self else { return }
        try await self.retryAnalysis(messageID: messageID)
      },
      retryOpenRouterConnection: { [weak self] in
        guard let self else { return }
        try await self.retryOpenRouterConnection()
      },
      retryOpenRouterAnalysis: { [weak self] in
        guard let self else { return }
        try await self.retryOpenRouterAnalysis()
      },
      loadEmailDetail: { [weak self] messageId in
        guard let self else { throw EmailFeatureStoreError.messageNotFound }
        return try self.loadEmailDetail(messageId: messageId)
      }
    ))
  }

  private func cleanupLegacyGemmaModelsIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: Self.legacyGemmaModelsCleanupKey) else { return }
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let modelsDirectory = support.appendingPathComponent("Dimo/Models", isDirectory: true)
    try? FileManager.default.removeItem(at: modelsDirectory)
    defaults.set(true, forKey: Self.legacyGemmaModelsCleanupKey)
  }

  private func startObservations() {
    _ = try? repository.reconcilePendingPurchaseGroups()
    accountRecords = (try? repository.emailAccounts()) ?? []
    suggestionRecords = (try? repository.emailSuggestions()) ?? []
    messageSummaries = (try? repository.emailMessageSummaries()) ?? []
    publishAccounts()
    publishSuggestions()
    publishAllEmails()
    accountsObservation = repository.observeEmailAccounts { [weak self] accounts in
      Task { @MainActor in
        self?.accountRecords = accounts
        self?.schedulePublishUI(accounts: true, suggestions: false, emails: true)
      }
    }
    suggestionsObservation = repository.observeEmailSuggestions { [weak self] suggestions in
      Task { @MainActor in
        self?.suggestionRecords = suggestions
        self?.schedulePublishUI(accounts: false, suggestions: true, emails: false)
      }
    }
    messageSummariesObservation = repository.observeEmailMessageSummaries { [weak self] messages in
      Task { @MainActor in
        self?.messageSummaries = messages
        self?.schedulePublishUI(accounts: false, suggestions: false, emails: true)
      }
    }
  }

  private func schedulePublishUI(accounts: Bool, suggestions: Bool, emails: Bool) {
    pendingPublishAccounts = pendingPublishAccounts || accounts
    pendingPublishSuggestions = pendingPublishSuggestions || suggestions
    pendingPublishEmails = pendingPublishEmails || emails
    publishUITask?.cancel()
    publishUITask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 32_000_000)
      guard let self, !Task.isCancelled else { return }
      let publishAccounts = self.pendingPublishAccounts
      let publishSuggestions = self.pendingPublishSuggestions
      let publishEmails = self.pendingPublishEmails
      self.pendingPublishAccounts = false
      self.pendingPublishSuggestions = false
      self.pendingPublishEmails = false
      await Task(priority: .utility) { @MainActor in
        if publishAccounts { self.publishAccounts() }
        if publishSuggestions { self.publishSuggestions() }
        if publishEmails { self.publishAllEmails() }
      }.value
    }
  }

  private func connectAccount() async throws {
    guard let oauthClient else { throw EmailFeatureControllerError.gmailNotConfigured }
    let account = try await oauthClient.connect(dimoUserId: userId)
    guard !stopped, !Task.isCancelled else {
      try? await vault.remove(subject: account.subject, dimoUserId: userId)
      throw CancellationError()
    }
    do {
      let existing = try repository.emailAccount(id: account.subject)
      try repository.saveEmailAccount(EmailAccountRecordModel(
        id: account.subject,
        emailAddress: account.emailAddress,
        historyId: existing?.historyId,
        backfillPageToken: existing?.backfillPageToken,
        backfillCompletedAt: existing?.backfillCompletedAt,
        lastAttemptAt: existing?.lastAttemptAt,
        lastSuccessfulSyncAt: existing?.lastSuccessfulSyncAt,
        syncState: .idle,
        createdAt: existing?.createdAt ?? Int(account.connectedAt.timeIntervalSince1970 * 1_000)
      ))
      try repository.materializeSyncedEmailMessages(accountId: account.subject)
    } catch {
      try? await vault.remove(subject: account.subject, dimoUserId: userId)
      throw error
    }
    try await refresh(accountId: account.subject)
  }

  /// Replaces a dead Gmail refresh token in place. Local messages, reviewed
  /// suggestions, and sync cursors are preserved.
  private func reconnectAccount(_ accountId: String) async throws {
    guard let oauthClient else { throw EmailFeatureControllerError.gmailNotConfigured }
    guard let existing = try repository.emailAccount(id: accountId) else {
      throw EmailRepositoryError.accountNotFound
    }
    let account = try await oauthClient.reauthorize(
      subject: accountId,
      emailAddress: existing.emailAddress,
      dimoUserId: userId
    )
    guard !stopped, !Task.isCancelled else {
      throw CancellationError()
    }
    await tokenManager?.invalidate(subject: accountId)
    try repository.updateEmailAccount(id: accountId) { record in
      record.emailAddress = account.emailAddress
      record.syncState = .idle
      record.lastError = nil
    }
    try await refresh(accountId: accountId)
  }

  private func disconnectAccount(_ accountId: String) async throws {
    if let oauthClient {
      try await oauthClient.disconnect(subject: accountId, dimoUserId: userId)
    } else {
      try await vault.remove(subject: accountId, dimoUserId: userId)
    }
    await tokenManager?.invalidate(subject: accountId)
    _ = try repository.deleteEmailAccount(id: accountId)
  }

  private func refresh(accountId: String?) async throws {
    guard let syncCoordinator else { throw EmailFeatureControllerError.gmailNotConfigured }
    try Task.checkCancellation()
    guard !stopped else { throw CancellationError() }
    await syncCoordinator.refresh(
      dimoUserId: userId,
      accountSubject: accountId,
      syncWindow: analysisSettings.syncWindow
    )
    try Task.checkCancellation()
    guard !stopped else { throw CancellationError() }
    try enforceRetention()
    _ = try await runPendingAnalysis()
  }

  private func enforceRetention(now: Date = .now) throws {
    let cutoff = Int(analysisSettings.syncWindow.cutoff(from: now).timeIntervalSince1970 * 1_000)
    _ = try repository.expireEmailMessages(olderThan: cutoff)
    _ = try repository.purgeEmailMessages(olderThan: cutoff)
    _ = try repository.purgeReviewedEmailBodies()
  }

  private func runPendingAnalysis(maximumCount: Int? = nil) async throws -> Int {
    if let pendingAnalysisTask {
      return try await pendingAnalysisTask.value
    }
    let runId = UUID()
    pendingAnalysisRunId = runId
    let task = Task { [weak self] () throws -> Int in
      guard let self else { throw CancellationError() }
      return try await self.analyzePending(maximumCount: maximumCount)
    }
    pendingAnalysisTask = task
    defer {
      if pendingAnalysisRunId == runId {
        pendingAnalysisTask = nil
        pendingAnalysisRunId = nil
      }
    }
    return try await task.value
  }

  private func analyzePending(maximumCount: Int? = nil) async throws -> Int {
    let accountIds = try repository.emailAccounts().map(\.id)
    guard !accountIds.isEmpty else { return 0 }
    if let maximumCount, maximumCount <= 0 { return 0 }
    var analyzed = 0
    var madeProgress = true
    while madeProgress, !Task.isCancelled, !stopped {
      if let maximumCount, analyzed >= maximumCount { break }
      madeProgress = false
      for accountId in accountIds {
        if let maximumCount, analyzed >= maximumCount { break }
        try Task.checkCancellation()
        try await waitWhileUIScrolling()
        guard let message = try repository.emailMessagesPendingAnalysis(
          accountId: accountId,
          limit: 1
        ).first else { continue }
        let outcome = try await analyze(message)
        guard outcome == .processed else { return analyzed }
        analyzed += 1
        madeProgress = true
        await Task.yield()
      }
    }
    return analyzed
  }

  private func analyze(_ message: EmailMessageRecordModel) async throws -> EmailAnalysisAttemptOutcome {
    guard let body = message.normalizedBodyText else {
      try repository.markEmailSuggestionUnactionable(messageKey: message.key)
      return .processed
    }
    guard analysisSettings.selectedProvider == .openRouter else {
      store.analysisStatusDetail = EmailFeatureControllerError.analysisNotConfigured.localizedDescription
      return .paused
    }
    let request = makeAnalysisRequest(message: message, body: body)

    do {
      if let retry = try repository.emailAnalysisRetryState(),
         let notBefore = retry.notBefore,
         notBefore > Int(Date().timeIntervalSince1970 * 1_000) {
        store.analysisStatusDetail = retry.reason ?? "OpenRouter analysis is waiting to retry."
        return .paused
      }
      guard let analyzer = try await preparedOpenRouterAnalyzer() else {
        store.analysisStatusDetail = EmailFeatureControllerError.openRouterNotConfigured.localizedDescription
        return .paused
      }
      try await openRouterThrottle.waitForNextStart(
        minimumInterval: EmailOpenRouterPacing.minimumStartInterval
      )
      let envelope = try await analyzer.analyze(request)
      try repository.clearEmailAnalysisRetryState()
      try Task.checkCancellation()
      guard !stopped else { throw CancellationError() }
      try repository.saveEmailAnalysis(
        messageKey: message.key,
        analysis: persisted(envelope)
      )
      emailAnalysisLogger.notice(
        "Email analysis succeeded; message: \(message.key, privacy: .private(mask: .hash)); analyzer: \(envelope.analyzer.rawValue, privacy: .public); model: \(envelope.modelID, privacy: .public); request ID: \(envelope.requestID ?? "none", privacy: .public); classification: \(envelope.result.kind.rawValue, privacy: .public)"
      )
      store.analysisStatusDetail = "Analysis complete."
      return .processed
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as OpenRouterClientError where error.isTransient {
      emailAnalysisLogger.error(
        "Transient OpenRouter analysis failure; message: \(message.key, privacy: .private(mask: .hash)); model: \(self.analysisSettings.openRouterModelID ?? "none", privacy: .public); error: \(String(reflecting: error), privacy: .public)"
      )
      try scheduleOpenRouterRetry(for: error)
      store.analysisStatusDetail = error.localizedDescription
      return .paused
    } catch let error as OpenRouterClientError {
      emailAnalysisLogger.error(
        "OpenRouter analysis failure; message: \(message.key, privacy: .private(mask: .hash)); model: \(self.analysisSettings.openRouterModelID ?? "none", privacy: .public); error: \(String(reflecting: error), privacy: .public)"
      )
      switch error {
      case .invalidKey:
        store.analysisStatusDetail = error.localizedDescription
        store.openRouterConnectionState = .failed(error.localizedDescription)
        return .paused
      case .forbidden, .insufficientCredits:
        store.analysisStatusDetail = error.localizedDescription
        return .paused
      case .modelUnavailable:
        try repository.clearEmailAnalysisRetryState()
        store.analysisStatusDetail =
          "The selected OpenRouter model is unavailable. Choose another model in Email settings."
        return .paused
      default:
        try repository.markEmailAnalysisFailed(
          messageKey: message.key,
          analyzer: .openRouter,
          modelVersion: analysisSettings.openRouterModelID
        )
        store.analysisStatusDetail = "Analysis failed"
        return .processed
      }
    } catch {
      emailAnalysisLogger.error(
        "Email analysis failure; message: \(message.key, privacy: .private(mask: .hash)); model: \(self.analysisSettings.openRouterModelID ?? "none", privacy: .public); error: \(String(reflecting: error), privacy: .public)"
      )
      try repository.markEmailAnalysisFailed(
        messageKey: message.key,
        analyzer: .openRouter,
        modelVersion: analysisSettings.openRouterModelID
      )
      store.analysisStatusDetail = "Analysis failed"
      return .processed
    }
  }

  private func makeAnalysisRequest(
    message: EmailMessageRecordModel,
    body: String
  ) -> EmailAnalysisRequest {
    EmailAnalysisRequest(
      messageId: message.gmailMessageId,
      accountSubject: message.accountId,
      senderName: message.senderName,
      senderAddress: message.senderAddress,
      subject: message.subject,
      receivedAt: Date(timeIntervalSince1970: TimeInterval(message.internalDate) / 1_000),
      normalizedBody: body,
      categories: categories.map { EmailCategoryOption(id: $0.id, name: $0.name) },
      paymentMethods: paymentMethods.map {
        EmailPaymentMethodHint(
          id: $0.id,
          label: $0.label,
          lastFour: Self.lastFour(in: $0.detail + " " + $0.name),
          archived: $0.archived
        )
      },
      merchantHistory: merchantHistory(),
      activeCurrency: currency
    )
  }

  private func merchantHistory() -> [EmailMerchantCategoryHint] {
    var seen = Set<String>()
    var hints: [EmailMerchantCategoryHint] = []
    for transaction in transactions {
      let key = transaction.name
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty,
            let categoryId = transaction.categoryId,
            seen.insert(key).inserted else { continue }
      hints.append(EmailMerchantCategoryHint(
        merchant: transaction.name,
        categoryId: categoryId
      ))
      if hints.count == 40 { break }
    }
    return hints
  }

  private func persisted(_ envelope: EmailAnalysisEnvelope) -> PersistedEmailAnalysis {
    let result = envelope.result
    return PersistedEmailAnalysis(
      analyzerType: envelope.analyzer == .gemma ? .gemma : .openRouter,
      modelVersion: envelope.modelID,
      promptVersion: EmailAnalysisResult.schemaVersion,
      classification: EmailMessageClassification(rawValue: result.kind.rawValue) ?? .irrelevant,
      merchant: result.merchant,
      amount: result.amount.map { NSDecimalNumber(decimal: $0).stringValue },
      currency: result.currency,
      occurredAt: result.occurredAt.map { Int($0.timeIntervalSince1970 * 1_000) },
      categoryId: result.categoryId,
      paymentMethodId: result.paymentMethodId,
      paymentLastFour: result.paymentLastFour,
      reference: result.reference
    )
  }

  /// Attach the authenticated Convex client once sync login succeeds.
  func attachOpenRouterConvexTransport(_ transport: (any OpenRouterConvexTransporting)?) {
    openRouterConvexTransport = transport
    guard analysisSettings.openRouterAccessMode == .freeShared else { return }
    Task { [weak self] in
      await self?.restoreOpenRouterConfiguration()
    }
  }

  private func preparedOpenRouterAnalyzer() async throws -> (any EmailAnalysisProviding)? {
    guard let modelID = analysisSettings.openRouterModelID else { return nil }
    guard let model = openRouterModels.first(where: { $0.id == modelID }) else {
      throw OpenRouterClientError.modelUnavailable
    }
    if analysisSettings.openRouterPrivacyMode == .zdrOnly, !model.hasZDREndpoint {
      throw OpenRouterClientError.modelUnavailable
    }

    switch analysisSettings.openRouterAccessMode {
    case .freeShared:
      guard model.isFree else { throw OpenRouterClientError.modelUnavailable }
      guard let transport = openRouterConvexTransport else {
        throw OpenRouterConvexTransportError.notReady.openRouterClientError
      }
      let analyzer = ConvexFreeOpenRouterEmailAnalyzer(
        transport: transport,
        model: model,
        privacyMode: analysisSettings.openRouterPrivacyMode
      )
      await analysisCoordinator.set(analyzer, for: .openRouter)
      return analyzer
    case .bringYourOwnKey:
      guard let credential = try await openRouterVault.credential(dimoUserId: userId) else {
        return nil
      }
      let analyzer = OpenRouterEmailAnalyzer(
        client: openRouterClient,
        model: model,
        privacyMode: analysisSettings.openRouterPrivacyMode,
        apiKey: credential.apiKey
      )
      await analysisCoordinator.set(analyzer, for: .openRouter)
      return analyzer
    }
  }

  private func restoreOpenRouterConfiguration() async {
    switch analysisSettings.openRouterAccessMode {
    case .freeShared:
      await restoreFreeOpenRouterConfiguration()
    case .bringYourOwnKey:
      await restoreBYOKOpenRouterConfiguration()
    }
  }

  private func restoreFreeOpenRouterConfiguration() async {
    guard let transport = openRouterConvexTransport else {
      store.openRouterConnectionState = .disconnected
      if analysisSettings.selectedProvider == .openRouter {
        store.analysisStatusDetail =
          OpenRouterConvexTransportError.notReady.localizedDescription
      }
      return
    }
    store.openRouterConnectionState = .validating
    do {
      let models = try await transport.listFreeModels()
      openRouterModels = models
      store.openRouterModels = models
      store.openRouterConnectionState = .connected(
        label: "Free models",
        creditLimit: nil,
        limitRemaining: nil
      )
      try ensureDefaultFreeModelSelection(in: models)
      if let selected = analysisSettings.openRouterModelID,
         !models.contains(where: { $0.id == selected }) {
        store.analysisStatusDetail = "The selected OpenRouter model is no longer available."
      }
      publishAnalysisSettings()
    } catch {
      let message = (error as? OpenRouterConvexTransportError)?.errorDescription
        ?? error.localizedDescription
      store.openRouterConnectionState = .failed(message)
      if analysisSettings.selectedProvider == .openRouter {
        store.analysisStatusDetail = message
      }
    }
  }

  private func restoreBYOKOpenRouterConfiguration() async {
    do {
      guard let credential = try await openRouterVault.credential(dimoUserId: userId) else {
        store.openRouterConnectionState = .disconnected
        return
      }
      store.openRouterConnectionState = .validating
      let keyInfo = try await openRouterClient.validateKey(credential.apiKey)
      openRouterModels = try await openRouterClient.models(apiKey: credential.apiKey)
      store.openRouterModels = openRouterModels
      store.openRouterConnectionState = .connected(
        label: keyInfo.label,
        creditLimit: keyInfo.limit,
        limitRemaining: keyInfo.limitRemaining
      )
      if try repository.emailAnalysisRetryState()?.lastHTTPStatus == 404 {
        try repository.clearEmailAnalysisRetryState()
        store.analysisStatusDetail =
          "The selected OpenRouter model is unavailable. Choose another model in Email settings."
      }
      if let selected = analysisSettings.openRouterModelID,
         !openRouterModels.contains(where: { $0.id == selected }) {
        store.analysisStatusDetail = "The selected OpenRouter model is no longer available."
      }
    } catch {
      store.openRouterConnectionState = .failed(error.localizedDescription)
      if analysisSettings.selectedProvider == .openRouter {
        store.analysisStatusDetail = error.localizedDescription
      }
    }
  }

  private func ensureDefaultFreeModelSelection(in models: [OpenRouterModel]) throws {
    if let selected = analysisSettings.openRouterModelID,
       models.contains(where: { $0.id == selected && $0.isFree }) {
      rememberModelSelection(selected, for: .freeShared)
      try saveAnalysisSettings()
      return
    }
    if let remembered = analysisSettings.lastFreeOpenRouterModelID,
       models.contains(where: { $0.id == remembered && $0.isFree }) {
      analysisSettings.openRouterModelID = remembered
      try saveAnalysisSettings()
      return
    }
    if models.contains(where: { $0.id == OpenRouterClient.defaultModelID }) {
      analysisSettings.openRouterModelID = OpenRouterClient.defaultModelID
      rememberModelSelection(OpenRouterClient.defaultModelID, for: .freeShared)
      try saveAnalysisSettings()
      return
    }
    if let firstFree = models.first(where: \.isFree) {
      analysisSettings.openRouterModelID = firstFree.id
      rememberModelSelection(firstFree.id, for: .freeShared)
      try saveAnalysisSettings()
    }
  }

  private func rememberModelSelection(_ modelID: String?, for mode: OpenRouterAccessMode) {
    guard let modelID else { return }
    switch mode {
    case .freeShared:
      analysisSettings.lastFreeOpenRouterModelID = modelID
    case .bringYourOwnKey:
      analysisSettings.lastBYOKOpenRouterModelID = modelID
    }
  }

  private func rememberPrivacySelection(
    privacyMode: OpenRouterPrivacyMode,
    consentVersion: Int?,
    for mode: OpenRouterAccessMode
  ) {
    switch mode {
    case .freeShared:
      analysisSettings.lastFreeOpenRouterPrivacyMode = privacyMode
      analysisSettings.lastFreeNonZDRConsentVersion = consentVersion
    case .bringYourOwnKey:
      analysisSettings.lastBYOKOpenRouterPrivacyMode = privacyMode
      analysisSettings.lastBYOKNonZDRConsentVersion = consentVersion
    }
  }

  private func restorePrivacySelection(for mode: OpenRouterAccessMode) {
    switch mode {
    case .freeShared:
      analysisSettings.openRouterPrivacyMode = analysisSettings.lastFreeOpenRouterPrivacyMode
      analysisSettings.nonZDRConsentVersion = analysisSettings.lastFreeNonZDRConsentVersion
    case .bringYourOwnKey:
      analysisSettings.openRouterPrivacyMode = analysisSettings.lastBYOKOpenRouterPrivacyMode
      analysisSettings.nonZDRConsentVersion = analysisSettings.lastBYOKNonZDRConsentVersion
    }
  }

  private func selectOpenRouterAccessMode(_ mode: OpenRouterAccessMode) async throws {
    guard analysisSettings.openRouterAccessMode != mode else { return }
    if let pendingAnalysisTask {
      pendingAnalysisTask.cancel()
      _ = try? await pendingAnalysisTask.value
      self.pendingAnalysisTask = nil
      pendingAnalysisRunId = nil
    }
    analysisWork?.cancel()
    if let analysisWork { await analysisWork.value }
    self.analysisWork = nil
    await analysisCoordinator.set(nil, for: .openRouter)
    try repository.clearEmailAnalysisRetryState()

    let previousMode = analysisSettings.openRouterAccessMode
    // Remember model + ZDR preference for the mode we're leaving.
    rememberModelSelection(analysisSettings.openRouterModelID, for: previousMode)
    rememberPrivacySelection(
      privacyMode: analysisSettings.openRouterPrivacyMode,
      consentVersion: analysisSettings.nonZDRConsentVersion,
      for: previousMode
    )

    analysisSettings.openRouterAccessMode = mode

    // Restore remembered model + ZDR preference for the mode we're entering.
    switch mode {
    case .freeShared:
      analysisSettings.openRouterModelID = analysisSettings.lastFreeOpenRouterModelID
    case .bringYourOwnKey:
      analysisSettings.openRouterModelID = analysisSettings.lastBYOKOpenRouterModelID
    }
    restorePrivacySelection(for: mode)

    try saveAnalysisSettings()
    publishAnalysisSettings()
    openRouterModels = []
    store.openRouterModels = []
    store.openRouterConnectionState = .validating
    await restoreOpenRouterConfiguration()
    // Keep OpenRouter active across Free/BYOK switches when the restored mode
    // already has a compatible model + privacy setup (avoids tapping Use
    // OpenRouter again after every mode change).
    await activateRestoredOpenRouterModeIfPossible()
  }

  /// After a Free/BYOK switch, keep analysis active when the restored model and
  /// privacy settings are compatible with the new catalog.
  private func activateRestoredOpenRouterModeIfPossible() async {
    guard case .connected = store.openRouterConnectionState else {
      analysisSettings.selectedProvider = nil
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      return
    }
    guard let modelID = analysisSettings.openRouterModelID,
          let model = openRouterModels.first(where: { $0.id == modelID }) else {
      analysisSettings.selectedProvider = nil
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      return
    }
    if analysisSettings.openRouterAccessMode == .freeShared, !model.isFree {
      analysisSettings.selectedProvider = nil
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      return
    }
    if analysisSettings.openRouterPrivacyMode == .zdrOnly, !model.hasZDREndpoint {
      // Mode previously required ZDR, but remembered model is non-ZDR — need consent.
      analysisSettings.selectedProvider = nil
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      store.analysisStatusDetail =
        "Confirm non-ZDR use for this model, or choose a ZDR model."
      return
    }

    analysisSettings.selectedProvider = .openRouter
    try? saveAnalysisSettings()
    publishAnalysisSettings()
    EmailBackgroundTasks.scheduleAnalysis(requiresNetworkConnectivity: true)
    analysisWork = Task(priority: .utility) { [weak self] in
      _ = try? await self?.runPendingAnalysis()
      self?.analysisWork = nil
    }
  }

  private func saveOpenRouterKey(_ apiKey: String) async throws {
    analysisSettings.openRouterAccessMode = .bringYourOwnKey
    try saveAnalysisSettings()
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    store.openRouterConnectionState = .validating
    do {
      let info = try await openRouterClient.validateKey(trimmed)
      let models = try await openRouterClient.models(apiKey: trimmed)
      try await openRouterVault.save(apiKey: trimmed, dimoUserId: userId)
      openRouterModels = models
      store.openRouterModels = models
      store.openRouterConnectionState = .connected(
        label: info.label,
        creditLimit: info.limit,
        limitRemaining: info.limitRemaining
      )
      if analysisSettings.openRouterModelID == nil {
        if let remembered = analysisSettings.lastBYOKOpenRouterModelID,
           models.contains(where: { $0.id == remembered }) {
          analysisSettings.openRouterModelID = remembered
        } else if models.contains(where: { $0.id == OpenRouterClient.defaultModelID }) {
          analysisSettings.openRouterModelID = OpenRouterClient.defaultModelID
        }
        if let selected = analysisSettings.openRouterModelID {
          rememberModelSelection(selected, for: .bringYourOwnKey)
          try saveAnalysisSettings()
        }
      } else {
        rememberModelSelection(analysisSettings.openRouterModelID, for: .bringYourOwnKey)
        try saveAnalysisSettings()
      }
      publishAnalysisSettings()
    } catch {
      store.openRouterConnectionState = .failed(error.localizedDescription)
      throw error
    }
  }

  private func removeOpenRouterKey() async throws {
    try await switchProvider(to: analysisSettings.selectedProvider == .openRouter ? nil : analysisSettings.selectedProvider)
    try await openRouterVault.remove(dimoUserId: userId)
    if analysisSettings.openRouterAccessMode == .bringYourOwnKey {
      openRouterModels = []
      store.openRouterModels = []
      store.openRouterConnectionState = .disconnected
    }
    await analysisCoordinator.set(nil, for: .openRouter)
  }

  private func refreshOpenRouterModels() async throws {
    switch analysisSettings.openRouterAccessMode {
    case .freeShared:
      guard let transport = openRouterConvexTransport else {
        throw OpenRouterConvexTransportError.notReady
      }
      store.openRouterConnectionState = .validating
      let models = try await transport.listFreeModels()
      openRouterModels = models
      store.openRouterModels = models
      store.openRouterConnectionState = .connected(
        label: "Free models",
        creditLimit: nil,
        limitRemaining: nil
      )
      try ensureDefaultFreeModelSelection(in: models)
      publishAnalysisSettings()
      if let selected = analysisSettings.openRouterModelID,
         !models.contains(where: { $0.id == selected }) {
        store.analysisStatusDetail = "The selected OpenRouter model is no longer available."
      }
    case .bringYourOwnKey:
      guard let credential = try await openRouterVault.credential(dimoUserId: userId) else {
        throw EmailFeatureControllerError.openRouterNotConfigured
      }
      let info = try await openRouterClient.validateKey(credential.apiKey)
      openRouterModels = try await openRouterClient.models(apiKey: credential.apiKey)
      store.openRouterModels = openRouterModels
      store.openRouterConnectionState = .connected(
        label: info.label,
        creditLimit: info.limit,
        limitRemaining: info.limitRemaining
      )
      if let selected = analysisSettings.openRouterModelID,
         !openRouterModels.contains(where: { $0.id == selected }) {
        store.analysisStatusDetail = "The selected OpenRouter model is no longer available."
      }
    }
  }

  private func selectOpenRouterModel(_ modelID: String, allowNonZDR: Bool) async throws {
    guard let model = openRouterModels.first(where: { $0.id == modelID }) else {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    if analysisSettings.openRouterAccessMode == .freeShared, !model.isFree {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    if !model.hasZDREndpoint, !allowNonZDR {
      throw EmailFeatureControllerError.nonZDRConsentRequired
    }

    let privacyMode: OpenRouterPrivacyMode =
      model.hasZDREndpoint && !allowNonZDR ? .zdrOnly : .allowNonZDR
    let consentVersion: Int? = allowNonZDR ? 1 : nil
    let alreadyOnOpenRouter = analysisSettings.selectedProvider == .openRouter
    let unchanged =
      alreadyOnOpenRouter
      && analysisSettings.openRouterModelID == model.id
      && analysisSettings.openRouterPrivacyMode == privacyMode
      && analysisSettings.nonZDRConsentVersion == consentVersion

    analysisSettings.openRouterModelID = model.id
    rememberModelSelection(model.id, for: analysisSettings.openRouterAccessMode)
    analysisSettings.openRouterPrivacyMode = privacyMode
    analysisSettings.nonZDRConsentVersion = consentVersion
    rememberPrivacySelection(
      privacyMode: privacyMode,
      consentVersion: consentVersion,
      for: analysisSettings.openRouterAccessMode
    )

    if unchanged {
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      return
    }
    if alreadyOnOpenRouter {
      try saveAnalysisSettings()
      publishAnalysisSettings()
      await analysisCoordinator.set(nil, for: .openRouter)
      return
    }

    try await switchProvider(to: .openRouter)
  }

  private func selectSyncWindow(_ window: EmailSyncWindow) async throws {
    guard analysisSettings.syncWindow != window else { return }
    await syncCoordinator?.stop()
    let previous = analysisSettings.syncWindow
    analysisSettings.syncWindow = window
    do {
      try saveAnalysisSettings()
      try enforceRetention()

      let accounts = try repository.emailAccounts()
      for account in accounts {
        try repository.updateEmailAccount(id: account.id) { value in
          value.historyId = nil
          value.backfillPageToken = nil
          value.backfillCompletedAt = nil
          value.syncState = .backfilling
          value.lastError = nil
        }
      }
      publishAnalysisSettings()
      guard !accounts.isEmpty else { return }
      try await refresh(accountId: nil)
    } catch {
      analysisSettings.syncWindow = previous
      try? saveAnalysisSettings()
      publishAnalysisSettings()
      throw error
    }
  }

  private func switchProvider(to provider: EmailAnalysisProvider?) async throws {
    if analysisSettings.selectedProvider == provider { return }
    if let pendingAnalysisTask {
      pendingAnalysisTask.cancel()
      _ = try? await pendingAnalysisTask.value
      self.pendingAnalysisTask = nil
      pendingAnalysisRunId = nil
    }
    analysisWork?.cancel()
    if let analysisWork { await analysisWork.value }
    self.analysisWork = nil
    await analysisCoordinator.set(nil, for: .openRouter)
    try repository.clearEmailAnalysisRetryState()
    analysisSettings.selectedProvider = provider
    try saveAnalysisSettings()
    publishAnalysisSettings()
    EmailBackgroundTasks.scheduleAnalysis(
      requiresNetworkConnectivity: provider == .openRouter
    )
    guard provider != nil else { return }
    analysisWork = Task(priority: .utility) { [weak self] in
      _ = try? await self?.runPendingAnalysis()
      self?.analysisWork = nil
    }
  }

  private func retryAnalysis(messageID: String) async throws {
    guard let message = try repository.emailMessage(key: messageID),
          message.state == .analysisFailed else {
      throw EmailRepositoryError.invalidSuggestionState
    }
    guard analysisSettings.selectedProvider == .openRouter else {
      throw EmailFeatureControllerError.analysisNotConfigured
    }
    guard try await preparedOpenRouterAnalyzer() != nil else {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    try repository.clearEmailAnalysisRetryState()
    try repository.retryEmailAnalysis(messageKey: messageID, providerOverride: .openRouter)
    try refreshEmailUIFromRepository()
    _ = try await runPendingAnalysis(maximumCount: 1)
  }

  private func retryOpenRouterConnection() async throws {
    store.openRouterConnectionState = .validating
    do {
      try await refreshOpenRouterModels()
      try repository.clearEmailAnalysisRetryState()
      publishAnalysisSettings()
      try await resumeOpenRouterAnalysisQueue()
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      store.openRouterConnectionState = .failed(message)
      if analysisSettings.selectedProvider == .openRouter {
        store.analysisStatusDetail = message
      }
      throw error
    }
  }

  private func retryOpenRouterAnalysis() async throws {
    guard analysisSettings.selectedProvider == .openRouter else {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    guard try await preparedOpenRouterAnalyzer() != nil else {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    try repository.clearEmailAnalysisRetryState()
    store.analysisStatusDetail = "Retrying OpenRouter analysis…"
    try await resumeOpenRouterAnalysisQueue()
  }

  private func resumeOpenRouterAnalysisQueue() async throws {
    guard analysisSettings.selectedProvider == .openRouter else { return }
    if let analysisWork {
      analysisWork.cancel()
      await analysisWork.value
      self.analysisWork = nil
    }
    if let pendingAnalysisTask {
      pendingAnalysisTask.cancel()
      _ = try? await pendingAnalysisTask.value
      self.pendingAnalysisTask = nil
      pendingAnalysisRunId = nil
    }
    _ = try await runPendingAnalysis()
  }

  private func reanalyzeAllEmails() async throws {
    guard analysisSettings.selectedProvider == .openRouter else {
      throw EmailFeatureControllerError.analysisNotConfigured
    }
    guard try await preparedOpenRouterAnalyzer() != nil else {
      throw EmailFeatureControllerError.openRouterNotConfigured
    }
    if let analysisWork {
      analysisWork.cancel()
      await analysisWork.value
      self.analysisWork = nil
    }
    if let pendingAnalysisTask {
      pendingAnalysisTask.cancel()
      _ = try? await pendingAnalysisTask.value
      self.pendingAnalysisTask = nil
      pendingAnalysisRunId = nil
    }
    try repository.clearEmailAnalysisRetryState()

    let resetCount = try repository.resetEmailMessagesForReanalysis()
    try refreshEmailUIFromRepository()
    await Task.yield()

    guard resetCount > 0 else { return }
    _ = try await runPendingAnalysis()
  }

  private func refreshEmailUIFromRepository() throws {
    suggestionRecords = try repository.emailSuggestions()
    messageSummaries = try repository.emailMessageSummaries()
    store.purchaseReview = nil
    store.refundReview = nil
    store.emailDetail = nil
    publishSuggestions()
    publishAllEmails()
  }

  private func resumeAnalysisIfNeeded() async {
    guard !stopped else { return }
    guard analysisSettings.selectedProvider == .openRouter else { return }
    guard analysisWork == nil, pendingAnalysisTask == nil else { return }
    analysisWork = Task(priority: .utility) { [weak self] in
      _ = try? await self?.runPendingAnalysis()
      self?.analysisWork = nil
    }
  }

  private func saveAnalysisSettings() throws {
    analysisSettings.updatedAt = Int(Date().timeIntervalSince1970 * 1_000)
    try repository.saveEmailAnalysisSettings(analysisSettings)
  }

  private func publishAnalysisSettings() {
    store.selectedProvider = analysisSettings.selectedProvider
    store.openRouterAccessMode = analysisSettings.openRouterAccessMode
    store.selectedOpenRouterModelID = analysisSettings.openRouterModelID
    store.openRouterPrivacyMode = analysisSettings.openRouterPrivacyMode
    store.syncWindow = analysisSettings.syncWindow
    switch analysisSettings.selectedProvider {
    case .openRouter:
      let modeLabel = analysisSettings.openRouterAccessMode == .freeShared
        ? "OpenRouter Free"
        : "OpenRouter"
      store.analysisStatusDetail = analysisSettings.openRouterModelID.map {
        "\(modeLabel) · \($0)"
      } ?? "Choose an OpenRouter model."
    case nil:
      store.analysisStatusDetail = EmailFeatureControllerError.analysisNotConfigured.localizedDescription
    }
  }

  private func scheduleOpenRouterRetry(for error: OpenRouterClientError) throws {
    let previous = try repository.emailAnalysisRetryState()
    let attempt = min((previous?.attempt ?? 0) + 1, 6)
    let fallbackDelays: [TimeInterval] = [900, 1_800, 3_600, 7_200, 14_400, 21_600]
    let base = error.retryAfter ?? fallbackDelays[attempt - 1]
    let jitter = error.retryAfter == nil ? Double.random(in: 0...(base * 0.1)) : 0
    let notBeforeDate = Date().addingTimeInterval(base + jitter)
    try repository.saveEmailAnalysisRetryState(EmailAnalysisRetryState(
      attempt: attempt,
      notBefore: Int(notBeforeDate.timeIntervalSince1970 * 1_000),
      reason: error.localizedDescription,
      lastHTTPStatus: error.statusCode,
      updatedAt: Int(Date().timeIntervalSince1970 * 1_000)
    ))
    EmailBackgroundTasks.scheduleAnalysis(
      earliest: notBeforeDate,
      requiresNetworkConnectivity: true
    )
  }

  private var hasConnectedAccounts: Bool {
    accountRecords.contains { $0.syncState != .disconnected }
  }

  private func acceptPurchase(_ draft: EmailUIPurchaseReviewDraft) async throws {
    guard let amount = Decimal(string: draft.amount, locale: Locale(identifier: "en_US_POSIX")),
          let amountMinor = Self.minorUnits(amount), amountMinor > 0,
          let categoryId = draft.categoryID,
          let category = categories.first(where: { $0.id == categoryId }) else {
      throw EmailFeatureControllerError.invalidSuggestion
    }
    let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    let paymentMethodId = Self.resolvedPaymentMethodId(
      draft.paymentMethodID,
      paymentMethods: paymentMethods
    )
    let transaction = TransactionEntity(
      id: "tx_\(UUID().uuidString.lowercased())",
      name: merchant.isEmpty ? category.name : merchant,
      amountMinor: amountMinor,
      occurredAt: min(
        Int(draft.occurredAt.timeIntervalSince1970 * 1_000),
        Int(Date().timeIntervalSince1970 * 1_000)
      ),
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      currency: currency.rawValue
    )
    let recurring = draft.isRecurring ? RecurringEntity(
      id: "rec_\(UUID().uuidString.lowercased())",
      name: transaction.name,
      amountMinor: amountMinor,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      frequency: draft.recurringFrequency,
      anchorDate: DateHelpers.localDateKey(draft.occurredAt),
      paused: false,
      currency: currency.rawValue
    ) : nil
    let sourceIds = draft.sourceMessageIDs.isEmpty ? [draft.suggestionID] : draft.sourceMessageIDs
    try repository.acceptEmailSuggestions(
      messageKeys: sourceIds,
      transaction: transaction,
      recurring: recurring
    )
  }

  private func publishAccounts() {
    store.accounts = accountRecords.map { account in
      EmailUIAccount(
        id: account.id,
        emailAddress: account.emailAddress,
        syncState: Self.uiSyncState(account.syncState),
        statusDetail: accountStatusDetail(account),
        lastSuccessfulSyncAt: account.lastSuccessfulSyncAt.map(Self.date(milliseconds:)),
        lastError: account.lastError,
        initialScanComplete: account.backfillCompletedAt != nil
      )
    }
  }

  private func publishSuggestions() {
    let accountEmail = Dictionary(uniqueKeysWithValues: accountRecords.map { ($0.id, $0.emailAddress) })
    let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
    let methods = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })
    let individual: [EmailUISuggestion] = suggestionRecords.compactMap {
      message -> EmailUISuggestion? in
      guard let analyzerKind = message.analyzerType,
            analyzerKind == .gemma || analyzerKind == .openRouter,
            let classification = message.classification,
            let kind = EmailUISuggestionKind(rawValue: classification.rawValue),
            let status = Self.uiStatus(message.state) else { return nil }
      let analyzer: EmailUIAnalyzer = analyzerKind == .openRouter ? .openRouter : .gemma
      let amount = message.amount.flatMap {
        Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX"))
      }
      let amountMinor = amount.flatMap(Self.minorUnits)
      let occurredMilliseconds = message.occurredAt ?? message.internalDate
      let duplicateDescriptions = EmailSuggestionSelectors.likelyDuplicateDescriptions(
        merchant: message.merchant,
        amountMinor: amountMinor,
        occurredAt: message.occurredAt,
        transactions: transactions
      )
      let partialSource = [message.subject, message.snippet, message.normalizedBodyText ?? ""]
        .joined(separator: "\n")
      let partial = EmailSuggestionSelectors.isExplicitlyPartialRefund(partialSource)
      let refundMatches = EmailSuggestionSelectors.refundMatches(
        evidence: EmailRefundEvidence(
          merchant: message.merchant,
          amountMinor: amountMinor,
          currency: message.currency,
          occurredAt: occurredMilliseconds,
          paymentLastFour: message.paymentLastFour,
          reference: message.reference
        ),
        activeCurrency: currency,
        transactions: transactions,
        paymentMethods: paymentMethods,
        isExplicitlyPartial: partial
      )
      let refundCandidates = refundMatches.candidates.compactMap { match -> EmailUIRefundCandidate? in
        guard let transaction = transactions.first(where: { $0.id == match.transactionId }),
              let transactionAmountMinor = transaction.amountMinor,
              let occurredAt = transaction.occurredAt else { return nil }
        return EmailUIRefundCandidate(
          id: transaction.id,
          merchant: transaction.name,
          amount: Decimal(transactionAmountMinor) / 100,
          currency: currency,
          occurredAt: Self.date(milliseconds: occurredAt),
          categoryName: transaction.category,
          paymentMethodLabel: transaction.paymentMethodId.flatMap { methods[$0]?.label },
          matchReason: match.reasons.joined(separator: " · ")
        )
      }
      return EmailUISuggestion(
        id: message.key,
        accountID: message.accountId,
        accountEmail: accountEmail[message.accountId] ?? message.accountId,
        kind: kind,
        status: status,
        sender: message.senderName ?? message.senderAddress,
        subject: message.subject,
        snippet: message.snippet,
        receivedAt: Self.date(milliseconds: message.internalDate),
        merchant: message.merchant,
        amount: amount,
        currency: message.currency,
        occurredAt: message.occurredAt.map(Self.date(milliseconds:)),
        categoryID: message.categoryId,
        categoryName: message.categoryId.flatMap { categoryNames[$0] },
        paymentMethodID: message.paymentMethodId,
        paymentMethodLabel: message.paymentMethodId.flatMap { methods[$0]?.label },
        paymentLastFour: message.paymentLastFour,
        reference: message.reference,
        analyzer: analyzer,
        modelVersion: message.modelVersion,
        currencyWarning: message.currency.flatMap { suggestionCurrency in
          suggestionCurrency == currency
            ? nil
            : "Email amount is \(suggestionCurrency.rawValue); Dimo is set to \(currency.rawValue). No conversion will be performed."
        },
        possibleDuplicateDescriptions: duplicateDescriptions,
        isFullRefund: refundMatches.isFullRefund,
        refundCandidates: refundCandidates,
        preselectedRefundTransactionID: refundMatches.preselectedTransactionId
      )
    }
    store.suggestions = groupedSuggestions(individual, records: suggestionRecords)
  }

  private func groupedSuggestions(
    _ suggestions: [EmailUISuggestion],
    records: [EmailMessageRecordModel]
  ) -> [EmailUISuggestion] {
    let recordById = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
    let reviewedRecords = (try? repository.reviewedEmailPurchaseSources()) ?? []
    var grouped: [String: [EmailUISuggestion]] = [:]
    for suggestion in suggestions {
      let record = recordById[suggestion.id]
      let sharedGroup = record?.purchaseGroupId.flatMap { $0 == suggestion.id ? nil : $0 }
      grouped[sharedGroup ?? suggestion.id, default: []].append(suggestion)
    }

    return grouped.values.compactMap { members -> EmailUISuggestion? in
      let ordered = members.sorted {
        if $0.kind != $1.kind { return $0.kind == .purchase }
        return $0.receivedAt > $1.receivedAt
      }
      guard var primary = ordered.first else { return nil }
      let isPurchaseGroup = ordered.count > 1
        && ordered.contains(where: { $0.kind == .purchase })
        && ordered.contains(where: { $0.kind == .debit })
      if isPurchaseGroup {
        let debit = ordered.first { $0.kind == .debit }
        primary.groupID = recordById[primary.id]?.purchaseGroupId
        primary.sourceMessageIDs = ordered.map(\.id)
        primary.sourceSenders = ordered.map(\.sender)
        primary.sources = ordered.map {
          EmailUISourceSummary(id: $0.id, sender: $0.sender, subject: $0.subject)
        }
        primary.paymentMethodID = debit?.paymentMethodID ?? primary.paymentMethodID
        primary.paymentMethodLabel = debit?.paymentMethodLabel ?? primary.paymentMethodLabel
        primary.paymentLastFour = debit?.paymentLastFour ?? primary.paymentLastFour
        primary.occurredAt = debit?.occurredAt ?? primary.occurredAt
        primary.possibleDuplicateDescriptions = Array(
          Set(ordered.flatMap(\.possibleDuplicateDescriptions))
        ).sorted()
      } else {
        primary.sourceMessageIDs = [primary.id]
        primary.sourceSenders = [primary.sender]
        primary.sources = [
          EmailUISourceSummary(id: primary.id, sender: primary.sender, subject: primary.subject),
        ]
      }

      if primary.status == .pendingPurchase,
         primary.sourceMessageIDs.count == 1,
         let pending = recordById[primary.id],
         let reviewed = EmailPurchaseGroupingSelector.uniqueReviewedMatch(
           for: pending,
           reviewed: reviewedRecords
         ),
         let transactionId = reviewed.linkedTransactionId,
         let transaction = transactions.first(where: { $0.id == transactionId }) {
        primary.lateMatch = EmailUILatePurchaseMatch(
          reviewedSourceMessageID: reviewed.key,
          transactionID: transactionId,
          transactionName: transaction.name
        )
      }
      return primary
    }
    .sorted { $0.receivedAt > $1.receivedAt }
  }

  private func publishAllEmails() {
    let accountEmails = Dictionary(
      uniqueKeysWithValues: accountRecords.map { ($0.id, $0.emailAddress) }
    )
    store.allEmails = messageSummaries.map { message in
      EmailUIMessage(
        id: message.id,
        accountEmail: accountEmails[message.accountId] ?? message.accountId,
        sender: message.senderName ?? message.senderAddress,
        subject: message.subject,
        snippet: message.snippet,
        receivedAt: Self.date(milliseconds: message.internalDate),
        analyzer: Self.uiAnalyzer(message.analyzerType),
        modelVersion: message.modelVersion,
        classification: message.classification.flatMap {
          EmailUISuggestionKind(rawValue: $0.rawValue)
        },
        analysisState: Self.uiAnalysisState(message.state),
        analyzedAt: message.analyzedAt.map(Self.date(milliseconds:)),
        reviewedAt: message.reviewedAt.map(Self.date(milliseconds:))
      )
    }
  }

  func sourceEmailDetail(forTransactionId transactionId: String) -> EmailUIEmailDetail? {
    sourceEmailDetails(forTransactionId: transactionId).first
  }

  func sourceEmailDetails(forTransactionId transactionId: String) -> [EmailUIEmailDetail] {
    guard let messages = try? repository.emailMessages(linkedTransactionId: transactionId) else {
      return []
    }
    return messages.compactMap { try? loadEmailDetail(messageId: $0.key) }
  }

  private func loadEmailDetail(messageId: String) throws -> EmailUIEmailDetail {
    guard let message = try repository.emailMessage(key: messageId) else {
      throw EmailRepositoryError.messageNotFound
    }
    let accountEmail = accountRecords.first { $0.id == message.accountId }?.emailAddress
      ?? message.accountId
    let retainedBody = message.normalizedBodyText?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let hasRetainedBody = !(retainedBody?.isEmpty ?? true)
    let fallback = message.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    let senderName = message.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return EmailUIEmailDetail(
      id: message.id,
      accountEmail: accountEmail,
      sender: (senderName?.isEmpty == false ? senderName : nil) ?? message.senderAddress,
      senderAddress: message.senderAddress,
      subject: message.subject,
      bodyText: hasRetainedBody ? (retainedBody ?? fallback) : fallback,
      receivedAt: Self.date(milliseconds: message.internalDate),
      analyzer: Self.uiAnalyzer(message.analyzerType),
      modelVersion: message.modelVersion,
      classification: message.classification.flatMap {
        EmailUISuggestionKind(rawValue: $0.rawValue)
      },
      analysisState: Self.uiAnalysisState(message.state),
      isBodyRetained: hasRetainedBody
    )
  }

  private static func uiAnalysisState(_ state: EmailSuggestionState) -> EmailUIMessageAnalysisState {
    switch state {
    case .pendingAnalysis: return .pending
    case .analysisFailed: return .failed
    case .pendingPurchase, .pendingRefund: return .needsReview
    case .unactionable: return .analyzed
    case .added: return .added
    case .refundApplied: return .refundApplied
    case .dismissed: return .dismissed
    case .expired: return .expired
    }
  }

  private static func uiAnalyzer(_ analyzer: EmailAnalyzerKind?) -> EmailUIAnalyzer? {
    switch analyzer {
    case .gemma: return .gemma
    case .openRouter: return .openRouter
    case .rules, nil: return nil
    }
  }

  private static func uiSyncState(_ state: EmailAccountSyncState) -> EmailUIAccountSyncState {
    switch state {
    case .idle: return .idle
    case .backfilling, .syncing: return .syncing
    case .rateLimited: return .rateLimited
    case .offline: return .offline
    case .failed: return .failed
    case .needsReconnect: return .needsReconnect
    case .disconnected: return .disconnected
    }
  }

  private func accountStatusDetail(_ account: EmailAccountRecordModel) -> String? {
    switch account.syncState {
    case .backfilling: return "Scanning the latest \(analysisSettings.syncWindow.title)"
    case .syncing: return "Checking Gmail history"
    case .rateLimited: return "Paused briefly · retrying automatically"
    case .offline: return "Waiting for a network connection"
    case .failed: return account.lastError
    case .needsReconnect:
      return account.lastError
        ?? "Gmail access expired or was revoked. Reconnect this account to continue."
    case .disconnected: return "Reconnect to sync new mail. Reviewed suggestions are kept."
    case .idle: return nil
    }
  }

  private static func uiStatus(_ state: EmailSuggestionState) -> EmailUISuggestionStatus? {
    switch state {
    case .pendingAnalysis, .analysisFailed: return nil
    case .pendingPurchase: return .pendingPurchase
    case .pendingRefund: return .pendingRefund
    case .added: return .added
    case .refundApplied: return .refundApplied
    case .dismissed: return .dismissed
    case .unactionable: return .unactionable
    case .expired: return .expired
    }
  }

  private static func resolvedPaymentMethodId(
    _ requested: String?,
    paymentMethods: [PaymentMethodOption]
  ) -> String {
    if let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines),
       !requested.isEmpty,
       paymentMethods.contains(where: { $0.id == requested }) {
      return requested
    }
    return paymentMethods.first(where: { $0.isDefault && !$0.archived })?.id
      ?? paymentMethods.first(where: { !$0.archived })?.id
      ?? SeedData.cashPaymentMethod.id
  }

  private static func minorUnits(_ amount: Decimal) -> Int? {
    guard amount > 0 else { return nil }
    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 2, .plain)
    let number = NSDecimalNumber(decimal: rounded).multiplying(byPowerOf10: 2)
    guard number != .notANumber else { return nil }
    return number.intValue
  }

  private static func lastFour(in value: String) -> String? {
    let digits = value.filter(\.isNumber)
    return digits.count >= 4 ? String(digits.suffix(4)) : nil
  }

  private static func date(milliseconds: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
  }
}
