package app.dimo.android.auth

import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

/** Port of `ios-native/Dimo/Auth/PKCE.swift`. */
object PKCE {
  private val random = SecureRandom()

  fun makeVerifier(): String = base64UrlEncode(ByteArray(32).also { random.nextBytes(it) })

  fun challenge(verifier: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.UTF_8))
    return base64UrlEncode(digest)
  }

  fun makeState(): String = base64UrlEncode(ByteArray(16).also { random.nextBytes(it) })

  private fun base64UrlEncode(bytes: ByteArray): String =
    Base64.encodeToString(bytes, Base64.NO_WRAP or Base64.NO_PADDING or Base64.URL_SAFE)
}
