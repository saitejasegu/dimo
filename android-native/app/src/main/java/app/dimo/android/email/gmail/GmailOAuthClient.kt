package app.dimo.android.email.gmail

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import app.dimo.android.app.AppConfig
import app.dimo.android.auth.PKCE
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Port of `ios-native/Dimo/Email/Gmail/GmailOAuthClient.swift`.
 *
 * Gmail has its own installed-app OAuth flow and never uses the WorkOS token. The
 * browser leg is a Custom Tab instead of `ASWebAuthenticationSession`; PKCE, the
 * `state` round-trip and the subject check on reconnect are identical.
 */
object GmailOAuthConfigurationDefaults {
  const val AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
  const val TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
  const val REVOCATION_ENDPOINT = "https://oauth2.googleapis.com/revoke"
  const val USER_INFO_ENDPOINT = "https://openidconnect.googleapis.com/v1/userinfo"
  const val READ_ONLY_SCOPE = "https://www.googleapis.com/auth/gmail.readonly"
}

data class GmailOAuthConfiguration(
  val clientId: String,
  val redirectScheme: String,
  val redirectUri: String = "$redirectScheme:/oauthredirect",
) {
  companion object {
    fun fromAppConfig(): GmailOAuthConfiguration {
      if (!AppConfig.isGmailConfigured) throw GmailOAuthException.NotConfigured
      return GmailOAuthConfiguration(
        clientId = AppConfig.gmailOAuthClientID,
        redirectScheme = AppConfig.gmailOAuthRedirectScheme,
        redirectUri = AppConfig.gmailOAuthRedirectURI,
      )
    }
  }
}

data class GmailAccessToken(val value: String, val expiresAt: Long)

interface GmailAccessTokenProviding {
  suspend fun accessToken(
    subject: String,
    dimoUserId: String,
    forceRefresh: Boolean = false,
  ): GmailAccessToken

  suspend fun invalidate(subject: String)
}

/**
 * Bridges the Gmail OAuth redirect back to the suspended connect call.
 *
 * Kept separate from `AuthRedirectBus` so a Gmail redirect can never complete a
 * parked WorkOS sign-in, or the reverse — they use different URI schemes and can
 * in principle be in flight at once.
 */
object GmailRedirectBus {
  @Volatile
  private var pending: CompletableDeferred<Uri>? = null

  fun expectRedirect(): CompletableDeferred<Uri> {
    pending?.cancel()
    return CompletableDeferred<Uri>().also { pending = it }
  }

  fun publish(uri: Uri): Boolean {
    val deferred = pending ?: return false
    pending = null
    return deferred.complete(uri)
  }

  fun cancelPending() {
    pending?.completeExceptionally(GmailOAuthException.Cancelled)
    pending = null
  }

  fun hasPending(): Boolean = pending?.isActive == true
}

