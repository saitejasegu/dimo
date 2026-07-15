package app.dimo.android.features.signin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.dimo.android.design.ActionButton
import app.dimo.android.design.DimoColors

@Composable
fun SignInScreen(onSignIn: () -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(DimoColors.canvasLight)
      .padding(28.dp),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.Start,
  ) {
    Text("Dimo", style = MaterialTheme.typography.displayLarge, color = DimoColors.green)
    Spacer(Modifier.height(12.dp))
    Text(
      "Local-first spending tracker that syncs when you’re ready.",
      style = MaterialTheme.typography.bodyLarge,
      color = DimoColors.mutedLight,
    )
    Spacer(Modifier.height(36.dp))
    ActionButton("Continue with Google", onClick = onSignIn)
  }
}
