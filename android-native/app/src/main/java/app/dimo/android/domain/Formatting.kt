package app.dimo.android.domain

import app.dimo.android.data.model.Currency
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

object Formatting {
  fun symbol(currency: Currency): String = when (currency) {
    Currency.INR -> "₹"
    Currency.USD -> "$"
    Currency.EUR -> "€"
  }

  fun money(amount: Double, currency: Currency): String {
    val sign = if (amount < 0) "−" else ""
    val absAmount = abs(amount)
    val frac = if (abs(absAmount - absAmount.roundToInt()) < 0.0001) 0 else 2
    val formatted = String.format(Locale("en", "IN"), "%,.${frac}f", absAmount)
    return "$sign${symbol(currency)}$formatted"
  }

  fun spent(amount: Double, currency: Currency): String = "−${money(abs(amount), currency)}"

  fun percent(value: Double, total: Double): Int =
    if (total <= 0) 0 else ((value / total) * 100).roundToInt()

  fun compactMoney(amount: Double, currency: Currency): String {
    val sym = symbol(currency)
    val absAmount = abs(amount)
    return if (absAmount >= 1000) {
      var k = String.format(Locale.US, "%.1fk", absAmount / 1000.0)
      if (k.endsWith(".0k")) k = k.removeSuffix(".0k") + "k"
      "$sym$k"
    } else {
      money(amount, currency).removePrefix(sym).let { "$sym${it.trimStart('−').trimStart()}" }
        .let { if (amount < 0) "−$it" else it }
    }
  }
}

object Greeting {
  fun greetingFor(dateTime: LocalDateTime = LocalDateTime.now(ZoneId.systemDefault())): String {
    val hour = dateTime.hour
    return when {
      hour < 12 -> "Good morning"
      hour < 17 -> "Good afternoon"
      else -> "Good evening"
    }
  }
}
