import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
  case home, stats, recurring, budgets, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "Home"
    case .stats: return "Stats"
    case .recurring: return "Recurring"
    case .budgets: return "Budgets"
    case .settings: return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house.fill"
    case .stats: return "chart.bar.fill"
    case .recurring: return "arrow.2.circlepath"
    case .budgets: return "target"
    case .settings: return "gearshape.fill"
    }
  }
}

struct MainTabShell: View {
  @Bindable var store: AppStore
  @Environment(\.scenePhase) private var scenePhase
  @State private var tab: AppTab = .home

  var body: some View {
    TabView(selection: $tab) {
      Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: .home) {
        HomeScreen(store: store)
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
      Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
        SettingsScreen(store: store)
      }
    }
    .tint(Theme.green)
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      if showsFAB {
        fabAccessory
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
    .fullScreenCover(isPresented: Binding(
      get: { store.view == .account },
      set: { if !$0 { store.closeAccount() } }
    )) {
      AccountScreen(store: store)
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

  private var fabAccessory: some View {
    Button {
      switch tab {
      case .home: store.openOverlay(.add)
      case .recurring: store.openOverlay(.recurring)
      case .budgets: store.openOverlay(.category)
      default: break
      }
    } label: {
      Label(fabTitle, systemImage: "plus")
        .font(DimoFont.body(15, weight: .semibold))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(Theme.green)
  }

  private var fabTitle: String {
    switch tab {
    case .home: return "Add expense"
    case .recurring: return "Add recurring"
    case .budgets: return "New category"
    default: return "Add"
    }
  }

  private func viewKey(for tab: AppTab) -> ViewKey {
    switch tab {
    case .home: return .home
    case .stats: return .stats
    case .recurring: return .recurring
    case .budgets: return .budgets
    case .settings: return .settings
    }
  }

  private func tab(for view: ViewKey) -> AppTab? {
    switch view {
    case .home, .tx: return .home
    case .stats: return .stats
    case .recurring: return .recurring
    case .budgets: return .budgets
    case .settings: return .settings
    case .account: return nil
    }
  }
}

private struct DetailSheetItem: Identifiable {
  let id: String
}

enum OverlayKey: String, Identifiable {
  case add, recurring, category
  var id: String { rawValue }
}
