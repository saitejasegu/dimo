import SwiftUI

struct RootView: View {
  @Environment(AppEnvironment.self) private var environment

  var body: some View {
    Group {
      if !AppConfig.isConfigured {
        ConfigRequiredView()
      } else {
        switch environment.session.phase {
        case .loading:
          LaunchLoadingView()
        case .signedOut:
          SignInScreen()
        case .signedIn:
          if let store = environment.session.appStore {
            MainTabShell(store: store)
          } else {
            Theme.canvas.ignoresSafeArea()
          }
        }
      }
    }
    .tint(Theme.green)
  }
}

private struct LaunchLoadingView: View {
  var body: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(Theme.green)
      Text("Starting Dimo…")
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas.ignoresSafeArea())
  }
}

private struct ConfigRequiredView: View {
  var body: some View {
    VStack(spacing: 12) {
      Text("Configuration required")
        .font(DimoFont.display(22, weight: .bold))
      Text("Set CONVEX_URL and WORKOS_CLIENT_ID in Config/Shared.xcconfig.")
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas.ignoresSafeArea())
  }
}
