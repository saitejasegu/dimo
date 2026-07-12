import SwiftUI

@main
struct DimoApp: App {
  @State private var environment = AppEnvironment()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(environment)
        .preferredColorScheme(environment.preferredColorScheme)
    }
  }
}
