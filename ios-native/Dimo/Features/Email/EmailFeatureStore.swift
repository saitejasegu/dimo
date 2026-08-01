import Foundation
import SwiftUI

enum EmailSuggestionFilter: String, CaseIterable, Identifiable, Sendable {
  case purchases
  case refunds
  case awaitingAnalysis
  case errors
  case reviewed
  case all

  var id: String { rawValue }

  var title: String {
    switch self {
    case .purchases: return "Purchases"
    case .refunds: return "Refunds"
    case .awaitingAnalysis: return "Awaiting analysis"
    case .errors: return "Errors"
    case .reviewed: return "Reviewed"
    case .all: return "All"
    }
  }

  var displaysMessages: Bool {
    self == .awaitingAnalysis || self == .errors || self == .all
  }
}

enum EmailUIMessageAnalysisState: String, Sendable {
  case pending
  case failed
  case needsReview
  case analyzed
  case added
  case refundApplied
  case dismissed
  case expired

  var title: String {
    switch self {
    case .pending: return "Awaiting analysis"
    case .failed: return "Analysis failed"
    case .needsReview: return "Needs review"
    case .analyzed: return "Analyzed"
    case .added: return "Added"
    case .refundApplied: return "Refund applied"
    case .dismissed: return "Dismissed"
    case .expired: return "Expired"
    }
  }
}

struct EmailUIMessage: Identifiable, Hashable, Sendable {
  var id: String
  var accountEmail: String
  var sender: String
  var subject: String
  var snippet: String
  var receivedAt: Date
  var analyzer: EmailUIAnalyzer?
  var modelVersion: String?
  var classification: EmailUISuggestionKind?
  var analysisState: EmailUIMessageAnalysisState
  var analyzedAt: Date?
  var reviewedAt: Date?
}

struct EmailUIEmailDetail: Identifiable, Hashable, Sendable {
  var id: String
  var accountEmail: String
  var sender: String
  var senderAddress: String
  var subject: String
  var bodyText: String
  var receivedAt: Date
  var analyzer: EmailUIAnalyzer?
  var modelVersion: String? = nil
  var classification: EmailUISuggestionKind?
  var analysisState: EmailUIMessageAnalysisState
  var isBodyRetained: Bool
}

enum EmailUISuggestionKind: String, Sendable {
  case purchase
  case debit
  case refund
  case irrelevant

  var title: String {
    switch self {
    case .purchase: return "Purchase"
    case .debit: return "Debit"
    case .refund: return "Refund"
    case .irrelevant: return "Not a transaction"
    }
  }

}

enum EmailUIAnalyzer: String, Sendable {
  case gemma
  case openRouter

  var title: String {
    switch self {
    case .gemma: return "Gemma"
    case .openRouter: return "OpenRouter"
    }
  }

  func provenanceTitle(modelVersion: String?) -> String {
    guard self == .openRouter,
          let modelVersion = modelVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
          !modelVersion.isEmpty else { return title }
    let modelName = modelVersion.split(separator: "/").last.map(String.init) ?? modelVersion
    return "OpenRouter · \(modelName)"
  }
}

enum OpenRouterUIConnectionState: Equatable, Sendable {
  case disconnected
  case validating
  case connected(label: String, creditLimit: Double?, limitRemaining: Double?)
  case failed(String)
}

enum OpenRouterModelFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case free
  case zdr

  var id: String { rawValue }
  var title: String { rawValue.uppercased() }
}

enum EmailUISuggestionStatus: String, Sendable {
  case pendingPurchase
  case pendingRefund
  case added
  case refundApplied
  case dismissed
  case unactionable
  case expired

  var isReviewed: Bool {
    switch self {
    case .pendingPurchase, .pendingRefund, .unactionable, .expired: return false
    case .added, .refundApplied, .dismissed: return true
    }
  }

  var title: String {
    switch self {
    case .pendingPurchase, .pendingRefund: return "Needs review"
    case .added: return "Added"
    case .refundApplied: return "Refund applied"
    case .dismissed: return "Dismissed"
    case .unactionable: return "Informational"
    case .expired: return "Expired"
    }
  }
}

