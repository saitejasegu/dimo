import Foundation

struct GmailMessageReference: Decodable, Hashable, Sendable {
  var id: String
  var threadId: String?
}

struct GmailMessageListPage: Sendable {
  var messages: [GmailMessageReference]
  var nextPageToken: String?
}

struct GmailHistoryPage: Sendable {
  var addedMessageIds: [String]
  var latestHistoryId: String
  var nextPageToken: String?
}

struct GmailProfile: Decodable, Hashable, Sendable {
  var emailAddress: String
  var historyId: String
}

struct GmailMessageHeader: Decodable, Hashable, Sendable {
  var name: String
  var value: String
}

struct GmailMessageBody: Decodable, Hashable, Sendable {
  var attachmentId: String?
  var size: Int?
  var data: String?
}

struct GmailMessagePart: Decodable, Hashable, Sendable {
  var partId: String?
  var mimeType: String?
  var filename: String?
  var headers: [GmailMessageHeader]?
  var body: GmailMessageBody?
  var parts: [GmailMessagePart]?
}

struct GmailMessageResource: Decodable, Hashable, Sendable {
  var id: String
  var threadId: String
  var labelIds: [String]?
  var snippet: String?
  var historyId: String?
  var internalDate: String
  var payload: GmailMessagePart?
}

protocol GmailAPIClient: Sendable {
  func listMessages(
    subject: String,
    dimoUserId: String,
    since: Date,
    pageToken: String?
  ) async throws -> GmailMessageListPage

  func getMessages(
    subject: String,
    dimoUserId: String,
    ids: [String]
  ) async throws -> [GmailMessageResource]

  /// Fetches a MIME part body that Gmail returned as `attachmentId` instead of
  /// inline `data` (common for larger text/html bodies even without a file).
  func getAttachmentData(
    subject: String,
    dimoUserId: String,
    messageId: String,
    attachmentId: String
  ) async throws -> Data

  func listHistory(
    subject: String,
    dimoUserId: String,
    startHistoryId: String,
    pageToken: String?
  ) async throws -> GmailHistoryPage

  func profile(subject: String, dimoUserId: String) async throws -> GmailProfile
}

