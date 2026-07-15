package app.dimo.android.data.model

object SeedData {
  val cash = EntityPayload.PaymentMethod(
    id = CASH_PAYMENT_METHOD_ID,
    name = "Cash",
    type = PaymentMethodType.Cash,
    detail = "",
    archived = false,
  )

  val defaultPreferences = EntityPayload.Preferences(
    id = PREFERENCES_ID,
    profileName = "",
    profileEmail = "",
    currency = Currency.INR,
    weekStart = WeekStart.Mon,
    theme = ThemePreference.light,
    navGlassOpacity = NAV_GLASS_OPACITY_MIN,
    defaultView = ViewKey.home,
    defaultStatsRange = StatsRange.OneYear,
    notifications = NotificationsPrefs(),
    defaultPaymentMethodId = CASH_PAYMENT_METHOD_ID,
  )
}
