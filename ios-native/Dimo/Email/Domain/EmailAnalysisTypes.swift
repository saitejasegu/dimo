import Foundation

enum EmailAnalysisKind: String, Codable, CaseIterable, Sendable {
  case purchase
  case debit
  case refund
  case irrelevant
}

enum EmailAnalyzerType: String, Codable, Sendable {
  case gemma
  case openRouter
}

struct EmailAnalysisEnvelope: Hashable, Sendable {
  var result: EmailAnalysisResult
  var analyzer: EmailAnalyzerType
  var modelID: String
  var requestID: String?
}

protocol EmailAnalysisProviding: Sendable {
  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisEnvelope
}

enum EmailAnalysisConfidence: String, Codable, Sendable {
  case high
  case medium
  case low
}

struct EmailCategoryOption: Codable, Hashable, Sendable {
  var id: String
  var name: String
}

struct EmailPaymentMethodHint: Codable, Hashable, Sendable {
  var id: String
  var label: String
  var lastFour: String?
  var archived: Bool
}

struct EmailMerchantCategoryHint: Codable, Hashable, Sendable {
  var merchant: String
  var categoryId: String
}

struct EmailAnalysisRequest: Hashable, Sendable {
  var messageId: String
  var accountSubject: String
  var senderName: String?
  var senderAddress: String
  var subject: String
  var receivedAt: Date
  var normalizedBody: String
  var categories: [EmailCategoryOption]
  var paymentMethods: [EmailPaymentMethodHint]
  var merchantHistory: [EmailMerchantCategoryHint]
  var activeCurrency: Currency

  init(
    messageId: String,
    accountSubject: String,
    senderName: String? = nil,
    senderAddress: String,
    subject: String,
    receivedAt: Date,
    normalizedBody: String,
    categories: [EmailCategoryOption],
    paymentMethods: [EmailPaymentMethodHint],
    merchantHistory: [EmailMerchantCategoryHint],
    activeCurrency: Currency
  ) {
    self.messageId = messageId
    self.accountSubject = accountSubject
    self.senderName = senderName
    self.senderAddress = senderAddress
    self.subject = subject
    self.receivedAt = receivedAt
    self.normalizedBody = normalizedBody
    self.categories = categories
    self.paymentMethods = paymentMethods
    self.merchantHistory = merchantHistory
    self.activeCurrency = activeCurrency
  }
}

struct EmailAnalysisResult: Hashable, Sendable {
  static let schemaVersion = 1

  var kind: EmailAnalysisKind
  var merchant: String?
  var amount: Decimal?
  var currency: Currency?
  var occurredAt: Date?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
  var analyzer: EmailAnalyzerType
  var confidence: EmailAnalysisConfidence

  static func irrelevant(analyzer: EmailAnalyzerType) -> EmailAnalysisResult {
    EmailAnalysisResult(
      kind: .irrelevant,
      merchant: nil,
      amount: nil,
      currency: nil,
      occurredAt: nil,
      categoryId: nil,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil,
      analyzer: analyzer,
      confidence: .high
    )
  }
}

struct EmailDeterministicEvidence: Hashable, Sendable {
  struct Amount: Hashable, Sendable {
    var value: Decimal
    var currency: Currency
    var source: String
  }

  var amounts: [Amount]
  var paymentLastFour: String?
  var reference: String?
}

protocol EmailLanguageModel: Sendable {
  func load() async throws
  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisResult
  func unload() async
}

enum EmailLanguageModelError: LocalizedError, Sendable {
  case modelNotInstalled
  case runtimeUnavailable
  case unsupportedDevice
  case corruptModel
  case initializationFailed(String)
  case outOfMemory
  case timedOut
  case invalidOutput(String)
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotInstalled: return "Gemma has not been downloaded."
    case .runtimeUnavailable: return "The on-device language model runtime is unavailable."
    case .unsupportedDevice: return "This device does not support the on-device model."
    case .corruptModel: return "The downloaded model is corrupt."
    case .initializationFailed(let message): return "Gemma could not be initialized: \(message)"
    case .outOfMemory: return "There is not enough memory to run Gemma."
    case .timedOut: return "Gemma analysis timed out."
    case .invalidOutput(let message): return "Gemma returned invalid output: \(message)"
    case .generationFailed(let message): return "Gemma analysis failed: \(message)"
    }
  }

  var shouldUnloadRuntime: Bool {
    switch self {
    case .unsupportedDevice, .corruptModel, .initializationFailed, .outOfMemory, .timedOut:
      return true
    case .modelNotInstalled, .runtimeUnavailable, .invalidOutput, .generationFailed:
      return false
    }
  }
}
