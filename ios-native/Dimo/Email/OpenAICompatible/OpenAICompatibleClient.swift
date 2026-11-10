import CryptoKit
import Foundation
import OSLog
import Security

private let openAICompatibleLogger = Logger(
  subsystem: "app.dimo.ios",
  category: "EmailOpenAICompatible"
)

/// A user-configured OpenAI-compatible endpoint (OpenAI, Groq, Together, a
/// self-hosted vLLM / Ollama / LM Studio server, …). The base URL is the path
/// that `chat/completions` and `models` hang off, e.g. `https://api.openai.com/v1`.
struct OpenAICompatibleEndpoint: Codable, Hashable, Sendable {
  var baseURL: URL
  /// Optional: many self-hosted servers accept unauthenticated requests.
  var apiKey: String?

  var hostLabel: String {
    guard let host = baseURL.host(percentEncoded: false) else { return baseURL.absoluteString }
    if let port = baseURL.port { return "\(host):\(port)" }
    return host
  }

  /// Accepts `https://host/v1`, `host/v1`, or a pasted `…/chat/completions` URL.
  static func normalizedBaseURL(_ input: String) throws -> URL {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw OpenAICompatibleEndpointError.missingBaseURL }
    if !value.contains("://") { value = "https://" + value }
    for suffix in ["/chat/completions", "/models"] where value.lowercased().hasSuffix(suffix) {
      value.removeLast(suffix.count)
    }
    while value.hasSuffix("/") { value.removeLast() }
    guard var components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          scheme == "https" || scheme == "http",
          let host = components.host, !host.isEmpty else {
      throw OpenAICompatibleEndpointError.invalidBaseURL
    }
    components.scheme = scheme
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw OpenAICompatibleEndpointError.invalidBaseURL }
    return url
  }
}

enum OpenAICompatibleEndpointError: LocalizedError, Sendable {
  case missingBaseURL
  case invalidBaseURL
  case missingModel

  var errorDescription: String? {
    switch self {
    case .missingBaseURL: return "Enter the endpoint base URL, for example https://api.openai.com/v1."
    case .invalidBaseURL: return "The endpoint URL must be an http or https address, for example https://api.openai.com/v1."
    case .missingModel: return "This endpoint does not list its models. Enter a model ID."
    }
  }
}

