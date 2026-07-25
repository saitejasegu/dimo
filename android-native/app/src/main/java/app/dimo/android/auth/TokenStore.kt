package app.dimo.android.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Keystore-backed replacement for `ios-native/Dimo/Auth/KeychainStore.swift`.
 *
 * Only the refresh token and the cached profile live here. Nothing else about a
 * session is persisted, and sign-out clears the whole file.
 */
class TokenStore(context: Context) {
  private val appContext = context.applicationContext

  private val prefs: SharedPreferences by lazy {
    val masterKey = MasterKey.Builder(appContext)
      .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
      .build()
    EncryptedSharedPreferences.create(
      appContext,
      FILE_NAME,
      masterKey,
      EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
      EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )
  }

  var refreshToken: String?
    get() = prefs.getString(KEY_REFRESH, null)
    set(value) = prefs.edit().apply {
      if (value == null) remove(KEY_REFRESH) else putString(KEY_REFRESH, value)
    }.apply()

  var userJson: String?
    get() = prefs.getString(KEY_USER, null)
    set(value) = prefs.edit().apply {
      if (value == null) remove(KEY_USER) else putString(KEY_USER, value)
    }.apply()

  fun clear() {
    prefs.edit().clear().apply()
  }

  private companion object {
    const val FILE_NAME = "dimo.workos"
    const val KEY_REFRESH = "workos.refreshToken"
    const val KEY_USER = "workos.user"
  }
}