actor GmailRESTClient: GmailAPIClient {
  private static let apiBase = URL(string: "https://gmail.googleapis.com/gmail/v1")!
  private static let batchURL = URL(string: "https://gmail.googleapis.com/batch/gmail/v1")!
  private static let messageBatchSize = 20
  private static let batchPacingDelay: Duration = .milliseconds(1_500)
  private static let maximumRateLimitRetries = 6
  private let tokenProvider: any GmailAccessTokenProviding
  private let session: URLSession
  private let decoder = JSONDecoder()

  init(
    tokenProvider: any GmailAccessTokenProviding,
    session: URLSession = GmailURLSession.make()
  ) {
    self.tokenProvider = tokenProvider
    self.session = session
  }

  func listMessages(
    subject: String,
    dimoUserId: String,
    since: Date,
    pageToken: String?
  ) async throws -> GmailMessageListPage {
    let epochSeconds = Int(since.timeIntervalSince1970)
    var items = [
      URLQueryItem(name: "q", value: "after:\(epochSeconds) -in:spam -in:trash"),
      URLQueryItem(name: "includeSpamTrash", value: "false"),
      URLQueryItem(name: "maxResults", value: "100"),
    ]
    if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
    let url = try endpoint(path: "users/me/messages", queryItems: items)
    let data = try await authorizedData(
      request: URLRequest(url: url),
      subject: subject,
      dimoUserId: dimoUserId
    )
    let response = try decode(GmailMessageListResponse.self, from: data)
    return GmailMessageListPage(
      messages: response.messages ?? [],
      nextPageToken: response.nextPageToken
    )
  }

  func getMessages(
    subject: String,
    dimoUserId: String,
    ids: [String]
  ) async throws -> [GmailMessageResource] {
    var messages: [GmailMessageResource] = []
    let batches = ids.uniqued().chunked(maxCount: Self.messageBatchSize)
    for (index, batch) in batches.enumerated() {
      try Task.checkCancellation()
      var rateLimitAttempt = 0
      while true {
        do {
          messages += try await getMessageBatch(
            subject: subject,
            dimoUserId: dimoUserId,
            ids: batch
          )
          break
        } catch let GmailAPIError.rateLimited(retryAfter) {
          guard rateLimitAttempt < Self.maximumRateLimitRetries else { throw GmailAPIError.rateLimited(retryAfter: retryAfter) }
          try await waitForRateLimit(retryAfter: retryAfter, attempt: rateLimitAttempt)
          rateLimitAttempt += 1
        }
      }
      if index < batches.count - 1 {
        try await Task.sleep(for: Self.batchPacingDelay)
      }
    }
    return messages
  }

  func listHistory(
    subject: String,
    dimoUserId: String,
    startHistoryId: String,
    pageToken: String?
  ) async throws -> GmailHistoryPage {
    var items = [
      URLQueryItem(name: "startHistoryId", value: startHistoryId),
      URLQueryItem(name: "historyTypes", value: "messageAdded"),
      URLQueryItem(name: "maxResults", value: "100"),
    ]
    if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
    let url = try endpoint(path: "users/me/history", queryItems: items)
    do {
      let data = try await authorizedData(
        request: URLRequest(url: url),
        subject: subject,
        dimoUserId: dimoUserId
      )
      let response = try decode(GmailHistoryListResponse.self, from: data)
      let ids = (response.history ?? [])
        .flatMap { $0.messagesAdded ?? [] }
        .map(\.message.id)
        .uniqued()
      return GmailHistoryPage(
        addedMessageIds: ids,
        latestHistoryId: response.historyId,
        nextPageToken: response.nextPageToken
      )
    } catch let error as GmailAPIError {
      if case .httpStatus(404, _) = error { throw GmailAPIError.historyCursorExpired }
      throw error
    }
  }

  func profile(subject: String, dimoUserId: String) async throws -> GmailProfile {
    let url = try endpoint(path: "users/me/profile")
    let data = try await authorizedData(
      request: URLRequest(url: url),
      subject: subject,
      dimoUserId: dimoUserId
    )
    return try decode(GmailProfile.self, from: data)
  }

  func getAttachmentData(
    subject: String,
    dimoUserId: String,
    messageId: String,
    attachmentId: String
  ) async throws -> Data {
    let encodedMessage = messageId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? messageId
    let encodedAttachment = attachmentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
      ?? attachmentId
    let url = try endpoint(
      path: "users/me/messages/\(encodedMessage)/attachments/\(encodedAttachment)"
    )
    let data = try await authorizedData(
      request: URLRequest(url: url),
      subject: subject,
      dimoUserId: dimoUserId
    )
    let response = try decode(GmailAttachmentResponse.self, from: data)
    guard let encoded = response.data,
          let decoded = GmailMessageParser.decodeBase64URLData(encoded)
    else {
      throw GmailAPIError.invalidResponse
    }
    return decoded
  }

  private func getMessageBatch(
    subject: String,
    dimoUserId: String,
    ids: [String],
    retriedAfterAuthentication: Bool = false
  ) async throws -> [GmailMessageResource] {
    guard !ids.isEmpty else { return [] }
    let boundary = "dimo_email_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    var body = Data()
    for id in ids {
      let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
      // Build this byte-for-byte instead of using a multiline literal. Swift
      // strips the final source newline from a multiline string, which can
      // leave a bare CR immediately before the next MIME boundary.
      let part = "--\(boundary)\r\n"
        + "Content-Type: application/http\r\n"
        + "\r\n"
        + "GET /gmail/v1/users/me/messages/\(encodedId)?format=full HTTP/1.1\r\n"
        + "\r\n"
      body.append(Data(part.utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))

    let token = try await tokenProvider.accessToken(
      subject: subject,
      dimoUserId: dimoUserId,
      forceRefresh: retriedAfterAuthentication
    )
    var request = URLRequest(url: Self.batchURL)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/mixed; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw GmailAPIError.invalidResponse }
    if http.statusCode == 401, !retriedAfterAuthentication {
      await tokenProvider.invalidate(subject: subject)
      return try await getMessageBatch(
        subject: subject,
        dimoUserId: dimoUserId,
        ids: ids,
        retriedAfterAuthentication: true
      )
    }
    try validate(http: http, data: data)
    guard let contentType = http.value(forHTTPHeaderField: "Content-Type") else {
      throw GmailAPIError.invalidBatchResponse
    }
    do {
      return try GmailBatchResponseParser.decodeMessages(
        data: data,
        contentType: contentType,
        decoder: decoder
      )
    } catch let GmailAPIError.httpStatus(status, _) where status == 401
      && !retriedAfterAuthentication {
      await tokenProvider.invalidate(subject: subject)
      return try await getMessageBatch(
        subject: subject,
        dimoUserId: dimoUserId,
        ids: ids,
        retriedAfterAuthentication: true
      )
    }
  }

  private func authorizedData(
    request: URLRequest,
    subject: String,
    dimoUserId: String,
    retriedAfterAuthentication: Bool = false,
    rateLimitAttempt: Int = 0
  ) async throws -> Data {
    let token = try await tokenProvider.accessToken(
      subject: subject,
      dimoUserId: dimoUserId,
      forceRefresh: retriedAfterAuthentication
    )
    var authorized = request
    authorized.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: authorized)
    guard let http = response as? HTTPURLResponse else { throw GmailAPIError.invalidResponse }
    if http.statusCode == 401, !retriedAfterAuthentication {
      await tokenProvider.invalidate(subject: subject)
      return try await authorizedData(
        request: request,
        subject: subject,
        dimoUserId: dimoUserId,
        retriedAfterAuthentication: true,
        rateLimitAttempt: rateLimitAttempt
      )
    }
    do {
      try validate(http: http, data: data)
    } catch let GmailAPIError.rateLimited(retryAfter) {
      guard rateLimitAttempt < Self.maximumRateLimitRetries else {
        throw GmailAPIError.rateLimited(retryAfter: retryAfter)
      }
      try await waitForRateLimit(retryAfter: retryAfter, attempt: rateLimitAttempt)
      return try await authorizedData(
        request: request,
        subject: subject,
        dimoUserId: dimoUserId,
        retriedAfterAuthentication: retriedAfterAuthentication,
        rateLimitAttempt: rateLimitAttempt + 1
      )
    }
    return data
  }

  private func waitForRateLimit(retryAfter: TimeInterval?, attempt: Int) async throws {
    let exponentialDelay = min(32, pow(2, Double(attempt)))
    let requestedDelay = retryAfter.map { min(max($0, 1), 60) }
    let jitter = retryAfter == nil ? Double.random(in: 0..<0.75) : 0
    let delay = (requestedDelay ?? exponentialDelay) + jitter
    try await Task.sleep(for: .milliseconds(Int64(delay * 1_000)))
  }

  private func endpoint(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
    let url = Self.apiBase.appending(path: path)
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw GmailAPIError.invalidRequest
    }
    if !queryItems.isEmpty { components.queryItems = queryItems }
    guard let result = components.url else { throw GmailAPIError.invalidRequest }
    return result
  }

  private func validate(http: HTTPURLResponse, data: Data) throws {
    guard !(200..<300).contains(http.statusCode) else { return }
    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    if http.statusCode == 429 {
      throw GmailAPIError.rateLimited(retryAfter: retryAfter)
    }
    let envelope = try? decoder.decode(GmailErrorEnvelope.self, from: data)
    let reasons = envelope?.error.errors?.compactMap(\.reason) ?? []
    if http.statusCode == 403,
       reasons.contains(where: Self.isRateLimitReason) {
      throw GmailAPIError.rateLimited(retryAfter: retryAfter)
    }
    let message = envelope?.error.message
    throw GmailAPIError.httpStatus(http.statusCode, message)
  }

  private static func isRateLimitReason(_ reason: String) -> Bool {
    switch reason.lowercased() {
    case "ratelimitexceeded", "userratelimitexceeded", "quotaexceeded":
      return true
    default:
      return false
    }
  }

  private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    do { return try decoder.decode(type, from: data) }
    catch { throw GmailAPIError.invalidResponse }
  }
}

