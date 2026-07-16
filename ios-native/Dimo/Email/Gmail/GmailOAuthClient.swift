import AuthenticationServices
import Foundation
import UIKit

enum GmailURLSession {
  static func make() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.waitsForConnectivity = true
    return URLSession(configuration: configuration)
  }
}

struct GmailOAuthConfiguration: Hashable, Sendable {
  static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
  static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
  static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
  static let userInfoEndpoint = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
  static let readOnlyScope = "https://www.googleapis.com/auth/gmail.readonly"

  var clientId: String
  var redirectScheme: String
  var redirectURI: String

  init(clientId: String, redirectScheme: String, redirectURI: String? = nil) {
    self.clientId = clientId
    self.redirectScheme = redirectScheme
    self.redirectURI = redirectURI ?? "\(redirectScheme):/oauthredirect"
  }

  static func fromAppConfig() throws -> GmailOAuthConfiguration {
    guard AppConfig.isGmailConfigured else {
      throw GmailOAuthError.notConfigured
    }
    return GmailOAuthConfiguration(
      clientId: AppConfig.gmailOAuthClientID,
      redirectScheme: AppConfig.gmailOAuthRedirectScheme,
      redirectURI: AppConfig.gmailOAuthRedirectURI
    )
  }
}

struct GmailAccessToken: Hashable, Sendable {
  var value: String
  var expiresAt: Date
}

protocol GmailAccessTokenProviding: Sendable {
  func accessToken(subject: String, dimoUserId: String, forceRefresh: Bool) async throws
    -> GmailAccessToken
  func invalidate(subject: String) async
}

/// Performs Gmail's separate installed-app OAuth flow. It never uses the WorkOS token.
final class GmailOAuthClient: NSObject, @unchecked Sendable {
  private let configuration: GmailOAuthConfiguration
  private let vault: GmailCredentialVault
  private let session: URLSession
  @MainActor private var webAuthenticationSession: ASWebAuthenticationSession?

  init(
    configuration: GmailOAuthConfiguration,
    vault: GmailCredentialVault,
    session: URLSession = GmailURLSession.make()
  ) {
    self.configuration = configuration
    self.vault = vault
    self.session = session
  }

  func connect(dimoUserId: String) async throws -> ConnectedGmailAccount {
    let verifier = PKCE.makeVerifier()
    let state = PKCE.makeState()
    let authorizationURL = try makeAuthorizationURL(verifier: verifier, state: state)
    let callback = try await startWebAuthentication(url: authorizationURL)
    let queryItems = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
    var parameters: [String: String] = [:]
    for item in queryItems {
      if let value = item.value { parameters[item.name] = value }
    }
    if let oauthError = parameters["error"] {
      if oauthError == "access_denied" { throw GmailOAuthError.cancelled }
      throw GmailOAuthError.authorization(oauthError)
    }
    guard parameters["state"] == state else { throw GmailOAuthError.stateMismatch }
    guard let code = parameters["code"], !code.isEmpty else { throw GmailOAuthError.missingCode }

    let token = try await exchangeCode(code, verifier: verifier)
    guard let refreshToken = token.refreshToken, !refreshToken.isEmpty else {
      throw GmailOAuthError.missingRefreshToken
    }
    let identity = try await fetchIdentity(accessToken: token.accessToken)
    let credential = GmailStoredCredential(
      subject: identity.subject,
      emailAddress: identity.emailAddress,
      refreshToken: refreshToken,
      connectedAt: .now
    )
    try await vault.upsert(credential, dimoUserId: dimoUserId)
    return credential.account
  }

  @MainActor
  func cancel() {
    webAuthenticationSession?.cancel()
    webAuthenticationSession = nil
  }

  /// Revocation is best effort; local credentials are always removed.
  func disconnect(subject: String, dimoUserId: String) async throws {
    let refreshToken = try await vault.credential(subject: subject, dimoUserId: dimoUserId)?.refreshToken
    if let refreshToken { try? await revoke(token: refreshToken) }
    try await vault.remove(subject: subject, dimoUserId: dimoUserId)
  }

  func deleteLocalCredentialsOnSignOut(dimoUserId: String) async {
    try? await vault.removeAll(dimoUserId: dimoUserId)
  }

