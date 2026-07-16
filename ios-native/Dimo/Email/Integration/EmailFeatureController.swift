import Foundation
import GRDB
import Network
import OSLog
import UIKit

private let emailAnalysisLogger = Logger(
  subsystem: "app.dimo.ios",
  category: "EmailAnalysis"
)

enum EmailFeatureControllerError: LocalizedError {
  case gmailNotConfigured
  case invalidSuggestion
  case modelUnavailable
  case gemmaUnavailable(String)
  case analysisNotConfigured
  case openRouterNotConfigured
  case nonZDRConsentRequired

  var errorDescription: String? {
    switch self {
    case .gmailNotConfigured:
      return "Gmail OAuth is not configured for this build."
    case .invalidSuggestion:
      return "The email suggestion is missing a valid amount, date, or category."
    case .modelUnavailable:
      return "The Gemma model manager is unavailable in this build."
    case .gemmaUnavailable(let reason):
      return reason
    case .analysisNotConfigured:
      return "Email analysis is not configured. Choose Local Gemma or OpenRouter in Email settings."
    case .openRouterNotConfigured:
      return "Add a valid OpenRouter key and choose a model first."
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

  private let userId: String
  private let repository: Repository
  private let vault: GmailCredentialVault
  private let oauthClient: GmailOAuthClient?
  private let tokenManager: GmailAccessTokenManager?
  private let syncCoordinator: EmailSyncCoordinator?
  private let modelManager: GemmaModelManager?
  private let manifest: GemmaModelManifest?
  private let gemmaThrottle = EmailAnalysisStartThrottle.gemma
  private let openRouterThrottle = EmailAnalysisStartThrottle.openRouter
  private let openRouterVault = OpenRouterCredentialVault()
  private let openRouterClient = OpenRouterClient()
  private let analysisCoordinator = EmailAnalysisCoordinator()

  private var router: EmailLanguageModelRouter?
  private var gemmaAnalyzer: GemmaEmailAnalyzer?
  private var analysisSettings: EmailAnalysisSettings = .defaults
  private var openRouterModels: [OpenRouterModel] = []
  private var accountsObservation: DatabaseCancellable?
  private var suggestionsObservation: DatabaseCancellable?
  private var messageSummariesObservation: DatabaseCancellable?
  private var modelStateTask: Task<Void, Never>?
  private var foregroundWork: Task<Void, Never>?
  private var analysisWork: Task<Void, Never>?
  private var pendingAnalysisTask: Task<Int, Error>?
  private var pendingAnalysisRunId: UUID?
  private var notificationTokens: [NSObjectProtocol] = []
  private let pathMonitor = NWPathMonitor()
  private let pathQueue = DispatchQueue(label: "app.dimo.ios.email-network")

  private var accountRecords: [EmailAccountRecordModel] = []
  private var suggestionRecords: [EmailMessageRecordModel] = []
  private var messageSummaries: [EmailMessageSummaryModel] = []
  private var categories: [CategoryEntity] = []
  private var paymentMethods: [PaymentMethodOption] = []
  private var transactions: [Transaction] = []
  private var currency: Currency = .INR
  private var lastModelProgress = 0.0
  private var lastDownloadAllowedCellular = false
  private var installedModelVersionPrepared: String?
  private var stopped = false

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

    if let modelServices = GemmaModelServicesProvider.shared() {
      manifest = modelServices.manifest
      modelManager = modelServices.manager
      store.modelDownloadSizeDescription = Self.fileSizeDescription(
        bytes: modelServices.manifest.exactByteCount,
        prefix: "about "
      )
      store.modelStorageRequirementDescription = Self.fileSizeDescription(
        bytes: modelServices.manifest.minimumFreeStorageBytes,
        suffix: " free storage required"
      )
    } else {
      manifest = nil
      modelManager = nil
    }
  }

  func start(
    categories: [CategoryEntity],
    paymentMethods: [PaymentMethodOption],
    transactions: [Transaction],
    currency: Currency
  ) async {
    stopped = false
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
    startResourceMonitoring()
    EmailBackgroundWorkRegistry.provider = self
    EmailBackgroundTasks.schedule(
      requiresAnalysisNetworkConnectivity: analysisSettings.selectedProvider == .openRouter
    )

    do {
      try enforceRetention()
    } catch {
      store.lastActionError = "Email retention cleanup failed: \(error.localizedDescription)"
    }

    if let modelManager {
      modelStateTask = Task { [weak self, modelManager] in
        let states = await modelManager.observeState()
        for await state in states {
          guard !Task.isCancelled else { return }
          await self?.consumeModelState(state)
        }
      }
      await modelManager.restoreBackgroundDownload()
    } else {
      store.modelState = .unavailable(message: "GemmaModelManifest.json could not be loaded.")
    }


    await restoreOpenRouterConfiguration()

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

  func tearDown() async {
    stopped = true
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
    modelStateTask?.cancel()
    accountsObservation?.cancel()
    suggestionsObservation?.cancel()
    messageSummariesObservation?.cancel()
    pathMonitor.cancel()
    notificationTokens.forEach(NotificationCenter.default.removeObserver)
    notificationTokens.removeAll()
    oauthClient?.cancel()
    await syncCoordinator?.stop()
    await router?.unload()
    gemmaAnalyzer = nil
    await analysisCoordinator.removeAll()
    await modelManager?.cancelDownload()
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
      // Initial range scans stay foreground-first. Background refresh only
      // advances accounts that already have a durable history cursor.
      let incrementalAccounts = try repository.emailAccounts().filter {
        $0.syncState != .disconnected
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
    guard let provider = analysisSettings.selectedProvider else { return true }
    if provider == .gemma {
      guard await canRunGemma(), await modelManager?.installedURLs() != nil else { return false }
    } else if let retry = try? repository.emailAnalysisRetryState(),
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
      await self?.router?.resourcePressureDidIncrease()
      self?.router = nil
      self?.gemmaAnalyzer = nil
      await self?.analysisCoordinator.set(nil, for: .gemma)
      self?.store.isGemmaAnalyzerAvailable = false
    }
  }

  private func configureActions() {
    store.configure(actions: EmailFeatureActions(
      connectAccount: { [weak self] in try await self?.connectAccount() },
      disconnectAccount: { [weak self] accountId in
        try await self?.disconnectAccount(accountId)
      },
      refresh: { [weak self] accountId in try await self?.refresh(accountId: accountId) },
      dismissSuggestion: { [weak self] suggestionId in
        try self?.repository.dismissEmailSuggestion(messageKey: suggestionId)
      },
      restoreSuggestion: { [weak self] suggestionId in
        try self?.repository.restoreDismissedEmailSuggestion(messageKey: suggestionId)
      },
      acceptPurchase: { [weak self] draft in try await self?.acceptPurchase(draft) },
      linkPurchaseToTransaction: { [weak self] suggestionId, transactionId in
        try self?.repository.linkEmailSuggestionToTransaction(
          messageKey: suggestionId,
          transactionId: transactionId
        )
      },
      applyFullRefund: { [weak self] suggestionId, transactionId in
        try self?.repository.applyFullEmailRefund(
          messageKey: suggestionId,
          transactionId: transactionId
        )
      },
      downloadModel: { [weak self] allowCellular in
        try await self?.startModelDownload(allowCellular: allowCellular)
      },
      pauseModelDownload: { [weak self] in await self?.modelManager?.pauseDownload() },
      cancelModelDownload: { [weak self] in await self?.modelManager?.cancelDownload() },
      retryModelDownload: { [weak self] in try await self?.retryModelDownload() },
      retryGemmaAnalysis: { [weak self] in try await self?.retryGemmaAnalysis() },
      reanalyzeAllEmails: { [weak self] in try await self?.reanalyzeAllEmails() },
      deleteModel: { [weak self] in try await self?.deleteModel() },
      selectGemma: { [weak self] in try await self?.selectGemma() },
      saveOpenRouterKey: { [weak self] key in try await self?.saveOpenRouterKey(key) },
      removeOpenRouterKey: { [weak self] in try await self?.removeOpenRouterKey() },
      refreshOpenRouterModels: { [weak self] in try await self?.refreshOpenRouterModels() },
      selectOpenRouterModel: { [weak self] modelID, allowNonZDR in
        try await self?.selectOpenRouterModel(modelID, allowNonZDR: allowNonZDR)
      },
      selectProvider: { [weak self] provider in try await self?.switchProvider(to: provider) },
      selectSyncWindow: { [weak self] window in try await self?.selectSyncWindow(window) },
      retryWithAlternateProvider: { [weak self] messageID in
        try await self?.retryWithAlternateProvider(messageID: messageID)
      },
      loadEmailDetail: { [weak self] messageId in
        guard let self else { throw EmailFeatureStoreError.messageNotFound }
        return try self.loadEmailDetail(messageId: messageId)
      }
    ))
  }

  private func startObservations() {
    accountRecords = (try? repository.emailAccounts()) ?? []
    suggestionRecords = (try? repository.emailSuggestions()) ?? []
    messageSummaries = (try? repository.emailMessageSummaries()) ?? []
    publishAccounts()
    publishSuggestions()
    publishAllEmails()
    accountsObservation = repository.observeEmailAccounts { [weak self] accounts in
      Task { @MainActor in
        self?.accountRecords = accounts
        self?.publishAccounts()
        self?.publishAllEmails()
      }
    }
    suggestionsObservation = repository.observeEmailSuggestions { [weak self] suggestions in
      Task { @MainActor in
        self?.suggestionRecords = suggestions
        self?.publishSuggestions()
      }
    }
    messageSummariesObservation = repository.observeEmailMessageSummaries { [weak self] messages in
      Task { @MainActor in
        self?.messageSummaries = messages
        self?.publishAllEmails()
      }
    }
  }

  private func startResourceMonitoring() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        self?.store.requiresCellularDownloadConfirmation = path.usesInterfaceType(.cellular)
      }
    }
    pathMonitor.start(queue: pathQueue)

