package app.dimo.android.data

import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.domain.DateHelpers
import java.time.LocalDate
import kotlin.math.max

/**
 * Port of `ios-native/Dimo/Data/PayloadSanitizer.swift`, minus the `emailMessage`
 * branch (Android is not an email writer).
 *
 * Every local write goes through this so the same normalization runs before the
 * row is persisted and before it is enqueued for Convex.
 */
object PayloadSanitizer {
  private val ANCHOR_DATE = Regex("^\\d{4}-\\d{2}-\\d{2}$")

  fun sanitize(payload: EntityPayload, now: Long = System.currentTimeMillis()): EntityPayload =
    when (payload) {
      is EntityPayload.Category -> {
        val value = payload.value
        EntityPayload.Category(
          value.copy(
            emoji = value.emoji.ifEmpty { DEFAULT_CATEGORY_EMOJI },
            tint = if (value.tint == CategoryTint.GREEN) CategoryTint.GREEN else CategoryTint.NEUTRAL,
          ),
        )
      }

      is EntityPayload.PaymentMethod -> {
        // Every PaymentMethodType constant is allowed; decoding already falls back
        // to Cash for unknown wire values.
        payload
      }

      is EntityPayload.Transaction -> {
        val value = payload.value
        val occurredAt = if (value.occurredAt == 0L) now else value.occurredAt
        val currency = value.currency?.trim()
        val sourceCurrency = value.sourceCurrency?.trim()
        val hasSource = !sourceCurrency.isNullOrEmpty()
        val paymentMethodId = value.paymentMethodId?.trim()
        EntityPayload.Transaction(
          value.copy(
            amountMinor = max(1L, value.amountMinor),
            occurredAt = occurredAt,
            paymentMethodId = if (!paymentMethodId.isNullOrEmpty()) {
              paymentMethodId
            } else {
              SeedData.CASH_PAYMENT_METHOD.id
            },
            currency = if (!currency.isNullOrEmpty()) currency else null,
            sourceCurrency = if (hasSource) sourceCurrency else null,
            sourceAmountMinor = if (hasSource) max(1L, value.sourceAmountMinor ?: 0L) else null,
            exchangeRate = if (hasSource) value.exchangeRate else null,
          ),
        )
      }

      is EntityPayload.Recurring -> {
        val value = payload.value
        val validAnchor = ANCHOR_DATE.matches(value.anchorDate)
        val recurringCurrency = value.currency?.trim()
        val paymentMethodId = value.paymentMethodId?.trim()
        EntityPayload.Recurring(
          value.copy(
            amountMinor = max(1L, value.amountMinor),
            paymentMethodId = if (!paymentMethodId.isNullOrEmpty()) {
              paymentMethodId
            } else {
              SeedData.CASH_PAYMENT_METHOD.id
            },
            frequency = if (value.frequency == RecurringFrequency.YEARLY) {
              RecurringFrequency.YEARLY
            } else {
              RecurringFrequency.MONTHLY
            },
            anchorDate = if (validAnchor) {
              value.anchorDate
            } else {
              DateHelpers.localDateKey(LocalDate.now(DateHelpers.zone()))
            },
            currency = if (!recurringCurrency.isNullOrEmpty()) recurringCurrency else null,
          ),
        )
      }

      is EntityPayload.Lend -> {
        val value = payload.value
        val occurredAt = if (value.occurredAt == 0L) now else value.occurredAt
        val contactId = value.contactId.trim()
        EntityPayload.Lend(
          value.copy(
            contactId = contactId.ifEmpty { value.contactName },
            amountMinor = max(1L, value.amountMinor),
            occurredAt = occurredAt,
            kind = value.kind ?: LendKind.LENT,
          ),
        )
      }

      is EntityPayload.Preferences -> {
        val value = payload.value
        val allowedRanges = setOf(
          StatsRange.ONE_WEEK,
          StatsRange.MONTH,
          StatsRange.THREE_MONTHS,
          StatsRange.SIX_MONTHS,
          StatsRange.ONE_YEAR,
          StatsRange.TWO_YEARS,
        )
        EntityPayload.Preferences(
          value.copy(
            id = "preferences",
            currency = if (value.currency == Currency.USD || value.currency == Currency.EUR) {
              value.currency
            } else {
              Currency.INR
            },
            weekStart = if (value.weekStart == WeekStart.SUN) WeekStart.SUN else WeekStart.MON,
            theme = value.theme.takeIf {
              it == ThemePreference.LIGHT || it == ThemePreference.DARK || it == ThemePreference.SYSTEM
            } ?: ThemePreference.LIGHT,
            navGlassOpacity = value.navGlassOpacity.coerceIn(40, 100),
            // preferences.defaultView is currently normalized to home on every client.
            defaultView = ViewKey.HOME,
            defaultStatsRange = if (allowedRanges.contains(value.defaultStatsRange)) {
              value.defaultStatsRange
            } else {
              StatsRange.ONE_YEAR
            },
            defaultPaymentMethodId = value.defaultPaymentMethodId.ifEmpty {
              SeedData.CASH_PAYMENT_METHOD.id
            },
          ),
        )
      }
    }
}