enum EmailUIAccountSyncState: String, Sendable {
  case idle
  case syncing
  case rateLimited
  case offline
  case failed
  case needsReconnect
  case disconnected

  var title: String {
    switch self {
    case .idle: return "Up to date"
    case .syncing: return "Syncing"
    case .rateLimited: return "Waiting"
    case .offline: return "Offline"
    case .failed: return "Needs attention"
    case .needsReconnect: return "Reconnect"
    case .disconnected: return "Disconnected"
    }
  }
}

struct EmailUIAccount: Identifiable, Hashable, Sendable {
  var id: String
  var emailAddress: String
  var syncState: EmailUIAccountSyncState = .idle
  var statusDetail: String?
  var lastSuccessfulSyncAt: Date?
  var lastError: String?
  var initialScanComplete = false
}

struct EmailUIRefundCandidate: Identifiable, Hashable, Sendable {
  var id: String
  var merchant: String
  var amount: Decimal
  var currency: Currency
  var occurredAt: Date
  var categoryName: String
  var paymentMethodLabel: String?
  var matchReason: String?
}

struct EmailUISuggestion: Identifiable, Hashable, Sendable {
  var id: String
  var accountID: String
  var accountEmail: String
  var kind: EmailUISuggestionKind
  var status: EmailUISuggestionStatus
  var sender: String
  var subject: String
  var snippet: String
  var receivedAt: Date
  var merchant: String?
  var amount: Decimal?
  var currency: Currency?
  var occurredAt: Date?
  var categoryID: String?
  var categoryName: String?
  var paymentMethodID: String?
  var paymentMethodLabel: String?
  var paymentLastFour: String?
  var reference: String?
  var analyzer: EmailUIAnalyzer
  var modelVersion: String? = nil
  var currencyWarning: String?
  var possibleDuplicateDescriptions: [String] = []
  var isFullRefund = true
  var refundCandidates: [EmailUIRefundCandidate] = []
  var preselectedRefundTransactionID: String?
  var groupID: String? = nil
  var sourceMessageIDs: [String] = []
  var sourceSenders: [String] = []
  var sources: [EmailUISourceSummary] = []
  var lateMatch: EmailUILatePurchaseMatch? = nil

  var actionMessageIDs: [String] {
    sourceMessageIDs.isEmpty ? [id] : sourceMessageIDs
  }
}

struct EmailUISourceSummary: Identifiable, Hashable, Sendable {
  var id: String
  var sender: String
  var subject: String
}

struct EmailUISourceEmailsPresentation: Identifiable, Hashable, Sendable {
  var suggestion: EmailUISuggestion
  var emails: [EmailUIEmailDetail]

  var id: String { suggestion.id }

  var canSeparate: Bool {
    suggestion.actionMessageIDs.count > 1 && !suggestion.status.isReviewed
  }
}

struct EmailUILatePurchaseMatch: Hashable, Sendable {
  var reviewedSourceMessageID: String
  var transactionID: String
  var transactionName: String
}

struct EmailUIPurchaseReviewDraft: Identifiable, Equatable, Sendable {
  var suggestionID: String
  var groupID: String? = nil
  var sourceMessageIDs: [String] = []
  var merchant: String
  var amount: String
  var occurredAt: Date
  var categoryID: String?
  var paymentMethodID: String?
  var isRecurring = false
  var recurringFrequency: RecurringFrequency = .monthly
  var accountEmail: String
  var analyzer: EmailUIAnalyzer
  var currency: Currency?
  var currencyWarning: String?
  var possibleDuplicateDescriptions: [String]

  var id: String { suggestionID }
}

struct EmailUIRefundReview: Identifiable, Equatable, Sendable {
  var suggestionID: String
  var merchant: String
  var amount: Decimal?
  var currency: Currency?
  var occurredAt: Date?
  var accountEmail: String
  var analyzer: EmailUIAnalyzer
  var isFullRefund: Bool
  var candidates: [EmailUIRefundCandidate]
  var selectedTransactionID: String?

  var id: String { suggestionID }
}

