import Foundation
import OSLog

private let openRouterLogger = Logger(
  subsystem: "app.dimo.ios",
  category: "EmailOpenRouter"
)

struct OpenRouterKeyInfo: Codable, Hashable, Sendable {
  var label: String
  var limit: Double?
  var limitRemaining: Double?
  var usage: Double
  var usageDaily: Double
  var isFreeTier: Bool

  enum CodingKeys: String, CodingKey {
    case label, limit, usage
    case limitRemaining = "limit_remaining"
    case usageDaily = "usage_daily"
    case isFreeTier = "is_free_tier"
  }
}

struct OpenRouterModel: Codable, Hashable, Sendable, Identifiable {
  struct Pricing: Codable, Hashable, Sendable {
    var prompt: String?
    var completion: String?
  }

  var id: String
  var name: String
  var contextLength: Int
  var pricing: Pricing
  var supportedParameters: [String]
  var hasZDREndpoint: Bool = false
  var zdrSupportedParameters: [String] = []

  enum CodingKeys: String, CodingKey {
    case id, name, pricing
    case contextLength = "context_length"
    case supportedParameters = "supported_parameters"
  }

  var isFree: Bool {
    pricePerToken(pricing.prompt) == 0 && pricePerToken(pricing.completion) == 0
  }

  var hasKnownPrice: Bool {
    pricePerToken(pricing.prompt) != nil && pricePerToken(pricing.completion) != nil
  }

  var inputPricePerMillion: Double? {
    pricePerToken(pricing.prompt).map { $0 * 1_000_000 }
  }

  var outputPricePerMillion: Double? {
    pricePerToken(pricing.completion).map { $0 * 1_000_000 }
  }

  func supports(_ parameter: String) -> Bool {
    supportedParameters.contains(parameter)
  }

  private func pricePerToken(_ value: String?) -> Double? {
    value.flatMap(Double.init)
  }
}

enum OpenRouterClientError: LocalizedError, Sendable {
  case invalidKey
  case forbidden
  case insufficientCredits
  case rateLimited(retryAfter: TimeInterval?)
  case temporarilyUnavailable(status: Int, retryAfter: TimeInterval?)
  case modelUnavailable
  case invalidRequest(String)
  case invalidResponse
  case invalidOutput(String)
  case transport(String)
  case timedOut

  var errorDescription: String? {
    switch self {
    case .invalidKey: return "The OpenRouter key is invalid or has been revoked."
    case .forbidden: return "The OpenRouter key or guardrail blocked this request."
    case .insufficientCredits: return "The OpenRouter key has insufficient credits or reached its spending limit."
    case .rateLimited: return "OpenRouter is rate limiting requests. Analysis will retry automatically."
    case .temporarilyUnavailable: return "The selected OpenRouter model is temporarily unavailable."
    case .modelUnavailable: return "The selected OpenRouter model is unavailable for the current privacy settings."
    case .invalidRequest(let message): return message
    case .invalidResponse: return "OpenRouter returned an invalid response."
    case .invalidOutput: return "Analysis failed."
    case .transport: return "OpenRouter could not be reached. Analysis will retry automatically."
    case .timedOut: return "OpenRouter analysis timed out."
    }
  }

  var statusCode: Int? {
    switch self {
    case .invalidKey: return 401
    case .insufficientCredits: return 402
    case .forbidden: return 403
    case .rateLimited: return 429
    case .temporarilyUnavailable(let status, _): return status
    default: return nil
    }
  }

  var retryAfter: TimeInterval? {
    switch self {
    case .rateLimited(let value), .temporarilyUnavailable(_, let value): return value
    default: return nil
    }
  }

  var isTransient: Bool {
    switch self {
    case .rateLimited, .temporarilyUnavailable, .transport, .timedOut: return true
    default: return false
    }
  }
}