class GmailOAuthClient(
  private val configuration: GmailOAuthConfiguration,
  private val vault: GmailCredentialVault,
  private val http: OkHttpClient = GmailHttp.client,
) {
  private val json = Json { ignoreUnknownKeys = true }

  suspend fun connect(context: Context, dimoUserId: String): ConnectedGmailAccount =
    authorize(context, dimoUserId, loginHint = null, expectedSubject = null)

  /**
   * Replaces the stored refresh token for an existing account without wiping local
   * email rows. Verifies Google returns the same subject.
   */
  suspend fun reauthorize(
    context: Context,
    subject: String,
    emailAddress: String,
    dimoUserId: String,
  ): ConnectedGmailAccount {
    val existing = vault.credential(subject, dimoUserId)
    return authorize(
      context = context,
      dimoUserId = dimoUserId,
      loginHint = emailAddress,
      expectedSubject = subject,
      connectedAt = existing?.connectedAt,
    )
  }

  /** Revocation is best effort; local credentials are always removed. */
  suspend fun disconnect(subject: String, dimoUserId: String) {
    val refreshToken = vault.credential(subject, dimoUserId)?.refreshToken
    if (refreshToken != null) runCatching { revoke(refreshToken) }
    vault.remove(subject, dimoUserId)
  }

  suspend fun deleteLocalCredentialsOnSignOut(dimoUserId: String) {
    runCatching { vault.removeAll(dimoUserId) }
  }

  // MARK: - Private

  private suspend fun authorize(
    context: Context,
    dimoUserId: String,
    loginHint: String?,
    expectedSubject: String?,
    connectedAt: Long? = null,
  ): ConnectedGmailAccount {
    val verifier = PKCE.makeVerifier()
    val state = PKCE.makeState()
    val url = authorizationUrl(verifier, state, loginHint)

    val redirect = GmailRedirectBus.expectRedirect()
    launchCustomTab(context, url)
    val callback = redirect.await()

    callback.getQueryParameter("error")?.let { oauthError ->
      if (oauthError == "access_denied") throw GmailOAuthException.Cancelled
      throw GmailOAuthException.Authorization(oauthError)
    }
    if (callback.getQueryParameter("state") != state) throw GmailOAuthException.StateMismatch
    val code = callback.getQueryParameter("code")?.takeIf { it.isNotEmpty() }
      ?: throw GmailOAuthException.MissingCode

    val token = exchangeCode(code, verifier)
    val refreshToken = token.refreshToken?.takeIf { it.isNotEmpty() }
      ?: throw GmailOAuthException.MissingRefreshToken
    val identity = fetchIdentity(token.accessToken)
    if (expectedSubject != null && identity.subject != expectedSubject) {
      throw GmailOAuthException.AccountMismatch
    }
    val credential = GmailStoredCredential(
      subject = identity.subject,
      emailAddress = identity.emailAddress,
      refreshToken = refreshToken,
      connectedAt = connectedAt ?: System.currentTimeMillis(),
    )
    vault.upsert(credential, dimoUserId)
    return credential.account
  }

  private fun authorizationUrl(verifier: String, state: String, loginHint: String?): Uri {
    val builder = Uri.parse(GmailOAuthConfigurationDefaults.AUTHORIZATION_ENDPOINT)
      .buildUpon()
      .appendQueryParameter("client_id", configuration.clientId)
      .appendQueryParameter("redirect_uri", configuration.redirectUri)
      .appendQueryParameter("response_type", "code")
      .appendQueryParameter(
        "scope",
        listOf("openid", "email", GmailOAuthConfigurationDefaults.READ_ONLY_SCOPE)
          .joinToString(" "),
      )
      // `offline` + a forced consent screen is what makes Google return a refresh
      // token; without it a reconnect silently yields access-token-only grants.
      .appendQueryParameter("access_type", "offline")
      .appendQueryParameter("prompt", "consent select_account")
      .appendQueryParameter("include_granted_scopes", "true")
      .appendQueryParameter("code_challenge", PKCE.challenge(verifier))
      .appendQueryParameter("code_challenge_method", "S256")
      .appendQueryParameter("state", state)
    loginHint?.trim()?.takeIf { it.isNotEmpty() }?.let {
      builder.appendQueryParameter("login_hint", it)
    }
    return builder.build()
  }

  private fun launchCustomTab(context: Context, url: Uri) {
    val intent = CustomTabsIntent.Builder()
      .setShowTitle(false)
      .setUrlBarHidingEnabled(true)
      .build()
    intent.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    intent.launchUrl(context, url)
  }

  private suspend fun exchangeCode(code: String, verifier: String): OAuthTokenResponse =
    postForm(
      GmailOAuthConfigurationDefaults.TOKEN_ENDPOINT,
      mapOf(
        "client_id" to configuration.clientId,
        "code" to code,
        "code_verifier" to verifier,
        "grant_type" to "authorization_code",
        "redirect_uri" to configuration.redirectUri,
      ),
    )

  private suspend fun fetchIdentity(accessToken: String): GmailIdentityResponse =
    withContext(Dispatchers.IO) {
      val request = Request.Builder()
        .url(GmailOAuthConfigurationDefaults.USER_INFO_ENDPOINT)
        .header("Authorization", "Bearer $accessToken")
        .build()
      http.newCall(request).execute().use { response ->
        val body = response.body.string()
        validate(response.code, body)
        runCatching { json.decodeFromString<GmailIdentityResponse>(body) }.getOrNull()
          ?: throw GmailOAuthException.InvalidResponse
      }
    }

  private suspend fun revoke(token: String) = withContext(Dispatchers.IO) {
    val url = GmailOAuthConfigurationDefaults.REVOCATION_ENDPOINT.toHttpUrl()
      .newBuilder()
      .addQueryParameter("token", token)
      .build()
    val request = Request.Builder()
      .url(url)
      .post(FormBody.Builder().build())
      .build()
    http.newCall(request).execute().use { response ->
      validate(response.code, response.body.string())
    }
  }

  private suspend fun postForm(url: String, values: Map<String, String>): OAuthTokenResponse =
    withContext(Dispatchers.IO) {
      val form = FormBody.Builder().apply {
        values.toSortedMap().forEach { (key, value) -> add(key, value) }
      }.build()
      val request = Request.Builder().url(url).post(form).build()
      http.newCall(request).execute().use { response ->
        val body = response.body.string()
        validate(response.code, body)
        runCatching { json.decodeFromString<OAuthTokenResponse>(body) }.getOrNull()
          ?: throw GmailOAuthException.InvalidResponse
      }
    }

  private fun validate(code: Int, body: String) {
    if (code in 200..299) return
    val payload = runCatching { json.decodeFromString<GoogleOAuthErrorResponse>(body) }.getOrNull()
    // `invalid_grant` is the one error the user can fix, by reconnecting.
    if (payload?.error == "invalid_grant") throw GmailOAuthException.RequiresReconnect
    throw GmailOAuthException.Server(
      payload?.errorDescription ?: payload?.error ?: "HTTP $code",
    )
  }
}

