import UIKit
import UserNotifications

final class DimoAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

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

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    ExpenseReminderScheduler.handleNotificationResponse(response)
    completionHandler()
  }
}
