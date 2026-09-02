import Foundation
import Observation

enum SessionPhase: Equatable {
  case loading
  case signedOut
  case signedIn
}

/// Identity providers offered on the sign-in screen. The raw strings are WorkOS
/// OAuth provider identifiers passed straight through to the authorize URL.
enum AuthProviderKind: String, CaseIterable, Sendable {
  case apple
  case google

  var workOSProvider: String {
    switch self {
    case .apple: return "AppleOAuth"
    case .google: return "GoogleOAuth"
    }
  }
}

@Observable
@MainActor
final class SessionController {
  private(set) var phase: SessionPhase = .loading
  private(set) var userId: String?
  private(set) var profileName: String?
  private(set) var profileEmail: String?
  private(set) var appStore: AppStore?

  private let authProvider = WorkOSAuthProvider()
  private var tokenRefresher: TokenRefresher?

  init() {
    Task { await bootstrap() }
  }

  func bootstrap() async {
    phase = .loading
    if let session = await authProvider.restoreSession() {
      await enterSignedIn(session: session)
      return
    }
    // Transient network failure leaves the refresh token in Keychain. Keep the
    // splash briefly and retry once more before showing sign-in so a flaky
    // cold start does not look like a logout.
    if authProvider.hasPersistedRefreshToken {
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      if let session = await authProvider.restoreSession() {
        await enterSignedIn(session: session)
        return
      }
    }
    phase = .signedOut
  }

  func signIn(with kind: AuthProviderKind) async throws {
    let session = try await authProvider.signIn(provider: kind.workOSProvider)
    await enterSignedIn(session: session)
  }

  func signOut() async throws {
    tokenRefresher?.stop()
    tokenRefresher = nil
    let signedOutUserId = userId
    await appStore?.tearDown()
    if let signedOutUserId {
      try await GmailCredentialVault().removeAll(dimoUserId: signedOutUserId)
      try await OpenRouterCredentialVault().remove(dimoUserId: signedOutUserId)
      ExpenseReminderStore.clear(userId: signedOutUserId)
    }
    try AppDatabase.deleteAllLocalDatabases()
    await authProvider.signOut()
    appStore = nil
    userId = nil
    profileName = nil
    profileEmail = nil
    phase = .signedOut
  }

  func deleteAccount() async throws {
    guard let store = appStore else { return }
    try await store.clearCloudWorkspace()
    try await signOut()
  }

  private func enterSignedIn(session: WorkOSSession) async {
    userId = session.user.id
    profileName = session.user.displayName
    profileEmail = session.user.email
    let store = AppStore(
      userId: session.user.id,
      profileName: session.user.displayName,
      profileEmail: session.user.email,
      profilePhotoUrl: session.user.profilePictureUrl,
      authProvider: authProvider
    )
    await store.start()
    appStore = store
    let refresher = TokenRefresher(authProvider: authProvider)
    refresher.onTerminalFailure = { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        // Terminal WorkOS session end — sign out UI without deleting local DBs
        // mid-refresh; next explicit sign-in reuses account-scoped storage.
        self.tokenRefresher?.stop()
        self.tokenRefresher = nil
        await self.appStore?.tearDown()
        self.appStore = nil
        self.userId = nil
        self.profileName = nil
        self.profileEmail = nil
        self.phase = .signedOut
      }
    }
    tokenRefresher = refresher
    refresher.start()
    phase = .signedIn
  }
}