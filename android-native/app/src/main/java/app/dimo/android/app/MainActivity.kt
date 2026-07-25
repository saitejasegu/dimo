package app.dimo.android.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.remember
import app.dimo.android.auth.AuthRedirectBus

class MainActivity : ComponentActivity() {
  /** Set when `dimo://callback` was delivered this resume cycle. */
  private var consumedRedirect = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    handleIntent(intent)
    enableEdgeToEdge()
    setContent {
      val environment = remember { AppEnvironment(applicationContext) }
      RootView(environment = environment)
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleIntent(intent)
  }

  override fun onResume() {
    super.onResume()
    // Custom Tab dismissed without a redirect: cancel the parked sign-in.
    // A successful callback sets [consumedRedirect] via [handleIntent] first
    // (often from onNewIntent before onResume).
    if (AuthRedirectBus.hasPending() && !consumedRedirect) {
      AuthRedirectBus.cancelPending()
    }
    consumedRedirect = false
  }

  private fun handleIntent(intent: Intent?) {
    val uri = intent?.data ?: return
    if (uri.scheme == "dimo" && uri.host == "callback") {
      AuthRedirectBus.publish(uri)
      intent.data = null
      consumedRedirect = true
    }
  }
}
