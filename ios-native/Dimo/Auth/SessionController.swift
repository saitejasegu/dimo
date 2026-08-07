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
    } else {
      phase = .signedOut
    }
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
    tokenRefresher = TokenRefresher(authProvider: authProvider)
    tokenRefresher?.start()
    phase = .signedIn
  }
}
