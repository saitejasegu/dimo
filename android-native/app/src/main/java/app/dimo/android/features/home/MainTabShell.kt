package app.dimo.android.features.home

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.dimo.android.app.LocalAppEnvironment
import app.dimo.android.data.model.ViewKey
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.FabButton
import app.dimo.android.design.ToastOverlay
import app.dimo.android.features.budgets.BudgetsScreen
import app.dimo.android.features.lending.LendingScreen
import app.dimo.android.features.recurring.RecurringScreen
import app.dimo.android.features.settings.AccountScreen
import app.dimo.android.features.settings.PaymentMethodsScreen
import app.dimo.android.features.settings.SettingsScreen
import app.dimo.android.features.sheets.CategorySheet
import app.dimo.android.features.sheets.ExpenseEditorMode
import app.dimo.android.features.sheets.ExpenseEditorSheet
import app.dimo.android.features.sheets.LendSheet
import app.dimo.android.features.sheets.RecurringSheet
import app.dimo.android.features.stats.StatsScreen
import app.dimo.android.store.AppStore
import app.dimo.android.store.OverlayKey

enum class AppTab(val title: String, val icon: ImageVector, val view: ViewKey) {
  Home("Home", Icons.Filled.Home, ViewKey.HOME),
  Stats("Stats", Icons.Filled.BarChart, ViewKey.STATS),
  Budgets("Budgets", Icons.Filled.TrackChanges, ViewKey.BUDGETS),
  Lending("Lending", Icons.Filled.People, ViewKey.LENDING),
  ;

  companion object {
    fun forView(view: ViewKey): AppTab? = entries.firstOrNull { it.view == view }
  }
}

/** Routes pushed on top of the tab surface; `store.view` owns Settings/Account. */
private enum class PushedRoute { Recurring, PaymentMethods }

/**
 * Four-tab shell (no Email tab on Android). Port of
 * `ios-native/Dimo/Features/Home/MainTabShell.swift`.
 *
 * `store.view` stays the source of truth for the tab selection and for the
 * Settings/Account destinations, so a deep link or a store-driven navigation
 * moves the UI. Recurring and Payment methods are local pushes because
 * `AppStore.setView` folds `RECURRING` back into `HOME`.
 */
