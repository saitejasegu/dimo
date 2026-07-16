import BackgroundTasks
import Foundation

@MainActor
protocol EmailBackgroundWorkProviding: AnyObject {
  func performEmailBackgroundRefresh() async -> Bool
  func performEmailBackgroundAnalysis() async -> Bool
  func cancelEmailBackgroundWork()
}

@MainActor
enum EmailBackgroundWorkRegistry {
  static weak var provider: (any EmailBackgroundWorkProviding)?
}

enum EmailBackgroundTasks {
  private static let registrationLock = NSLock()
  private static var registered = false

  static func register() {
    registrationLock.lock()
    defer { registrationLock.unlock() }
    guard !registered else { return }
    registered = true

    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: AppConfig.emailRefreshTaskIdentifier,
      using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      runRefresh(refreshTask)
    }

    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: AppConfig.emailAnalysisTaskIdentifier,
      using: nil
    ) { task in
      guard let processingTask = task as? BGProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      runAnalysis(processingTask)
    }
  }

  static func schedule(requiresAnalysisNetworkConnectivity: Bool = false) {
    scheduleRefresh()
    scheduleAnalysis(requiresNetworkConnectivity: requiresAnalysisNetworkConnectivity)
  }

  static func scheduleRefresh(earliest: Date = Date().addingTimeInterval(30 * 60)) {
    let request = BGAppRefreshTaskRequest(identifier: AppConfig.emailRefreshTaskIdentifier)
    request.earliestBeginDate = earliest
    try? BGTaskScheduler.shared.submit(request)
  }

  static func scheduleAnalysis(
    earliest: Date = Date().addingTimeInterval(15 * 60),
    requiresNetworkConnectivity: Bool = false
  ) {
    let request = BGProcessingTaskRequest(identifier: AppConfig.emailAnalysisTaskIdentifier)
    request.earliestBeginDate = earliest
    request.requiresNetworkConnectivity = requiresNetworkConnectivity
    request.requiresExternalPower = false
    try? BGTaskScheduler.shared.submit(request)
  }

  static func cancelScheduledTasks() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConfig.emailRefreshTaskIdentifier)
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConfig.emailAnalysisTaskIdentifier)
  }

  private static func runRefresh(_ task: BGAppRefreshTask) {
    scheduleRefresh()
    let operation = Task { @MainActor in
      guard let provider = EmailBackgroundWorkRegistry.provider else {
        task.setTaskCompleted(success: false)
        return
      }
      let succeeded = await provider.performEmailBackgroundRefresh()
      task.setTaskCompleted(success: succeeded && !Task.isCancelled)
    }
    task.expirationHandler = {
      operation.cancel()
      Task { @MainActor in EmailBackgroundWorkRegistry.provider?.cancelEmailBackgroundWork() }
    }
  }

  private static func runAnalysis(_ task: BGProcessingTask) {
    let operation = Task { @MainActor in
      guard let provider = EmailBackgroundWorkRegistry.provider else {
        task.setTaskCompleted(success: false)
        return
      }
      let succeeded = await provider.performEmailBackgroundAnalysis()
      task.setTaskCompleted(success: succeeded && !Task.isCancelled)
    }
    task.expirationHandler = {
      operation.cancel()
      Task { @MainActor in EmailBackgroundWorkRegistry.provider?.cancelEmailBackgroundWork() }
    }
  }
}
