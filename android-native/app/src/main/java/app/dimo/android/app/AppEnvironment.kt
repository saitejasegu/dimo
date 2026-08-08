package app.dimo.android.app

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.dimo.android.auth.SessionController
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.design.DimoTheme
import app.dimo.android.domain.OnboardingStore

/**
 * Port of `ios-native/Dimo/App/AppEnvironment.swift`.
 *
 * Holds the session controller, onboarding completion gate, and the dark-theme
 * override driven by the synced theme preference (`null` follows the system).
 */
class AppEnvironment(context: Context) {
  private val appContext = context.applicationContext
  val session = SessionController(appContext)

  /** `true` → dark, `false` → light, `null` → follow system. */
  var preferredDarkTheme by mutableStateOf<Boolean?>(null)
    private set

  var onboardingCompleted by mutableStateOf(OnboardingStore.hasCompleted(appContext))
    private set

  fun completeOnboarding() {
    OnboardingStore.markCompleted(appContext)
    onboardingCompleted = true
  }

  fun applyTheme(preference: ThemePreference) {
    preferredDarkTheme = when (preference) {
      ThemePreference.SYSTEM -> null
      ThemePreference.LIGHT -> false
      ThemePreference.DARK -> true
    }
  }
}

@Composable
fun AppEnvironment.resolvedDarkTheme(): Boolean =
  preferredDarkTheme ?: isSystemInDarkTheme()

@Composable
fun ProvideDimoTheme(
  environment: AppEnvironment,
  content: @Composable () -> Unit,
) {
  DimoTheme(darkTheme = environment.resolvedDarkTheme(), content = content)
}
