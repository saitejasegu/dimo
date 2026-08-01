import Foundation

/// Per-type content fingerprints so unchanged entity types can skip remapping.
struct EntityTypeFingerprints: Equatable, Sendable {
  var category: Int
  var paymentMethod: Int
  var transaction: Int
  var recurring: Int
  var lend: Int
  /// Full preferences payload — theme, notifications, glass opacity, etc.
  var preferences: Int
  /// Currency + default payment method only — fields that rematerialize money projections.
  var preferencesProjection: Int

  static let empty = EntityTypeFingerprints(
    category: 0,
    paymentMethod: 0,
    transaction: 0,
    recurring: 0,
    lend: 0,
    preferences: 0,
    preferencesProjection: 0
  )

  /// One pass with six hashers, rather than six passes over the whole batch.
  static func compute(_ entities: [StoredEntity]) -> EntityTypeFingerprints {
    var hashers: [EntityType: Hasher] = [:]
    var counts: [EntityType: Int] = [:]
    var preferencesProjectionHasher = Hasher()
    for type in [EntityType.category, .paymentMethod, .transaction, .recurring, .lend, .preferences] {
      hashers[type] = Hasher()
      counts[type] = 0
    }

    for entity in entities {
      let type = entity.entityType
      guard var hasher = hashers[type] else { continue }
      counts[type, default: 0] += 1
      hasher.combine(entity.entityId)
      hasher.combine(entity.version.timestamp)
      hasher.combine(entity.version.counter)
      hasher.combine(entity.deleted)
      // Category and preference *content* feeds other types' projections, so their
      // payloads participate in the hash; the rest change their logical version.
      if type == .preferences || type == .category {
        hasher.combine(entity.payload)
      }
      if type == .preferences, case .preferences(let prefs) = entity.payload {
        preferencesProjectionHasher.combine(prefs.currency)
        preferencesProjectionHasher.combine(prefs.defaultPaymentMethodId)
      }
      hashers[type] = hasher
    }

    func finalize(_ type: EntityType) -> Int {
      guard var hasher = hashers[type] else { return 0 }
      hasher.combine(counts[type] ?? 0)
      return hasher.finalize()
    }

    preferencesProjectionHasher.combine(counts[.preferences] ?? 0)
    return EntityTypeFingerprints(
      category: finalize(.category),
      paymentMethod: finalize(.paymentMethod),
      transaction: finalize(.transaction),
      recurring: finalize(.recurring),
      lend: finalize(.lend),
      preferences: finalize(.preferences),
      preferencesProjection: preferencesProjectionHasher.finalize()
    )
  }

  /// Types whose display projection depends on FX / category / payment labels.
  func emailRelevantChanges(from previous: EntityTypeFingerprints) -> Bool {
    category != previous.category
      || paymentMethod != previous.paymentMethod
      || transaction != previous.transaction
      || preferencesProjection != previous.preferencesProjection
  }

  func transactionsNeedRebuild(from previous: EntityTypeFingerprints, ratesDateChanged: Bool) -> Bool {
    transaction != previous.transaction
      || category != previous.category
      || paymentMethod != previous.paymentMethod
      || preferencesProjection != previous.preferencesProjection
      || ratesDateChanged
  }

  func recurringNeedsRebuild(from previous: EntityTypeFingerprints, ratesDateChanged: Bool) -> Bool {
    recurring != previous.recurring
      || category != previous.category
      || preferencesProjection != previous.preferencesProjection
      || ratesDateChanged
  }

  func paymentMethodsNeedRebuild(from previous: EntityTypeFingerprints) -> Bool {
    paymentMethod != previous.paymentMethod
      || preferencesProjection != previous.preferencesProjection
  }
}

