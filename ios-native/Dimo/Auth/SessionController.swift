import Foundation
import Observation

enum SessionPhase: Equatable {
  case loading
  case signedOut
  case signedIn
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

  func signInWithGoogle() async throws {
    let session = try await authProvider.signIn(provider: "GoogleOAuth")
    await enterSignedIn(session: session)
  }

  func signOut() async {
    tokenRefresher?.stop()
    tokenRefresher = nil
    appStore?.tearDown()
    appStore = nil
    await authProvider.signOut()
    try? AppDatabase.deleteAllLocalDatabases()
    userId = nil
    profileName = nil
    profileEmail = nil
    phase = .signedOut
  }

  func deleteAccount() async throws {
    guard let store = appStore else { return }
    try await store.clearCloudWorkspace()
    await signOut()
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
