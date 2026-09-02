import Foundation

@MainActor
final class TokenRefresher {
  private let authProvider: WorkOSAuthProvider
  private var task: Task<Void, Never>?
  /// Called only when WorkOS reports a terminal refresh failure so the UI can
  /// return to sign-in without wiping local data mid-failure storm.
  var onTerminalFailure: (() -> Void)?

  init(authProvider: WorkOSAuthProvider) {
    self.authProvider = authProvider
  }

  func start() {
    stop()
    task = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        do {
          let session = try await self.authProvider.refreshIfNeeded(force: false)
          let delay = max(5, session.expiresAt.timeIntervalSinceNow - 60)
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch let error as AuthError where error.isTerminalRefresh {
          self.onTerminalFailure?()
          return
        } catch {
          // Transient — keep the session and retry with backoff.
          try? await Task.sleep(nanoseconds: 30_000_000_000)
        }
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}
