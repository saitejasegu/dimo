import Foundation

struct WorkOSUser: Codable, Sendable, Equatable {
  var id: String
  var email: String
  var firstName: String?
  var lastName: String?
  var profilePictureUrl: String?

  // WorkOS returns snake_case fields; without these keys the names decode as
  // nil and displayName falls back to the email address.
  enum CodingKeys: String, CodingKey {
    case id
    case email
    case firstName = "first_name"
    case lastName = "last_name"
    case profilePictureUrl = "profile_picture_url"
  }

  var displayName: String {
    let parts = [firstName, lastName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    if !parts.isEmpty { return parts.joined(separator: " ") }
    return email
  }
}

struct WorkOSSession: Sendable {
  var accessToken: String
  var refreshToken: String
  var user: WorkOSUser
  var expiresAt: Date
}

enum WorkOSAPI {
  struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var user: WorkOSUser

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case user
    }
  }

  static func exchangeCode(
    code: String,
    codeVerifier: String,
    clientId: String,
    redirectURI: String
  ) async throws -> WorkOSSession {
    var request = URLRequest(url: URL(string: "\(AppConfig.workOSAuthBaseURL)/user_management/authenticate")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = [
      "client_id": clientId,
      "grant_type": "authorization_code",
      "code": code,
      "code_verifier": codeVerifier,
      "redirect_uri": redirectURI,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    try throwIfNeeded(response: response, data: data)
    let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
    guard let refresh = decoded.refreshToken else {
      throw AuthError.missingRefreshToken
    }
    return WorkOSSession(
      accessToken: decoded.accessToken,
      refreshToken: refresh,
      user: decoded.user,
      expiresAt: jwtExpiry(decoded.accessToken) ?? Date().addingTimeInterval(3600)
    )
  }

  /// Exchanges a refresh token. Retries transient transport / 429 / 5xx failures
  /// per WorkOS session-resilience guidance; surfaces `invalid_grant` as terminal.
  static func refresh(
    refreshToken: String,
    clientId: String,
    maxAttempts: Int = 4
  ) async throws -> WorkOSSession {
    var lastError: Error?
    for attempt in 0..<max(1, maxAttempts) {
      do {
        return try await refreshOnce(refreshToken: refreshToken, clientId: clientId)
      } catch let error as AuthError where error.isTerminalRefresh {
        throw error
      } catch {
        lastError = error
        if attempt + 1 >= maxAttempts { break }
        let delay = min(8.0, pow(2.0, Double(attempt))) * (0.75 + Double.random(in: 0...0.5))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
    }
    throw lastError ?? AuthError.transientRefresh("Refresh failed")
  }

  private static func refreshOnce(
    refreshToken: String,
    clientId: String
  ) async throws -> WorkOSSession {
    var request = URLRequest(url: URL(string: "\(AppConfig.workOSAuthBaseURL)/user_management/authenticate")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30
    let body: [String: String] = [
      "client_id": clientId,
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    try throwIfNeeded(response: response, data: data)
    let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
    // Always prefer the rotated refresh token when WorkOS returns one.
    let refresh = decoded.refreshToken ?? refreshToken
    return WorkOSSession(
      accessToken: decoded.accessToken,
      refreshToken: refresh,
      user: decoded.user,
      expiresAt: jwtExpiry(decoded.accessToken) ?? Date().addingTimeInterval(3600)
    )
  }

  static func authorizationURL(
    clientId: String,
    redirectURI: String,
    state: String,
    codeChallenge: String,
    provider: String
  ) -> URL {
    var components = URLComponents(string: "\(AppConfig.workOSAuthBaseURL)/user_management/authorize")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientId),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "provider", value: provider),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: codeChallenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    return components.url!
  }

  static func jwtExpiry(_ token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var payload = String(parts[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    guard let data = Data(base64Encoded: payload),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let exp: TimeInterval?
    if let value = json["exp"] as? TimeInterval {
      exp = value
    } else if let value = json["exp"] as? Int {
      exp = TimeInterval(value)
    } else if let number = json["exp"] as? NSNumber {
      exp = number.doubleValue
    } else {
      exp = nil
    }
    guard let exp else { return nil }
    return Date(timeIntervalSince1970: exp)
  }

  private static func throwIfNeeded(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
      throw AuthError.fromHTTP(status: http.statusCode, data: data)
    }
  }
}

enum AuthError: LocalizedError {
  case missingRefreshToken
  case cancelled
  case stateMismatch
  case missingCode
  case notAuthenticated
  case server(String)
  /// Refresh token revoked/expired — clear Keychain and send user to sign-in.
  case terminalRefresh(String)
  /// Network / 429 / 5xx — keep Keychain and retry; never treat as sign-out.
  case transientRefresh(String)

  var errorDescription: String? {
    switch self {
    case .missingRefreshToken: return "Missing refresh token"
    case .cancelled: return "Sign-in cancelled"
    case .stateMismatch: return "OAuth state mismatch"
    case .missingCode: return "Missing authorization code"
    case .notAuthenticated: return "Not authenticated"
    case .server(let message): return message
    case .terminalRefresh(let message): return message
    case .transientRefresh(let message): return message
    }
  }

  var isTerminalRefresh: Bool {
    switch self {
    case .terminalRefresh, .notAuthenticated, .missingRefreshToken:
      return true
    default:
      return false
    }
  }

  static func fromHTTP(status: Int, data: Data) -> AuthError {
    let body = String(data: data, encoding: .utf8) ?? ""
    let oauthError = oauthErrorCode(from: data)
    if status == 400, oauthError == "invalid_grant" {
      return .terminalRefresh(sanitizeMessage(body, fallback: "Session expired"))
    }
    if status == 408 || status == 429 || (500...599).contains(status) {
      return .transientRefresh(sanitizeMessage(body, fallback: "HTTP \(status)"))
    }
    // Unexpected auth errors are treated as terminal so we do not loop forever
    // on a permanently rejected client configuration.
    if (400..<500).contains(status) {
      return .terminalRefresh(sanitizeMessage(body, fallback: "HTTP \(status)"))
    }
    return .transientRefresh(sanitizeMessage(body, fallback: "HTTP \(status)"))
  }

  static func isTransient(_ error: Error) -> Bool {
    if let auth = error as? AuthError {
      switch auth {
      case .transientRefresh: return true
      default: return false
      }
    }
    if error is URLError { return true }
    return false
  }

  private static func oauthErrorCode(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    if let code = json["error"] as? String { return code }
    if let nested = json["error"] as? [String: Any], let code = nested["code"] as? String {
      return code
    }
    return nil
  }

  private static func sanitizeMessage(_ body: String, fallback: String) -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return fallback }
    return String(trimmed.prefix(200))
  }
}
