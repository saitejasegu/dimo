import Foundation
import Network

final class NetworkMonitor: @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "app.dimo.network")
  private let lock = NSLock()
  private var _isOnline = true
  private var onOnline: (() -> Void)?

  var isOnline: Bool {
    lock.lock(); defer { lock.unlock() }
    return _isOnline
  }

  func start(onOnline: @escaping () -> Void) {
    self.onOnline = onOnline
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let online = path.status == .satisfied
      self.lock.lock()
      let wasOnline = self._isOnline
      self._isOnline = online
      self.lock.unlock()
      if online && !wasOnline {
        onOnline()
      }
    }
    monitor.start(queue: queue)
  }

  func stop() {
    monitor.cancel()
    onOnline = nil
  }
}
