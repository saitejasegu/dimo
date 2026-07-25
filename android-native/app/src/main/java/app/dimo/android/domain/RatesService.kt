package app.dimo.android.domain

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

private val Context.ratesDataStore: DataStore<Preferences> by preferencesDataStore(
  name = "dimo_exchange_rates",
)

/**
 * DataStore-backed cache for the Convex `exchangeRates:latest` snapshot.
 * Port of `RatesService` in `ios-native/Dimo/Domain/ExchangeRates.swift`
 * (UserDefaults there).
 */
class RatesService(context: Context) {
  private val dataStore = context.applicationContext.ratesDataStore
  private val json = Json { ignoreUnknownKeys = true }

  suspend fun loadCached(): RateTable? {
    val raw = dataStore.data.map { prefs -> prefs[CACHE_KEY] }.first() ?: return null
    return runCatching { json.decodeFromString(RateTable.serializer(), raw) }.getOrNull()
  }

  suspend fun store(table: RateTable) {
    val encoded = json.encodeToString(RateTable.serializer(), table)
    dataStore.edit { prefs -> prefs[CACHE_KEY] = encoded }
  }

  private companion object {
    val CACHE_KEY = stringPreferencesKey("dimo.exchangeRates")
  }
}
