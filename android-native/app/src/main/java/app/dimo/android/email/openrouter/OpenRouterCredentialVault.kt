package app.dimo.android.email.openrouter

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Port of `ios-native/Dimo/Email/OpenRouter/OpenRouterCredentialVault.swift`.
 *
 * Holds the user's own OpenRouter API key (BYOK mode) in a Keystore-backed,
 * Dimo-user-scoped encrypted file. Free mode never stores a key here — those
 * requests are proxied through Convex.
 */
@Serializable
data class OpenRouterCredential(
  val version: Int = CURRENT_VERSION,
  val apiKey: String,
) {
  companion object {
    const val CURRENT_VERSION = 1
  }
}

class OpenRouterCredentialVault(context: Context) {
  private val appContext = context.applicationContext
  private val mutex = Mutex()
  private val json = Json { ignoreUnknownKeys = true }
  private val files = ConcurrentHashMap<String, SharedPreferences>()

  suspend fun credential(dimoUserId: String): OpenRouterCredential? = mutex.withLock {
    val raw = prefs(dimoUserId).getString(KEY_CREDENTIAL, null) ?: return null
    val value = runCatching { json.decodeFromString<OpenRouterCredential>(raw) }.getOrNull()
      ?: throw OpenRouterCredentialVaultException("The saved OpenRouter credential is corrupt.")
    if (value.version != OpenRouterCredential.CURRENT_VERSION) {
      throw OpenRouterCredentialVaultException("The saved OpenRouter credential is corrupt.")
    }
    return value
  }

  suspend fun save(apiKey: String, dimoUserId: String) = mutex.withLock {
    val trimmed = apiKey.trim()
    if (trimmed.isEmpty()) {
      throw OpenRouterCredentialVaultException("Enter an OpenRouter API key.")
    }
    prefs(dimoUserId).edit()
      .putString(KEY_CREDENTIAL, json.encodeToString(OpenRouterCredential(apiKey = trimmed)))
      .apply()
  }

  suspend fun remove(dimoUserId: String) = mutex.withLock {
    prefs(dimoUserId).edit().clear().apply()
  }

  private fun prefs(dimoUserId: String): SharedPreferences = files.getOrPut(dimoUserId) {
    val masterKey = MasterKey.Builder(appContext)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
    EncryptedSharedPreferences.create(
      appContext,
      fileName(dimoUserId),
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  /** Digested so a WorkOS user id never lands in a filename on disk. */
  private fun fileName(dimoUserId: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(dimoUserId.toByteArray(Charsets.UTF_8))
    return FILE_PREFIX + digest.joinToString("") { "%02x".format(it) }
  }

  private companion object {
    const val FILE_PREFIX = "dimo.openrouter."
    const val KEY_CREDENTIAL = "openrouter.credential"
  }
}

class OpenRouterCredentialVaultException(message: String) : Exception(message)
