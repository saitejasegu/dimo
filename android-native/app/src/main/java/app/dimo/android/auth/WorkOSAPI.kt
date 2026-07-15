package app.dimo.android.auth

import app.dimo.android.app.AppConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class WorkOSAPI(
  private val client: OkHttpClient = OkHttpClient.Builder()
    .connectTimeout(30, TimeUnit.SECONDS)
    .readTimeout(30, TimeUnit.SECONDS)
    .build(),
  private val json: Json = WorkOSJson.json,
) {
  fun authorizeUrl(provider: String, state: String, challenge: String): String {
    val base = AppConfig.workOSAuthBaseUrl.trimEnd('/')
    val params = listOf(
      "client_id" to AppConfig.workOSClientId,
      "redirect_uri" to AppConfig.workOSRedirectUri,
      "response_type" to "code",
      "provider" to provider,
      "state" to state,
      "code_challenge" to challenge,
      "code_challenge_method" to "S256",
    ).joinToString("&") { (k, v) ->
      "${URLEncoder.encode(k, "UTF-8")}=${URLEncoder.encode(v, "UTF-8")}"
    }
    return "$base/user_management/authorize?$params"
  }

  fun exchangeCode(code: String, verifier: String): WorkOSSession {
    val body = AuthCodeRequest(
      clientId = AppConfig.workOSClientId,
      grantType = "authorization_code",
      code = code,
      codeVerifier = verifier,
      redirectUri = AppConfig.workOSRedirectUri,
    )
    return authenticate(body)
  }

  fun refresh(refreshToken: String): WorkOSSession {
    val body = RefreshRequest(
      clientId = AppConfig.workOSClientId,
      grantType = "refresh_token",
      refreshToken = refreshToken,
    )
    return authenticate(body, fallbackRefresh = refreshToken)
  }

  private fun authenticate(body: Any, fallbackRefresh: String? = null): WorkOSSession {
    val payload = when (body) {
      is AuthCodeRequest -> json.encodeToString(AuthCodeRequest.serializer(), body)
      is RefreshRequest -> json.encodeToString(RefreshRequest.serializer(), body)
      else -> error("Unknown body")
    }
    val request = Request.Builder()
      .url("${AppConfig.workOSAuthBaseUrl.trimEnd('/')}/user_management/authenticate")
      .post(payload.toRequestBody("application/json".toMediaType()))
      .build()
    client.newCall(request).execute().use { response ->
      val text = response.body?.string().orEmpty()
      if (!response.isSuccessful) {
        throw IllegalStateException("WorkOS auth failed (${response.code}): $text")
      }
      val parsed = json.decodeFromString(AuthResponse.serializer(), text)
      val refresh = parsed.refreshToken ?: fallbackRefresh
        ?: throw IllegalStateException("Missing refresh token")
      val expires = Jwt.expiresAtEpochSeconds(parsed.accessToken)
        ?: (System.currentTimeMillis() / 1000 + 3600)
      return WorkOSSession(
        accessToken = parsed.accessToken,
        refreshToken = refresh,
        user = parsed.user,
        expiresAtEpochSeconds = expires,
      )
    }
  }

  @Serializable
  private data class AuthCodeRequest(
    @SerialName("client_id") val clientId: String,
    @SerialName("grant_type") val grantType: String,
    val code: String,
    @SerialName("code_verifier") val codeVerifier: String,
    @SerialName("redirect_uri") val redirectUri: String,
  )

  @Serializable
  private data class RefreshRequest(
    @SerialName("client_id") val clientId: String,
    @SerialName("grant_type") val grantType: String,
    @SerialName("refresh_token") val refreshToken: String,
  )

  @Serializable
  private data class AuthResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String? = null,
    val user: WorkOSUser,
  )
}

object Jwt {
  fun expiresAtEpochSeconds(token: String): Long? {
    return try {
      val parts = token.split('.')
      if (parts.size < 2) return null
      val payload = String(
        android.util.Base64.decode(
          parts[1],
          android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING,
        ),
        Charsets.UTF_8,
      )
      val exp = Regex("\"exp\"\\s*:\\s*(\\d+)").find(payload)?.groupValues?.get(1)
      exp?.toLongOrNull()
    } catch (_: Exception) {
      null
    }
  }
}
