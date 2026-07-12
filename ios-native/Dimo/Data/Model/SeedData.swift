import Foundation

enum SeedData {
  static let cashPaymentMethod = PaymentMethodEntity(
    id: "payment-method-cash",
    name: "Cash",
    type: .Cash,
    detail: "",
    archived: false
  )

  static let defaultPreferences = PreferencesEntity(
    id: "preferences",
    profileName: "",
    profileEmail: "",
    currency: .INR,
    weekStart: .Mon,
    theme: .light,
    navGlassOpacity: 40,
    defaultView: .home,
    defaultStatsRange: .oneYear,
    notifications: NotificationSettings(bills: true, budget: true, weekly: false, large: true),
    defaultPaymentMethodId: cashPaymentMethod.id
  )
}