struct EmailFeatureActions {
  var connectAccount: () async throws -> Void = {}
  var reconnectAccount: (_ accountID: String) async throws -> Void = { _ in }
  var disconnectAccount: (_ accountID: String) async throws -> Void = { _ in }
  var refresh: (_ accountID: String?) async throws -> Void = { _ in }
  var dismissSuggestion: (_ suggestionID: String) async throws -> Void = { _ in }
  var dismissSuggestions: (_ suggestionIDs: [String]) async throws -> Void = { _ in }
  var restoreSuggestion: (_ suggestionID: String) async throws -> Void = { _ in }
  var restoreSuggestions: (_ suggestionIDs: [String]) async throws -> Void = { _ in }
  var separateSuggestions: (_ suggestionIDs: [String]) async throws -> Void = { _ in }
  var linkLateSuggestion: (_ suggestionID: String, _ reviewedSourceID: String) async throws -> Void = { _, _ in }
  var keepLateSuggestionSeparate: (_ suggestionID: String) async throws -> Void = { _ in }
  var acceptPurchase: (_ draft: EmailUIPurchaseReviewDraft) async throws -> Void = { _ in }
  var linkPurchaseToTransaction: (_ suggestionID: String, _ transactionID: String) async throws -> Void = { _, _ in }
  var applyFullRefund: (_ suggestionID: String, _ transactionID: String) async throws -> Void = { _, _ in }
  var reanalyzeAllEmails: () async throws -> Void = {}
  var saveOpenRouterKey: (_ apiKey: String) async throws -> Void = { _ in }
  var removeOpenRouterKey: () async throws -> Void = {}
  var refreshOpenRouterModels: () async throws -> Void = {}
  var selectOpenRouterModel: (_ modelID: String, _ allowNonZDR: Bool) async throws -> Void = { _, _ in }
  var selectOpenRouterAccessMode: (_ mode: OpenRouterAccessMode) async throws -> Void = { _ in }
  var selectProvider: (_ provider: EmailAnalysisProvider?) async throws -> Void = { _ in }
  var selectSyncWindow: (_ window: EmailSyncWindow) async throws -> Void = { _ in }
  var retryAnalysis: (_ messageID: String) async throws -> Void = { _ in }
  var retryOpenRouterConnection: () async throws -> Void = {}
  var retryOpenRouterAnalysis: () async throws -> Void = {}
  var loadEmailDetail: (_ messageID: String) async throws -> EmailUIEmailDetail = { _ in
    throw EmailFeatureStoreError.messageNotFound
  }
}

enum EmailFeatureStoreError: Error, LocalizedError {
  case messageNotFound

  var errorDescription: String? {
    switch self {
    case .messageNotFound: return "The email no longer exists on this iPhone."
    }
  }
}

/// UI-facing state for the Email feature. Gmail, database, and model services
/// inject actions and publish presentation values without being imported here.
@MainActor
@Observable
final class EmailFeatureStore {
  var accounts: [EmailUIAccount]
  var suggestions: [EmailUISuggestion] {
    didSet { rebuildSuggestionDerived() }
  }
  var allEmails: [EmailUIMessage] {
    didSet { rebuildEmailDerived() }
  }
  var selectedProvider: EmailAnalysisProvider?
  var openRouterAccessMode: OpenRouterAccessMode = .bringYourOwnKey
  var openRouterConnectionState: OpenRouterUIConnectionState = .disconnected
  var openRouterModels: [OpenRouterModel] = []
  var selectedOpenRouterModelID: String?
  var openRouterPrivacyMode: OpenRouterPrivacyMode = .zdrOnly
  var syncWindow: EmailSyncWindow = .defaultValue
  var openRouterAPIKeyInput = ""
  var isRefreshingOpenRouterModels = false
  var isUpdatingSyncWindow = false
  var analysisStatusDetail = "Email analysis is not configured. Choose Free models or Bring your own key in Email settings."
  var activeCurrency: Currency
  var categories: [CategoryEntity]
  var paymentMethods: [PaymentMethodOption]
  var selectedFilter: EmailSuggestionFilter = .purchases {
    didSet { rebuildFilterCaches() }
  }
  var purchaseReview: EmailUIPurchaseReviewDraft?
  var refundReview: EmailUIRefundReview?
  var emailDetail: EmailUIEmailDetail?
  var sourceEmailsPresentation: EmailUISourceEmailsPresentation?
  var isRefreshing = false
  var isReanalyzing = false
  var lastActionError: String?
  /// When set, the action-failed alert can offer an in-place Gmail reconnect.
  var pendingReconnectAccountID: String?

