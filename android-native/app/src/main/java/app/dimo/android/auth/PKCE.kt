package app.dimo.android.auth

import java.security.MessageDigest
import java.security.SecureRandom
import android.util.Base64

object PKCE {
  private val random = SecureRandom()

  fun verifier(): String = base64Url(randomBytes(32))
  fun state(): String = base64Url(randomBytes(16))

  fun challenge(verifier: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.UTF_8))
    return base64Url(digest)
  }

  private fun randomBytes(size: Int): ByteArray = ByteArray(size).also { random.nextBytes(it) }

  private fun base64Url(bytes: ByteArray): String =
    Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
}