/// Talks to `/models` and `/chat/completions` on any OpenAI-compatible server.
/// Compatible servers differ in which optional parameters they accept, so a
/// rejected `response_format`, `temperature`, or `max_tokens` is dropped or
/// downgraded and the request retried; what worked is remembered per model.
actor OpenAICompatibleClient {
  static let standardOutputTokenLimit = 1_024
  static let incompleteOutputRetryTokenLimit = 4_096

  enum StructuredOutputMode: Int, Comparable, Sendable {
    case jsonSchema = 2
    case jsonObject = 1
    case promptOnly = 0
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  enum TokenLimitParameter: Sendable {
    case maxTokens
    case maxCompletionTokens
    case none
  }

  struct RequestShape: Hashable, Sendable {
    var structuredOutput: StructuredOutputMode = .jsonSchema
    var sendsTemperature = true
    var tokenLimit: TokenLimitParameter = .maxTokens
  }

  private let session: URLSession
  private var learnedShapes: [String: RequestShape] = [:]

  init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      // Self-hosted models on modest hardware can be slow to answer.
      configuration.timeoutIntervalForRequest = 180
      configuration.timeoutIntervalForResource = 240
      self.session = URLSession(configuration: configuration)
    }
  }

  /// Lists models, or returns `nil` when the server has no `/models` route
  /// (the user then enters a model ID by hand). Auth failures still throw.
  func models(endpoint: OpenAICompatibleEndpoint) async throws -> [OpenRouterModel]? {
    let data: Data
    do {
      (data, _) = try await perform(endpoint: endpoint, path: "models", method: "GET", body: nil)
    } catch OpenRouterClientError.modelUnavailable, OpenRouterClientError.invalidRequest {
      return nil
    }
    guard let envelope = try? JSONDecoder().decode(ModelsEnvelope.self, from: data) else {
      throw OpenRouterClientError.invalidResponse
    }
    return envelope.data
      .map { Self.model(id: $0.id) }
      .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
  }

  /// Placeholder catalog entry for a model the server named or the user typed.
  static func model(id: String) -> OpenRouterModel {
    OpenRouterModel(
      id: id,
      name: id,
      contextLength: 0,
      pricing: .init(prompt: nil, completion: nil),
      supportedParameters: []
    )
  }

  func analyze(
    _ analysisRequest: EmailAnalysisRequest,
    modelID: String,
    endpoint: OpenAICompatibleEndpoint,
    outputTokenLimit: Int = standardOutputTokenLimit
  ) async throws -> EmailAnalysisEnvelope {
    let prompt = EmailPromptBuilder.build(analysisRequest)
    let shapeKey = endpoint.baseURL.absoluteString + "\n" + modelID
    var shape = learnedShapes[shapeKey] ?? RequestShape()

    // Each retry removes one rejected parameter, so this always terminates.
    for _ in 0..<6 {
      let body = try Self.payload(
        prompt: prompt,
        modelID: modelID,
        shape: shape,
        outputTokenLimit: outputTokenLimit
      )
      do {
        let (data, response) = try await perform(
          endpoint: endpoint,
          path: "chat/completions",
          method: "POST",
          body: body
        )
        learnedShapes[shapeKey] = shape
        return try decode(
          data: data,
          response: response,
          request: analysisRequest,
          modelID: modelID
        )
      } catch let error as OpenRouterClientError {
        guard case .invalidRequest(let message) = error,
              let relaxed = Self.relaxed(shape, afterRejection: message) else {
          throw error
        }
        openAICompatibleLogger.notice(
          "OpenAI-compatible endpoint rejected a parameter; retrying with a relaxed request; model: \(modelID, privacy: .public)"
        )
        shape = relaxed
      }
    }
    throw OpenRouterClientError.invalidRequest("The endpoint rejected every request format Dimo tried.")
  }

  // MARK: - Request building

  static func payload(
    prompt: String,
    modelID: String,
    shape: RequestShape,
    outputTokenLimit: Int
  ) throws -> Data {
    var payload: [String: Any] = [
      "model": modelID,
      "messages": [["role": "user", "content": prompt]],
      "stream": false,
    ]
    switch shape.structuredOutput {
    case .jsonSchema: payload["response_format"] = OpenRouterClient.responseFormat
    case .jsonObject: payload["response_format"] = ["type": "json_object"]
    case .promptOnly: break
    }
    if shape.sendsTemperature { payload["temperature"] = 0 }
    switch shape.tokenLimit {
    case .maxTokens: payload["max_tokens"] = outputTokenLimit
    case .maxCompletionTokens: payload["max_completion_tokens"] = outputTokenLimit
    case .none: break
    }
    guard JSONSerialization.isValidJSONObject(payload) else {
      throw OpenRouterClientError.invalidRequest("The analysis request could not be encoded.")
    }
    return try JSONSerialization.data(withJSONObject: payload)
  }

  /// Returns a request shape without the parameter a 400 response complained
  /// about, or `nil` when the error is not about an optional parameter.
  static func relaxed(_ shape: RequestShape, afterRejection message: String) -> RequestShape? {
    let text = message.lowercased()
    var next = shape
    if text.contains("max_completion_tokens"), shape.tokenLimit == .maxCompletionTokens {
      next.tokenLimit = .none
      return next
    }
    if text.contains("max_tokens"), shape.tokenLimit == .maxTokens {
      // OpenAI reasoning models ask for max_completion_tokens instead.
      next.tokenLimit = text.contains("max_completion_tokens") ? .maxCompletionTokens : .none
      return next
    }
    if text.contains("temperature"), shape.sendsTemperature {
      next.sendsTemperature = false
      return next
    }
    let mentionsStructuredOutput = text.contains("response_format")
      || text.contains("json_schema")
      || text.contains("json_object")
      || text.contains("structured output")
      || text.contains("response format")
    if mentionsStructuredOutput, shape.structuredOutput > .promptOnly {
      next.structuredOutput = shape.structuredOutput == .jsonSchema ? .jsonObject : .promptOnly
      return next
    }
    return nil
  }

  // MARK: - Response handling

  private func decode(
    data: Data,
    response: HTTPURLResponse,
    request: EmailAnalysisRequest,
    modelID: String
  ) throws -> EmailAnalysisEnvelope {
    let decoded: CompletionResponse
    do {
      decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
    } catch {
      openAICompatibleLogger.error(
        "OpenAI-compatible response decoding failed; status: \(response.statusCode, privacy: .public); model: \(modelID, privacy: .public); response bytes: \(data.count, privacy: .public)"
      )
      throw OpenRouterClientError.invalidResponse
    }
    guard let choice = decoded.choices.first else { throw OpenRouterClientError.invalidResponse }
    let content = choice.message.textContent?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if content.isEmpty {
      // Reasoning models can spend the whole budget thinking; the analyzer
      // retries "incomplete" output once with a larger limit.
      if choice.finishReason == "length" {
        throw OpenRouterClientError.invalidOutput("incomplete output: token limit reached")
      }
      throw OpenRouterClientError.invalidResponse
    }
    do {
      let result = try EmailStructuredOutputValidator.validate(
        response: Self.strippingThinking(content),
        request: request,
        analyzer: .openRouter
      )
      return EmailAnalysisEnvelope(
        result: result,
        analyzer: .openRouter,
        modelID: decoded.model?.nilIfBlank ?? modelID,
        requestID: decoded.id
      )
    } catch {
      let detail = String(reflecting: error)
      openAICompatibleLogger.error(
        "OpenAI-compatible structured-output validation failed; model: \(modelID, privacy: .public); finish reason: \(choice.finishReason ?? "none", privacy: .public); error: \(detail, privacy: .public)"
      )
      if choice.finishReason == "length" {
        throw OpenRouterClientError.invalidOutput("incomplete output: \(detail)")
      }
      throw OpenRouterClientError.invalidOutput(detail)
    }
  }

  /// Local reasoning models (DeepSeek R1, Qwen 3, …) often inline their
  /// thinking as `<think>…</think>` ahead of the JSON answer.
  static func strippingThinking(_ content: String) -> String {
    guard let close = content.range(of: "</think>", options: [.caseInsensitive, .backwards]) else {
      return content
    }
    return String(content[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Transport

  private func perform(
    endpoint: OpenAICompatibleEndpoint,
    path: String,
    method: String,
    body: Data?
  ) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: endpoint.baseURL.appending(path: path))
    request.httpMethod = method
    request.httpBody = body
    if let apiKey = endpoint.apiKey?.nilIfBlank {
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let data: Data
    let urlResponse: URLResponse
    do {
      (data, urlResponse) = try await session.data(for: request)
    } catch let error as URLError {
      if error.code == .timedOut { throw OpenRouterClientError.timedOut }
      if error.code == .appTransportSecurityRequiresSecureConnection {
        throw OpenRouterClientError.invalidRequest(
          "iOS only allows plain http for servers on your local network. Use https for this endpoint."
        )
      }
      throw OpenRouterClientError.transport(error.code.rawValue.description)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw OpenRouterClientError.transport(String(describing: type(of: error)))
    }
    guard let response = urlResponse as? HTTPURLResponse else {
      throw OpenRouterClientError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      openAICompatibleLogger.error(
        "OpenAI-compatible HTTP failure; path: \(path, privacy: .public); status: \(response.statusCode, privacy: .public); response bytes: \(data.count, privacy: .public)"
      )
      throw Self.error(for: response, data: data, path: path)
    }
    return (data, response)
  }

  static func error(for response: HTTPURLResponse, data: Data, path: String) -> OpenRouterClientError {
    let retryAfter = OpenRouterClient.parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
    let message = apiErrorMessage(from: data)
    let normalized = message.lowercased()
    switch response.statusCode {
    case 400, 422:
      if normalized.contains("context length") || normalized.contains("context window")
        || normalized.contains("maximum context") {
        return .invalidRequest("The selected model context is too small for this email.")
      }
      if normalized.contains("model") && (normalized.contains("not found")
        || normalized.contains("does not exist") || normalized.contains("unknown model")) {
        return .modelUnavailable
      }
      return .invalidRequest(message)
    case 401: return .invalidKey
    case 402: return .insufficientCredits
    case 403: return .forbidden
    case 404, 405, 501:
      // A missing /models route is expected on some servers; a missing
      // chat route or model is a configuration problem.
      return path == "models"
        ? .invalidRequest(message)
        : (normalized.contains("model") ? .modelUnavailable : .invalidRequest(
            "The endpoint has no chat/completions route. Check the base URL (it usually ends in /v1)."
          ))
    case 408: return .temporarilyUnavailable(status: 408, retryAfter: retryAfter)
    case 429:
      if normalized.contains("quota") || normalized.contains("billing") {
        return .insufficientCredits
      }
      return .rateLimited(retryAfter: retryAfter)
    case 500, 502, 503, 504:
      return .temporarilyUnavailable(status: response.statusCode, retryAfter: retryAfter)
    default:
      return .invalidRequest(
        message.isEmpty ? "The endpoint rejected this request (HTTP \(response.statusCode))." : message
      )
    }
  }

  static func apiErrorMessage(from data: Data) -> String {
    if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let error = root["error"] as? [String: Any],
         let message = (error["message"] as? String)?.nilIfBlank {
        return String(message.prefix(500))
      }
      if let error = (root["error"] as? String)?.nilIfBlank { return String(error.prefix(500)) }
      if let message = (root["message"] as? String)?.nilIfBlank { return String(message.prefix(500)) }
      if let detail = (root["detail"] as? String)?.nilIfBlank { return String(detail.prefix(500)) }
    }
    let text = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return String(text.prefix(500))
  }
}