  private func makeAuthorizationURL(verifier: String, state: String) throws -> URL {
    var components = URLComponents(
      url: GmailOAuthConfiguration.authorizationEndpoint,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: configuration.clientId),
      URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(
        name: "scope",
        value: ["openid", "email", GmailOAuthConfiguration.readOnlyScope].joined(separator: " ")
      ),
      URLQueryItem(name: "access_type", value: "offline"),
      URLQueryItem(name: "prompt", value: "consent select_account"),
      URLQueryItem(name: "include_granted_scopes", value: "true"),
      URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state),
    ]
    guard let url = components.url else { throw GmailOAuthError.invalidAuthorizationURL }
    return url
  }

  private func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokenResponse {
    try await postForm(
      to: GmailOAuthConfiguration.tokenEndpoint,
      values: [
        "client_id": configuration.clientId,
        "code": code,
        "code_verifier": verifier,
        "grant_type": "authorization_code",
        "redirect_uri": configuration.redirectURI,
      ],
      as: OAuthTokenResponse.self
    )
  }

  private func fetchIdentity(accessToken: String) async throws -> GmailIdentityResponse {
    var request = URLRequest(url: GmailOAuthConfiguration.userInfoEndpoint)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    do {
      return try JSONDecoder().decode(GmailIdentityResponse.self, from: data)
    } catch {
      throw GmailOAuthError.invalidResponse
    }
  }

  private func revoke(token: String) async throws {
    var components = URLComponents(
      url: GmailOAuthConfiguration.revocationEndpoint,
      resolvingAgainstBaseURL: false
    )!
    components.queryItems = [URLQueryItem(name: "token", value: token)]
    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
  }

  private func postForm<Response: Decodable>(
    to url: URL,
    values: [String: String],
    as type: Response.Type
  ) async throws -> Response {
    var body = URLComponents()
    body.queryItems = values.sorted { $0.key < $1.key }.map(URLQueryItem.init(name:value:))
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
    let (data, response) = try await session.data(for: request)
    try validate(response: response, data: data)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw GmailOAuthError.invalidResponse
    }
  }

  private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { throw GmailOAuthError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let payload = try? JSONDecoder().decode(GoogleOAuthErrorResponse.self, from: data)
      let message = payload?.errorDescription ?? payload?.error ?? "HTTP \(http.statusCode)"
      if payload?.error == "invalid_grant" { throw GmailOAuthError.requiresReconnect }
      throw GmailOAuthError.server(message)
    }
  }

  @MainActor
  private func startWebAuthentication(url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let authSession = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: configuration.redirectScheme
      ) { callbackURL, error in
        Task { @MainActor [weak self] in self?.webAuthenticationSession = nil }
        if let error {
          let nsError = error as NSError
          if nsError.domain == ASWebAuthenticationSessionErrorDomain,
             nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            continuation.resume(throwing: GmailOAuthError.cancelled)
          } else {
            continuation.resume(throwing: error)
          }
          return
        }
        guard let callbackURL else {
          continuation.resume(throwing: GmailOAuthError.missingCode)
          return
        }
        continuation.resume(returning: callbackURL)
      }
      authSession.presentationContextProvider = self
      authSession.prefersEphemeralWebBrowserSession = false
      webAuthenticationSession = authSession
      guard authSession.start() else {
        webAuthenticationSession = nil
        continuation.resume(throwing: GmailOAuthError.couldNotStartSession)
        return
      }
    }
  }
}

extension GmailOAuthClient: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    if let window = windows.first(where: \.isKeyWindow) ?? windows.first { return window }
    guard let scene = scenes.first else {
      preconditionFailure("Gmail authentication requires an active window scene")
    }
    return UIWindow(windowScene: scene)
  }
}

actor GmailAccessTokenManager: GmailAccessTokenProviding {
  private let configuration: GmailOAuthConfiguration
  private let vault: GmailCredentialVault
  private let session: URLSession
  private var cachedTokens: [String: GmailAccessToken] = [:]

  init(
    configuration: GmailOAuthConfiguration,
    vault: GmailCredentialVault,
    session: URLSession = GmailURLSession.make()
  ) {
    self.configuration = configuration
    self.vault = vault
    self.session = session
  }

  func accessToken(
    subject: String,
    dimoUserId: String,
    forceRefresh: Bool = false
  ) async throws -> GmailAccessToken {
    if !forceRefresh, let cached = cachedTokens[subject], cached.expiresAt.timeIntervalSinceNow > 60 {
      return cached
    }
    guard let credential = try await vault.credential(subject: subject, dimoUserId: dimoUserId) else {
      throw GmailOAuthError.requiresReconnect
    }
    var form = URLComponents()
    form.queryItems = [
      URLQueryItem(name: "client_id", value: configuration.clientId),
      URLQueryItem(name: "refresh_token", value: credential.refreshToken),
      URLQueryItem(name: "grant_type", value: "refresh_token"),
    ]
    var request = URLRequest(url: GmailOAuthConfiguration.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw GmailOAuthError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let payload = try? JSONDecoder().decode(GoogleOAuthErrorResponse.self, from: data)
      if payload?.error == "invalid_grant" { throw GmailOAuthError.requiresReconnect }
      throw GmailOAuthError.server(payload?.errorDescription ?? payload?.error ?? "HTTP \(http.statusCode)")
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let response = try? decoder.decode(OAuthTokenResponse.self, from: data) else {
      throw GmailOAuthError.invalidResponse
    }
    let token = GmailAccessToken(
      value: response.accessToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(max(response.expiresIn - 60, 1)))
    )
    cachedTokens[subject] = token
    return token
  }

  func invalidate(subject: String) {
    cachedTokens[subject] = nil
  }

  func clearAll() {
    cachedTokens.removeAll()
  }
}

private struct OAuthTokenResponse: Decodable {
  var accessToken: String
  var expiresIn: Int
  var refreshToken: String?
}

private struct GmailIdentityResponse: Decodable {
  var subject: String
  var emailAddress: String

  enum CodingKeys: String, CodingKey {
    case subject = "sub"
    case emailAddress = "email"
  }
}

private struct GoogleOAuthErrorResponse: Decodable {
  var error: String?
  var errorDescription: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescription = "error_description"
  }
}

enum GmailOAuthError: LocalizedError, Sendable {
  case notConfigured
  case invalidAuthorizationURL
  case couldNotStartSession
  case cancelled
  case stateMismatch
  case missingCode
  case missingRefreshToken
  case invalidResponse
  case requiresReconnect
  case authorization(String)
  case server(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured: return "Gmail OAuth is not configured."
    case .invalidAuthorizationURL: return "The Gmail authorization URL is invalid."
    case .couldNotStartSession: return "Gmail sign-in could not be opened."
    case .cancelled: return "Gmail sign-in was cancelled."
    case .stateMismatch: return "Gmail sign-in failed its security check."
    case .missingCode: return "Gmail did not return an authorization code."
    case .missingRefreshToken: return "Gmail did not grant offline access. Please connect again."
    case .invalidResponse: return "Gmail returned an invalid response."
    case .requiresReconnect: return "Gmail access expired or was revoked. Please connect again."
    case .authorization(let message): return "Gmail authorization failed: \(message)"
    case .server(let message): return "Gmail authorization failed: \(message)"
    }
  }
}
