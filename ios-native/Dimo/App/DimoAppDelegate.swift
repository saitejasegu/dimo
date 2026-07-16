import UIKit

final class DimoAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == GemmaModelManager.backgroundSessionIdentifier else {
      completionHandler()
      return
    }
    guard let modelServices = GemmaModelServicesProvider.shared() else {
      completionHandler()
      return
    }
    GemmaBackgroundSessionEvents.registerCompletion(completionHandler)
    Task {
      await modelServices.manager.restoreBackgroundDownload()
    }
  }
}
