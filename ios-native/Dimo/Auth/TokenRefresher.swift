import Foundation

@MainActor
final class TokenRefresher {
  private let authProvider: WorkOSAuthProvider
  private var task: Task<Void, Never>?

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
        } catch {
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
