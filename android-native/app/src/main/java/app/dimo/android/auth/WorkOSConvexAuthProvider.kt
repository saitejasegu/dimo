package app.dimo.android.auth

import android.content.Context
import dev.convex.android.AuthProvider

/**
 * Bridges WorkOS access tokens into ConvexClientWithAuth.
 * Matches iOS: extractIdToken returns the WorkOS access token.
 */
class WorkOSConvexAuthProvider(
  private val getSession: suspend (force: Boolean) -> WorkOSSession,
  private val clearSession: suspend () -> Unit,
) : AuthProvider<WorkOSSession> {
  private var onIdToken: ((String?) -> Unit)? = null

  override suspend fun login(context: Context, onIdToken: (String?) -> Unit): Result<WorkOSSession> {
    this.onIdToken = onIdToken
    return runCatching {
      val session = getSession(false)
      onIdToken(session.accessToken)
      session
    }
  }

  override suspend fun loginFromCache(onIdToken: (String?) -> Unit): Result<WorkOSSession> {
    this.onIdToken = onIdToken
    return runCatching {
      val session = getSession(false)
      onIdToken(session.accessToken)
      session
    }
  }

  override suspend fun logout(context: Context): Result<Void?> = runCatching {
    onIdToken?.invoke(null)
    clearSession()
    null
  }

  override fun extractIdToken(authResult: WorkOSSession): String = authResult.accessToken

  fun publishToken(accessToken: String?) {
    onIdToken?.invoke(accessToken)
  }
}
