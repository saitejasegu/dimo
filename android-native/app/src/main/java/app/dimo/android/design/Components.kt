package app.dimo.android.design

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun DimoFab(onClick: () -> Unit, contentDescription: String) {
  FloatingActionButton(
    onClick = onClick,
    containerColor = DimoColors.green,
    contentColor = Color.White,
  ) {
    Icon(Icons.Default.Add, contentDescription = contentDescription)
  }
}

@Composable
fun ProgressBar(progress: Float, modifier: Modifier = Modifier, over: Boolean = false) {
  val clamped = progress.coerceIn(0f, 1f)
  Box(
    modifier
      .fillMaxWidth()
      .height(8.dp)
      .clip(RoundedCornerShape(999.dp))
      .background(MaterialTheme.colorScheme.secondary),
  ) {
    Box(
      Box.Modifier
        .fillMaxWidth(clamped)
        .height(8.dp)
        .background(if (over) Color(0xFFB42318) else DimoColors.green),
    )
  }
}

// helper to silence Box.modifier typo — use Modifier.align pattern via fill
private val Box.modifier get() = Modifier

@Composable
fun Chip(label: String, selected: Boolean, onClick: () -> Unit) {
  Surface(
    onClick = onClick,
    shape = RoundedCornerShape(999.dp),
    color = if (selected) DimoColors.green else MaterialTheme.colorScheme.surface,
    contentColor = if (selected) Color.White else MaterialTheme.colorScheme.onSurface,
  ) {
    Text(label, modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp))
  }
}

@Composable
fun ActionButton(label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
  Button(
    onClick = onClick,
    modifier = modifier.fillMaxWidth(),
    colors = ButtonDefaults.buttonColors(containerColor = DimoColors.green),
    contentPadding = PaddingValues(vertical = 14.dp),
    shape = RoundedCornerShape(16.dp),
  ) {
    Text(label)
  }
}

@Composable
fun Avatar(initials: String, modifier: Modifier = Modifier) {
  Box(
    modifier
      .size(40.dp)
      .clip(CircleShape)
      .background(DimoColors.greenSoft),
    contentAlignment = Alignment.Center,
  ) {
    Text(initials.take(2).uppercase(), color = DimoColors.green)
  }
}

@Composable
fun ToastBanner(message: String) {
  Surface(
    color = DimoColors.hero,
    contentColor = Color.White,
    shape = RoundedCornerShape(14.dp),
    shadowElevation = 4.dp,
  ) {
    Text(message, modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
  }
}
