import Foundation

enum EmailOpenRouterPacing {
  /// Three seconds keeps requests sequential while allowing up to 20 starts per minute.
  static let minimumStartInterval: Duration = .seconds(3)
}

/// Reserves process-wide start times across every OpenRouter analysis path.
/// Reserving before sleeping prevents concurrent refresh and upgrade work from
/// beginning two requests after the same delay.
actor EmailAnalysisStartThrottle {
  static let openRouter = EmailAnalysisStartThrottle()

  private let clock = ContinuousClock()
  private var nextStart: ContinuousClock.Instant?

  func waitForNextStart(minimumInterval: Duration) async throws {
    let now = clock.now
    let scheduledStart: ContinuousClock.Instant
    if let nextStart, nextStart > now {
      scheduledStart = nextStart
    } else {
      scheduledStart = now
    }
    nextStart = scheduledStart.advanced(by: minimumInterval)

    if scheduledStart > now {
      try await clock.sleep(until: scheduledStart, tolerance: .seconds(1))
    }
    try Task.checkCancellation()
  }
}
