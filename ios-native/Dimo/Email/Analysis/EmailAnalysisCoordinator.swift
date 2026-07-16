import Foundation

actor GemmaEmailAnalyzer: EmailAnalysisProviding {
  private let model: any EmailLanguageModel
  private let modelID: String

  init(model: any EmailLanguageModel, modelID: String) {
    self.model = model
    self.modelID = modelID
  }

  func load() async throws { try await model.load() }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisEnvelope {
    let result = try await model.analyze(request)
    return EmailAnalysisEnvelope(
      result: result,
      analyzer: .gemma,
      modelID: modelID,
      requestID: nil
    )
  }

  func unload() async { await model.unload() }
}

actor OpenRouterEmailAnalyzer: EmailAnalysisProviding {
  private let client: OpenRouterClient
  private let model: OpenRouterModel
  private let privacyMode: OpenRouterPrivacyMode
  private let apiKey: String

  init(
    client: OpenRouterClient,
    model: OpenRouterModel,
    privacyMode: OpenRouterPrivacyMode,
    apiKey: String
  ) {
    self.client = client
    self.model = model
    self.privacyMode = privacyMode
    self.apiKey = apiKey
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisEnvelope {
    do {
      return try await client.analyze(
        request,
        model: model,
        privacyMode: privacyMode,
        apiKey: apiKey
      )
    } catch let error as OpenRouterClientError {
      switch error {
      case .invalidOutput(let message)
        where message.localizedCaseInsensitiveContains("incomplete"):
        return try await client.analyze(
          request,
          model: model,
          privacyMode: privacyMode,
          apiKey: apiKey,
          outputTokenLimit: OpenRouterClient.incompleteOutputRetryTokenLimit
        )
      default:
        throw error
      }
    }
  }
}

actor EmailAnalysisCoordinator {
  private var providers: [EmailAnalysisProvider: any EmailAnalysisProviding] = [:]

  func set(_ analyzer: (any EmailAnalysisProviding)?, for provider: EmailAnalysisProvider) {
    providers[provider] = analyzer
  }

  func analyze(
    _ request: EmailAnalysisRequest,
    using provider: EmailAnalysisProvider
  ) async throws -> EmailAnalysisEnvelope {
    guard let analyzer = providers[provider] else {
      throw EmailAnalysisCoordinatorError.providerUnavailable(provider)
    }
    return try await analyzer.analyze(request)
  }

  func removeAll() { providers.removeAll() }
}

enum EmailAnalysisCoordinatorError: LocalizedError, Sendable {
  case providerUnavailable(EmailAnalysisProvider)

  var errorDescription: String? {
    switch self {
    case .providerUnavailable(.gemma): return "Local Gemma is not ready."
    case .providerUnavailable(.openRouter): return "OpenRouter is not configured."
    }
  }
}
