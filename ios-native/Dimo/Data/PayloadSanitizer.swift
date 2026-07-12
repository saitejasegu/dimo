import Foundation

enum PayloadSanitizer {
  static func sanitize(entityType: EntityType, payload: EntityPayload) -> EntityPayload {
    switch entityType {
    case .category:
      guard case .category(let value) = payload else { return payload }
      return .category(CategoryEntity(
        id: value.id,
        name: value.name,
        emoji: value.emoji.isEmpty ? defaultCategoryEmoji : value.emoji,
        monthlyBudgetMinor: value.monthlyBudgetMinor.map { Int(Double($0).rounded()) },
        tint: value.tint == .green ? .green : .neutral,
        sortOrder: value.sortOrder,
        system: value.system
      ))

    case .paymentMethod:
      guard case .paymentMethod(let value) = payload else { return payload }
      let allowed: Set<PaymentMethodType> = [.UPI, .Card, .Wallet, .Cash, .Bank]
      return .paymentMethod(PaymentMethodEntity(
        id: value.id,
        name: value.name,
        type: allowed.contains(value.type) ? value.type : .Cash,
        detail: value.detail,
        archived: value.archived
      ))

    case .transaction:
      guard case .transaction(let value) = payload else { return payload }
      var occurredAt = Int(Double(value.occurredAt).rounded())
      if occurredAt == 0 {
        occurredAt = Int(Date().timeIntervalSince1970 * 1000)
      }
      return .transaction(TransactionEntity(
        id: value.id,
        name: value.name,
        amountMinor: max(1, Int(Double(value.amountMinor).rounded())),
        occurredAt: occurredAt,
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId
      ))

    case .recurring:
      guard case .recurring(let value) = payload else { return payload }
      let anchor = value.anchorDate
      let validAnchor = anchor.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
      return .recurring(RecurringEntity(
        id: value.id,
        name: value.name,
        amountMinor: max(1, Int(Double(value.amountMinor).rounded())),
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId,
        frequency: value.frequency == .yearly ? .yearly : .monthly,
        anchorDate: validAnchor ? anchor : DateHelpers.localDateKey(Date()),
        paused: value.paused
      ))

    case .preferences:
      guard case .preferences(let value) = payload else { return payload }
      let allowedRanges: Set<StatsRange> = [.oneWeek, .month, .threeMonths, .sixMonths, .oneYear, .twoYears]
      let theme: ThemePreference =
        (value.theme == .light || value.theme == .dark || value.theme == .system) ? value.theme : .light
      return .preferences(PreferencesEntity(
        id: "preferences",
        profileName: value.profileName,
        profileEmail: value.profileEmail,
        currency: (value.currency == .USD || value.currency == .EUR) ? value.currency : .INR,
        weekStart: value.weekStart == .Sun ? .Sun : .Mon,
        theme: theme,
        navGlassOpacity: min(100, max(40, value.navGlassOpacity)),
        defaultView: .home,
        defaultStatsRange: allowedRanges.contains(value.defaultStatsRange) ? value.defaultStatsRange : .oneYear,
        notifications: value.notifications,
        defaultPaymentMethodId: value.defaultPaymentMethodId.isEmpty
          ? SeedData.cashPaymentMethod.id
          : value.defaultPaymentMethodId
      ))
    }
  }
}
