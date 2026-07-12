import SwiftUI

@Observable
@MainActor
final class AppEnvironment {
  var session: SessionController
  var preferredColorScheme: ColorScheme?

  init() {
    self.session = SessionController()
    self.preferredColorScheme = nil
  }

  func applyTheme(_ preference: ThemePreference) {
    preferredColorScheme = Theme.colorScheme(for: preference)
  }
}