/// UI-ready entity projections produced off the main actor.
struct EntitySnapshot: Equatable, Sendable {
  var fingerprints: EntityTypeFingerprints
  var ratesDate: String?
  var categories: [CategoryEntity]
  var paymentMethods: [PaymentMethodOption]
  var limits: CategoryLimits
  var transactions: [Transaction]
  var recurring: [Recurring]
  var lends: [Lend]
  var preferences: PreferencesEntity
  var statsRange: StatsRange
  var profileName: String
  var profileEmail: String
}

/// Which derived slices must be recomputed. Fingerprint-gated so lend-only edits
/// do not rescan budgets / upcoming.
struct DeriveDirtyFlags: Sendable {
  var budgets: Bool
  var lends: Bool
  var upcoming: Bool

  static let all = DeriveDirtyFlags(budgets: true, lends: true, upcoming: true)

  static func from(
    previous: EntitySnapshot?,
    next: EntitySnapshot
  ) -> DeriveDirtyFlags {
    guard let previous else { return .all }
    let fp = next.fingerprints
    let prev = previous.fingerprints
    let txOrLimitsChanged =
      fp.transaction != prev.transaction
      || fp.category != prev.category
      || fp.preferencesProjection != prev.preferencesProjection
      || previous.ratesDate != next.ratesDate
      || previous.limits != next.limits
    return DeriveDirtyFlags(
      budgets: txOrLimitsChanged,
      lends: fp.lend != prev.lend,
      upcoming: fp.transaction != prev.transaction
        || fp.recurring != prev.recurring
        || fp.preferencesProjection != prev.preferencesProjection
        || previous.ratesDate != next.ratesDate
    )
  }
}

/// Projections needed by Home, Budgets and Lending. Computed on every hydrate because
/// the tab bar can show any of them without warning.
struct DerivedSnapshot: Equatable, Sendable {
  var monthBudgetTotals: BudgetTotals
  var categoryBudgets: [CategoryBudget]
  var suggestedBudgetUpdates: [SuggestedCategoryBudgetUpdate]
  var lendSummaries: [LendContactSummary]
  var lendTotals: LendTotals
  var upcomingThisMonth: [Recurring]
  var upcomingAll: [Recurring]
  var upcomingThisMonthTotal: Double
  var upcomingAllTotal: Double

  static let empty = DerivedSnapshot(
    monthBudgetTotals: BudgetTotals(
      totalSpent: 0, totalLimit: 0, pct: 0, left: 0, over: false, transactionCount: 0
    ),
    categoryBudgets: [],
    suggestedBudgetUpdates: [],
    lendSummaries: [],
    lendTotals: .zero,
    upcomingThisMonth: [],
    upcomingAll: [],
    upcomingThisMonthTotal: 0,
    upcomingAllTotal: 0
  )
}

/// Stats-tab projections. The most expensive part of hydrate (range scoping, per-month
/// grouping, merchant aggregation) and useless until the Stats tab is on screen, so it
/// is computed on demand and cached against its inputs.
struct StatsSnapshot: Equatable, Sendable {
  var scope: StatsScope
  var trendBars: MonthBars
  var categories: [StatCategory]
  var categoriesTotal: Int
  var merchants: [MerchantStat]
  var merchantsTotal: Int

  static let empty = StatsSnapshot(
    scope: StatsScope(
      rangeMonths: 12,
      scopeTotal: 0,
      scopePast: 0,
      spentLabel: "",
      averageLabel: "",
      transactions: []
    ),
    trendBars: MonthBars(visible: false, title: "", caption: "", bars: []),
    categories: [],
    categoriesTotal: 0,
    merchants: [],
    merchantsTotal: 0
  )
}

/// Identifies a stats projection so an unchanged one is never recomputed.
struct StatsInputs: Equatable, Sendable {
  var revision: UInt64
  var range: StatsRange
  var selectedMonth: String?
  var categoriesExpanded: Bool
  var merchantsExpanded: Bool
}