@Composable
fun MainTabShell(
  store: AppStore,
  onSignOut: () -> Unit,
  onDeleteAccount: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val environment = LocalAppEnvironment.current
  val lifecycleOwner = LocalLifecycleOwner.current
  var tab by remember { mutableStateOf(AppTab.forView(store.view) ?: AppTab.Home) }
  var pushed by remember { mutableStateOf<PushedRoute?>(null) }

  DisposableEffect(lifecycleOwner, store) {
    val observer = LifecycleEventObserver { _, event ->
      if (event == Lifecycle.Event.ON_RESUME) {
        store.sceneBecameActive()
      }
    }
    lifecycleOwner.lifecycle.addObserver(observer)
    onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
  }

  // Keep the theme in step with the synced preference, including remote changes.
  LaunchedEffect(store.theme) { environment.applyTheme(store.theme) }

  LaunchedEffect(store.view) {
    AppTab.forView(store.view)?.let { next ->
      tab = next
      pushed = null
    }
  }

  val onSettings = store.view == ViewKey.SETTINGS
  val onAccount = store.view == ViewKey.ACCOUNT
  val fullScreen = onSettings || onAccount || pushed != null
  val showsFab = !fullScreen &&
    (tab == AppTab.Home || tab == AppTab.Budgets || tab == AppTab.Lending)

  BackHandler(enabled = fullScreen) {
    when {
      onAccount -> store.closeAccount()
      onSettings -> store.setView(ViewKey.HOME)
      else -> pushed = null
    }
  }

  Scaffold(
    modifier = modifier.fillMaxSize(),
    containerColor = DimoColors.canvas,
    contentWindowInsets = WindowInsets(0, 0, 0, 0),
    bottomBar = {
      AnimatedVisibility(visible = !fullScreen, enter = fadeIn(), exit = fadeOut()) {
        NavigationBar(
          containerColor = DimoColors.surface,
          contentColor = DimoColors.ink,
        ) {
          AppTab.entries.forEach { destination ->
            NavigationBarItem(
              selected = tab == destination,
              onClick = {
                pushed = null
                store.setView(destination.view)
                tab = destination
              },
              icon = { Icon(destination.icon, contentDescription = destination.title) },
              label = {
                Text(
                  text = destination.title,
                  style = DimoFont.body(11f, FontWeight.Medium),
                )
              },
              colors = NavigationBarItemDefaults.colors(
                selectedIconColor = DimoColors.green,
                selectedTextColor = DimoColors.green,
                unselectedIconColor = DimoColors.muted,
                unselectedTextColor = DimoColors.muted,
                indicatorColor = DimoColors.greenSoft,
              ),
            )
          }
        }
      }
    },
  ) { padding ->
    Box(
      modifier = Modifier
        .fillMaxSize()
        .padding(padding),
    ) {
      when {
        onAccount -> AccountScreen(
          store = store,
          onBack = { store.closeAccount() },
          onSignOut = onSignOut,
          onDeleteAccount = onDeleteAccount,
        )

        onSettings -> SettingsScreen(
          store = store,
          onBack = { store.setView(ViewKey.HOME) },
          onOpenAccount = { store.openAccount() },
          onApplyTheme = { environment.applyTheme(it) },
        )

        pushed == PushedRoute.PaymentMethods -> PaymentMethodsScreen(
          store = store,
          onBack = { pushed = null },
        )

        pushed == PushedRoute.Recurring -> RecurringScreen(
          store = store,
          onBack = { pushed = null },
        )

        else -> when (tab) {
          AppTab.Home -> HomeScreen(
            store = store,
            onOpenSettings = { store.setView(ViewKey.SETTINGS) },
            onOpenRecurring = { pushed = PushedRoute.Recurring },
          )
          AppTab.Stats -> StatsScreen(store = store)
          AppTab.Budgets -> BudgetsScreen(store = store)
          AppTab.Lending -> LendingScreen(store = store)
        }
      }

      ToastOverlay(
        message = store.toast,
        modifier = Modifier.align(Alignment.TopCenter),
      )

      if (showsFab) {
        FabButton(
          onClick = {
            when (tab) {
              AppTab.Home -> store.openOverlay(OverlayKey.Add)
              AppTab.Budgets -> store.openOverlay(OverlayKey.Category)
              AppTab.Lending -> store.openOverlay(OverlayKey.Lend)
              else -> Unit
            }
          },
          contentDescription = when (tab) {
            AppTab.Home -> "Add expense"
            AppTab.Budgets -> "Add category"
            AppTab.Lending -> "Add lend"
            else -> "Add"
          },
          modifier = Modifier
            .align(Alignment.BottomEnd)
            .navigationBarsPadding()
            .padding(end = 22.dp, bottom = 16.dp),
        )
      }
    }
  }

  val manageMethods: () -> Unit = {
    store.closeOverlay()
    store.closeDetail()
    pushed = PushedRoute.PaymentMethods
  }

  when (store.overlay) {
    OverlayKey.Add -> ExpenseEditorSheet(
      store = store,
      mode = ExpenseEditorMode.Add,
      onClose = { store.closeOverlay() },
      onManagePaymentMethods = manageMethods,
    )
    OverlayKey.Recurring -> RecurringSheet(store = store, onClose = { store.closeOverlay() })
    OverlayKey.Category -> CategorySheet(store = store, onClose = { store.closeOverlay() })
    OverlayKey.Lend -> LendSheet(store = store, onClose = { store.closeOverlay() })
    null -> Unit
  }

  // Tapping a transaction row edits it in the same sheet as the add flow.
  store.detailId?.let { id ->
    if (store.overlay == null) {
      ExpenseEditorSheet(
        store = store,
        mode = ExpenseEditorMode.Detail,
        onClose = { store.closeDetail() },
        transactionId = id,
        onManagePaymentMethods = manageMethods,
      )
    }
  }
}
