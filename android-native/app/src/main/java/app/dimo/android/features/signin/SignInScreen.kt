package app.dimo.android.features.signin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.app.LocalAppEnvironment
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import kotlinx.coroutines.launch

/** Port of `ios-native/Dimo/Features/SignIn/SignInScreen.swift`. */
@Composable
fun SignInScreen(modifier: Modifier = Modifier) {
  val environment = LocalAppEnvironment.current
  val scope = rememberCoroutineScope()
  var isSigningIn by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }

  Column(
    modifier = modifier
      .fillMaxSize()
      .background(DimoColors.canvas)
      .padding(horizontal = 24.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
  ) {
    Spacer(modifier = Modifier.weight(1f))
    Box(
      modifier = Modifier
        .size(88.dp)
        .clip(RoundedCornerShape(28.dp))
        .background(DimoColors.green),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        text = "D",
        style = DimoFont.display(44f, FontWeight.Bold),
        color = DimoColors.onGreen,
      )
    }
    Spacer(modifier = Modifier.height(28.dp))
    Column(
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      Text(
        text = "Welcome to Dimo",
        style = DimoFont.display(28f, FontWeight.Bold),
        color = DimoColors.ink,
      )
      Text(
        text = "Track spending with a calm, local-first ledger.",
        style = DimoFont.body(15f),
        color = DimoColors.muted,
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(horizontal = 12.dp),
      )
    }
    if (errorMessage != null) {
      Spacer(modifier = Modifier.height(16.dp))
      Text(
        text = errorMessage.orEmpty(),
        style = DimoFont.body(13f),
        color = DimoColors.danger,
        textAlign = TextAlign.Center,
      )
    }
    Spacer(modifier = Modifier.weight(1f))
    ActionButton(
      title = if (isSigningIn) "Signing in…" else "Continue with Google",
      onClick = {
        if (isSigningIn) return@ActionButton
        scope.launch {
          isSigningIn = true
          errorMessage = null
          try {
            environment.session.signInWithGoogle()
          } catch (error: Exception) {
            if (error.message != "Sign-in cancelled") {
              errorMessage = error.message ?: "Sign-in failed"
            }
          } finally {
            isSigningIn = false
          }
        }
      },
      variant = ActionButtonVariant.Accent,
      enabled = !isSigningIn,
      modifier = Modifier.fillMaxWidth(),
    )
    if (isSigningIn) {
      Spacer(modifier = Modifier.height(12.dp))
      CircularProgressIndicator(
        color = DimoColors.green,
        strokeWidth = 2.dp,
        modifier = Modifier.size(22.dp),
      )
    }
    Spacer(modifier = Modifier.height(40.dp))
  }
}
