import Foundation

enum EmailAccountSyncState: String, Codable, CaseIterable, Hashable, Sendable {
  case idle
  case backfilling
  case syncing
  case rateLimited
  case offline
  case failed
  /// Stub row kept after disconnect or restored from Convex without OAuth credentials.
  case disconnected
}

enum EmailAnalyzerKind: String, Codable, CaseIterable, Hashable, Sendable {
  case gemma
  case openRouter
  /// Backwards decoding only. New analyses never use the rules analyzer.
  case rules
}

enum EmailAnalysisProvider: String, Codable, CaseIterable, Hashable, Sendable {
  case gemma
  case openRouter
}

enum OpenRouterPrivacyMode: String, Codable, CaseIterable, Hashable, Sendable {
  case zdrOnly
  case allowNonZDR
}

enum EmailSyncWindow: String, Codable, CaseIterable, Hashable, Sendable {
  case oneDay
  case oneWeek
  case oneMonth
  case threeMonths

  static let defaultValue: EmailSyncWindow = .oneDay

  var title: String {
    switch self {
    case .oneDay: return "1 day"
    case .oneWeek: return "1 week"
    case .oneMonth: return "1 month"
    case .threeMonths: return "3 months"
    }
  }

  func cutoff(from now: Date, calendar: Calendar = .current) -> Date {
    let component: Calendar.Component
    let value: Int
    switch self {
    case .oneDay:
      component = .day
      value = -1
    case .oneWeek:
      component = .day
      value = -7
    case .oneMonth:
      component = .month
      value = -1
    case .threeMonths:
      component = .month
      value = -3
    }
    return calendar.date(byAdding: component, value: value, to: now)
      ?? now.addingTimeInterval(-fallbackDayCount * 86_400)
  }

  func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
    date >= cutoff(from: now, calendar: calendar)
  }

  private var fallbackDayCount: TimeInterval {
    switch self {
    case .oneDay: return 1
    case .oneWeek: return 7
    case .oneMonth: return 30
    case .threeMonths: return 90
    }
  }
}

struct EmailAnalysisSettings: Codable, Hashable, Sendable {
  static let singletonID = "settings"

  var selectedProvider: EmailAnalysisProvider?
  var gemmaModelVariant: EmailGemmaModelVariant
  var openRouterModelID: String?
  var openRouterPrivacyMode: OpenRouterPrivacyMode
  var nonZDRConsentVersion: Int?
  var syncWindow: EmailSyncWindow
  var updatedAt: Int

  static var defaults: EmailAnalysisSettings {
    EmailAnalysisSettings(
      selectedProvider: nil,
      gemmaModelVariant: .defaultValue,
      openRouterModelID: nil,
      openRouterPrivacyMode: .zdrOnly,
      nonZDRConsentVersion: nil,
      syncWindow: .defaultValue,
      updatedAt: Int(Date().timeIntervalSince1970 * 1_000)
    )
  }
}

struct EmailAnalysisRetryState: Codable, Hashable, Sendable {
  static let singletonID = "openrouter"

  var attempt: Int
  var notBefore: Int?
  var reason: String?
  var lastHTTPStatus: Int?
  var updatedAt: Int
}

enum EmailMessageClassification: String, Codable, CaseIterable, Hashable, Sendable {
  case purchase
  case debit
  case refund
  case irrelevant
}

enum EmailSuggestionState: String, Codable, CaseIterable, Hashable, Sendable {
  /// The message has been fetched but has not yet completed local analysis.
  case pendingAnalysis
  case analysisFailed
  case pendingPurchase
  case pendingRefund
  case added
  case refundApplied
  case dismissed
  case unactionable
  case expired

  var isPendingReview: Bool {
    self == .pendingPurchase || self == .pendingRefund
  }

  var isReviewed: Bool {
    switch self {
    case .added, .refundApplied, .dismissed:
      return true
    case .pendingAnalysis, .analysisFailed, .pendingPurchase, .pendingRefund, .unactionable, .expired:
      return false
    }
  }
}

enum EmailLocalSuggestionFilter: Hashable, Sendable {
  case purchases
  case refunds
  case reviewed
}

/// Device-local Gmail account metadata. OAuth tokens are intentionally absent;
/// refresh tokens belong in the user-scoped Keychain bundle and access tokens
/// must remain in memory.
struct EmailAccountRecordModel: Codable, Hashable, Sendable, Identifiable {
  /// Stable Google OpenID subject identifier.
  var id: String
  var emailAddress: String
  var historyId: String?
  var backfillPageToken: String?
  var backfillCompletedAt: Int?
  var lastAttemptAt: Int?
  var lastSuccessfulSyncAt: Int?
  var syncState: EmailAccountSyncState
  var lastError: String?
  var createdAt: Int
  var updatedAt: Int

