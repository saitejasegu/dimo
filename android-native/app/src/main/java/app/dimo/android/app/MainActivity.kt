package app.dimo.android.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.WindowCompat
import app.dimo.android.auth.SessionController

class MainActivity : ComponentActivity() {
  private lateinit var sessionController: SessionController

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    WindowCompat.setDecorFitsSystemWindows(window, false)
    enableEdgeToEdge()
    sessionController = SessionController(applicationContext)
    handleAuthIntent(intent)
    setContent {
      RootView(sessionController)
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    handleAuthIntent(intent)
  }

  private fun handleAuthIntent(intent: Intent?) {
    val data = intent?.data ?: return
    if (data.scheme == "dimo" && data.host == "callback") {
      sessionController.handleRedirect(data)
    }
  }
}
