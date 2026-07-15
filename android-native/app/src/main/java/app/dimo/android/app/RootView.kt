package app.dimo.android.app

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.auth.SessionController
import app.dimo.android.auth.SessionPhase
import app.dimo.android.design.DimoColors
import app.dimo.android.features.home.MainTabShell
import app.dimo.android.features.signin.SignInScreen

@Composable
fun RootView(sessionController: SessionController) {
  val phase by sessionController.phase.collectAsStateWithLifecycle()
  val context = LocalContext.current

  when (val current = phase) {
    SessionPhase.Loading -> {
      Box(
        Modifier.fillMaxSize().background(DimoColors.canvasLight),
        contentAlignment = Alignment.Center,
      ) {}
    }
    SessionPhase.SignedOut -> {
      if (!AppConfig.isConfigured) {
        Box(
          Modifier
            .fillMaxSize()
            .background(DimoColors.canvasLight)
            .padding(24.dp),
          contentAlignment = Alignment.Center,
        ) {
          Text("Missing CONVEX_URL or WORKOS_CLIENT_ID configuration.")
        }
      } else {
        SignInScreen(
          onSignIn = {
            val url = sessionController.beginSignIn()
            CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url))
          },
        )
      }
    }
    is SessionPhase.SignedIn -> {
      MainTabShell(
        store = current.store,
        onSignOut = { sessionController.signOut() },
        onDeleteAccount = { sessionController.deleteAccount() },
      )
    }
  }
}