  /// Pending purchase/debit suggestions waiting for review. Used for the Email
  /// tab badge and Purchases filter count.
  private(set) var pendingPurchaseCount = 0
  private(set) var analysisErrorCount = 0
  private(set) var filteredSuggestions: [EmailUISuggestion] = []
  private(set) var filteredEmails: [EmailUIMessage] = []

  private var actions: EmailFeatureActions

  init(
    accounts: [EmailUIAccount] = [],
    suggestions: [EmailUISuggestion] = [],
    allEmails: [EmailUIMessage] = [],
    selectedProvider: EmailAnalysisProvider? = nil,
    activeCurrency: Currency = .INR,
    categories: [CategoryEntity] = [],
    paymentMethods: [PaymentMethodOption] = [],
    actions: EmailFeatureActions = EmailFeatureActions()
  ) {
    self.accounts = accounts
    self.suggestions = suggestions
    self.allEmails = allEmails
    self.selectedProvider = selectedProvider
    self.activeCurrency = activeCurrency
    self.categories = categories
    self.paymentMethods = paymentMethods
    self.actions = actions
    rebuildSuggestionDerived()
    rebuildEmailDerived()
  }

  func configure(actions: EmailFeatureActions) {
    self.actions = actions
  }

  var hasFailedAnalyses: Bool {
    analysisErrorCount > 0
  }

  private func rebuildSuggestionDerived() {
    pendingPurchaseCount = suggestions.count { suggestion in
      suggestion.status == .pendingPurchase
        && (suggestion.kind == .purchase || suggestion.kind == .debit)
    }
    rebuildFilteredSuggestions()
  }

  private func rebuildEmailDerived() {
    analysisErrorCount = allEmails.count { $0.analysisState == .failed }
    rebuildFilteredEmails()
  }

  private func rebuildFilterCaches() {
    rebuildFilteredSuggestions()
    rebuildFilteredEmails()
  }

  private func rebuildFilteredSuggestions() {
    filteredSuggestions = suggestions.filter { suggestion in
      switch selectedFilter {
      case .all:
        return false
      case .purchases:
        return suggestion.status == .pendingPurchase
          && (suggestion.kind == .purchase || suggestion.kind == .debit)
      case .refunds:
        return suggestion.status == .pendingRefund && suggestion.kind == .refund
      case .awaitingAnalysis, .errors:
        return false
      case .reviewed:
        return suggestion.status.isReviewed
      }
    }
  }

  private func rebuildFilteredEmails() {
    switch selectedFilter {
    case .awaitingAnalysis:
      filteredEmails = allEmails.filter { $0.analysisState == .pending }
    case .errors:
      filteredEmails = allEmails.filter { $0.analysisState == .failed }
    case .all:
      filteredEmails = allEmails
    case .purchases, .refunds, .reviewed:
      filteredEmails = []
    }
  }

  var activeAnalyzerTitle: String {
    switch selectedProvider {
    case .openRouter: return "OpenRouter"
    case nil: return "Analysis not configured"
    }
  }

  var isOpenRouterReady: Bool {
    selectedProvider == .openRouter
      && selectedOpenRouterModelID != nil
      && {
        if case .connected = openRouterConnectionState { return true }
        return false
      }()
  }

  var selectedOpenRouterModel: OpenRouterModel? {
    openRouterModels.first { $0.id == selectedOpenRouterModelID }
  }

  func presentEmail(id: String) {
    run { self.emailDetail = try await self.actions.loadEmailDetail(id) }
  }

  func presentSources(for suggestion: EmailUISuggestion) {
    if suggestion.actionMessageIDs.count == 1 {
      presentEmail(id: suggestion.id)
      return
    }

    run {
      var emails: [EmailUIEmailDetail] = []
      emails.reserveCapacity(suggestion.actionMessageIDs.count)
      for messageID in suggestion.actionMessageIDs {
        emails.append(try await self.actions.loadEmailDetail(messageID))
      }
      self.sourceEmailsPresentation = EmailUISourceEmailsPresentation(
        suggestion: suggestion,
        emails: emails
      )
    }
  }

