package app.dimo.android.design

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.dimo.android.R

/** Port of `ios-native/Dimo/DesignSystem/Fonts.swift`. */

private val SpaceGrotesk = FontFamily(
  Font(R.font.space_grotesk_medium, FontWeight.Medium),
  Font(R.font.space_grotesk_semibold, FontWeight.SemiBold),
  Font(R.font.space_grotesk_bold, FontWeight.Bold),
)

private val IbmPlexSans = FontFamily(
  Font(R.font.ibm_plex_sans_regular, FontWeight.Normal),
  Font(R.font.ibm_plex_sans_medium, FontWeight.Medium),
  Font(R.font.ibm_plex_sans_semibold, FontWeight.SemiBold),
)

object DimoFont {
  fun display(size: Float, weight: FontWeight = FontWeight.Bold): TextStyle =
    TextStyle(
      fontFamily = SpaceGrotesk,
      fontWeight = when {
        weight.weight >= FontWeight.Bold.weight -> FontWeight.Bold
        weight.weight >= FontWeight.SemiBold.weight -> FontWeight.SemiBold
        else -> FontWeight.Medium
      },
      fontSize = size.sp,
    )

  fun body(size: Float, weight: FontWeight = FontWeight.Normal): TextStyle =
    TextStyle(
      fontFamily = IbmPlexSans,
      fontWeight = when {
        weight.weight >= FontWeight.SemiBold.weight -> FontWeight.SemiBold
        weight.weight >= FontWeight.Medium.weight -> FontWeight.Medium
        else -> FontWeight.Normal
      },
      fontSize = size.sp,
    )
}

val DimoTypography = Typography(
  displayLarge = TextStyle(
    fontFamily = SpaceGrotesk,
    fontWeight = FontWeight.Bold,
    fontSize = 32.sp,
  ),
  headlineMedium = TextStyle(
    fontFamily = SpaceGrotesk,
    fontWeight = FontWeight.Bold,
    fontSize = 22.sp,
  ),
  titleLarge = TextStyle(
    fontFamily = SpaceGrotesk,
    fontWeight = FontWeight.SemiBold,
    fontSize = 18.sp,
  ),
  bodyLarge = TextStyle(
    fontFamily = IbmPlexSans,
    fontWeight = FontWeight.Normal,
    fontSize = 16.sp,
  ),
  bodyMedium = TextStyle(
    fontFamily = IbmPlexSans,
    fontWeight = FontWeight.Normal,
    fontSize = 15.sp,
  ),
  bodySmall = TextStyle(
    fontFamily = IbmPlexSans,
    fontWeight = FontWeight.Normal,
    fontSize = 13.sp,
  ),
  labelLarge = TextStyle(
    fontFamily = IbmPlexSans,
    fontWeight = FontWeight.SemiBold,
    fontSize = 15.sp,
  ),
  labelMedium = TextStyle(
    fontFamily = IbmPlexSans,
    fontWeight = FontWeight.Medium,
    fontSize = 13.sp,
  ),
)
