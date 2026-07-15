package app.dimo.android.data

import app.dimo.android.data.model.CASH_PAYMENT_METHOD_ID
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.NAV_GLASS_OPACITY_MAX
import app.dimo.android.data.model.NAV_GLASS_OPACITY_MIN
import app.dimo.android.data.model.PREFERENCES_ID
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.domain.DateHelpers
import kotlin.math.max
import kotlin.math.roundToInt

object PayloadSanitizer {
  private val anchorRegex = Regex("""^\d{4}-\d{2}-\d{2}$""")

  fun sanitize(type: EntityType, payload: EntityPayload): EntityPayload = when (type) {
    EntityType.Category -> {
      val c = payload as EntityPayload.Category
      c.copy(
        emoji = c.emoji.ifBlank { DEFAULT_CATEGORY_EMOJI },
        monthlyBudgetMinor = c.monthlyBudgetMinor?.toDouble()?.roundToInt(),
        tint = if (c.tint == CategoryTint.green) CategoryTint.green else CategoryTint.neutral,
      )
    }
    EntityType.PaymentMethod -> {
      val p = payload as EntityPayload.PaymentMethod
      val type = PaymentMethodType.entries.firstOrNull { it.name == p.type.name }
        ?: PaymentMethodType.Cash
      p.copy(type = type)
    }
    EntityType.Transaction -> {
      val t = payload as EntityPayload.Transaction
      val amount = max(1, t.amountMinor.toDouble().roundToInt())
      val occurred = if (t.occurredAt == 0L) System.currentTimeMillis() else t.occurredAt.toDouble().roundToLong()
      t.copy(amountMinor = amount, occurredAt = occurred)
    }
    EntityType.Recurring -> {
      val r = payload as EntityPayload.Recurring
      val amount = max(1, r.amountMinor.toDouble().roundToInt())
      val freq = if (r.frequency == RecurringFrequency.yearly) RecurringFrequency.yearly else RecurringFrequency.monthly
      val anchor = if (anchorRegex.matches(r.anchorDate)) r.anchorDate else DateHelpers.localDateKey()
      r.copy(amountMinor = amount, frequency = freq, anchorDate = anchor)
    }
    EntityType.Lend -> {
      val l = payload as EntityPayload.Lend
      val amount = max(1, l.amountMinor.toDouble().roundToInt())
      val occurred = if (l.occurredAt == 0L) System.currentTimeMillis() else l.occurredAt.toDouble().roundToLong()
      val contactId = l.contactId.trim().ifEmpty { l.contactName }
      val kind = l.kind ?: LendKind.lent
      l.copy(amountMinor = amount, occurredAt = occurred, contactId = contactId, kind = kind)
    }
    EntityType.Preferences -> {
      val p = payload as EntityPayload.Preferences
      val currency = when (p.currency) {
        Currency.USD, Currency.EUR -> p.currency
        else -> Currency.INR
      }
      val weekStart = if (p.weekStart == WeekStart.Sun) WeekStart.Sun else WeekStart.Mon
      val theme = when (p.theme) {
        ThemePreference.light, ThemePreference.dark, ThemePreference.system -> p.theme
        else -> ThemePreference.light
      }
      val opacity = p.navGlassOpacity.coerceIn(NAV_GLASS_OPACITY_MIN, NAV_GLASS_OPACITY_MAX)
      val stats = StatsRange.fromWire(p.defaultStatsRange.wire)
      val pm = p.defaultPaymentMethodId.ifBlank { CASH_PAYMENT_METHOD_ID }
      p.copy(
        id = PREFERENCES_ID,
        defaultView = ViewKey.home,
        currency = currency,
        weekStart = weekStart,
        theme = theme,
        navGlassOpacity = opacity,
        defaultStatsRange = stats,
        defaultPaymentMethodId = pm,
      )
    }
  }

  private fun Double.roundToLong(): Long = roundToInt().toLong()
}
