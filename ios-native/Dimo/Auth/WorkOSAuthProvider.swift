import AuthenticationServices
import Combine
import ConvexMobile
import Foundation
import UIKit

final class WorkOSAuthProvider: NSObject, AuthProvider, @unchecked Sendable {
  typealias T = WorkOSSession

  private let refreshAccount = "workos.refreshToken"
  private let userAccount = "workos.user"
  private let lastProviderKey = "dimo.auth.lastProvider"
  private let lock = NSLock()
  private var cached: WorkOSSession?
  private var onIdToken: (@Sendable (String?) -> Void)?
  /// Single-flight refresh so concurrent TokenRefresher + cold-start paths
  /// cannot race WorkOS refresh-token rotation past the 30s grace window.
  private var refreshTask: Task<WorkOSSession, Error>?

  /// Provider used for the most recent successful sign-in, so a fresh `login`
  /// does not silently force Google on someone who signed up with Apple.
  private var lastProvider: String {
    get { UserDefaults.standard.string(forKey: lastProviderKey) ?? "GoogleOAuth" }
    set { UserDefaults.standard.set(newValue, forKey: lastProviderKey) }
  }

  var currentAccessToken: String? {
    lock.withLock { cached?.accessToken }
  }

  var currentSession: WorkOSSession? {
    lock.withLock { cached }
  }

  var hasPersistedRefreshToken: Bool {
    KeychainStore.get(account: refreshAccount) != nil
  }

  /// Cold-start restore. Retries transient network failures and only clears
  /// Keychain on a terminal `invalid_grant` (session truly over).
  func restoreSession() async -> WorkOSSession? {
    guard hasPersistedRefreshToken else { return nil }

    var lastTransient: Error?
    for attempt in 0..<5 {
      do {
        return try await loginFromCache(onIdToken: { _ in })
      } catch let error as AuthError where error.isTerminalRefresh {
        // Session revoked / expired at WorkOS — must re-authenticate.
        clearPersisted()
        return nil
      } catch {
        if AuthError.isTransient(error) || error is URLError {
          lastTransient = error
          let delay = min(8.0, pow(2.0, Double(attempt)))
          try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
          continue
        }
        // Unknown errors: keep the refresh token so a later launch can recover.
        lastTransient = error
        break
      }
    }

    // Still have a refresh token but WorkOS / network was unreachable. Keep
    // Keychain so the next launch can succeed — do not force a false logout.
    _ = lastTransient
    return nil
  }

  func signIn(provider: String) async throws -> WorkOSSession {
    try await performSignIn(provider: provider)
  }

  func signOut() async {
    try? await logout()
  }

  func refreshIfNeeded(force: Bool = false) async throws -> WorkOSSession {
    if !force, let current = lock.withLock({ cached }),
       current.expiresAt.timeIntervalSinceNow > 60 {
      return current
    }
    return try await refreshSingleFlight(force: force)
  }

  // MARK: AuthProvider

  func login(onIdToken: @Sendable @escaping (String?) -> Void) async throws -> WorkOSSession {
    self.onIdToken = onIdToken
    let session = try await performSignIn(provider: lastProvider)
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
    // Reuse a still-valid session from restore/sign-in so Convex auth does not
    // block on a second WorkOS refresh during every cold start.
    if let current = lock.withLock({ cached }),
       current.expiresAt.timeIntervalSinceNow > 60 {
      onIdToken(current.accessToken)
      return current
    }
    let session = try await refreshSingleFlight(force: true)
    onIdToken(session.accessToken)
    return session
  }

  func extractIdToken(from authResult: WorkOSSession) -> String {
    authResult.accessToken
  }

  // MARK: Private

  private func refreshSingleFlight(force: Bool) async throws -> WorkOSSession {
    if !force, let current = lock.withLock({ cached }),
       current.expiresAt.timeIntervalSinceNow > 60 {
      return current
    }

    let existing = lock.withLock { refreshTask }
    if let existing {
      return try await existing.value
    }

    let task = Task<WorkOSSession, Error> { [weak self] in
      guard let self else { throw AuthError.notAuthenticated }
      defer { self.lock.withLock { self.refreshTask = nil } }

      let refreshToken: String
      if let cachedToken = self.lock.withLock({ self.cached?.refreshToken }) {
        refreshToken = cachedToken
      } else if let stored = KeychainStore.get(account: self.refreshAccount) {
        refreshToken = stored
      } else {
        throw AuthError.notAuthenticated
      }

      do {
        let session = try await WorkOSAPI.refresh(
          refreshToken: refreshToken,
          clientId: AppConfig.workOSClientID
        )
        try self.persist(session)
        self.onIdToken?(session.accessToken)
        return session
      } catch let error as AuthError where error.isTerminalRefresh {
        self.clearPersisted()
        throw error
      }
    }

    lock.withLock { refreshTask = task }
    return try await task.value
  }

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
    lastProvider = provider
    return session
  }

  private func persist(_ session: WorkOSSession) throws {
    // Persist the rotated refresh token before publishing the session so a
    // crash mid-refresh cannot leave the retired token as the only copy.
    try KeychainStore.set(session.refreshToken, account: refreshAccount)
    let userData = try JSONEncoder().encode(session.user)
    try KeychainStore.set(String(data: userData, encoding: .utf8) ?? "", account: userAccount)
    lock.withLock { cached = session }
  }

  private func clearPersisted() {
    KeychainStore.delete(account: refreshAccount)
    KeychainStore.delete(account: userAccount)
    UserDefaults.standard.removeObject(forKey: lastProviderKey)
    lock.withLock {
      cached = nil
      refreshTask?.cancel()
      refreshTask = nil
    }
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
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap(\.windows)
    if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
      return window
    }
    guard let scene = scenes.first else {
      preconditionFailure("Web authentication requires an active window scene")
    }
    return UIWindow(windowScene: scene)
  }
}
