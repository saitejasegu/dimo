import Foundation

/// One page of the first-run walkthrough.
struct OnboardingPage: Identifiable, Hashable, Sendable {
  /// SF Symbol name.
  var icon: String
  var title: String
  var body: String

  var id: String { title }
}

enum OnboardingCopy {
  /// Feature pages, in order. The notification priming page is not here — it
  /// carries its own actions and is rendered separately.
  static let pages: [OnboardingPage] = [
    OnboardingPage(
      icon: "wallet.bifold.fill",
      title: "Welcome to Dimo",
      body: """
        A calm, local-first ledger. Everything is saved on your iPhone first, \
        works offline, and syncs to web and Android when you're back online.
        """
    ),
    OnboardingPage(
      icon: "house.fill",
      title: "Log spending in seconds",
      body: """
        Add an expense from anywhere with the keypad, see it grouped by day, \
        and keep upcoming bills in view.
        """
    ),
    OnboardingPage(
      icon: "chart.bar.fill",
      title: "See where it goes",
      body: """
        Monthly trends, top categories, and top merchants — tap any bar to \
        drill into the month behind it.
        """
    ),
    OnboardingPage(
      icon: "target",
      title: "Stay inside your budget",
      body: """
        Set a monthly limit per category and watch the bars fill. Dimo can \
        suggest starting budgets from your history.
        """
    ),
    OnboardingPage(
      icon: "person.2.fill",
      title: "Track money you lend",
      body: """
        Two-way balances per contact for money lent and borrowed, with \
        settlements you can share.
        """
    ),
    OnboardingPage(
      icon: "envelope.fill",
      title: "Turn receipts into expenses",
      body: """
        Connect Gmail read-only. Mail is parsed on your device, and you \
        approve every suggested purchase before it becomes a transaction.
        """
    ),
  ]

  static let remindersPage = OnboardingPage(
    icon: "bell.badge.fill",
    title: "Never lose a day",
    body: """
      A gentle nudge each evening to log what you spent. You can change the \
      time or turn it off in Settings.
      """
  )
}

/// Device-local first-run state. Deliberately not scoped by userId and not
/// cleared on sign-out — onboarding runs before a user exists, and signing out
/// should not replay the tour.
enum OnboardingStore {
  /// Bump to re-show a revised walkthrough to everyone.
  static let currentVersion = 1

  private static let completedVersionKey = "dimo.onboarding.completedVersion"
  private static let pendingReminderKey = "dimo.onboarding.pendingReminderOptIn"

  static var hasCompleted: Bool {
    UserDefaults.standard.integer(forKey: completedVersionKey) >= currentVersion
  }

  static func markCompleted() {
    UserDefaults.standard.set(currentVersion, forKey: completedVersionKey)
  }

  /// Set only when the user granted notification permission during onboarding.
  /// The daily reminder itself is userId-scoped, so it can only be enabled once
  /// a session exists — `consumePendingReminderOptIn` bridges the two.
  static func setPendingReminderOptIn() {
    UserDefaults.standard.set(true, forKey: pendingReminderKey)
  }

  /// Reads and clears in one shot so the opt-in applies to exactly one sign-in.
  static func consumePendingReminderOptIn() -> Bool {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: pendingReminderKey) else { return false }
    defaults.removeObject(forKey: pendingReminderKey)
    return true
  }

  /// Test hook — resets both keys.
  static func resetForTesting() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: completedVersionKey)
    defaults.removeObject(forKey: pendingReminderKey)
  }
}
