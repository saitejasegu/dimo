import SwiftUI

@main
struct DimoApp: App {
  @UIApplicationDelegateAdaptor(DimoAppDelegate.self) private var appDelegate
  @State private var environment = AppEnvironment()

  init() {
    EmailBackgroundTasks.register()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(environment)
        .preferredColorScheme(environment.preferredColorScheme)
    }
  }
}
