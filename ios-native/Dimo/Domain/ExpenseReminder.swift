import Foundation

/// Device-local daily expense reminder. Not synced — local notifications are
/// per-device, same as last-used payment method metadata.
struct ExpenseReminderSettings: Codable, Hashable, Sendable {
  var enabled: Bool
  /// Local-clock hour in 0...23.
  var hour: Int
  /// Local-clock minute in 0...59.
  var minute: Int

  static let `default` = ExpenseReminderSettings(enabled: false, hour: 20, minute: 0)

  var clamped: ExpenseReminderSettings {
    ExpenseReminderSettings(
      enabled: enabled,
      hour: min(max(hour, 0), 23),
      minute: min(max(minute, 0), 59)
    )
  }
}

enum ExpenseReminderCopy {
  static let notificationIdentifier = "dimo.expense-reminder.daily"
  static let userInfoTypeKey = "dimo.reminder.type"
  static let userInfoTypeValue = "expense"
  static let userInfoPendingPurchasesKey = "dimo.reminder.pendingPurchases"

  static func title(pendingPurchaseCount: Int) -> String {
    pendingPurchaseCount > 0
      ? "Expenses and reviews waiting"
      : "Log today's expenses"
  }

  static func body(pendingPurchaseCount: Int) -> String {
    let base = "Take a moment to add anything you spent today."
    guard pendingPurchaseCount > 0 else { return base }
    let noun = pendingPurchaseCount == 1 ? "purchase" : "purchases"
    return "\(base) You also have \(pendingPurchaseCount) \(noun) waiting for review."
  }
}

enum ExpenseReminderStore {
  private static let keyPrefix = "dimo.expenseReminder.settings."

  static func load(userId: String) -> ExpenseReminderSettings {
    let key = keyPrefix + userId
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode(ExpenseReminderSettings.self, from: data)
    else {
      return .default
    }
    return decoded.clamped
  }

  static func save(_ settings: ExpenseReminderSettings, userId: String) {
    let key = keyPrefix + userId
    let value = settings.clamped
    if let data = try? JSONEncoder().encode(value) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  static func clear(userId: String) {
    UserDefaults.standard.removeObject(forKey: keyPrefix + userId)
  }
}