/// Builds display models away from the main thread. Owns its own DateFormatters
/// so hydrate never contends with UI formatters.
enum EntityHydrator {
  private static let queue = DispatchQueue(label: "app.dimo.entity-hydrator", qos: .userInitiated)
  /// Cap expanded stats lists so "See all" cannot lay out unbounded rows.
  static let expandedStatsLimit = 50

  static func project(
    entities: [StoredEntity],
    rates: RateTable?,
    currentStatsRange: StatsRange,
    previousDefaultStatsRange: StatsRange,
    dataReady: Bool,
    profileName: String,
    profileEmail: String,
    previous: EntitySnapshot?
  ) async -> EntitySnapshot? {
    await withCheckedContinuation { continuation in
      queue.async {
        let fingerprints = EntityTypeFingerprints.compute(entities)
        let ratesDate = rates?.date
        // Skip rebuild when entity content and FX table are unchanged.
        if let previous,
           previous.fingerprints == fingerprints,
           previous.ratesDate == ratesDate {
          continuation.resume(returning: nil)
          return
        }

        let snapshot = build(
          entities: entities,
          fingerprints: fingerprints,
          rates: rates,
          ratesDate: ratesDate,
          currentStatsRange: currentStatsRange,
          previousDefaultStatsRange: previousDefaultStatsRange,
          dataReady: dataReady,
          profileName: profileName,
          profileEmail: profileEmail,
          previous: previous
        )
        continuation.resume(returning: snapshot)
      }
    }
  }

