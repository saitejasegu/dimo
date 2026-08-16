package app.dimo.android.auth

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import app.dimo.android.app.AppConfig
import dev.convex.android.AuthProvider
import kotlin.math.min
import kotlin.math.pow
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * Port of `ios-native/Dimo/Auth/WorkOSAuthProvider.swift`, implementing the
 * Convex Android `AuthProvider` contract.
 *
 * Session resilience: transient refresh failures are retried and never clear
 * the stored refresh token; only terminal `invalid_grant` signs the user out.
 */
class WorkOSAuthProvider(context: Context) : AuthProvider<WorkOSSession> {
  private val appContext = context.applicationContext
  private val store = TokenStore(appContext)
  private val json = Json { ignoreUnknownKeys = true }
  private val lock = Any()
  private val refreshMutex = Mutex()

  @Volatile
  private var cached: WorkOSSession? = null

  private var onIdToken: ((String?) -> Unit)? = null

  val currentAccessToken: String? get() = synchronized(lock) { cached?.accessToken }
  val currentSession: WorkOSSession? get() = synchronized(lock) { cached }
  val hasPersistedRefreshToken: Boolean get() = store.refreshToken != null

  /**
   * Cold-start restore. Retries transient failures; clears storage only on a
   * terminal WorkOS session end.
   */
  suspend fun restoreSession(): WorkOSSession? {
    if (!hasPersistedRefreshToken) return null
    repeat(5) { attempt ->
      try {
        return loginFromCache {}.getOrThrow()
      } catch (error: AuthException) {
        if (error.isTerminalRefresh) {
          clearPersisted()
          return null
        }
        delay((min(8.0, 2.0.pow(attempt.toDouble())) * 1000).toLong())
      } catch (_: Throwable) {
        delay((min(8.0, 2.0.pow(attempt.toDouble())) * 1000).toLong())
      }
    }
    // Keep the refresh token so a later launch can succeed.
    return null
  }

  suspend fun signIn(provider: String = "GoogleOAuth"): WorkOSSession =
    performSignIn(appContext, provider)

  suspend fun signOut() {
    clearPersisted()
    onIdToken = null
  }

  /**
   * Returns a valid session, refreshing when the access token is within a minute
   * of expiry. [force] refreshes unconditionally.
   */
  suspend fun refreshIfNeeded(force: Boolean = false): WorkOSSession {
    val current = synchronized(lock) { cached }
    if (!force && current != null && current.expiresAt - System.currentTimeMillis() > EXPIRY_SKEW_MS) {
      return current
    }
    return refreshSingleFlight()
  }

  // MARK: AuthProvider

  override suspend fun login(
    context: Context,
    onIdToken: (String?) -> Unit,
  ): Result<WorkOSSession> = runCatching {
    this.onIdToken = onIdToken
    val session = performSignIn(context, "GoogleOAuth")
    onIdToken(session.accessToken)
    session
  }

  override suspend fun loginFromCache(
    onIdToken: (String?) -> Unit,
  ): Result<WorkOSSession> = runCatching {
    this.onIdToken = onIdToken
    val current = synchronized(lock) { cached }
    if (current != null && current.expiresAt - System.currentTimeMillis() > EXPIRY_SKEW_MS) {
      onIdToken(current.accessToken)
      return@runCatching current
    }
    val session = refreshSingleFlight()
    onIdToken(session.accessToken)
    session
  }

  override suspend fun logout(context: Context): Result<Void?> = runCatching {
    clearPersisted()
    onIdToken = null
    null
  }

  override fun extractIdToken(authResult: WorkOSSession): String = authResult.accessToken

  // MARK: Private

  private suspend fun refreshSingleFlight(): WorkOSSession = refreshMutex.withLock {
    val current = synchronized(lock) { cached }
    if (current != null && current.expiresAt - System.currentTimeMillis() > EXPIRY_SKEW_MS) {
      return current
    }
    val refreshToken = synchronized(lock) { cached?.refreshToken } ?: store.refreshToken
      ?: throw AuthException.NotAuthenticated
    try {
      val session = WorkOSAPI.refresh(refreshToken, AppConfig.workOSClientID)
      persist(session)
      onIdToken?.invoke(session.accessToken)
      session
    } catch (error: AuthException) {
      if (error.isTerminalRefresh) clearPersisted()
      throw error
    }
  }

  private suspend fun performSignIn(context: Context, provider: String): WorkOSSession {
    val verifier = PKCE.makeVerifier()
    val challenge = PKCE.challenge(verifier)
    val state = PKCE.makeState()
    val url = WorkOSAPI.authorizationURL(
      clientId = AppConfig.workOSClientID,
      redirectURI = AppConfig.workOSRedirectURI,
      state = state,
      codeChallenge = challenge,
      provider = provider,
    )

    val redirect = AuthRedirectBus.expectRedirect()
    launchCustomTab(context, url)
    val callback: Uri = redirect.await()

    if (callback.getQueryParameter("state") != state) throw AuthException.StateMismatch
    val code = callback.getQueryParameter("code") ?: throw AuthException.MissingCode

    val session = WorkOSAPI.exchangeCode(
      code = code,
      codeVerifier = verifier,
      clientId = AppConfig.workOSClientID,
      redirectURI = AppConfig.workOSRedirectURI,
    )
    persist(session)
    return session
  }

  private fun launchCustomTab(context: Context, url: Uri) {
    val intent = CustomTabsIntent.Builder()
      .setShowTitle(false)
      .setUrlBarHidingEnabled(true)
      .build()
    intent.intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
    intent.launchUrl(context, url)
  }

  private fun persist(session: WorkOSSession) {
    store.refreshToken = session.refreshToken
    store.userJson = json.encodeToString(WorkOSUser.serializer(), session.user)
    synchronized(lock) { cached = session }
  }

  private fun clearPersisted() {
    store.clear()
    synchronized(lock) { cached = null }
  }

  private companion object {
    const val EXPIRY_SKEW_MS = 60_000L
  }
}
