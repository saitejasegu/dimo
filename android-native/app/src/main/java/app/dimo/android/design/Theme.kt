package app.dimo.android.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.sp
import app.dimo.android.data.model.ThemePreference

object DimoColors {
  val green = Color(0xFF2F6B4F)
  val greenSoft = Color(0xFFDCECE3)
  val canvasLight = Color(0xFFF5F8F6)
  val canvasDark = Color(0xFF0C1210)
  val inkLight = Color(0xFF14231C)
  val inkDark = Color(0xFFE8F0EB)
  val hero = Color(0xFF14231C)
  val surfaceLight = Color(0xFFFFFFFF)
  val surfaceDark = Color(0xFF152019)
  val mutedLight = Color(0xFF5F7268)
  val mutedDark = Color(0xFF9BB0A4)
}

@Composable
fun DimoTheme(preference: ThemePreference, content: @Composable () -> Unit) {
  val dark = when (preference) {
    ThemePreference.dark -> true
    ThemePreference.light -> false
    ThemePreference.system -> isSystemInDarkTheme()
  }
  val colors = if (dark) {
    darkColorScheme(
      primary = DimoColors.green,
      onPrimary = Color.White,
      background = DimoColors.canvasDark,
      onBackground = DimoColors.inkDark,
      surface = DimoColors.surfaceDark,
      onSurface = DimoColors.inkDark,
      secondary = DimoColors.greenSoft,
    )
  } else {
    lightColorScheme(
      primary = DimoColors.green,
      onPrimary = Color.White,
      background = DimoColors.canvasLight,
      onBackground = DimoColors.inkLight,
      surface = DimoColors.surfaceLight,
      onSurface = DimoColors.inkLight,
      secondary = DimoColors.greenSoft,
    )
  }
  MaterialTheme(colorScheme = colors, typography = dimoTypography(), content = content)
}

@Composable
private fun dimoTypography() = androidx.compose.material3.Typography(
  displayLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Bold, fontSize = 34.sp),
  titleLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 22.sp),
  titleMedium = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 18.sp),
  bodyLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Normal, fontSize = 16.sp),
  bodyMedium = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Normal, fontSize = 14.sp),
  labelLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Medium, fontSize = 14.sp),
)
