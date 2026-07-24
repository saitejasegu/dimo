import Foundation
import UserNotifications

enum ExpenseReminderAuthorization: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
}

@MainActor
enum ExpenseReminderRouter {
  /// Active signed-in store for notification taps. Cleared on tearDown.
  static weak var store: AppStore?
}

enum ExpenseReminderScheduler {
  static func authorizationStatus() async -> ExpenseReminderAuthorization {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return .authorized
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .denied
    }
  }

  /// Requests permission when needed. Returns whether notifications may be scheduled.
  @discardableResult
  static func requestAuthorizationIfNeeded() async -> Bool {
    switch await authorizationStatus() {
    case .authorized:
      return true
    case .denied:
      return false
    case .notDetermined:
      do {
        return try await UNUserNotificationCenter.current()
          .requestAuthorization(options: [.alert, .sound, .badge])
      } catch {
        return false
      }
    }
  }

  static func cancel() {
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(
        withIdentifiers: [ExpenseReminderCopy.notificationIdentifier]
      )
  }

  /// Schedules (or replaces) the daily reminder. Cancels when disabled.
  static func apply(
    settings: ExpenseReminderSettings,
    pendingPurchaseCount: Int
  ) async {
    let settings = settings.clamped
    cancel()
    guard settings.enabled else { return }
    guard await requestAuthorizationIfNeeded() else { return }

    let content = UNMutableNotificationContent()
    content.title = ExpenseReminderCopy.title(pendingPurchaseCount: pendingPurchaseCount)
    content.body = ExpenseReminderCopy.body(pendingPurchaseCount: pendingPurchaseCount)
    content.sound = .default
    content.userInfo = [
      ExpenseReminderCopy.userInfoTypeKey: ExpenseReminderCopy.userInfoTypeValue,
      ExpenseReminderCopy.userInfoPendingPurchasesKey: pendingPurchaseCount,
    ]

    var components = DateComponents()
    components.hour = settings.hour
    components.minute = settings.minute
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
    let request = UNNotificationRequest(
      identifier: ExpenseReminderCopy.notificationIdentifier,
      content: content,
      trigger: trigger
    )
    try? await UNUserNotificationCenter.current().add(request)
  }

  static func handleNotificationResponse(_ response: UNNotificationResponse) {
    let info = response.notification.request.content.userInfo
    guard let type = info[ExpenseReminderCopy.userInfoTypeKey] as? String,
          type == ExpenseReminderCopy.userInfoTypeValue
    else { return }

    let pending = (info[ExpenseReminderCopy.userInfoPendingPurchasesKey] as? Int) ?? 0
    Task { @MainActor in
      guard let store = ExpenseReminderRouter.store else { return }
      if pending > 0 {
        store.setView(.email)
      } else {
        store.setView(.home)
        store.openOverlay(.add)
      }
    }
  }
}
