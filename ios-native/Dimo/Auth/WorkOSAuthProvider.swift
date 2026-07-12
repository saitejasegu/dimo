import AuthenticationServices
import Combine
import ConvexMobile
import Foundation
import UIKit

final class WorkOSAuthProvider: NSObject, AuthProvider, @unchecked Sendable {
  typealias T = WorkOSSession

  private let refreshAccount = "workos.refreshToken"
  private let userAccount = "workos.user"
  private let lock = NSLock()
  private var cached: WorkOSSession?
  private var onIdToken: (@Sendable (String?) -> Void)?

  var currentAccessToken: String? {
    lock.lock(); defer { lock.unlock() }
    return cached?.accessToken
  }

  var currentSession: WorkOSSession? {
    lock.lock(); defer { lock.unlock() }
    return cached
  }

  func restoreSession() async -> WorkOSSession? {
    do {
      return try await loginFromCache(onIdToken: { _ in })
    } catch {
      return nil
    }
  }

  func signIn(provider: String) async throws -> WorkOSSession {
    try await performSignIn(provider: provider)
  }

  func signOut() async {
    try? await logout()
  }

  func refreshIfNeeded(force: Bool = false) async throws -> WorkOSSession {
    lock.lock()
    let current = cached
    lock.unlock()
    guard let current else { throw AuthError.notAuthenticated }
    if !force, current.expiresAt.timeIntervalSinceNow > 60 {
      return current
    }
    let session = try await WorkOSAPI.refresh(
      refreshToken: current.refreshToken,
      clientId: AppConfig.workOSClientID
    )
    try persist(session)
    onIdToken?(session.accessToken)
    return session
  }

  // MARK: AuthProvider

  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> WorkOSSession {
    self.onIdToken = onIdToken
    let session = try await performSignIn(provider: "GoogleOAuth")
    onIdToken(session.accessToken)
    return session
  }

  func logout() async throws {
    clearPersisted()
    onIdToken?(nil)
    onIdToken = nil
  }

  func loginFromCache(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> WorkOSSession {
    self.onIdToken = onIdToken
    guard let refresh = KeychainStore.get(account: refreshAccount) else {
      throw AuthError.notAuthenticated
    }
    let session = try await WorkOSAPI.refresh(refreshToken: refresh, clientId: AppConfig.workOSClientID)
    try persist(session)
    onIdToken(session.accessToken)
    return session
  }

  func extractIdToken(from authResult: WorkOSSession) -> String {
    authResult.accessToken
  }

  // MARK: Private

  private func performSignIn(provider: String) async throws -> WorkOSSession {
    let verifier = PKCE.makeVerifier()
    let challenge = PKCE.challenge(for: verifier)
    let state = PKCE.makeState()
    let url = WorkOSAPI.authorizationURL(
      clientId: AppConfig.workOSClientID,
      redirectURI: AppConfig.workOSRedirectURI,
      state: state,
      codeChallenge: challenge,
      provider: provider
    )
    let callback = try await startWebAuth(url: url)
    guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
      throw AuthError.missingCode
    }
    let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
      item.value.map { (item.name, $0) }
    })
    guard items["state"] == state else { throw AuthError.stateMismatch }
    guard let code = items["code"] else { throw AuthError.missingCode }
    let session = try await WorkOSAPI.exchangeCode(
      code: code,
      codeVerifier: verifier,
      clientId: AppConfig.workOSClientID,
      redirectURI: AppConfig.workOSRedirectURI
    )
    try persist(session)
    return session
  }

  private func persist(_ session: WorkOSSession) throws {
    try KeychainStore.set(session.refreshToken, account: refreshAccount)
    let userData = try JSONEncoder().encode(session.user)
    try KeychainStore.set(String(data: userData, encoding: .utf8) ?? "", account: userAccount)
    lock.lock()
    cached = session
    lock.unlock()
  }

  private func clearPersisted() {
    KeychainStore.delete(account: refreshAccount)
    KeychainStore.delete(account: userAccount)
    lock.lock()
    cached = nil
    lock.unlock()
  }

  @MainActor
  private func startWebAuth(url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: "dimo"
      ) { callbackURL, error in
        if let error {
          let ns = error as NSError
          if ns.domain == ASWebAuthenticationSessionErrorDomain,
             ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            continuation.resume(throwing: AuthError.cancelled)
          } else {
            continuation.resume(throwing: error)
          }
          return
        }
        guard let callbackURL else {
          continuation.resume(throwing: AuthError.missingCode)
          return
        }
        continuation.resume(returning: callbackURL)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      if !session.start() {
        continuation.resume(throwing: AuthError.server("Could not start authentication session"))
      }
    }
  }
}

extension WorkOSAuthProvider: ASWebAuthenticationPresentationContextProviding {
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow } ?? ASPresentationAnchor()
  }
}