  static func derive(
    transactions: [Transaction],
    recurring: [Recurring],
    lends: [Lend],
    limits: CategoryLimits,
    categories: [CategoryEntity],
    rates: RateTable?,
    defaultCurrency: String,
    previous: DerivedSnapshot?,
    dirty: DeriveDirtyFlags
  ) async -> DerivedSnapshot {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: buildDerived(
            transactions: transactions,
            recurring: recurring,
            lends: lends,
            limits: limits,
            categories: categories,
            rates: rates,
            defaultCurrency: defaultCurrency,
            previous: previous,
            dirty: dirty
          )
        )
      }
    }
  }

  /// Stats projections, off the main actor. Only called while the Stats tab is on
  /// screen or its controls change.
  static func deriveStats(
    transactions: [Transaction],
    statsRange: StatsRange,
    selectedMonth: String?,
    categoriesExpanded: Bool,
    merchantsExpanded: Bool
  ) async -> StatsSnapshot {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: buildStats(
            transactions: transactions,
            statsRange: statsRange,
            selectedMonth: selectedMonth,
            categoriesExpanded: categoriesExpanded,
            merchantsExpanded: merchantsExpanded
          )
        )
      }
    }
  }

  static func buildStats(
    transactions: [Transaction],
    statsRange: StatsRange,
    selectedMonth: String?,
    categoriesExpanded: Bool,
    merchantsExpanded: Bool
  ) -> StatsSnapshot {
    let scope = StatsSelectors.statsScope(range: statsRange, transactions: transactions)
    let trendBars = StatsSelectors.trendBars(
      range: statsRange,
      transactions: scope.transactions,
      selectedKey: selectedMonth
    )
    let cats = StatsSelectors.statCategories(
      scope: scope,
      limit: categoriesExpanded ? expandedStatsLimit : 5
    )
    let merchants = StatsSelectors.topMerchants(
      scope: scope,
      limit: merchantsExpanded ? expandedStatsLimit : 5
    )
    return StatsSnapshot(
      scope: scope,
      trendBars: trendBars,
      categories: cats.categories,
      categoriesTotal: cats.total,
      merchants: merchants.merchants,
      merchantsTotal: merchants.total
    )
  }

  static func buildDerived(
    transactions: [Transaction],
    recurring: [Recurring],
    lends: [Lend],
    limits: CategoryLimits,
    categories: [CategoryEntity],
    rates: RateTable?,
    defaultCurrency: String,
    previous: DerivedSnapshot?,
    dirty: DeriveDirtyFlags
  ) -> DerivedSnapshot {
    var result = previous ?? .empty

    if dirty.budgets || previous == nil {
      result.monthBudgetTotals = BudgetSelectors.budgetTotals(transactions, limits: limits)
      result.categoryBudgets = BudgetSelectors.categoryBudgets(transactions, limits: limits)
      result.suggestedBudgetUpdates = BudgetSelectors.suggestedCategoryBudgetUpdates(
        transactions,
        categories: categories.map { ($0.id, $0.name, $0.monthlyBudgetMinor) }
      )
    }

    if dirty.lends || previous == nil {
      let summaries = LendSelectors.contactSummaries(lends)
      result.lendSummaries = summaries
      result.lendTotals = LendSelectors.totals(from: summaries)
    }

    if dirty.upcoming || previous == nil {
      let recordedIDs = RecurringSelectors.recordedOccurrenceIDs(transactions)
      result.upcomingThisMonth = RecurringSelectors.upcomingBills(recurring, recordedIDs: recordedIDs)
      result.upcomingAll = RecurringSelectors.allUpcomingBills(recurring, recordedIDs: recordedIDs)
      result.upcomingThisMonthTotal = upcomingTotal(
        result.upcomingThisMonth,
        defaultCurrency: defaultCurrency,
        rates: rates
      )
      result.upcomingAllTotal = upcomingTotal(
        result.upcomingAll,
        defaultCurrency: defaultCurrency,
        rates: rates
      )
    }

    return result
  }

  private static func upcomingTotal(
    _ items: [Recurring],
    defaultCurrency: String,
    rates: RateTable?
  ) -> Double {
    items.reduce(0) { total, item in
      total + (item.paused
        ? 0
        : ExchangeRates.recurringAmountInDefault(
            item,
            defaultCurrency: defaultCurrency,
            rates: rates
          ))
    }
  }

  private static func build(
    entities: [StoredEntity],
    fingerprints: EntityTypeFingerprints,
    rates: RateTable?,
    ratesDate: String?,
    currentStatsRange: StatsRange,
    previousDefaultStatsRange: StatsRange,
    dataReady: Bool,
    profileName: String,
    profileEmail: String,
    previous: EntitySnapshot?
  ) -> EntitySnapshot {
    let prevFp = previous?.fingerprints
    let ratesDateChanged = previous?.ratesDate != ratesDate
    let rebuildCategories = prevFp.map { $0.category != fingerprints.category } ?? true
    let rebuildPaymentMethods =
      prevFp.map { fingerprints.paymentMethodsNeedRebuild(from: $0) } ?? true
    let rebuildTransactions =
      prevFp.map { fingerprints.transactionsNeedRebuild(from: $0, ratesDateChanged: ratesDateChanged) }
      ?? true
    let rebuildRecurring =
      prevFp.map { fingerprints.recurringNeedsRebuild(from: $0, ratesDateChanged: ratesDateChanged) }
      ?? true
    let rebuildLends = prevFp.map { $0.lend != fingerprints.lend } ?? true
    let rebuildPreferences = prevFp.map { $0.preferences != fingerprints.preferences } ?? true

    var nextCategories: [CategoryEntity] = []
    var nextPaymentMethods: [PaymentMethodEntity] = []
    var nextTransactions: [TransactionEntity] = []
    var nextRecurring: [RecurringEntity] = []
    var nextLends: [LendEntity] = []
    var prefs = previous?.preferences ?? SeedData.defaultPreferences

    let needsScan =
      rebuildCategories || rebuildPaymentMethods || rebuildTransactions
      || rebuildRecurring || rebuildLends || rebuildPreferences
    if needsScan {
      for entity in entities where !entity.deleted {
        switch entity.payload {
        case .category(let c):
          if rebuildCategories { nextCategories.append(c) }
        case .paymentMethod(let p):
          if rebuildPaymentMethods { nextPaymentMethods.append(p) }
        case .transaction(let t):
          if rebuildTransactions { nextTransactions.append(t) }
        case .recurring(let r):
          if rebuildRecurring { nextRecurring.append(r) }
        case .lend(let l):
          if rebuildLends { nextLends.append(l) }
        case .emailMessage:
          break
        case .preferences(let p):
          if rebuildPreferences { prefs = p }
        }
      }
    }

    let categories: [CategoryEntity]
    let limits: CategoryLimits
    if rebuildCategories {
      nextCategories.sort { $0.sortOrder < $1.sortOrder }
      categories = nextCategories
      limits = Dictionary(uniqueKeysWithValues: categories.map {
        ($0.name, $0.monthlyBudgetMinor.map { Double($0) / 100 })
      })
    } else {
      categories = previous?.categories ?? []
      limits = previous?.limits ?? [:]
    }

    let paymentMethods: [PaymentMethodOption]
    if rebuildPaymentMethods {
      let defaultPM = prefs.defaultPaymentMethodId
      paymentMethods = nextPaymentMethods
        .sorted { $0.name < $1.name }
        .map {
          PaymentMethodOption(
            id: $0.id, name: $0.name, type: $0.type, detail: $0.detail,
            isDefault: $0.id == defaultPM, archived: $0.archived
          )
        }
    } else {
      paymentMethods = previous?.paymentMethods ?? []
    }

    let categoryById = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    let pmById = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })
    let formatters = Formatters()
    let defaultCurrency = prefs.currency.rawValue

    let transactions: [Transaction]
    if rebuildTransactions {
      transactions = nextTransactions
        .sorted { $0.occurredAt > $1.occurredAt }
        .map { tx -> Transaction in
          let cat = categoryById[tx.categoryId]
          let pm = tx.paymentMethodId.flatMap { pmById[$0] }
          let sourceAmount = tx.sourceCurrency.flatMap { code in
            tx.sourceAmountMinor.map { ExchangeRates.toMajorUnits($0, code) }
          }
          let amountCurrency = tx.currency ?? defaultCurrency
          let categoryName = cat?.name ?? "Unknown"
          return Transaction(
            id: tx.id,
            name: tx.name,
            category: categoryName,
            time: formatters.time(tx.occurredAt),
            day: formatters.day(tx.occurredAt),
            amount: ExchangeRates.transactionAmountInDefault(
              amountMinor: tx.amountMinor,
              currency: tx.currency,
              defaultCurrency: defaultCurrency,
              rates: rates
            ),
            paymentMethod: pm?.label,
            green: cat?.tint == .green,
            emoji: cat?.emoji,
            amountMinor: tx.amountMinor,
            occurredAt: tx.occurredAt,
            categoryId: tx.categoryId,
            paymentMethodId: tx.paymentMethodId,
            currency: amountCurrency,
            sourceCurrency: tx.sourceCurrency,
            sourceAmount: sourceAmount,
            searchText: "\(tx.name) \(categoryName)".lowercased(),
            dayKey: formatters.dayKey(tx.occurredAt)
          )
        }
    } else {
      transactions = previous?.transactions ?? []
    }

    let lends: [Lend]
    if rebuildLends {
      lends = nextLends
        .sorted { $0.occurredAt > $1.occurredAt }
        .map { lend in
          Lend(
            id: lend.id,
            contactName: lend.contactName,
            contactId: lend.contactId,
            amount: Double(lend.amountMinor) / 100,
            comment: lend.comment,
            time: formatters.time(lend.occurredAt),
            day: formatters.day(lend.occurredAt),
            amountMinor: lend.amountMinor,
            occurredAt: lend.occurredAt,
            kind: lend.kind ?? .lent
          )
        }
    } else {
      lends = previous?.lends ?? []
    }

    let recurring: [Recurring]
    if rebuildRecurring {
      nextRecurring.sort {
        DateHelpers.nextOccurrence(anchorDate: $0.anchorDate, frequency: $0.frequency)
          < DateHelpers.nextOccurrence(anchorDate: $1.anchorDate, frequency: $1.frequency)
      }
      recurring = nextRecurring.map { rec -> Recurring in
        let cat = categoryById[rec.categoryId]
        let sourceCurrency = rec.currency
        let convertedEstimateLabel: String?
        if let sourceCurrency, sourceCurrency != defaultCurrency {
          let sourceMinor = rec.amountMinor
          if let convertedMinor = ExchangeRates.convertMinor(
            sourceMinor,
            from: sourceCurrency,
            to: defaultCurrency,
            rates: rates
          ) {
            let converted = ExchangeRates.toMajorUnits(convertedMinor, defaultCurrency)
            convertedEstimateLabel =
              "≈ \(Formatting.money(converted, currencyCode: defaultCurrency)) today"
          } else {
            convertedEstimateLabel = "Rate unavailable"
          }
        } else {
          convertedEstimateLabel = nil
        }
        return Recurring(
          id: rec.id,
          name: rec.name,
          category: cat?.name ?? "",
          due: DateHelpers.recurringDueLabel(anchorDate: rec.anchorDate, frequency: rec.frequency),
          amount: ExchangeRates.toMajorUnits(rec.amountMinor, sourceCurrency ?? defaultCurrency),
          paused: rec.paused,
          green: cat?.tint == .green,
          emoji: cat?.emoji,
          amountMinor: rec.amountMinor,
          categoryId: rec.categoryId,
          paymentMethodId: rec.paymentMethodId,
          anchorDate: rec.anchorDate,
          frequency: rec.frequency,
          currency: rec.currency,
          convertedEstimateLabel: convertedEstimateLabel
        )
      }
    } else {
      recurring = previous?.recurring ?? []
    }

    let statsRange = StatsConstants.hydratedRange(
      current: currentStatsRange,
      previousDefault: previousDefaultStatsRange,
      nextDefault: prefs.defaultStatsRange,
      dataReady: dataReady
    )

    return EntitySnapshot(
      fingerprints: fingerprints,
      ratesDate: ratesDate,
      categories: categories,
      paymentMethods: paymentMethods,
      limits: limits,
      transactions: transactions,
      recurring: recurring,
      lends: lends,
      preferences: prefs,
      statsRange: statsRange,
      profileName: profileName.isEmpty ? prefs.profileName : profileName,
      profileEmail: profileEmail.isEmpty ? prefs.profileEmail : profileEmail
    )
  }

  private struct Formatters {
    let timeFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = .current
      formatter.setLocalizedDateFormatFromTemplate("jmm")
      return formatter
    }()
    let daySameYear: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = .current
      formatter.setLocalizedDateFormatFromTemplate("EEEE MMMd")
      return formatter
    }()
    let dayOtherYear: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = .current
      formatter.setLocalizedDateFormatFromTemplate("EEEE MMMd yyyy")
      return formatter
    }()

    /// Reuses one `Calendar`; `Calendar.current` allocates a fresh value per access,
    /// which is measurable when it runs once per transaction.
    let calendar = Calendar.current

    func time(_ timestamp: Int) -> String {
      let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
      return timeFormatter.string(from: date)
    }

    func dayKey(_ timestamp: Int) -> String {
      DateHelpers.localDateKey(
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000),
        calendar: calendar
      )
    }

    func day(_ timestamp: Int, now: Date = Date(), calendar: Calendar = .current) -> String {
      let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
      let today = DateHelpers.localDateKey(now, calendar: calendar)
      let key = DateHelpers.localDateKey(date, calendar: calendar)
      if key == today { return "Today" }
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else {
        return key
      }
      if key == DateHelpers.localDateKey(yesterday, calendar: calendar) { return "Yesterday" }
      let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
      return (sameYear ? daySameYear : dayOtherYear).string(from: date)
    }
  }
}
