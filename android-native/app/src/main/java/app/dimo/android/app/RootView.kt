package app.dimo.android.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.auth.SessionPhase
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.features.home.MainTabShell
import app.dimo.android.features.signin.SignInScreen
import kotlinx.coroutines.launch

val LocalAppEnvironment = staticCompositionLocalOf<AppEnvironment> {
  error("AppEnvironment not provided")
}

/** Port of `ios-native/Dimo/App/RootView.swift`. */
@Composable
fun RootView(
  environment: AppEnvironment,
  modifier: Modifier = Modifier,
) {
  val scope = rememberCoroutineScope()
  CompositionLocalProvider(LocalAppEnvironment provides environment) {
    ProvideDimoTheme(environment) {
      Box(
        modifier = modifier
          .fillMaxSize()
          .background(DimoColors.canvas),
      ) {
        when {
          !AppConfig.isConfigured -> ConfigRequiredView()
          environment.session.phase == SessionPhase.Loading -> LaunchLoadingView()
          environment.session.phase == SessionPhase.SignedOut -> SignInScreen()
          else -> {
            val store = environment.session.appStore
            if (store != null) {
              MainTabShell(
                store = store,
                onSignOut = {
                  scope.launch {
                    try {
                      environment.session.signOut()
                    } catch (error: Throwable) {
                      store.showToast(
                        error.message ?: "Could not remove local account data",
                      )
                    }
                  }
                },
                onDeleteAccount = {
                  scope.launch {
                    try {
                      environment.session.deleteAccount()
                    } catch (error: Throwable) {
                      store.showToast(error.message ?: "Could not delete this account")
                    }
                  }
                },
              )
            } else {
              Box(
                modifier = Modifier
                  .fillMaxSize()
                  .background(DimoColors.canvas),
              )
            }
          }
        }
      }
    }
  }
}

@Composable
private fun LaunchLoadingView() {
  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(DimoColors.canvas),
    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    CircularProgressIndicator(color = DimoColors.green, strokeWidth = 2.dp)
    Text(
      text = "Starting Dimo…",
      style = DimoFont.body(15f),
      color = DimoColors.muted,
    )
  }
}

@Composable
private fun ConfigRequiredView() {
  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(DimoColors.canvas)
      .padding(horizontal = 32.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Text(
      text = "Configuration required",
      style = DimoFont.display(22f, FontWeight.Bold),
      color = DimoColors.ink,
      textAlign = TextAlign.Center,
    )
    Text(
      text = "Set CONVEX_URL and WORKOS_CLIENT_ID in the product flavor BuildConfig fields.",
      style = DimoFont.body(15f),
      color = DimoColors.muted,
      textAlign = TextAlign.Center,
    )
  }
}