    let center = NotificationCenter.default
    notificationTokens.append(center.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.unloadGemmaForPressure() }
    })
    notificationTokens.append(center.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard ProcessInfo.processInfo.thermalState == .serious
          || ProcessInfo.processInfo.thermalState == .critical else { return }
        await self?.unloadGemmaForPressure()
      }
    })
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
      // Restore reviewed suggestions from the synced entity store before Gmail
      // refresh so the same messages stay reviewed and are not re-analyzed.
      try repository.materializeSyncedEmailMessages(accountId: account.subject)
    } catch {
      try? await vault.remove(subject: account.subject, dimoUserId: userId)
      throw error
    }
    try await refresh(accountId: account.subject)
  }

  private func disconnectAccount(_ accountId: String) async throws {
    if let oauthClient {
      try await oauthClient.disconnect(subject: accountId, dimoUserId: userId)
    } else {
      try await vault.remove(subject: accountId, dimoUserId: userId)
    }
    await tokenManager?.invalidate(subject: accountId)
    _ = try repository.deleteEmailAccount(id: accountId)
    await unloadGemmaIfNoConnectedAccounts()
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
      var analyzedCount = 0
      do {
        analyzedCount = try await self.analyzePending(maximumCount: maximumCount)
        await self.unloadGemmaAfterAnalysis(analyzedCount: analyzedCount)
        return analyzedCount
      } catch {
        await self.unloadGemmaAfterAnalysis(analyzedCount: analyzedCount)
        throw error
      }
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
    guard let provider = message.analysisProviderOverride ?? analysisSettings.selectedProvider else {
      store.analysisStatusDetail = EmailFeatureControllerError.analysisNotConfigured.localizedDescription
      return .paused
    }
    let request = makeAnalysisRequest(message: message, body: body)

    do {
      let envelope: EmailAnalysisEnvelope
      switch provider {
      case .gemma:
        guard await canRunGemma(), let analyzer = await preparedGemmaAnalyzer() else {
          store.analysisStatusDetail = store.gemmaStatusDetail ?? "Local Gemma is not ready."
          return .paused
        }
        try await gemmaThrottle.waitForNextStart(
          minimumInterval: EmailGemmaPacing.minimumStartInterval(
            for: ProcessInfo.processInfo.thermalState
          )
        )
        envelope = try await analyzer.analyze(request)
        if let router { await publishRouterState(router) }
      case .openRouter:
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
        envelope = try await analyzer.analyze(request)
        try repository.clearEmailAnalysisRetryState()
      }
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
        "Email analysis failure; message: \(message.key, privacy: .private(mask: .hash)); provider: \(provider.rawValue, privacy: .public); model: \((provider == .gemma ? self.manifest?.version : self.analysisSettings.openRouterModelID) ?? "none", privacy: .public); error: \(String(reflecting: error), privacy: .public)"
      )
      if let router { await publishRouterState(router) }
      try repository.markEmailAnalysisFailed(
        messageKey: message.key,
        analyzer: provider == .gemma ? .gemma : .openRouter,
        modelVersion: provider == .gemma ? manifest?.version : analysisSettings.openRouterModelID
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
      promptVersion: manifest?.promptSchemaVersion ?? EmailAnalysisResult.schemaVersion,
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

  private func preparedGemmaAnalyzer() async -> GemmaEmailAnalyzer? {
    // The model is intentionally lazy. Merely installing Gemma or opening the
    // app must not map its weights into memory without a connected mailbox.
    guard hasConnectedAccounts else { return nil }
    guard let modelManager, let urls = await modelManager.installedURLs() else { return nil }
    if let gemmaAnalyzer { return gemmaAnalyzer }
    let runtime = LiteRTLMEmailRuntime(modelURL: urls.model, cacheURL: urls.cache)
    let next = EmailLanguageModelRouter(gemma: GemmaEmailLanguageModel(runtime: runtime))
    try? await next.load()
    router = next
    await publishRouterState(next)
    guard await next.availability() == .gemma, let manifest else { return nil }
    let analyzer = GemmaEmailAnalyzer(model: next, modelID: manifest.version)
    gemmaAnalyzer = analyzer
    await analysisCoordinator.set(analyzer, for: .gemma)
    return analyzer
  }

  private func publishRouterState(_ router: EmailLanguageModelRouter) async {
    store.isGemmaAnalyzerAvailable = await router.availability() == .gemma
    store.gemmaStatusDetail = await router.failureReason()
  }

  private func preparedOpenRouterAnalyzer() async throws -> OpenRouterEmailAnalyzer? {
    guard let credential = try await openRouterVault.credential(dimoUserId: userId),
          let modelID = analysisSettings.openRouterModelID else { return nil }
    guard let model = openRouterModels.first(where: { $0.id == modelID }) else {
      throw OpenRouterClientError.modelUnavailable
    }
    if analysisSettings.openRouterPrivacyMode == .zdrOnly, !model.hasZDREndpoint {
      throw OpenRouterClientError.modelUnavailable
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

  private func restoreOpenRouterConfiguration() async {
    do {
      guard let credential = try await openRouterVault.credential(dimoUserId: userId) else {
        store.openRouterConnectionState = .disconnected
        return
      }
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

  private func saveOpenRouterKey(_ apiKey: String) async throws {
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
      if analysisSettings.openRouterModelID == nil,
         models.contains(where: { $0.id == OpenRouterClient.defaultModelID }) {
        analysisSettings.openRouterModelID = OpenRouterClient.defaultModelID
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
    openRouterModels = []
    store.openRouterModels = []
    store.openRouterConnectionState = .disconnected
    await analysisCoordinator.set(nil, for: .openRouter)
  }

  private func refreshOpenRouterModels() async throws {
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

  private func selectOpenRouterModel(_ modelID: String, allowNonZDR: Bool) async throws {
    guard try await openRouterVault.credential(dimoUserId: userId) != nil,
          let model = openRouterModels.first(where: { $0.id == modelID }) else {
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
    analysisSettings.openRouterPrivacyMode = privacyMode
    analysisSettings.nonZDRConsentVersion = consentVersion

    // Same OpenRouter selection: skip teardown. Changing model/privacy while
    // already on OpenRouter only persists settings — the next analysis rebuilds
    // the analyzer from analysisSettings. Avoid cancelling in-flight work
    // (forceRestart made the picker feel stuck).
    if unchanged {
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

  private func selectGemma() async throws {
    try await switchProvider(to: .gemma)
    guard !store.modelState.isInstalled else { return }
    if store.requiresCellularDownloadConfirmation {
      store.analysisStatusDetail = "Local Gemma is selected. Confirm the model download in Email settings."
    } else {
      try await startModelDownload(allowCellular: false)
    }
  }

  private func selectSyncWindow(_ window: EmailSyncWindow) async throws {
    guard analysisSettings.syncWindow != window else { return }
    await syncCoordinator?.stop()
    let previous = analysisSettings.syncWindow
    analysisSettings.syncWindow = window
    do {
      try saveAnalysisSettings()
      try enforceRetention()

      // Gmail page tokens belong to the original query. Reset every account so
      // the new cutoff is applied from page one, including when the range grows.
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
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil
    await analysisCoordinator.set(nil, for: .gemma)
    try repository.clearEmailAnalysisRetryState()
    analysisSettings.selectedProvider = provider
    try saveAnalysisSettings()
    publishAnalysisSettings()
    EmailBackgroundTasks.scheduleAnalysis(
      requiresNetworkConnectivity: provider == .openRouter
    )
    guard provider != nil else { return }
    analysisWork = Task { [weak self] in
      _ = try? await self?.runPendingAnalysis()
      self?.analysisWork = nil
    }
  }

  private func retryWithAlternateProvider(messageID: String) async throws {
    guard let message = try repository.emailMessage(key: messageID),
          message.state == .analysisFailed else {
      throw EmailRepositoryError.invalidSuggestionState
    }
    let alternate: EmailAnalysisProvider = message.analyzerType == .openRouter ? .gemma : .openRouter
    switch alternate {
    case .gemma:
      guard store.modelState.isInstalled else {
        throw EmailFeatureControllerError.gemmaUnavailable("Download Local Gemma before retrying this email.")
      }
    case .openRouter:
      guard try await preparedOpenRouterAnalyzer() != nil else {
        throw EmailFeatureControllerError.openRouterNotConfigured
      }
    }
    try repository.retryEmailAnalysis(messageKey: messageID, providerOverride: alternate)
    try refreshEmailUIFromRepository()
    _ = try await runPendingAnalysis(maximumCount: 1)
  }

  private func saveAnalysisSettings() throws {
    analysisSettings.updatedAt = Int(Date().timeIntervalSince1970 * 1_000)
    try repository.saveEmailAnalysisSettings(analysisSettings)
  }

  private func publishAnalysisSettings() {
    store.selectedProvider = analysisSettings.selectedProvider
    store.selectedOpenRouterModelID = analysisSettings.openRouterModelID
    store.openRouterPrivacyMode = analysisSettings.openRouterPrivacyMode
    store.syncWindow = analysisSettings.syncWindow
    switch analysisSettings.selectedProvider {
    case .gemma:
      store.analysisStatusDetail = store.modelState.isInstalled
        ? "Local Gemma will load only when an email needs analysis."
        : "Local Gemma is selected. Download the model to begin analysis."
    case .openRouter:
      store.analysisStatusDetail = analysisSettings.openRouterModelID.map {
        "OpenRouter · \($0)"
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

  private func consumeModelState(_ state: GemmaModelInstallationState) async {
    switch state {
    case .notInstalled:
      store.modelState = .notInstalled
      store.isGemmaAnalyzerAvailable = false
      store.gemmaStatusDetail = nil
    case .checking:
      store.modelState = .checkingStorage
    case .downloading(let progress, _, _):
      lastModelProgress = progress
      store.modelState = .downloading(progress: progress)
    case .paused:
      store.modelState = .paused(progress: lastModelProgress)
    case .verifying, .initializing:
      store.modelState = .verifying
    case .installed(let version, _):
      store.modelState = .installed(version: version)
      if installedModelVersionPrepared != version {
        await router?.unload()
        router = nil
        gemmaAnalyzer = nil
        installedModelVersionPrepared = version
      }
      guard hasConnectedAccounts else {
        await router?.unload()
        router = nil
        store.isGemmaAnalyzerAvailable = false
        store.gemmaStatusDetail =
          "Gemma is installed and will load after a Gmail account is connected."
        return
      }
      if let router {
        await publishRouterState(router)
      } else {
        store.isGemmaAnalyzerAvailable = false
        store.gemmaStatusDetail =
          "Gemma is installed and will load when an email needs analysis."
      }
      if analysisSettings.selectedProvider == .gemma, analysisWork == nil {
        analysisWork = Task { [weak self] in
          _ = try? await self?.runPendingAnalysis()
          self?.analysisWork = nil
        }
      }
    case .failed(let message):
      store.modelState = .failed(message: message)
      store.isGemmaAnalyzerAvailable = false
      store.gemmaStatusDetail = message
    }
  }

  private func startModelDownload(allowCellular: Bool) async throws {
    guard let modelManager else { throw EmailFeatureControllerError.modelUnavailable }
    lastDownloadAllowedCellular = allowCellular
    await consumeModelState(.checking)
    try await modelManager.startDownload(allowCellular: allowCellular)
  }

  private func retryModelDownload() async throws {
    guard let modelManager else { throw EmailFeatureControllerError.modelUnavailable }
    try await modelManager.retryDownload(allowCellular: lastDownloadAllowedCellular)
  }

  private func retryGemmaAnalysis() async throws {
    guard analysisSettings.selectedProvider == .gemma else {
      throw EmailFeatureControllerError.gemmaUnavailable("Select Local Gemma before retrying its analysis.")
    }
    guard store.modelState.isInstalled else {
      throw EmailFeatureControllerError.gemmaUnavailable(
        "Download Gemma before retrying on-device analysis."
      )
    }
    if let reason = gemmaExecutionBlockReason() {
      store.gemmaStatusDetail = reason
      throw EmailFeatureControllerError.gemmaUnavailable(reason)
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
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil

    let resetCount = try repository.resetEmailMessagesForReanalysis()
    try refreshEmailUIFromRepository()
    await Task.yield()
    guard resetCount > 0 else { return }
    _ = try await runPendingAnalysis()
  }

  private func reanalyzeAllEmails() async throws {
    guard analysisSettings.selectedProvider != nil else {
      throw EmailFeatureControllerError.analysisNotConfigured
    }
    switch analysisSettings.selectedProvider {
    case .gemma:
      guard store.modelState.isInstalled else {
        throw EmailFeatureControllerError.gemmaUnavailable("Download Local Gemma before reanalysing emails.")
      }
    case .openRouter:
      guard try await preparedOpenRouterAnalyzer() != nil else {
        throw EmailFeatureControllerError.openRouterNotConfigured
      }
    case nil: break
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
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil
    try repository.clearEmailAnalysisRetryState()

    let resetCount = try repository.resetEmailMessagesForReanalysis()
    try refreshEmailUIFromRepository()
    await Task.yield()

    guard resetCount > 0 else { return }
    _ = try await runPendingAnalysis()
  }

  /// Publishes the reset transaction synchronously instead of waiting for the
  /// asynchronous GRDB observations, so SwiftUI shows the queued state before
  /// any analyzer is allowed to start filling the fields again.
  private func refreshEmailUIFromRepository() throws {
    suggestionRecords = try repository.emailSuggestions()
    messageSummaries = try repository.emailMessageSummaries()
    store.purchaseReview = nil
    store.refundReview = nil
    store.emailDetail = nil
    publishSuggestions()
    publishAllEmails()
  }

  private func deleteModel() async throws {
    guard let modelManager else { throw EmailFeatureControllerError.modelUnavailable }
    analysisWork?.cancel()
    pendingAnalysisTask?.cancel()
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil
    await analysisCoordinator.set(nil, for: .gemma)
    installedModelVersionPrepared = nil
    store.isGemmaAnalyzerAvailable = false
    store.gemmaStatusDetail = nil
    try await modelManager.deleteDownloadedModel()
    if analysisSettings.selectedProvider == .gemma {
      analysisSettings.selectedProvider = nil
      try saveAnalysisSettings()
      publishAnalysisSettings()
    }
  }

  private var hasConnectedAccounts: Bool {
    accountRecords.contains { $0.syncState != .disconnected }
  }

  private func unloadGemmaIfNoConnectedAccounts() async {
    guard !hasConnectedAccounts else { return }
    analysisWork?.cancel()
    if let analysisWork { await analysisWork.value }
    self.analysisWork = nil
    pendingAnalysisTask?.cancel()
    if let pendingAnalysisTask { _ = try? await pendingAnalysisTask.value }
    self.pendingAnalysisTask = nil
    pendingAnalysisRunId = nil
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil
    await analysisCoordinator.set(nil, for: .gemma)
    store.isGemmaAnalyzerAvailable = false
    store.gemmaStatusDetail = store.modelState.isInstalled
      ? "Gemma is installed and will load after a Gmail account is connected."
      : nil
  }

  /// Keeps the large runtime resident only while a queue is actively running.
  /// A later Gmail refresh will lazily create it again after finding new work.
  private func unloadGemmaAfterAnalysis(analyzedCount: Int) async {
    let failureReason = await router?.failureReason()
    await router?.unload()
    router = nil
    gemmaAnalyzer = nil
    await analysisCoordinator.set(nil, for: .gemma)

    guard analysisSettings.selectedProvider == .gemma else { return }

    guard store.modelState.isInstalled else {
      store.isGemmaAnalyzerAvailable = false
      return
    }
    guard hasConnectedAccounts else {
      store.isGemmaAnalyzerAvailable = false
      store.gemmaStatusDetail =
        "Gemma is installed and will load after a Gmail account is connected."
      return
    }
    if let failureReason {
      store.isGemmaAnalyzerAvailable = false
      store.gemmaStatusDetail = failureReason
    } else {
      store.isGemmaAnalyzerAvailable = true
      store.gemmaStatusDetail = analyzedCount > 0
        ? "Analysis complete. Gemma will load when a new email needs analysis."
        : "Gemma is installed and will load when a new email needs analysis."
    }
  }

  private func acceptPurchase(_ draft: EmailUIPurchaseReviewDraft) async throws {
    guard let amount = Decimal(string: draft.amount, locale: Locale(identifier: "en_US_POSIX")),
          let amountMinor = Self.minorUnits(amount), amountMinor > 0,
          let categoryId = draft.categoryID,
          let category = categories.first(where: { $0.id == categoryId }) else {
      throw EmailFeatureControllerError.invalidSuggestion
    }
    let merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
    let transaction = TransactionEntity(
      id: "tx_\(UUID().uuidString.lowercased())",
      name: merchant.isEmpty ? category.name : merchant,
      amountMinor: amountMinor,
      occurredAt: min(
        Int(draft.occurredAt.timeIntervalSince1970 * 1_000),
        Int(Date().timeIntervalSince1970 * 1_000)
      ),
      categoryId: categoryId,
      paymentMethodId: draft.paymentMethodID
    )
    let recurring = draft.isRecurring ? RecurringEntity(
      id: "rec_\(UUID().uuidString.lowercased())",
      name: transaction.name,
      amountMinor: amountMinor,
      categoryId: categoryId,
      paymentMethodId: draft.paymentMethodID,
      frequency: draft.recurringFrequency,
      anchorDate: DateHelpers.localDateKey(draft.occurredAt),
      paused: false
    ) : nil
    try repository.acceptEmailSuggestion(
      messageKey: draft.suggestionID,
      transaction: transaction,
      recurring: recurring
    )
  }

  private func unloadGemmaForPressure() async {
    analysisWork?.cancel()
    pendingAnalysisTask?.cancel()
    await router?.resourcePressureDidIncrease()
    router = nil
    gemmaAnalyzer = nil
    await analysisCoordinator.set(nil, for: .gemma)
    store.isGemmaAnalyzerAvailable = false
    store.gemmaStatusDetail = "Gemma was paused because the iPhone reported resource pressure. Tap Retry Gemma analysis when the device has recovered."
  }

  private func canRunGemma() async -> Bool {
    gemmaExecutionBlockReason() == nil
  }

  private func gemmaExecutionBlockReason() -> String? {
    guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
      return "Gemma is paused while Low Power Mode is on. Turn it off, then retry."
    }
    switch ProcessInfo.processInfo.thermalState {
    case .serious, .critical:
      return "Gemma is paused until this iPhone cools down."
    default: break
    }
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let available = try? support.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ).volumeAvailableCapacityForImportantUsage
    guard (available ?? 0) >= 256 * 1_024 * 1_024 else {
      return "Gemma needs at least 256 MB of currently available storage to run."
    }
    return nil
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
    store.suggestions = suggestionRecords.compactMap { message in
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

  /// The retained source email for a transaction the user accepted from an
  /// email suggestion, or nil when none is linked or it left this device.
  func sourceEmailDetail(forTransactionId transactionId: String) -> EmailUIEmailDetail? {
    guard let message = try? repository.emailMessage(linkedTransactionId: transactionId) else {
      return nil
    }
    return try? loadEmailDetail(messageId: message.key)
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

  private static func minorUnits(_ amount: Decimal) -> Int? {
    guard amount > 0 else { return nil }
    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 2, .plain)
    let number = NSDecimalNumber(decimal: rounded).multiplying(byPowerOf10: 2)
    guard number != .notANumber else { return nil }
    return number.intValue
  }

  private static func fileSizeDescription(
    bytes: Int64,
    prefix: String = "",
    suffix: String = ""
  ) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return prefix + formatter.string(fromByteCount: bytes) + suffix
  }

  private static func lastFour(in value: String) -> String? {
    let digits = value.filter(\.isNumber)
    return digits.count >= 4 ? String(digits.suffix(4)) : nil
  }

  private static func date(milliseconds: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
  }
}
