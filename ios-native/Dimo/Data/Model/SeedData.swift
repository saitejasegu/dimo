import Foundation

enum SeedData {
  static let defaultCategories: [CategoryEntity] = [
    CategoryEntity(
      id: "category-dining", name: "Dining", emoji: "🍽️",
      monthlyBudgetMinor: nil, tint: .green, sortOrder: 0, system: true
    ),
    CategoryEntity(
      id: "category-groceries", name: "Groceries", emoji: "🛒",
      monthlyBudgetMinor: nil, tint: .neutral, sortOrder: 1, system: true
    ),
    CategoryEntity(
      id: "category-bills", name: "Bills", emoji: "📄",
      monthlyBudgetMinor: nil, tint: .green, sortOrder: 2, system: true
    ),
    CategoryEntity(
      id: "category-transit", name: "Transit", emoji: "🚌",
      monthlyBudgetMinor: nil, tint: .neutral, sortOrder: 3, system: true
    ),
    CategoryEntity(
      id: "category-shopping", name: "Shopping", emoji: "🛍️",
      monthlyBudgetMinor: nil, tint: .neutral, sortOrder: 4, system: true
    ),
  ]

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
