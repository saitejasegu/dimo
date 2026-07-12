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

  static func refresh(
    refreshToken: String,
    clientId: String
  ) async throws -> WorkOSSession {
    var request = URLRequest(url: URL(string: "\(AppConfig.workOSAuthBaseURL)/user_management/authenticate")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: String] = [
      "client_id": clientId,
      "grant_type": "refresh_token",
      "refresh_token": refreshToken,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    try throwIfNeeded(response: response, data: data)
    let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
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
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let exp = json["exp"] as? TimeInterval else { return nil }
    return Date(timeIntervalSince1970: exp)
  }

  private static func throwIfNeeded(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
      throw AuthError.server(message)
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

  var errorDescription: String? {
    switch self {
    case .missingRefreshToken: return "Missing refresh token"
    case .cancelled: return "Sign-in cancelled"
    case .stateMismatch: return "OAuth state mismatch"
    case .missingCode: return "Missing authorization code"
    case .notAuthenticated: return "Not authenticated"
    case .server(let message): return message
    }
  }
}
