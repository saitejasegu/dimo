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
      let sourceCurrency = value.sourceCurrency?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hasSource = (sourceCurrency?.isEmpty == false)
      return .transaction(TransactionEntity(
        id: value.id,
        name: value.name,
        amountMinor: max(1, Int(Double(value.amountMinor).rounded())),
        occurredAt: occurredAt,
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId,
        sourceCurrency: hasSource ? sourceCurrency : nil,
        sourceAmountMinor: hasSource ? max(1, Int(Double(value.sourceAmountMinor ?? 0).rounded())) : nil,
        exchangeRate: hasSource ? value.exchangeRate : nil
      ))

    case .recurring:
      guard case .recurring(let value) = payload else { return payload }
      let anchor = value.anchorDate
      let validAnchor = anchor.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
      let recurringCurrency = value.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
      return .recurring(RecurringEntity(
        id: value.id,
        name: value.name,
        amountMinor: max(1, Int(Double(value.amountMinor).rounded())),
        categoryId: value.categoryId,
        paymentMethodId: value.paymentMethodId,
        frequency: value.frequency == .yearly ? .yearly : .monthly,
        anchorDate: validAnchor ? anchor : DateHelpers.localDateKey(Date()),
        paused: value.paused,
        currency: (recurringCurrency?.isEmpty == false) ? recurringCurrency : nil
      ))

    case .lend:
      guard case .lend(let value) = payload else { return payload }
      var occurredAt = Int(Double(value.occurredAt).rounded())
      if occurredAt == 0 {
        occurredAt = Int(Date().timeIntervalSince1970 * 1000)
      }
      let contactId = value.contactId.trimmingCharacters(in: .whitespacesAndNewlines)
      return .lend(LendEntity(
        id: value.id,
        contactName: value.contactName,
        contactId: contactId.isEmpty ? value.contactName : contactId,
        amountMinor: max(1, Int(Double(value.amountMinor).rounded())),
        occurredAt: occurredAt,
        comment: value.comment,
        kind: value.kind ?? .lent
      ))

    case .emailMessage:
      guard case .emailMessage(let value) = payload else { return payload }
      let allowedStates: Set<String> = [
        EmailSuggestionState.added.rawValue,
        EmailSuggestionState.dismissed.rawValue,
        EmailSuggestionState.refundApplied.rawValue,
        EmailSuggestionState.pendingPurchase.rawValue,
        EmailSuggestionState.pendingRefund.rawValue,
      ]
      let nonempty: (String?) -> String? = { raw in
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
      }
      return .emailMessage(EmailMessageEntity(
        id: value.id,
        accountId: value.accountId.trimmingCharacters(in: .whitespacesAndNewlines),
        accountEmail: value.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines),
        gmailMessageId: value.gmailMessageId.trimmingCharacters(in: .whitespacesAndNewlines),
        threadId: value.threadId.trimmingCharacters(in: .whitespacesAndNewlines),
        rfcMessageId: nonempty(value.rfcMessageId),
        senderName: nonempty(value.senderName),
        senderAddress: value.senderAddress.trimmingCharacters(in: .whitespacesAndNewlines),
        subject: value.subject,
        snippet: value.snippet,
        internalDate: Int(Double(value.internalDate).rounded()),
        normalizedBodyText: value.normalizedBodyText,
        analyzerType: nonempty(value.analyzerType),
        modelVersion: nonempty(value.modelVersion),
        promptVersion: value.promptVersion.map { Int(Double($0).rounded()) },
        classification: nonempty(value.classification),
        merchant: nonempty(value.merchant),
        amount: nonempty(value.amount),
        currency: nonempty(value.currency),
        occurredAt: value.occurredAt.map { Int(Double($0).rounded()) },
        categoryId: nonempty(value.categoryId),
        paymentMethodId: nonempty(value.paymentMethodId),
        paymentLastFour: nonempty(value.paymentLastFour),
        reference: nonempty(value.reference),
        state: allowedStates.contains(value.state) ? value.state : EmailSuggestionState.dismissed.rawValue,
        linkedTransactionId: nonempty(value.linkedTransactionId),
        analyzedAt: value.analyzedAt.map { Int(Double($0).rounded()) },
        reviewedAt: value.reviewedAt.map { Int(Double($0).rounded()) },
        createdAt: Int(Double(value.createdAt).rounded()),
        updatedAt: Int(Double(value.updatedAt).rounded())
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
