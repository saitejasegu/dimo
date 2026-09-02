package app.dimo.android.auth

import android.net.Uri
import android.util.Base64
import app.dimo.android.app.AppConfig
import java.io.IOException
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

/** Port of `ios-native/Dimo/Auth/WorkOSAPI.swift`. */

@Serializable
data class WorkOSUser(
  val id: String,
  val email: String,
  // WorkOS returns snake_case; without these names the fields decode as null and
  // displayName falls back to the email address.
  @SerialName("first_name") val firstName: String? = null,
  @SerialName("last_name") val lastName: String? = null,
  @SerialName("profile_picture_url") val profilePictureUrl: String? = null,
) {
  val displayName: String
    get() {
      val parts = listOfNotNull(firstName, lastName).map { it.trim() }.filter { it.isNotEmpty() }
      return if (parts.isNotEmpty()) parts.joinToString(" ") else email
    }
}

data class WorkOSSession(
  val accessToken: String,
  val refreshToken: String,
  val user: WorkOSUser,
  /** Epoch millis at which [accessToken] expires. */
  val expiresAt: Long,
)

sealed class AuthException(message: String) : Exception(message) {
  data object MissingRefreshToken : AuthException("Missing refresh token")
  data object Cancelled : AuthException("Sign-in cancelled")
  data object StateMismatch : AuthException("OAuth state mismatch")
  data object MissingCode : AuthException("Missing authorization code")
  data object NotAuthenticated : AuthException("Not authenticated")
  data class Server(val detail: String) : AuthException(detail)
  /** Refresh token revoked/expired — clear storage and send user to sign-in. */
  data class TerminalRefresh(val detail: String) : AuthException(detail)
  /** Network / 429 / 5xx — keep storage and retry; never treat as sign-out. */
  data class TransientRefresh(val detail: String) : AuthException(detail)

  val isTerminalRefresh: Boolean
    get() = this is TerminalRefresh || this is NotAuthenticated || this is MissingRefreshToken

  companion object {
    fun fromHttp(status: Int, body: String): AuthException {
      val oauthError = oauthErrorCode(body)
      if (status == 400 && oauthError == "invalid_grant") {
        return TerminalRefresh(sanitize(body, "Session expired"))
      }
      if (status == 408 || status == 429 || status in 500..599) {
        return TransientRefresh(sanitize(body, "HTTP $status"))
      }
      if (status in 400..499) {
        return TerminalRefresh(sanitize(body, "HTTP $status"))
      }
      return TransientRefresh(sanitize(body, "HTTP $status"))
    }

    fun isTransient(error: Throwable): Boolean =
      error is TransientRefresh || error is IOException

    private fun oauthErrorCode(body: String): String? = runCatching {
      val json = JSONObject(body)
      when (val error = json.opt("error")) {
        is String -> error
        is JSONObject -> error.optString("code").ifEmpty { null }
        else -> null
      }
    }.getOrNull()

    private fun sanitize(body: String, fallback: String): String {
      val trimmed = body.trim()
      if (trimmed.isEmpty()) return fallback
      return trimmed.take(200)
    }
  }
}

object WorkOSAPI {
  private val json = Json { ignoreUnknownKeys = true }
  private val jsonMediaType = "application/json".toMediaType()

  private val client: OkHttpClient by lazy {
    OkHttpClient.Builder()
      .callTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
      .build()
  }

  @Serializable
  private data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String? = null,
    val user: WorkOSUser,
  )

  suspend fun exchangeCode(
    code: String,
    codeVerifier: String,
    clientId: String,
    redirectURI: String,
  ): WorkOSSession {
    val body = JSONObject(
      mapOf(
        "client_id" to clientId,
        "grant_type" to "authorization_code",
        "code" to code,
        "code_verifier" to codeVerifier,
        "redirect_uri" to redirectURI,
      ),
    ).toString()
    val decoded = post(body)
    val refresh = decoded.refreshToken ?: throw AuthException.MissingRefreshToken
    return WorkOSSession(
      accessToken = decoded.accessToken,
      refreshToken = refresh,
      user = decoded.user,
      expiresAt = jwtExpiry(decoded.accessToken) ?: (System.currentTimeMillis() + 3_600_000),
    )
  }

  /** Retries transient failures; surfaces terminal `invalid_grant` immediately. */
  suspend fun refresh(
    refreshToken: String,
    clientId: String,
    maxAttempts: Int = 4,
  ): WorkOSSession {
    var lastError: Throwable? = null
    repeat(maxAttempts.coerceAtLeast(1)) { attempt ->
      try {
        return refreshOnce(refreshToken, clientId)
      } catch (error: AuthException) {
        if (error.isTerminalRefresh) throw error
        lastError = error
      } catch (error: IOException) {
        lastError = AuthException.TransientRefresh(error.message ?: "Network error")
      }
      if (attempt + 1 < maxAttempts) {
        val delayMs = (min(8.0, 2.0.pow(attempt.toDouble())) * (0.75 + Random.nextDouble()) * 1000).toLong()
        delay(delayMs)
      }
    }
    throw lastError ?: AuthException.TransientRefresh("Refresh failed")
  }

  private suspend fun refreshOnce(refreshToken: String, clientId: String): WorkOSSession {
    val body = JSONObject(
      mapOf(
        "client_id" to clientId,
        "grant_type" to "refresh_token",
        "refresh_token" to refreshToken,
      ),
    ).toString()
    val decoded = post(body)
    return WorkOSSession(
      accessToken = decoded.accessToken,
      refreshToken = decoded.refreshToken ?: refreshToken,
      user = decoded.user,
      expiresAt = jwtExpiry(decoded.accessToken) ?: (System.currentTimeMillis() + 3_600_000),
    )
  }

  fun authorizationURL(
    clientId: String,
    redirectURI: String,
    state: String,
    codeChallenge: String,
    provider: String,
  ): Uri = Uri.parse("${AppConfig.workOSAuthBaseURL}/user_management/authorize")
    .buildUpon()
    .appendQueryParameter("client_id", clientId)
    .appendQueryParameter("redirect_uri", redirectURI)
    .appendQueryParameter("response_type", "code")
    .appendQueryParameter("provider", provider)
    .appendQueryParameter("state", state)
    .appendQueryParameter("code_challenge", codeChallenge)
    .appendQueryParameter("code_challenge_method", "S256")
    .build()

  /** Epoch millis from the JWT `exp` claim, or null when it cannot be read. */
  fun jwtExpiry(token: String): Long? {
    val parts = token.split(".")
    if (parts.size < 2) return null
    return runCatching {
      val payload = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
      val exp = JSONObject(String(payload, Charsets.UTF_8)).optDouble("exp", Double.NaN)
      if (exp.isNaN()) null else (exp * 1000).toLong()
    }.getOrNull()
  }

  private suspend fun post(body: String): TokenResponse = withContext(Dispatchers.IO) {
    val request = Request.Builder()
      .url("${AppConfig.workOSAuthBaseURL}/user_management/authenticate")
      .post(body.toRequestBody(jsonMediaType))
      .build()
    try {
      client.newCall(request).execute().use { response ->
        val text = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
          throw AuthException.fromHttp(response.code, text)
        }
        json.decodeFromString(TokenResponse.serializer(), text)
      }
    } catch (io: IOException) {
      throw AuthException.TransientRefresh(io.message ?: "Network error")
    }
  }
}
