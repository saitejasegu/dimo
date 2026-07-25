package app.dimo.android.data

import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.PaymentMethodEntity
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.PreferencesEntity
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart

/**
 * Port of `ios-native/Dimo/Data/Model/SeedData.swift`.
 *
 * A fresh database seeds only Cash and default preferences — never categories.
 */
object SeedData {
  val CASH_PAYMENT_METHOD = PaymentMethodEntity(
    id = "payment-method-cash",
    name = "Cash",
    type = PaymentMethodType.CASH,
    detail = "",
    archived = false,
  )

  val DEFAULT_PREFERENCES = PreferencesEntity(
    id = "preferences",
    profileName = "",
    profileEmail = "",
    currency = Currency.INR,
    weekStart = WeekStart.MON,
    theme = ThemePreference.LIGHT,
    navGlassOpacity = 40,
    defaultView = ViewKey.HOME,
    defaultStatsRange = StatsRange.ONE_YEAR,
    notifications = NotificationSettings(bills = true, budget = true, weekly = false, large = true),
    defaultPaymentMethodId = CASH_PAYMENT_METHOD.id,
  )
}
