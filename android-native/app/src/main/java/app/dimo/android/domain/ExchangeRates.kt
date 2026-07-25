package app.dimo.android.domain

import app.dimo.android.data.model.Recurring
import kotlinx.serialization.Serializable
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToLong

/**
 * Port of `ios-native/Dimo/Domain/ExchangeRates.swift`.
 *
 * Rates are ECB daily reference rates stored in Convex and refreshed once per day
 * by the `refreshRates` cron — clients read `exchangeRates:latest` and never call
 * Frankfurter themselves.
 */
object CurrencyMeta {
  data class Info(val symbol: String, val label: String, val minorUnitDigits: Int)

  /** Metadata for every currency a single expense may be entered in. */
  val all: Map<String, Info> = mapOf(
    "INR" to Info("₹", "INR", 2),
    "USD" to Info("$", "USD", 2),
    "EUR" to Info("€", "EUR", 2),
    "GBP" to Info("£", "GBP", 2),
    "JPY" to Info("¥", "JPY", 0),
    "AUD" to Info("A$", "AUD", 2),
    "CAD" to Info("C$", "CAD", 2),
    "HKD" to Info("HK$", "HKD", 2),
    "SGD" to Info("S$", "SGD", 2),
    "CHF" to Info("CHF", "CHF", 2),
    "CNY" to Info("¥", "CNY", 2),
  )

  /** Ordered list for pickers; default currencies first. */
  val enterable: List<String> =
    listOf("INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "HKD", "SGD", "CHF", "CNY")

  fun minorUnitDigits(code: String): Int = all[code]?.minorUnitDigits ?: 2

  fun symbol(code: String): String = all[code]?.symbol ?: code

  fun label(code: String): String = all[code]?.label ?: code
}

/** A snapshot of exchange rates for a single day, quoted against [base]. */
@Serializable
data class RateTable(
  /** ECB rate date, `YYYY-MM-DD`. */
  val date: String,
  /** Base currency the raw rates were quoted against. */
  val base: String,
  /** Units of each currency per 1 unit of [base] (the base itself is implicitly 1). */
  val rates: Map<String, Double>,
)

object ExchangeRates {
  private fun factor(currency: String): Double =
    10.0.pow(CurrencyMeta.minorUnitDigits(currency))

  /** Major-unit ratio to convert 1 unit of [from] into [to], or null if unknown. */
  fun rateBetween(from: String, to: String, rates: RateTable?): Double? {
    if (from == to) return 1.0
    if (rates == null) return null
    fun unit(code: String): Double? = if (code == rates.base) 1.0 else rates.rates[code]
    val fromRate = unit(from) ?: return null
    val toRate = unit(to) ?: return null
    if (fromRate <= 0 || toRate <= 0) return null
    return toRate / fromRate
  }

  /**
   * Convert an integer minor-unit amount between currencies, honoring each
   * currency's minor-unit exponent. Returns null when the rate is unavailable.
   */
  fun convertMinor(amountMinor: Long, from: String, to: String, rates: RateTable?): Long? {
    val ratio = rateBetween(from, to, rates) ?: return null
    val major = (amountMinor.toDouble() / factor(from)) * ratio
    return (major * factor(to)).roundToLong()
  }

  /** Convert a major-unit amount (what a user types) into minor units. */
  fun toMinorUnits(amount: Double, currency: String): Long =
    (amount * factor(currency)).roundToLong()

  /** Convert an integer minor-unit amount back into major units. */
  fun toMajorUnits(amountMinor: Long, currency: String): Double =
    amountMinor.toDouble() / factor(currency)

  /** Canonical recurring fields. New rows always name their denomination. */
  fun recurringFields(amount: Double, currency: String): Pair<Long, String> =
    Pair(max(1L, toMinorUnits(amount, currency)), currency)

  /**
   * A recurring bill's amount in major units of [defaultCurrency] using today's
   * rates. Default-currency bills (or unavailable rates) return the raw amount.
   */
  fun recurringAmountInDefault(
    rec: Recurring,
    defaultCurrency: String,
    rates: RateTable?,
  ): Double {
    val currency = rec.currency
    if (currency == null || currency == defaultCurrency) return rec.amount
    val sourceMinor = rec.amountMinor ?: toMinorUnits(rec.amount, currency)
    val converted = convertMinor(sourceMinor, currency, defaultCurrency, rates) ?: return rec.amount
    return toMajorUnits(converted, defaultCurrency)
  }

  /**
   * A stored transaction's [amountMinor] in major units of [defaultCurrency].
   * Legacy rows without a currency are treated as already in the account default.
   */
  fun transactionAmountInDefault(
    amountMinor: Long,
    currency: String?,
    defaultCurrency: String,
    rates: RateTable?,
  ): Double {
    val code = currency ?: defaultCurrency
    if (code == defaultCurrency) return toMajorUnits(amountMinor, code)
    val converted =
      convertMinor(amountMinor, code, defaultCurrency, rates)
        ?: return toMajorUnits(amountMinor, code)
    return toMajorUnits(converted, defaultCurrency)
  }
}
