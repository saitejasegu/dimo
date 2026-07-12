import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case home, stats, recurring, budgets

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "Home"
    case .stats: return "Stats"
    case .recurring: return "Recurring"
    case .budgets: return "Budgets"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house.fill"
    case .stats: return "chart.bar.fill"
    case .recurring: return "arrow.2.circlepath"
    case .budgets: return "target"
    }
  }
}

struct MainTabShell: View {
  @Bindable var store: AppStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab: AppTab = .home
  @State private var settingsPath: [SettingsRoute] = []

  var body: some View {
    NavigationStack(path: $settingsPath) {
      tabShell
        .navigationDestination(for: SettingsRoute.self) { route in
          switch route {
          case .settings:
            SettingsScreen(store: store) {
              settingsPath.append(.account)
            }
            .toolbar(.hidden, for: .navigationBar)
          case .account:
            AccountScreen(store: store) {
              if !settingsPath.isEmpty { settingsPath.removeLast() }
            }
            .toolbar(.hidden, for: .navigationBar)
          }
        }
    }
  }

  private var tabShell: some View {
    TabView(selection: $tab) {
      Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
        HomeScreen(store: store) {
          settingsPath.append(.settings)
        }
      }
      Tab(AppTab.stats.title, systemImage: AppTab.stats.systemImage, value: .stats) {
        StatsScreen(store: store)
      }
      Tab(AppTab.recurring.title, systemImage: AppTab.recurring.systemImage, value: .recurring) {
        RecurringScreen(store: store)
      }
      Tab(AppTab.budgets.title, systemImage: AppTab.budgets.systemImage, value: .budgets) {
        BudgetsScreen(store: store)
      }
    }
    .tint(Theme.green)
    .tabBarMinimizeBehavior(.never)
    .overlay(alignment: .bottomTrailing) {
      if showsFAB {
        contextualAction
          .padding(.trailing, 22)
          .padding(.bottom, 68)
          .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }
    .sheet(item: $store.overlay) { overlay in
      switch overlay {
      case .add:
        AddExpenseSheet(store: store)
      case .recurring:
        AddRecurringSheet(store: store)
      case .category:
        NewCategorySheet(store: store)
      }
    }
    .sheet(item: Binding(
      get: { store.detailId.map(DetailSheetItem.init) },
      set: { store.detailId = $0?.id }
    )) { item in
      TxDetailSheet(store: store, transactionId: item.id)
    }
    .overlay(alignment: .top) {
      if let toast = store.toast {
        ToastView(message: toast)
          .padding(.top, 12)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.25), value: store.toast)
    .animation(.easeOut(duration: 0.2), value: showsFAB)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { store.sceneBecameActive() }
    }
    .onChange(of: tab) { _, newTab in
      store.setView(viewKey(for: newTab))
    }
    .onChange(of: store.view) { _, newView in
      if let destination = tab(for: newView), destination != tab {
        tab = destination
      }
    }
  }

  private var showsFAB: Bool {
    tab == .home || tab == .recurring || tab == .budgets
  }

  private var contextualAction: some View {
    Button {
      switch tab {
      case .home: store.openOverlay(.add)
      case .recurring: store.openOverlay(.recurring)
      case .budgets: store.openOverlay(.category)
      default: break
      }
    } label: {
      Image(systemName: "plus")
        .font(.system(size: 18, weight: .semibold))
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .tint(Theme.green)
    .shadow(color: Theme.ink.opacity(0.16), radius: 12, y: 5)
    .accessibilityLabel(fabTitle)
    .id(tab)
  }

  private var fabTitle: String {
    switch tab {
    case .home: return "Add expense"
    case .recurring: return "Add recurring"
    case .budgets: return "Add category"
    default: return "Add"
    }
  }

  private func viewKey(for tab: AppTab) -> ViewKey {
    switch tab {
    case .home: return .home
    case .stats: return .stats
    case .recurring: return .recurring
    case .budgets: return .budgets
    }
  }

  private func tab(for view: ViewKey) -> AppTab? {
    switch view {
    case .home, .tx: return .home
    case .stats: return .stats
    case .recurring: return .recurring
    case .budgets: return .budgets
    case .settings, .account: return nil
    }
  }
}

private enum SettingsRoute: Hashable {
  case settings, account
}

private struct DetailSheetItem: Identifiable {
  let id: String
}

enum OverlayKey: String, Identifiable {
  case add, recurring, category
  var id: String { rawValue }
}