/**
 * Exchanges refresh tokens for short-lived access tokens and caches them in
 * memory. Port of the `GmailAccessTokenManager` actor.
 */
class GmailAccessTokenManager(
  private val configuration: GmailOAuthConfiguration,
  private val vault: GmailCredentialVault,
  private val http: OkHttpClient = GmailHttp.client,
) : GmailAccessTokenProviding {
  private val json = Json { ignoreUnknownKeys = true }
  private val cached = ConcurrentHashMap<String, GmailAccessToken>()

  /** Serializes refreshes so a burst of Gmail calls cannot spend the same grant twice. */
  private val mutex = Mutex()

  override suspend fun accessToken(
    subject: String,
    dimoUserId: String,
    forceRefresh: Boolean,
  ): GmailAccessToken = mutex.withLock {
    if (!forceRefresh) {
      val hit = cached[subject]
      if (hit != null && hit.expiresAt - System.currentTimeMillis() > MIN_REMAINING_MS) return hit
    }
    val credential = vault.credential(subject, dimoUserId)
      ?: throw GmailOAuthException.RequiresReconnect
    val response = withContext(Dispatchers.IO) {
      val form = FormBody.Builder()
        .add("client_id", configuration.clientId)
        .add("refresh_token", credential.refreshToken)
        .add("grant_type", "refresh_token")
        .build()
      val request = Request.Builder()
        .url(GmailOAuthConfigurationDefaults.TOKEN_ENDPOINT)
        .post(form)
        .build()
      http.newCall(request).execute().use { httpResponse ->
        val body = httpResponse.body.string()
        if (httpResponse.code !in 200..299) {
          val payload = runCatching {
            json.decodeFromString<GoogleOAuthErrorResponse>(body)
          }.getOrNull()
          if (payload?.error == "invalid_grant") throw GmailOAuthException.RequiresReconnect
          throw GmailOAuthException.Server(
            payload?.errorDescription ?: payload?.error ?: "HTTP ${httpResponse.code}",
          )
        }
        runCatching { json.decodeFromString<OAuthTokenResponse>(body) }.getOrNull()
          ?: throw GmailOAuthException.InvalidResponse
      }
    }
    // Expire a minute early so a token cannot lapse mid-request.
    val token = GmailAccessToken(
      value = response.accessToken,
      expiresAt = System.currentTimeMillis() +
        maxOf(response.expiresIn - 60, 1) * 1000L,
    )
    cached[subject] = token
    token
  }

  override suspend fun invalidate(subject: String) {
    cached.remove(subject)
  }

  fun clearAll() = cached.clear()

  private companion object {
    const val MIN_REMAINING_MS = 60_000L
  }
}

/** Shared, cookie-free OkHttp client for every Google call. */
object GmailHttp {
  val client: OkHttpClient by lazy {
    OkHttpClient.Builder()
      .retryOnConnectionFailure(true)
      .build()
  }
}

@Serializable
private data class OAuthTokenResponse(
  @SerialName("access_token") val accessToken: String,
  @SerialName("expires_in") val expiresIn: Int,
  @SerialName("refresh_token") val refreshToken: String? = null,
)

@Serializable
private data class GmailIdentityResponse(
  @SerialName("sub") val subject: String,
  @SerialName("email") val emailAddress: String,
)

@Serializable
private data class GoogleOAuthErrorResponse(
  val error: String? = null,
  @SerialName("error_description") val errorDescription: String? = null,
)

sealed class GmailOAuthException(message: String) : Exception(message) {
  object NotConfigured : GmailOAuthException("Gmail OAuth is not configured.")
  object Cancelled : GmailOAuthException("Gmail sign-in was cancelled.")
  object StateMismatch : GmailOAuthException("Gmail sign-in failed its security check.")
  object MissingCode : GmailOAuthException("Gmail did not return an authorization code.")
  object MissingRefreshToken : GmailOAuthException(
    "Gmail did not grant offline access. Reconnect this account and approve access again.",
  )
  object InvalidResponse : GmailOAuthException("Gmail returned an invalid response.")
  object RequiresReconnect : GmailOAuthException(
    "Gmail access expired or was revoked. Reconnect this account to continue.",
  )
  object AccountMismatch : GmailOAuthException(
    "That Google account does not match the connected Gmail inbox. " +
      "Choose the same account to reconnect.",
  )

  class Authorization(reason: String) : GmailOAuthException("Gmail authorization failed: $reason")
  class Server(reason: String) : GmailOAuthException("Gmail authorization failed: $reason")
}
