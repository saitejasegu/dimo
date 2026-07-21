import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case home, stats, budgets, lending, email

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "Home"
    case .stats: return "Stats"
    case .budgets: return "Budgets"
    case .lending: return "Lending"
    case .email: return "Email"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house.fill"
    case .stats: return "chart.bar.fill"
    case .budgets: return "target"
    case .lending: return "person.2.fill"
    case .email: return "envelope.fill"
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
          case .settings(let initialSection):
            SettingsScreen(store: store, initialSection: initialSection) {
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
          openSettings()
        }
      }
      Tab(AppTab.stats.title, systemImage: AppTab.stats.systemImage, value: .stats) {
        StatsScreen(store: store)
      }
      Tab(AppTab.budgets.title, systemImage: AppTab.budgets.systemImage, value: .budgets) {
        BudgetsScreen(store: store)
      }
      Tab(AppTab.lending.title, systemImage: AppTab.lending.systemImage, value: .lending) {
        LendingScreen(store: store)
      }
      Tab(AppTab.email.title, systemImage: AppTab.email.systemImage, value: .email) {
        EmailScreen(store: store.emailFeatureStore) {
          openSettings(.email)
        }
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
        ExpenseEditorSheet(store: store, mode: .create) {
          openSettings()
        }
      case .recurring:
        if let id = store.recurringDraft.editingId {
          ExpenseEditorSheet(store: store, mode: .recurring(id)) {
            openSettings()
          }
        } else {
          AddRecurringSheet(store: store)
        }
      case .category:
        NewCategorySheet(store: store)
      case .lend:
        AddLendSheet(store: store)
      }
    }
    .sheet(item: Binding(
      get: { store.detailId.map(DetailSheetItem.init) },
      set: { store.detailId = $0?.id }
    )) { item in
      ExpenseEditorSheet(store: store, mode: .transaction(item.id)) {
        openSettings()
      }
    }
    .sheet(item: $store.emailFeatureStore.purchaseReview) { draft in
      ExpenseEditorSheet(store: store, mode: .emailSuggestion(draft.suggestionID)) {
        openSettings()
      }
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
    tab == .home || tab == .budgets || tab == .lending
  }

  private func openSettings(_ section: SettingsSection = .preferences) {
    settingsPath.append(.settings(section))
  }

  private var contextualAction: some View {
    Button {
      switch tab {
      case .home: store.openOverlay(.add)
      case .budgets: store.openOverlay(.category)
      case .lending: store.openOverlay(.lend)
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
    case .budgets: return "Add category"
    case .lending: return "Add lend"
    default: return "Add"
    }
  }

  private func viewKey(for tab: AppTab) -> ViewKey {
    switch tab {
    case .home: return .home
    case .stats: return .stats
    case .budgets: return .budgets
    case .lending: return .lending
    case .email: return .email
    }
  }

  private func tab(for view: ViewKey) -> AppTab? {
    switch view {
    case .home, .tx: return .home
    case .stats: return .stats
    case .recurring: return .home
    case .budgets: return .budgets
    case .lending: return .lending
    case .email: return .email
    case .settings, .account: return nil
    }
  }
}

private enum SettingsRoute: Hashable {
  case settings(SettingsSection), account
}

private struct DetailSheetItem: Identifiable {
  let id: String
}

enum OverlayKey: String, Identifiable {
  case add, recurring, category, lend
  var id: String { rawValue }
}
