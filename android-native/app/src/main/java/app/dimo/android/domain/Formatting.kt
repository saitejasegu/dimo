package app.dimo.android.domain

import app.dimo.android.data.model.Currency
import java.text.NumberFormat
import java.time.LocalTime
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Port of `ios-native/Dimo/Domain/Formatting.swift`.
 *
 * The Swift implementation pins `NumberFormatter` to `en_IN`, which produces the
 * lakh/crore grouping (`₹1,00,000`). Keep that locale so all three clients render
 * identical strings.
 */
object Formatting {
  private val INDIAN_LOCALE: Locale = Locale.forLanguageTag("en-IN")

  private val symbols = mapOf(
    Currency.INR to "₹",
    Currency.USD to "$",
    Currency.EUR to "€",
  )

  fun currencySymbol(currency: Currency = Currency.INR): String = symbols[currency] ?: "₹"

  fun money(amount: Double, currency: Currency = Currency.INR): String =
    moneyWithSymbol(amount, currencySymbol(currency))

  /** Format money for any currency code (default or a foreign entry currency). */
  fun money(amount: Double, currencyCode: String): String =
    moneyWithSymbol(amount, CurrencyMeta.symbol(currencyCode))

  fun decimal(value: Double, maximumFractionDigits: Int): String {
    val formatter = NumberFormat.getNumberInstance(INDIAN_LOCALE)
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.format(value)
  }

  private fun moneyWithSymbol(amount: Double, symbol: String): String {
    val hasFraction = abs(amount % 1) > 0.0001
    val formatter = NumberFormat.getNumberInstance(INDIAN_LOCALE)
    formatter.minimumFractionDigits = if (hasFraction) 2 else 0
    formatter.maximumFractionDigits = 2
    val formatted = formatter.format(abs(amount))
    // U+2212 MINUS SIGN, matching the Swift implementation.
    return (if (amount < 0) "−" else "") + symbol + formatted
  }

  fun spent(amount: Double, currency: Currency = Currency.INR): String =
    "−" + money(amount, currency)

  fun percent(value: Double, total: Double): Int {
    if (total <= 0) return 0
    return (value / total * 100).roundToInt()
  }

  fun compactMoney(amount: Double, currency: Currency = Currency.INR): String {
    val symbol = currencySymbol(currency)
    if (amount >= 1000) {
      val k = String.format(Locale.ROOT, "%.1f", amount / 1000).replace(".0", "")
      return "$symbol${k}k"
    }
    val trimmed = String.format(Locale.ROOT, "%.2f", amount).replace(Regex("\\.?0+$"), "")
    return "$symbol$trimmed"
  }
}

object Greeting {
  fun greetingFor(time: LocalTime = LocalTime.now(DateHelpers.zone())): String {
    val hour = time.hour
    if (hour < 12) return "Good morning"
    if (hour < 17) return "Good afternoon"
    return "Good evening"
  }
}