private struct GmailAttachmentResponse: Decodable {
  var size: Int?
  var data: String?
}

private struct GmailMessageListResponse: Decodable {
  var messages: [GmailMessageReference]?
  var nextPageToken: String?
}

private struct GmailHistoryListResponse: Decodable {
  struct History: Decodable {
    struct Added: Decodable { var message: GmailMessageReference }
    var messagesAdded: [Added]?
  }

  var history: [History]?
  var nextPageToken: String?
  var historyId: String
}

private struct GmailErrorEnvelope: Decodable {
  struct Body: Decodable {
    struct Detail: Decodable { var reason: String? }
    var message: String?
    var errors: [Detail]?
  }
  var error: Body
}

private enum GmailBatchResponseParser {
  static func decodeMessages(
    data: Data,
    contentType: String,
    decoder: JSONDecoder
  ) throws -> [GmailMessageResource] {
    guard let boundary = boundary(from: contentType),
          let response = String(data: data, encoding: .utf8) else {
      throw GmailAPIError.invalidBatchResponse
    }
    let delimiter = "--\(boundary)"
    var messages: [GmailMessageResource] = []
    for rawPart in response.components(separatedBy: delimiter) {
      let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !part.isEmpty, part != "--" else { continue }
      guard let statusRange = part.range(
        of: #"HTTP/(?:1\.1|2)\s+(\d{3})"#,
        options: .regularExpression
      ) else { throw GmailAPIError.invalidBatchResponse }
      let statusLine = String(part[statusRange])
      guard let status = statusLine.split(separator: " ").last.flatMap({ Int($0) }) else {
        throw GmailAPIError.invalidBatchResponse
      }
      if status == 404 { continue } // Message was deleted between list and get.
      if status == 429 { throw GmailAPIError.rateLimited(retryAfter: nil) }
      if status == 403 {
        let normalized = part.lowercased()
        if normalized.contains("ratelimitexceeded")
          || normalized.contains("userratelimitexceeded")
          || normalized.contains("quotaexceeded") {
          throw GmailAPIError.rateLimited(retryAfter: nil)
        }
      }
      guard (200..<300).contains(status) else {
        throw GmailAPIError.httpStatus(status, nil)
      }
      let afterStatus = part[statusRange.upperBound...]
      guard let headerEnd = afterStatus.range(of: "\r\n\r\n")
        ?? afterStatus.range(of: "\n\n") else {
        throw GmailAPIError.invalidBatchResponse
      }
      let json = afterStatus[headerEnd.upperBound...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let jsonData = json.data(using: .utf8) else {
        throw GmailAPIError.invalidBatchResponse
      }
      do {
        messages.append(try decoder.decode(GmailMessageResource.self, from: jsonData))
      } catch {
        throw GmailAPIError.invalidBatchResponse
      }
    }
    return messages
  }

  private static func boundary(from contentType: String) -> String? {
    for component in contentType.split(separator: ";").dropFirst() {
      let pieces = component.split(separator: "=", maxSplits: 1)
      guard pieces.count == 2,
            pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "boundary"
      else { continue }
      return pieces[1].trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
    }
    return nil
  }
}

enum GmailAPIError: LocalizedError, Sendable {
  case invalidRequest
  case invalidResponse
  case invalidBatchResponse
  case historyCursorExpired
  case rateLimited(retryAfter: TimeInterval?)
  case httpStatus(Int, String?)

  var errorDescription: String? {
    switch self {
    case .invalidRequest: return "The Gmail API request was invalid."
    case .invalidResponse: return "Gmail returned an invalid response."
    case .invalidBatchResponse: return "Gmail returned an invalid batch response."
    case .historyCursorExpired: return "Gmail history expired; a new email scan is required."
    case .rateLimited: return "Gmail temporarily limited requests."
    case .httpStatus(let status, let message):
      return message.map { "Gmail returned HTTP \(status): \($0)" } ?? "Gmail returned HTTP \(status)."
    }
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}

private extension Array {
  func chunked(maxCount: Int) -> [[Element]] {
    guard maxCount > 0 else { return [] }
    return stride(from: 0, to: count, by: maxCount).map {
      Array(self[$0..<Swift.min($0 + maxCount, count)])
    }
  }
}
