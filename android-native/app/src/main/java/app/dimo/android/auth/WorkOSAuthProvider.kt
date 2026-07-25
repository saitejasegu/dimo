package app.dimo.android.auth

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import app.dimo.android.app.AppConfig
import dev.convex.android.AuthProvider
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json

/**
 * Port of `ios-native/Dimo/Auth/WorkOSAuthProvider.swift`, implementing the
 * Convex Android `AuthProvider` contract.
 *
 * The browser leg uses Custom Tabs instead of `ASWebAuthenticationSession`; the
 * refresh token lives in Keystore-backed storage instead of Keychain. Everything
 * else — PKCE, the `state` round-trip, the reuse of a still-valid cached session
 * on cold start — mirrors the Swift implementation.
 */
class WorkOSAuthProvider(context: Context) : AuthProvider<WorkOSSession> {
  private val appContext = context.applicationContext
  private val store = TokenStore(appContext)
  private val json = Json { ignoreUnknownKeys = true }
  private val lock = Any()

  @Volatile
  private var cached: WorkOSSession? = null

  private var onIdToken: ((String?) -> Unit)? = null

  val currentAccessToken: String? get() = synchronized(lock) { cached?.accessToken }
  val currentSession: WorkOSSession? get() = synchronized(lock) { cached }

  /** Cold-start restore, bounded so a hung network cannot stall the splash. */
  suspend fun restoreSession(): WorkOSSession? = try {
    withTimeout(RESTORE_TIMEOUT_MS) { loginFromCache {}.getOrNull() }
  } catch (_: TimeoutCancellationException) {
    null
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
    val current = synchronized(lock) { cached } ?: throw AuthException.NotAuthenticated
    if (!force && current.expiresAt - System.currentTimeMillis() > EXPIRY_SKEW_MS) {
      return current
    }
    val session = WorkOSAPI.refresh(current.refreshToken, AppConfig.workOSClientID)
    persist(session)
    onIdToken?.invoke(session.accessToken)
    return session
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
    // Reuse a still-valid session from restore/sign-in so Convex auth does not
    // block on a second WorkOS refresh during every cold start.
    val current = synchronized(lock) { cached }
    if (current != null && current.expiresAt - System.currentTimeMillis() > EXPIRY_SKEW_MS) {
      onIdToken(current.accessToken)
      return@runCatching current
    }
    val refresh = store.refreshToken ?: throw AuthException.NotAuthenticated
    val session = WorkOSAPI.refresh(refresh, AppConfig.workOSClientID)
    persist(session)
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
    const val RESTORE_TIMEOUT_MS = 10_000L
    const val EXPIRY_SKEW_MS = 60_000L
  }
}