  init(
    id: String,
    emailAddress: String,
    historyId: String? = nil,
    backfillPageToken: String? = nil,
    backfillCompletedAt: Int? = nil,
    lastAttemptAt: Int? = nil,
    lastSuccessfulSyncAt: Int? = nil,
    syncState: EmailAccountSyncState = .idle,
    lastError: String? = nil,
    createdAt: Int = Int(Date().timeIntervalSince1970 * 1000),
    updatedAt: Int = Int(Date().timeIntervalSince1970 * 1000)
  ) {
    self.id = id
    self.emailAddress = emailAddress
    self.historyId = historyId
    self.backfillPageToken = backfillPageToken
    self.backfillCompletedAt = backfillCompletedAt
    self.lastAttemptAt = lastAttemptAt
    self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
    self.syncState = syncState
    self.lastError = lastError
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Immutable Gmail envelope plus the normalized body that is eligible for
/// analysis. Raw MIME, HTML, attachments, images, prompts, and model output do
/// not have fields in the local schema.
struct PendingEmailMessage: Hashable, Sendable {
  var accountId: String
  var gmailMessageId: String
  var threadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var normalizedBodyText: String

  var key: String {
    emailMessageKey(accountId: accountId, gmailMessageId: gmailMessageId)
  }
}

struct PersistedEmailAnalysis: Hashable, Sendable {
  var analyzerType: EmailAnalyzerKind
  var modelVersion: String?
  var promptVersion: Int
  var classification: EmailMessageClassification
  var merchant: String?
  /// Canonical base-unit decimal text, such as `1234.50`.
  var amount: String?
  var currency: Currency?
  var occurredAt: Int?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
}

struct EmailMessageRecordModel: Codable, Hashable, Sendable, Identifiable {
  var key: String
  var accountId: String
  var gmailMessageId: String
  var threadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var normalizedBodyText: String?
  var analysisProviderOverride: EmailAnalysisProvider?
  var analyzerType: EmailAnalyzerKind?
  var modelVersion: String?
  var promptVersion: Int?
  var classification: EmailMessageClassification?
  var merchant: String?
  var amount: String?
  var currency: Currency?
  var occurredAt: Int?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
  var state: EmailSuggestionState
  var linkedTransactionId: String?
  var analyzedAt: Int?
  var reviewedAt: Int?
  var createdAt: Int
  var updatedAt: Int

  var id: String { key }
}

/// Lightweight UI projection that deliberately excludes retained body text
/// and extracted transaction fields not needed by the all-email status feed.
struct EmailMessageSummaryModel: Hashable, Sendable, Identifiable {
  var id: String
  var accountId: String
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var analyzerType: EmailAnalyzerKind?
  var modelVersion: String?
  var classification: EmailMessageClassification?
  var state: EmailSuggestionState
  var analyzedAt: Int?
  var reviewedAt: Int?
}

enum EmailRepositoryError: Error, Equatable, LocalizedError {
  case invalidAccount
  case accountNotFound
  case messageNotFound
  case suggestionAlreadyReviewed
  case invalidSuggestionState
  case invalidAnalysis
  case invalidCategory
  case invalidPaymentMethod
  case duplicateTransaction
  case transactionNotFound
  case currencyMismatch
  case amountMismatch
  case transactionOutsideRefundWindow

  var errorDescription: String? {
    switch self {
    case .invalidAccount: return "The Gmail account details are invalid."
    case .accountNotFound: return "The Gmail account is no longer connected."
    case .messageNotFound: return "The email suggestion no longer exists."
    case .suggestionAlreadyReviewed: return "This email suggestion has already been reviewed."
    case .invalidSuggestionState: return "This action is not available for the email suggestion."
    case .invalidAnalysis: return "The email analysis is invalid."
    case .invalidCategory: return "Choose an existing category before saving."
    case .invalidPaymentMethod: return "The selected payment method no longer exists."
    case .duplicateTransaction: return "A transaction with this identifier already exists."
    case .transactionNotFound: return "The matched transaction no longer exists."
    case .currencyMismatch: return "The refund currency does not match Dimo's active currency."
    case .amountMismatch: return "Only an exact full refund can remove a transaction."
    case .transactionOutsideRefundWindow:
      return "The matched transaction is outside the refund matching window."
    }
  }
}

/// Length-prefixing the account ID avoids delimiter collisions while keeping
/// the key deterministic for paged and incremental Gmail sync.
func emailMessageKey(accountId: String, gmailMessageId: String) -> String {
  "\(accountId.utf8.count):\(accountId)\(gmailMessageId)"
}
