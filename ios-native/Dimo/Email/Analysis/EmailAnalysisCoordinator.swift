import Foundation

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

/// Free-mode analyzer: prompt + validation stay on-device; completions go through Convex.
actor ConvexFreeOpenRouterEmailAnalyzer: EmailAnalysisProviding {
  private let transport: any OpenRouterConvexTransporting
  private let model: OpenRouterModel
  private let privacyMode: OpenRouterPrivacyMode

  init(
    transport: any OpenRouterConvexTransporting,
    model: OpenRouterModel,
    privacyMode: OpenRouterPrivacyMode
  ) {
    self.transport = transport
    self.model = model
    self.privacyMode = privacyMode
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisEnvelope {
    let prompt = EmailPromptBuilder.build(request)
    do {
      return try await complete(
        request: request,
        prompt: prompt,
        outputTokenLimit: OpenRouterClient.standardOutputTokenLimit
      )
    } catch let error as OpenRouterClientError {
      switch error {
      case .invalidOutput(let message)
        where message.localizedCaseInsensitiveContains("incomplete"):
        return try await complete(
          request: request,
          prompt: prompt,
          outputTokenLimit: OpenRouterClient.incompleteOutputRetryTokenLimit
        )
      default:
        throw error
      }
    }
  }

  private func complete(
    request: EmailAnalysisRequest,
    prompt: String,
    outputTokenLimit: Int
  ) async throws -> EmailAnalysisEnvelope {
    let remote: OpenRouterConvexAnalyzeResult
    do {
      remote = try await transport.analyzeEmail(
        modelId: model.id,
        privacyMode: privacyMode,
        prompt: prompt,
        outputTokenLimit: outputTokenLimit
      )
    } catch let error as OpenRouterConvexTransportError {
      throw error.openRouterClientError
    }

    do {
      let result = try EmailStructuredOutputValidator.validate(
        response: remote.content,
        request: request,
        analyzer: .openRouter
      )
      return EmailAnalysisEnvelope(
        result: result,
        analyzer: .openRouter,
        modelID: remote.modelId,
        requestID: remote.requestId
      )
    } catch {
      throw OpenRouterClientError.invalidOutput(String(reflecting: error))
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
    case .providerUnavailable(.openRouter): return "OpenRouter is not configured."
    }
  }
}
