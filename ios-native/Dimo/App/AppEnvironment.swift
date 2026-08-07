import SwiftUI

@Observable
@MainActor
final class AppEnvironment {
  var session: SessionController
  var preferredColorScheme: ColorScheme?
  /// Device-local first-run gate. Not cleared on sign-out.
  private(set) var onboardingCompleted: Bool

  init() {
    self.session = SessionController()
    self.preferredColorScheme = nil
    self.onboardingCompleted = OnboardingStore.hasCompleted
  }

  func completeOnboarding() {
    OnboardingStore.markCompleted()
    onboardingCompleted = true
  }

  func applyTheme(_ preference: ThemePreference) {
    preferredColorScheme = Theme.colorScheme(for: preference)
  }
}
