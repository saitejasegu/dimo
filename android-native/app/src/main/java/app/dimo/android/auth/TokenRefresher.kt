package app.dimo.android.auth

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max

/**
 * Port of `ios-native/Dimo/Auth/TokenRefresher.swift`.
 *
 * Keeps the access token warm by refreshing a minute before expiry. Transient
 * failures back off for 30s; terminal failures invoke [onTerminalFailure].
 */
class TokenRefresher(
  private val authProvider: WorkOSAuthProvider,
  private val scope: CoroutineScope,
) {
  private var job: Job? = null
  var onTerminalFailure: (() -> Unit)? = null

  fun start() {
    stop()
    job = scope.launch {
      while (isActive) {
        try {
          val session = authProvider.refreshIfNeeded(force = false)
          val delayMs = max(5_000L, session.expiresAt - System.currentTimeMillis() - 60_000L)
          delay(delayMs)
        } catch (error: AuthException) {
          if (error.isTerminalRefresh) {
            onTerminalFailure?.invoke()
            return@launch
          }
          delay(30_000L)
        } catch (_: Exception) {
          delay(30_000L)
        }
      }
    }
  }

  fun stop() {
    job?.cancel()
    job = null
  }
}