private struct ModelsEnvelope: Decodable {
  struct Model: Decodable { var id: String }
  var data: [Model]
}

private struct CompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      struct ContentPart: Decodable { var text: String? }
      enum Content: Decodable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
          let container = try decoder.singleValueContainer()
          if let value = try? container.decode(String.self) { self = .text(value); return }
          self = .parts(try container.decode([ContentPart].self))
        }
      }

      var content: Content?

      var textContent: String? {
        switch content {
        case .text(let value): return value
        case .parts(let values): return values.compactMap(\.text).joined()
        case nil: return nil
        }
      }
    }

    var message: Message
    var finishReason: String?

    enum CodingKeys: String, CodingKey {
      case message
      case finishReason = "finish_reason"
    }
  }

  var id: String?
  var model: String?
  var choices: [Choice]
}

private extension String {
  var nilIfBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }
}

// MARK: - Analyzer

actor OpenAICompatibleEmailAnalyzer: EmailAnalysisProviding {
  private let client: OpenAICompatibleClient
  private let modelID: String
  private let endpoint: OpenAICompatibleEndpoint

  init(client: OpenAICompatibleClient, modelID: String, endpoint: OpenAICompatibleEndpoint) {
    self.client = client
    self.modelID = modelID
    self.endpoint = endpoint
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisEnvelope {
    do {
      return try await client.analyze(request, modelID: modelID, endpoint: endpoint)
    } catch OpenRouterClientError.invalidOutput(let message)
      where message.localizedCaseInsensitiveContains("incomplete") {
      return try await client.analyze(
        request,
        modelID: modelID,
        endpoint: endpoint,
        outputTokenLimit: OpenAICompatibleClient.incompleteOutputRetryTokenLimit
      )
    }
  }
}

// MARK: - Credential storage

/// Keychain storage for the endpoint URL and optional key. Both stay on this
/// device; neither syncs through Dimo.
actor OpenAICompatibleCredentialVault {
  private static let service = "app.dimo.ios.openai-compatible"

  private struct StoredEndpoint: Codable {
    static let currentVersion = 1
    var version: Int
    var endpoint: OpenAICompatibleEndpoint
  }

  func endpoint(dimoUserId: String) throws -> OpenAICompatibleEndpoint? {
    let query = baseQuery(dimoUserId: dimoUserId).merging([
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]) { _, new in new }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw OpenAICompatibleCredentialVaultError.keychain(status)
    }
    guard let value = try? JSONDecoder().decode(StoredEndpoint.self, from: data),
          value.version == StoredEndpoint.currentVersion else {
      throw OpenAICompatibleCredentialVaultError.corruptCredential
    }
    return value.endpoint
  }

  func save(_ endpoint: OpenAICompatibleEndpoint, dimoUserId: String) throws {
    let data = try JSONEncoder().encode(
      StoredEndpoint(version: StoredEndpoint.currentVersion, endpoint: endpoint)
    )
    let query = baseQuery(dimoUserId: dimoUserId)
    let update = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else {
      throw OpenAICompatibleCredentialVaultError.keychain(update)
    }
    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(insert as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw OpenAICompatibleCredentialVaultError.keychain(status)
    }
  }

  func remove(dimoUserId: String) throws {
    let status = SecItemDelete(baseQuery(dimoUserId: dimoUserId) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw OpenAICompatibleCredentialVaultError.keychain(status)
    }
  }

  private func baseQuery(dimoUserId: String) -> [String: Any] {
    let digest = SHA256.hash(data: Data(dimoUserId.utf8))
    let account = "openai-compatible.endpoint." + digest.map { String(format: "%02x", $0) }.joined()
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
    ]
  }
}

enum OpenAICompatibleCredentialVaultError: LocalizedError {
  case corruptCredential
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .corruptCredential: return "The saved OpenAI-compatible endpoint is corrupt. Disconnect and enter it again."
    case .keychain(let status): return "The OpenAI-compatible endpoint could not be accessed (\(status))."
    }
  }
}
