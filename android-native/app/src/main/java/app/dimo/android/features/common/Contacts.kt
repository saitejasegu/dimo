package app.dimo.android.features.common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont

/** Contact avatar: the contact's initials on a tinted tile. */
@Composable
fun ContactAvatar(
  name: String,
  modifier: Modifier = Modifier,
  size: Dp = 40.dp,
  radius: Dp = 13.dp,
  fontSize: Float = 16f,
  monogram: String? = null,
) {
  Box(
    modifier = modifier
      .size(size)
      .clip(RoundedCornerShape(radius))
      .background(DimoColors.greenSoft),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = monogram ?: name.trim().firstOrNull()?.uppercaseChar()?.toString().orEmpty(),
      style = DimoFont.display(fontSize, FontWeight.SemiBold),
      color = DimoColors.green,
    )
  }
}
