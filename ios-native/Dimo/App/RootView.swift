import SwiftUI

struct RootView: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var pendingWidgetURL: URL?

  var body: some View {
    Group {
      if !AppConfig.isConfigured {
        ConfigRequiredView()
      } else {
        switch environment.session.phase {
        case .loading:
          LaunchLoadingView()
        case .signedOut:
          if environment.onboardingCompleted {
            SignInScreen()
          } else {
            OnboardingFlow { environment.completeOnboarding() }
          }
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
    .onOpenURL { url in
      guard url.scheme == "dimo", url.host == "widget",
        ["/add-expense", "/stats"].contains(url.path) else { return }
      pendingWidgetURL = url
      openPendingWidgetURL()
    }
    .onChange(of: environment.session.phase) { _, _ in
      openPendingWidgetURL()
    }
  }

  private func openPendingWidgetURL() {
    guard environment.session.phase == .signedIn,
      let store = environment.session.appStore, let url = pendingWidgetURL else { return }
    pendingWidgetURL = nil
    store.nav.widgetNavigationID = UUID()
    store.detailId = nil
    if url.path == "/add-expense" {
      store.setView(.home)
      store.openOverlay(.add)
    } else {
      store.closeOverlay()
      store.statsRange = .oneWeek
      store.statsPeriodOffset = 0
      store.setView(.stats)
    }
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
