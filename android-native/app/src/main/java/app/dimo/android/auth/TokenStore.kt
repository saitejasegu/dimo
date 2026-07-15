package app.dimo.android.auth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class TokenStore(context: Context) {
  private val appContext = context.applicationContext
  private val lock = Any()
  @Volatile private var prefs: SharedPreferences? = null

  private fun prefs(): SharedPreferences {
    prefs?.let { return it }
    synchronized(lock) {
      prefs?.let { return it }
      val opened = try {
        EncryptedSharedPreferences.create(
          appContext,
          "app.dimo.android.secure",
          MasterKey.Builder(appContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
          EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
          EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
      } catch (_: Exception) {
        // Emulator / cold Keystore can fail; fall back so the UI can still boot.
        appContext.getSharedPreferences("app.dimo.android.tokens", Context.MODE_PRIVATE)
      }
      prefs = opened
      return opened
    }
  }

  var refreshToken: String?
    get() = prefs().getString(KEY_REFRESH, null)
    set(value) {
      prefs().edit().putString(KEY_REFRESH, value).apply()
    }

  var userJson: String?
    get() = prefs().getString(KEY_USER, null)
    set(value) {
      prefs().edit().putString(KEY_USER, value).apply()
    }

  fun clear() {
    prefs().edit().clear().apply()
  }

  companion object {
    private const val KEY_REFRESH = "workos.refreshToken"
    private const val KEY_USER = "workos.user"
  }
}
