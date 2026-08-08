package app.dimo.android.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.remember
import app.dimo.android.auth.AuthRedirectBus
import app.dimo.android.notifications.ExpenseReminderRouter
import app.dimo.android.notifications.ExpenseReminderScheduler

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
    // Cold-start notification taps may arrive before AppStore is ready; retry
    // once the session has hydrated.
    if (intent?.hasExtra(app.dimo.android.domain.ExpenseReminderCopy.USER_INFO_TYPE_KEY) == true &&
      ExpenseReminderRouter.store != null
    ) {
      if (ExpenseReminderScheduler.handleNotificationTap(this, intent)) {
        intent.removeExtra(app.dimo.android.domain.ExpenseReminderCopy.USER_INFO_TYPE_KEY)
      }
    }
  }

  private fun handleIntent(intent: Intent?) {
    val uri = intent?.data
    if (uri?.scheme == "dimo" && uri.host == "callback") {
      AuthRedirectBus.publish(uri)
      intent.data = null
      consumedRedirect = true
      return
    }
    ExpenseReminderScheduler.handleNotificationTap(this, intent)
  }
}