actor OpenRouterClient {
  static let defaultModelID = "openai/gpt-oss-20b:free"
  static let standardOutputTokenLimit = 512
  static let incompleteOutputRetryTokenLimit = 2_048

  private let baseURL = URL(string: "https://openrouter.ai/api/v1")!
  private let session: URLSession

  init(session: URLSession? = nil) {
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.urlCache = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
      configuration.httpCookieStorage = nil
      configuration.httpShouldSetCookies = false
      configuration.timeoutIntervalForRequest = 90
      configuration.timeoutIntervalForResource = 120
      self.session = URLSession(configuration: configuration)
    }
  }

  func validateKey(_ apiKey: String) async throws -> OpenRouterKeyInfo {
    let response: DataEnvelope<OpenRouterKeyInfo> = try await get(
      path: "key",
      apiKey: apiKey
    )
    return response.data
  }

  func models(apiKey: String) async throws -> [OpenRouterModel] {
    async let catalogResponse: DataEnvelope<[OpenRouterModel]> = get(
      path: "models/user",
      apiKey: apiKey
    )
    async let zdrResponse: ZDREndpointEnvelope = get(
      path: "endpoints/zdr",
      apiKey: apiKey
    )
    var catalog = try await catalogResponse.data
    let zdrEndpoints = Dictionary(grouping: try await zdrResponse.data, by: \.modelID)
    catalog = catalog.compactMap { model in
      guard model.supports("structured_outputs"), model.supports("response_format") else {
        return nil
      }
      var updated = model
      let compatibleEndpoints = (zdrEndpoints[model.id] ?? []).filter { endpoint in
        let parameters = Set(endpoint.supportedParameters ?? [])
        return parameters.contains("structured_outputs")
          && parameters.contains("response_format")
      }
      updated.hasZDREndpoint = !compatibleEndpoints.isEmpty
      if let first = compatibleEndpoints.first {
        let commonParameters = compatibleEndpoints.dropFirst().reduce(
          Set(first.supportedParameters ?? [])
        ) { current, endpoint in
          current.intersection(endpoint.supportedParameters ?? [])
        }
        updated.zdrSupportedParameters = commonParameters.sorted()
      }
      return updated
    }
    return catalog.sorted {
      if $0.isFree != $1.isFree { return $0.isFree }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  func analyze(
    _ analysisRequest: EmailAnalysisRequest,
    model: OpenRouterModel,
    privacyMode: OpenRouterPrivacyMode,
    apiKey: String,
    outputTokenLimit: Int = standardOutputTokenLimit
  ) async throws -> EmailAnalysisEnvelope {
    let prompt = EmailPromptBuilder.build(analysisRequest)

    var provider: [String: Any] = ["require_parameters": true]
    if privacyMode == .zdrOnly { provider["zdr"] = true }
    var payload: [String: Any] = [
      "model": model.id,
      "messages": [["role": "user", "content": prompt]],
      "stream": false,
      "provider": provider,
      "response_format": Self.responseFormat,
    ]
    let routeParameters = Set(
      privacyMode == .zdrOnly ? model.zdrSupportedParameters : model.supportedParameters
    )
    if routeParameters.contains("max_tokens") {
      payload["max_tokens"] = outputTokenLimit
    } else if routeParameters.contains("max_completion_tokens") {
      payload["max_completion_tokens"] = outputTokenLimit
    }
    if routeParameters.contains("temperature") { payload["temperature"] = 0 }
    if routeParameters.contains("reasoning") {
      payload["reasoning"] = ["effort": "low", "exclude": true]
    }
    openRouterLogger.notice(
      "OpenRouter analysis starting; message: \(analysisRequest.messageId, privacy: .private(mask: .hash)); model: \(model.id, privacy: .public); privacy: \(privacyMode.rawValue, privacy: .public); output token limit: \(outputTokenLimit, privacy: .public); prompt characters: \(prompt.count, privacy: .public); route parameters: \(routeParameters.sorted().joined(separator: ","), privacy: .public)"
    )
    guard JSONSerialization.isValidJSONObject(payload) else {
      openRouterLogger.error(
        "OpenRouter request payload is not valid JSON; model: \(model.id, privacy: .public)"
      )
      throw OpenRouterClientError.invalidRequest("The OpenRouter request could not be encoded.")
    }
    let body = try JSONSerialization.data(withJSONObject: payload)
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await perform(
        path: "chat/completions",
        method: "POST",
        apiKey: apiKey,
        body: body
      )
    } catch {
      openRouterLogger.error(
        "OpenRouter request failed; message: \(analysisRequest.messageId, privacy: .private(mask: .hash)); model: \(model.id, privacy: .public); error: \(String(reflecting: error), privacy: .public)"
      )
      throw error
    }
    let requestID = decodedRequestID(response: response)
    let decoded: ChatCompletionResponse
    do {
      decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    } catch {
      openRouterLogger.error(
        "OpenRouter response decoding failed; status: \(response.statusCode, privacy: .public); request ID: \(requestID ?? "none", privacy: .public); model: \(model.id, privacy: .public); response bytes: \(data.count, privacy: .public); decoding error: \(String(reflecting: error), privacy: .public)"
      )
      throw OpenRouterClientError.invalidResponse
    }
    guard let choice = decoded.choices.first,
          let content = choice.message.textContent,
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      openRouterLogger.error(
        "OpenRouter success response has no text content; status: \(response.statusCode, privacy: .public); request ID: \(decoded.id ?? requestID ?? "none", privacy: .public); requested model: \(model.id, privacy: .public); resolved model: \(decoded.model ?? "none", privacy: .public); choices: \(decoded.choices.count, privacy: .public)"
      )
      throw OpenRouterClientError.invalidResponse
    }
    do {
      let result = try EmailStructuredOutputValidator.validate(
        response: content,
        request: analysisRequest,
        analyzer: .openRouter
      )
      return EmailAnalysisEnvelope(
        result: result,
        analyzer: .openRouter,
        modelID: decoded.model ?? model.id,
        requestID: decoded.id ?? requestID
      )
    } catch {
      let exactError = String(reflecting: error)
      openRouterLogger.error(
        "OpenRouter structured-output validation failed; message: \(analysisRequest.messageId, privacy: .private(mask: .hash)); request ID: \(decoded.id ?? requestID ?? "none", privacy: .public); requested model: \(model.id, privacy: .public); resolved model: \(decoded.model ?? "none", privacy: .public); content characters: \(content.count, privacy: .public); JSON shape: \(Self.structuredOutputShape(content), privacy: .public); validation error: \(exactError, privacy: .public)"
      )
      throw OpenRouterClientError.invalidOutput(exactError)
    }
  }

  private func get<T: Decodable>(path: String, apiKey: String) async throws -> T {
    let (data, _) = try await perform(path: path, method: "GET", apiKey: apiKey, body: nil)
    do { return try JSONDecoder().decode(T.self, from: data) }
    catch { throw OpenRouterClientError.invalidResponse }
  }

  private func perform(
    path: String,
    method: String,
    apiKey: String,
    body: Data?
  ) async throws -> (Data, HTTPURLResponse) {
    var request = URLRequest(url: baseURL.appending(path: path))
    request.httpMethod = method
    request.httpBody = body
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Dimo", forHTTPHeaderField: "X-OpenRouter-Title")
    let data: Data
    let urlResponse: URLResponse
    do {
      (data, urlResponse) = try await session.data(for: request)
    } catch let error as URLError {
      if error.code == .timedOut { throw OpenRouterClientError.timedOut }
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
      let requestID = decodedRequestID(response: response) ?? "none"
      let apiMessage = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
      openRouterLogger.error(
        "OpenRouter HTTP failure; path: \(path, privacy: .public); status: \(response.statusCode, privacy: .public); request ID: \(requestID, privacy: .public); response bytes: \(data.count, privacy: .public); API error: \(Self.safeDiagnostic(apiMessage), privacy: .public)"
      )
      throw Self.error(for: response, data: data)
    }
    return (data, response)
  }

  private static func error(for response: HTTPURLResponse, data: Data) -> OpenRouterClientError {
    let retryAfter = parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
    let apiMessage = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
    switch response.statusCode {
    case 400:
      let message = apiMessage ?? "OpenRouter rejected the selected model or request."
      if message.localizedCaseInsensitiveContains("context") {
        return .invalidRequest("The selected model context is too small for this email.")
      }
      let normalized = message.lowercased()
      if normalized.contains("no endpoint")
        || normalized.contains("model not found")
        || normalized.contains("model is unavailable") {
        return .modelUnavailable
      }
      return .invalidRequest(message)
    case 401: return .invalidKey
    case 402: return .insufficientCredits
    case 403: return .forbidden
    case 404: return .modelUnavailable
    case 408: return .temporarilyUnavailable(status: 408, retryAfter: retryAfter)
    case 429: return .rateLimited(retryAfter: retryAfter)
    case 502, 503: return .temporarilyUnavailable(status: response.statusCode, retryAfter: retryAfter)
    default:
      return .invalidRequest(
        apiMessage ?? "OpenRouter rejected this analysis request (HTTP \(response.statusCode))."
      )
    }
  }

  static func parseRetryAfter(_ value: String?, now: Date = .now) -> TimeInterval? {
    guard let value else { return nil }
    if let seconds = TimeInterval(value), seconds > 0 { return seconds }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
    guard let date = formatter.date(from: value) else { return nil }
    return max(0, date.timeIntervalSince(now))
  }

  private func decodedRequestID(response: HTTPURLResponse) -> String? {
    response.value(forHTTPHeaderField: "x-request-id")
      ?? response.value(forHTTPHeaderField: "x-openrouter-request-id")
  }

  private static func safeDiagnostic(_ value: String?) -> String {
    guard let value else { return "none" }
    let singleLine = value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    return String(singleLine.prefix(500))
  }

  private static func structuredOutputShape(_ response: String) -> String {
    guard let object = try? EmailJSONEnvelopeExtractor.extract(response),
          let data = object.data(using: .utf8),
          let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return "no complete JSON object"
    }
    return dictionary.keys.sorted().map { key in
      let value = dictionary[key]
      let type: String
      switch value {
      case is NSNull: type = "null"
      case is String: type = "string"
      case is NSNumber: type = "number"
      case is [Any]: type = "array"
      case is [String: Any]: type = "object"
      default: type = "unknown"
      }
      return "\(key):\(type)"
    }.joined(separator: ",")
  }

  private static let responseFormat: [String: Any] = [
    "type": "json_schema",
    "json_schema": [
      "name": "email_analysis",
      "strict": true,
      "schema": [
        "type": "object",
        "additionalProperties": false,
        "required": [
          "schemaVersion", "kind", "merchant", "amount", "currency", "occurredAt",
          "categoryId", "paymentMethodId", "paymentLastFour", "reference",
        ],
        "properties": [
          "schemaVersion": ["type": "integer", "enum": [1]],
          "kind": ["type": "string", "enum": ["purchase", "debit", "refund", "irrelevant"]],
          "merchant": nullableString,
          "amount": nullableString,
          "currency": ["type": ["string", "null"], "enum": ["INR", "USD", "EUR", NSNull()]],
          "occurredAt": nullableString,
          "categoryId": nullableString,
          "paymentMethodId": nullableString,
          "paymentLastFour": nullableString,
          "reference": nullableString,
        ],
      ],
    ],
  ]

  private static let nullableString: [String: Any] = ["type": ["string", "null"]]
}

private struct DataEnvelope<T: Decodable>: Decodable { var data: T }

private struct ZDREndpointEnvelope: Decodable {
  struct Endpoint: Decodable {
    var modelID: String
    var supportedParameters: [String]?
    enum CodingKeys: String, CodingKey {
      case modelID = "model_id"
      case supportedParameters = "supported_parameters"
    }
  }
  var data: [Endpoint]
}

private struct APIErrorEnvelope: Decodable {
  struct APIError: Decodable { var message: String }
  var error: APIError
}

private struct ChatCompletionResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      struct ContentPart: Decodable { var type: String?; var text: String? }
      var content: Content

      enum Content: Decodable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
          let container = try decoder.singleValueContainer()
          if let value = try? container.decode(String.self) { self = .text(value); return }
          self = .parts(try container.decode([ContentPart].self))
        }
      }

      var textContent: String? {
        switch content {
        case .text(let value): return value
        case .parts(let values): return values.compactMap(\.text).joined()
        }
      }
    }
    var message: Message
  }
  var id: String?
  var model: String?
  var choices: [Choice]
}