  func dismissSourceEmails() {
    sourceEmailsPresentation = nil
  }

  func dismissEmailDetail() {
    emailDetail = nil
  }

  func connectAccount() {
    run { try await self.actions.connectAccount() }
  }

  func reconnectAccount(_ accountID: String) {
    Task { @MainActor in
      do {
        try await self.actions.reconnectAccount(accountID)
        self.pendingReconnectAccountID = nil
        self.lastActionError = nil
      } catch {
        self.presentActionError(error, reconnectAccountID: accountID)
      }
    }
  }

  func disconnectAccount(_ accountID: String) {
    run { try await self.actions.disconnectAccount(accountID) }
  }

  func refreshAll() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      try await actions.refresh(nil)
    } catch {
      presentActionError(error)
    }
  }

  func refreshAccount(_ accountID: String) {
    run { try await self.actions.refresh(accountID) }
  }

  func review(_ suggestion: EmailUISuggestion) {
    switch suggestion.kind {
    case .purchase, .debit:
      purchaseReview = EmailUIPurchaseReviewDraft(
        suggestionID: suggestion.id,
        groupID: suggestion.groupID,
        sourceMessageIDs: suggestion.actionMessageIDs,
        merchant: suggestion.merchant ?? "",
        amount: Self.decimalText(suggestion.amount),
        occurredAt: suggestion.occurredAt ?? suggestion.receivedAt,
        categoryID: suggestion.categoryID,
        paymentMethodID: suggestion.paymentMethodID,
        accountEmail: suggestion.accountEmail,
        analyzer: suggestion.analyzer,
        currency: suggestion.currency,
        currencyWarning: suggestion.currencyWarning,
        possibleDuplicateDescriptions: suggestion.possibleDuplicateDescriptions
      )
    case .refund:
      refundReview = EmailUIRefundReview(
        suggestionID: suggestion.id,
        merchant: suggestion.merchant ?? "Refund",
        amount: suggestion.amount,
        currency: suggestion.currency,
        occurredAt: suggestion.occurredAt,
        accountEmail: suggestion.accountEmail,
        analyzer: suggestion.analyzer,
        isFullRefund: suggestion.isFullRefund,
        candidates: suggestion.refundCandidates,
        selectedTransactionID: suggestion.preselectedRefundTransactionID
      )
    case .irrelevant:
      break
    }
  }

  func dismissSuggestion(_ suggestionID: String) {
    run { try await self.actions.dismissSuggestion(suggestionID) }
  }

  func dismissSuggestion(_ suggestion: EmailUISuggestion) {
    if suggestion.actionMessageIDs.count == 1 {
      dismissSuggestion(suggestion.id)
    } else {
      run { try await self.actions.dismissSuggestions(suggestion.actionMessageIDs) }
    }
  }

  func restoreSuggestion(_ suggestionID: String) {
    run { try await self.actions.restoreSuggestion(suggestionID) }
  }

  func restoreSuggestion(_ suggestion: EmailUISuggestion) {
    if suggestion.actionMessageIDs.count == 1 {
      restoreSuggestion(suggestion.id)
    } else {
      run { try await self.actions.restoreSuggestions(suggestion.actionMessageIDs) }
    }
  }

  func separateSuggestion(_ suggestion: EmailUISuggestion) {
    run { try await self.actions.separateSuggestions(suggestion.actionMessageIDs) }
  }

  func linkLateSuggestion(_ suggestion: EmailUISuggestion) {
    guard let match = suggestion.lateMatch else { return }
    run {
      try await self.actions.linkLateSuggestion(
        suggestion.id,
        match.reviewedSourceMessageID
      )
    }
  }

  func keepLateSuggestionSeparate(_ suggestion: EmailUISuggestion) {
    run { try await self.actions.keepLateSuggestionSeparate(suggestion.id) }
  }

  func acceptPurchase(_ draft: EmailUIPurchaseReviewDraft) {
    run(onSuccess: { self.purchaseReview = nil }) {
      try await self.actions.acceptPurchase(draft)
    }
  }

  /// Marks the suggestion reviewed against an expense the user already has,
  /// instead of adding a second one for the same purchase.
  func linkPurchaseToTransaction(suggestionID: String, transactionID: String) {
    run(onSuccess: { self.purchaseReview = nil }) {
      try await self.actions.linkPurchaseToTransaction(suggestionID, transactionID)
    }
  }

  func applyFullRefund(_ review: EmailUIRefundReview) {
    guard let transactionID = review.selectedTransactionID else { return }
    run(onSuccess: { self.refundReview = nil }) {
      try await self.actions.applyFullRefund(review.suggestionID, transactionID)
    }
  }

  func reanalyzeAllEmails() {
    guard !isReanalyzing else { return }
    isReanalyzing = true
    lastActionError = nil
    selectedFilter = .all
    Task { @MainActor in
      defer { self.isReanalyzing = false }
      do {
        try await self.actions.reanalyzeAllEmails()
      } catch {
        self.presentActionError(error)
      }
    }
  }

  func saveOpenRouterKey() {
    let key = openRouterAPIKeyInput
    run(onSuccess: { self.openRouterAPIKeyInput = "" }) {
      try await self.actions.saveOpenRouterKey(key)
    }
  }

  func removeOpenRouterKey() {
    run { try await self.actions.removeOpenRouterKey() }
  }

  func refreshOpenRouterModels() {
    guard !isRefreshingOpenRouterModels else { return }
    isRefreshingOpenRouterModels = true
    Task { @MainActor in
      defer { self.isRefreshingOpenRouterModels = false }
      do {
        try await self.actions.refreshOpenRouterModels()
      } catch {
        self.presentActionError(error)
      }
    }
  }

  func selectOpenRouterModel(_ modelID: String, allowNonZDR: Bool) {
    run { try await self.actions.selectOpenRouterModel(modelID, allowNonZDR) }
  }

  func selectOpenRouterAccessMode(_ mode: OpenRouterAccessMode) {
    run { try await self.actions.selectOpenRouterAccessMode(mode) }
  }

  func selectProvider(_ provider: EmailAnalysisProvider?) {
    run { try await self.actions.selectProvider(provider) }
  }

  func selectSyncWindow(_ window: EmailSyncWindow) {
    guard window != syncWindow, !isUpdatingSyncWindow else { return }
    let previous = syncWindow
    syncWindow = window
    isUpdatingSyncWindow = true
    Task { @MainActor in
      defer { self.isUpdatingSyncWindow = false }
      do {
        try await self.actions.selectSyncWindow(window)
      } catch {
        self.syncWindow = previous
        self.presentActionError(error)
      }
    }
  }

  func retryAnalysis(messageID: String) {
    run { try await self.actions.retryAnalysis(messageID) }
  }

  func retryOpenRouterConnection() {
    run { try await self.actions.retryOpenRouterConnection() }
  }

  func retryOpenRouterAnalysis() {
    run { try await self.actions.retryOpenRouterAnalysis() }
  }

  func clearError() {
    lastActionError = nil
    pendingReconnectAccountID = nil
  }

  private func presentActionError(_ error: Error, reconnectAccountID: String? = nil) {
    // Pull-to-refresh and overlapping work cancel in-flight tasks; that is not
    // a user-facing failure.
    if error is CancellationError { return }
    if let urlError = error as? URLError, urlError.code == .cancelled { return }
    lastActionError = error.localizedDescription
    if let reconnectAccountID {
      pendingReconnectAccountID = reconnectAccountID
      return
    }
    if let gmailError = error as? GmailOAuthError {
      switch gmailError {
      case .requiresReconnect, .missingRefreshToken, .accountMismatch:
        pendingReconnectAccountID = accounts.first(where: { $0.syncState == .needsReconnect })?.id
          ?? accounts.first?.id
      default:
        pendingReconnectAccountID = nil
      }
    } else {
      pendingReconnectAccountID = nil
    }
  }

  private func run(
    onSuccess: @escaping @MainActor () -> Void = {},
    _ operation: @escaping @MainActor () async throws -> Void
  ) {
    Task { @MainActor in
      do {
        try await operation()
        onSuccess()
      } catch {
        presentActionError(error)
      }
    }
  }

  private static func decimalText(_ value: Decimal?) -> String {
    guard let value else { return "" }
    return NSDecimalNumber(decimal: value).stringValue
  }
}
