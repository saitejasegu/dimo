package app.dimo.android.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Exact hex tokens from `ios-native/Dimo/DesignSystem/Theme.swift`. */

private fun hex(value: Long): Color = Color(value or 0xFF000000L)

@Immutable
data class DimoColorTokens(
  val ink: Color,
  val inkDeep: Color,
  val canvas: Color,
  val canvasDeep: Color,
  val surface: Color,
  val popup: Color,
  val line: Color,
  val lineSoft: Color,
  val hairline: Color,
  val muted: Color,
  val faint: Color,
  val body: Color,
  val green: Color,
  val greenDeep: Color,
  val greenSoft: Color,
  val greenBright: Color,
  val bar: Color,
  val barSoft: Color,
  val warn: Color,
  val danger: Color,
  val dangerSoft: Color,
  val dangerLine: Color,
  val dangerHover: Color,
  val disabled: Color,
  val toggleOff: Color,
  val onGreen: Color,
  val inverse: Color,
  val sideText: Color,
  val sideMuted: Color,
  val sideSub: Color,
)

val LightDimoColors = DimoColorTokens(
  ink = hex(0x14231C),
  inkDeep = hex(0x0D1512),
  canvas = hex(0xF5F8F6),
  canvasDeep = hex(0xEEF2F0),
  surface = hex(0xFFFFFF),
  popup = hex(0xFFFFFF),
  line = hex(0xE4EAE7),
  lineSoft = hex(0xF0F3F1),
  hairline = hex(0xDBE4DF),
  muted = hex(0x7C8A84),
  faint = hex(0xA3AEA8),
  body = hex(0x5F6D67),
  green = hex(0x1F9D63),
  greenDeep = hex(0x1B8B58),
  greenSoft = hex(0xE6F4EC),
  greenBright = hex(0x4FD598),
  bar = hex(0xCFE6D9),
  barSoft = hex(0x9FCEB5),
  warn = hex(0xD97B5A),
  danger = hex(0xC4573C),
  dangerSoft = hex(0xFDF3F0),
  dangerLine = hex(0xF2D9D3),
  dangerHover = hex(0xB04A33),
  disabled = hex(0xC3CDC7),
  toggleOff = hex(0xD7DED9),
  onGreen = hex(0xFFFFFF),
  inverse = hex(0x14231C),
  sideText = hex(0xEAF5EF),
  sideMuted = hex(0x8BA699),
  sideSub = hex(0x7D968A),
)

val DarkDimoColors = DimoColorTokens(
  ink = hex(0xF2F7F4),
  inkDeep = hex(0x0D1512),
  canvas = hex(0x0C1210),
  canvasDeep = hex(0x151E1A),
  surface = hex(0x1A2620),
  popup = hex(0x24332C),
  line = hex(0x51665C),
  lineSoft = hex(0x35453D),
  hairline = hex(0x6A8076),
  muted = hex(0xB4C4BB),
  faint = hex(0x95A69D),
  body = hex(0xD0DBD5),
  green = hex(0x4FD598),
  greenDeep = hex(0x3CC184),
  greenSoft = hex(0x153727),
  greenBright = hex(0x4FD598),
  bar = hex(0x254C39),
  barSoft = hex(0x37684E),
  warn = hex(0xF0A080),
  danger = hex(0xF08B72),
  dangerSoft = hex(0x3A201C),
  dangerLine = hex(0x653329),
  dangerHover = hex(0xFF9B82),
  disabled = hex(0x879990),
  toggleOff = hex(0x39473F),
  onGreen = hex(0x0D1512),
  inverse = hex(0x14231C),
  sideText = hex(0xEAF5EF),
  sideMuted = hex(0x8BA699),
  sideSub = hex(0x7D968A),
)

val LocalDimoColors = staticCompositionLocalOf { LightDimoColors }

/** Theme token accessors, mirroring Swift `Theme.*`. */
object DimoColors {
  val ink: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.ink
  val inkDeep: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.inkDeep
  val canvas: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.canvas
  val canvasDeep: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.canvasDeep
  val surface: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.surface
  val popup: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.popup
  val line: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.line
  val lineSoft: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.lineSoft
  val hairline: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.hairline
  val muted: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.muted
  val faint: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.faint
  val body: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.body
  val green: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.green
  val greenDeep: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.greenDeep
  val greenSoft: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.greenSoft
  val greenBright: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.greenBright
  val bar: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.bar
  val barSoft: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.barSoft
  val warn: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.warn
  val danger: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.danger
  val dangerSoft: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.dangerSoft
  val dangerLine: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.dangerLine
  val dangerHover: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.dangerHover
  val disabled: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.disabled
  val toggleOff: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.toggleOff
  val onGreen: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.onGreen
  val inverse: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.inverse
  val sideText: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.sideText
  val sideMuted: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.sideMuted
  val sideSub: Color @Composable @ReadOnlyComposable get() = LocalDimoColors.current.sideSub
}

private val LightMaterialScheme = lightColorScheme(
  primary = LightDimoColors.green,
  onPrimary = LightDimoColors.onGreen,
  primaryContainer = LightDimoColors.greenSoft,
  onPrimaryContainer = LightDimoColors.greenDeep,
  secondary = LightDimoColors.body,
  onSecondary = LightDimoColors.canvas,
  background = LightDimoColors.canvas,
  onBackground = LightDimoColors.ink,
  surface = LightDimoColors.surface,
  onSurface = LightDimoColors.ink,
  surfaceVariant = LightDimoColors.canvasDeep,
  onSurfaceVariant = LightDimoColors.muted,
  outline = LightDimoColors.line,
  error = LightDimoColors.danger,
  onError = LightDimoColors.onGreen,
  errorContainer = LightDimoColors.dangerSoft,
  onErrorContainer = LightDimoColors.danger,
)

private val DarkMaterialScheme = darkColorScheme(
  primary = DarkDimoColors.green,
  onPrimary = DarkDimoColors.onGreen,
  primaryContainer = DarkDimoColors.greenSoft,
  onPrimaryContainer = DarkDimoColors.greenDeep,
  secondary = DarkDimoColors.body,
  onSecondary = DarkDimoColors.canvas,
  background = DarkDimoColors.canvas,
  onBackground = DarkDimoColors.ink,
  surface = DarkDimoColors.surface,
  onSurface = DarkDimoColors.ink,
  surfaceVariant = DarkDimoColors.canvasDeep,
  onSurfaceVariant = DarkDimoColors.muted,
  outline = DarkDimoColors.line,
  error = DarkDimoColors.danger,
  onError = DarkDimoColors.onGreen,
  errorContainer = DarkDimoColors.dangerSoft,
  onErrorContainer = DarkDimoColors.danger,
)

@Composable
fun DimoTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  val tokens = if (darkTheme) DarkDimoColors else LightDimoColors
  val scheme = if (darkTheme) DarkMaterialScheme else LightMaterialScheme
  CompositionLocalProvider(LocalDimoColors provides tokens) {
    MaterialTheme(
      colorScheme = scheme,
      typography = DimoTypography,
      content = content,
    )
  }
}
