package app.dimo.android.features.home

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.design.DimoFab
import app.dimo.android.design.DimoTheme
import app.dimo.android.design.ToastBanner
import app.dimo.android.features.budgets.BudgetsScreen
import app.dimo.android.features.lending.LendingScreen
import app.dimo.android.features.settings.AccountScreen
import app.dimo.android.features.settings.SettingsScreen
import app.dimo.android.features.sheets.CategoryEditorSheet
import app.dimo.android.features.sheets.ExpenseEditorSheet
import app.dimo.android.features.sheets.LendEditorSheet
import app.dimo.android.features.stats.StatsScreen
import app.dimo.android.store.AppStore
import app.dimo.android.store.AppTab
import app.dimo.android.store.OverlayKey

@Composable
fun MainTabShell(
  store: AppStore,
  onSignOut: () -> Unit = {},
  onDeleteAccount: () -> Unit = {},
) {
  val state by store.state.collectAsStateWithLifecycle()
  val lifecycleOwner = LocalLifecycleOwner.current
  DisposableEffect(lifecycleOwner) {
    val observer = LifecycleEventObserver { _, event ->
      if (event == Lifecycle.Event.ON_RESUME) store.sceneBecameActive()
    }
    lifecycleOwner.lifecycle.addObserver(observer)
    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
  }

  DimoTheme(state.theme) {
    if (state.showAccount) {
      BackHandler { store.openSettings() }
      AccountScreen(
        store = store,
        onBack = { store.openSettings() },
        onSignOut = onSignOut,
        onDeleteAccount = onDeleteAccount,
      )
      return@DimoTheme
    }
    if (state.showSettings) {
      BackHandler { store.closeSettings() }
      SettingsScreen(store = store, onAccount = { store.openAccount() }, onBack = { store.closeSettings() })
      return@DimoTheme
    }

    Scaffold(
      bottomBar = {
        NavigationBar {
          NavigationBarItem(
            selected = state.tab == AppTab.home,
            onClick = { store.selectTab(AppTab.home) },
            icon = { Icon(Icons.Default.Home, contentDescription = "Home") },
            label = { Text("Home") },
          )
          NavigationBarItem(
            selected = state.tab == AppTab.stats,
            onClick = { store.selectTab(AppTab.stats) },
            icon = { Icon(Icons.Default.BarChart, contentDescription = "Stats") },
            label = { Text("Stats") },
          )
          NavigationBarItem(
            selected = state.tab == AppTab.budgets,
            onClick = { store.selectTab(AppTab.budgets) },
            icon = { Icon(Icons.Default.AccountBalanceWallet, contentDescription = "Budgets") },
            label = { Text("Budgets") },
          )
          NavigationBarItem(
            selected = state.tab == AppTab.lending,
            onClick = { store.selectTab(AppTab.lending) },
            icon = { Icon(Icons.Default.People, contentDescription = "Lending") },
            label = { Text("Lending") },
          )
        }
      },
      floatingActionButton = {
        when (state.tab) {
          AppTab.home -> DimoFab(onClick = { store.beginAddExpense() }, contentDescription = "Add expense")
          AppTab.budgets -> DimoFab(onClick = { store.beginAddCategory() }, contentDescription = "Add category")
          AppTab.lending -> DimoFab(onClick = { store.beginAddLend() }, contentDescription = "Add lend")
          AppTab.stats -> Unit
        }
      },
    ) { padding ->
      Box(Modifier.padding(padding).fillMaxSize()) {
        when (state.tab) {
          AppTab.home -> HomeScreen(store)
          AppTab.stats -> StatsScreen(store)
          AppTab.budgets -> BudgetsScreen(store)
          AppTab.lending -> LendingScreen(store)
        }
        state.toast?.let {
          Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp)) {
            ToastBanner(it)
          }
        }
      }
    }

    when (state.overlay) {
      OverlayKey.add -> ExpenseEditorSheet(store)
      OverlayKey.category -> CategoryEditorSheet(store)
      OverlayKey.lend -> LendEditorSheet(store)
      OverlayKey.recurring -> ExpenseEditorSheet(store)
      null -> Unit
    }
  }
}
