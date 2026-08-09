package app.dimo.android.email.gmail

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

@Serializable
data class ConnectedGmailAccount(
  val subject: String,
  val emailAddress: String,
  val connectedAt: Long,
) {
  val id: String get() = subject
}

@Serializable
data class GmailStoredCredential(
  val subject: String,
  val emailAddress: String,
  val refreshToken: String,
  val connectedAt: Long,
) {
  val account: ConnectedGmailAccount
    get() = ConnectedGmailAccount(subject, emailAddress, connectedAt)
}

@Serializable
private data class GmailCredentialBundle(
  val version: Int,
  val credentials: List<GmailStoredCredential>,
) {
  companion object {
    const val CURRENT_VERSION = 1
  }
}

/**
 * Stores Gmail refresh tokens in a device-only, Dimo-user-scoped encrypted file —
 * the Keystore counterpart of the Keychain vault in
 * `ios-native/Dimo/Email/Gmail/GmailCredentialVault.swift`.
 *
 * Access tokens are intentionally absent from this type and remain in memory.
 * Every accessor is guarded by a mutex so a concurrent connect and refresh cannot
 * lose a credential through read-modify-write.
 */
class GmailCredentialVault(context: Context) {
  private val appContext = context.applicationContext
  private val mutex = Mutex()
  private val json = Json { ignoreUnknownKeys = true }
  private val files = ConcurrentHashMap<String, SharedPreferences>()

  suspend fun accounts(dimoUserId: String): List<ConnectedGmailAccount> = mutex.withLock {
    loadBundle(dimoUserId).credentials
      .map { it.account }
      .sortedBy { it.emailAddress.lowercase() }
  }

  suspend fun credential(subject: String, dimoUserId: String): GmailStoredCredential? =
    mutex.withLock {
      loadBundle(dimoUserId).credentials.firstOrNull { it.subject == subject }
    }

  suspend fun upsert(credential: GmailStoredCredential, dimoUserId: String) = mutex.withLock {
    val bundle = loadBundle(dimoUserId)
    save(
      bundle.copy(
        credentials = bundle.credentials.filter { it.subject != credential.subject } +
          credential,
      ),
      dimoUserId,
    )
  }

  suspend fun remove(subject: String, dimoUserId: String) = mutex.withLock {
    val bundle = loadBundle(dimoUserId)
    val remaining = bundle.credentials.filter { it.subject != subject }
    if (remaining.isEmpty()) {
      deleteBundle(dimoUserId)
    } else {
      save(bundle.copy(credentials = remaining), dimoUserId)
    }
  }

  suspend fun removeAll(dimoUserId: String) = mutex.withLock { deleteBundle(dimoUserId) }

  // MARK: - Private

  private fun loadBundle(dimoUserId: String): GmailCredentialBundle {
    val raw = prefs(dimoUserId).getString(KEY_BUNDLE, null)
      ?: return GmailCredentialBundle(GmailCredentialBundle.CURRENT_VERSION, emptyList())
    val bundle = runCatching { json.decodeFromString<GmailCredentialBundle>(raw) }.getOrNull()
      ?: throw GmailCredentialVaultException("The saved Gmail credentials are corrupt.")
    if (bundle.version != GmailCredentialBundle.CURRENT_VERSION) {
      throw GmailCredentialVaultException(
        "The saved Gmail credential format (${bundle.version}) is unsupported.",
      )
    }
    return bundle
  }

  private fun save(bundle: GmailCredentialBundle, dimoUserId: String) {
    prefs(dimoUserId).edit().putString(KEY_BUNDLE, json.encodeToString(bundle)).apply()
  }

  private fun deleteBundle(dimoUserId: String) {
    prefs(dimoUserId).edit().clear().apply()
  }

  /**
   * One encrypted file per Dimo user. The name is a digest so a WorkOS user id
   * never lands in a filename on disk.
   */
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

  private fun fileName(dimoUserId: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
      .digest(dimoUserId.toByteArray(Charsets.UTF_8))
    return FILE_PREFIX + digest.joinToString("") { "%02x".format(it) }
  }

  private companion object {
    const val FILE_PREFIX = "dimo.gmail."
    const val KEY_BUNDLE = "gmail.credentials"
  }
}

class GmailCredentialVaultException(message: String) : Exception(message)
