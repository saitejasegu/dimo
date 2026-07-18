import UIKit

final class DimoAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard let modelServices = GemmaModelServicesProvider.shared(),
          let manager = modelServices.manager(forBackgroundSessionIdentifier: identifier) else {
      completionHandler()
      return
    }
    GemmaBackgroundSessionEvents.registerCompletion(completionHandler)
    Task {
      await manager.restoreBackgroundDownload()
    }
  }
}
