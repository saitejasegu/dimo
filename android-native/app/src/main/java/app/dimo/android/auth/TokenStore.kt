package app.dimo.android.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class TokenStore(context: Context) {
  private val prefs = EncryptedSharedPreferences.create(
    context,
    "app.dimo.android.secure",
    MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
  )

  var refreshToken: String?
    get() = prefs.getString(KEY_REFRESH, null)
    set(value) {
      prefs.edit().putString(KEY_REFRESH, value).apply()
    }

  var userJson: String?
    get() = prefs.getString(KEY_USER, null)
    set(value) {
      prefs.edit().putString(KEY_USER, value).apply()
    }

  fun clear() {
    prefs.edit().clear().apply()
  }

  companion object {
    private const val KEY_REFRESH = "workos.refreshToken"
    private const val KEY_USER = "workos.user"
  }
}
