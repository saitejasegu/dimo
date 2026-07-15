package app.dimo.android.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.view.WindowCompat
import app.dimo.android.auth.SessionController
import app.dimo.android.design.DimoColors

class MainActivity : ComponentActivity() {
  private var sessionController by mutableStateOf<SessionController?>(null)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    WindowCompat.setDecorFitsSystemWindows(window, false)
    enableEdgeToEdge()

    // Paint first frame before constructing SessionController so Keystore /
    // EncryptedSharedPreferences work cannot ANR cold start on slow emulators.
    setContent {
      val controller = sessionController
      if (controller == null) {
        Box(Modifier.fillMaxSize().background(DimoColors.canvasLight))
      } else {
        RootView(controller)
      }
    }

    window.decorView.post {
      val controller = SessionController(applicationContext)
      sessionController = controller
      handleAuthIntent(intent)
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
      sessionController?.handleRedirect(data)
    }
  }
}
