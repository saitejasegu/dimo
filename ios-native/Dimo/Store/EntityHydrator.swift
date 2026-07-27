import Foundation

/// Per-type content fingerprints so unchanged entity types can skip remapping.
struct EntityTypeFingerprints: Equatable, Sendable {
  var category: Int
  var paymentMethod: Int
  var transaction: Int
  var recurring: Int
  var lend: Int
  var preferences: Int

  static let empty = EntityTypeFingerprints(
    category: 0, paymentMethod: 0, transaction: 0, recurring: 0, lend: 0, preferences: 0
  )

  /// One pass with six hashers, rather than six passes over the whole batch.
  static func compute(_ entities: [StoredEntity]) -> EntityTypeFingerprints {
    var hashers: [EntityType: Hasher] = [:]
    var counts: [EntityType: Int] = [:]
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
      hashers[type] = hasher
    }

    func finalize(_ type: EntityType) -> Int {
      guard var hasher = hashers[type] else { return 0 }
      hasher.combine(counts[type] ?? 0)
      return hasher.finalize()
    }

    return EntityTypeFingerprints(
      category: finalize(.category),
      paymentMethod: finalize(.paymentMethod),
      transaction: finalize(.transaction),
      recurring: finalize(.recurring),
      lend: finalize(.lend),
      preferences: finalize(.preferences)
    )
  }

  /// Types whose display projection depends on FX / category / payment labels.
  func emailRelevantChanges(from previous: EntityTypeFingerprints) -> Bool {
    category != previous.category
      || paymentMethod != previous.paymentMethod
      || transaction != previous.transaction
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

/// Projections needed by Home, Budgets and Lending. Computed on every hydrate because
/// the tab bar can show any of them without warning.
struct DerivedSnapshot: Equatable, Sendable {
  var monthBudgetTotals: BudgetTotals
  var categoryBudgets: [CategoryBudget]
  var suggestedBudgetUpdates: [SuggestedCategoryBudgetUpdate]
  var lendSummaries: [LendContactSummary]
  var lendTotalOutstanding: Double
  var upcomingThisMonth: [Recurring]
  var upcomingAll: [Recurring]
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
        if snapshot == previous {
          continuation.resume(returning: nil)
        } else {
          continuation.resume(returning: snapshot)
        }
      }
    }
  }

  static func derive(
    transactions: [Transaction],
    recurring: [Recurring],
    lends: [Lend],
    limits: CategoryLimits,
    categories: [CategoryEntity]
  ) async -> DerivedSnapshot {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: buildDerived(
            transactions: transactions,
            recurring: recurring,
            lends: lends,
            limits: limits,
            categories: categories
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
      limit: categoriesExpanded ? Int.max : 5
    )
    let merchants = StatsSelectors.topMerchants(
      scope: scope,
      limit: merchantsExpanded ? Int.max : 5
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
    categories: [CategoryEntity]
  ) -> DerivedSnapshot {
    let monthBudgetTotals = BudgetSelectors.budgetTotals(transactions, limits: limits)
    let categoryBudgets = BudgetSelectors.categoryBudgets(transactions, limits: limits)
    let suggestedBudgetUpdates = BudgetSelectors.suggestedCategoryBudgetUpdates(
      transactions,
      categories: categories.map { ($0.id, $0.name, $0.monthlyBudgetMinor) }
    )
    let lendSummaries = LendSelectors.contactSummaries(lends)
    let lendTotalOutstanding = LendSelectors.totalLent(lends)
    // Built once and shared: this is a full pass over every transaction id, and both
    // upcoming views need the same set.
    let recordedIDs = RecurringSelectors.recordedOccurrenceIDs(transactions)
    let upcomingThisMonth = RecurringSelectors.upcomingBills(recurring, recordedIDs: recordedIDs)
    let upcomingAll = RecurringSelectors.allUpcomingBills(recurring, recordedIDs: recordedIDs)

    return DerivedSnapshot(
      monthBudgetTotals: monthBudgetTotals,
      categoryBudgets: categoryBudgets,
      suggestedBudgetUpdates: suggestedBudgetUpdates,
      lendSummaries: lendSummaries,
      lendTotalOutstanding: lendTotalOutstanding,
      upcomingThisMonth: upcomingThisMonth,
      upcomingAll: upcomingAll
    )
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
    let rebuildCategories = prevFp.map { $0.category != fingerprints.category } ?? true
    let rebuildPaymentMethods =
      prevFp.map {
        $0.paymentMethod != fingerprints.paymentMethod || $0.preferences != fingerprints.preferences
      } ?? true
    let rebuildTransactions =
      prevFp.map {
        $0.transaction != fingerprints.transaction
          || $0.category != fingerprints.category
          || $0.paymentMethod != fingerprints.paymentMethod
          || $0.preferences != fingerprints.preferences
          || previous?.ratesDate != ratesDate
      } ?? true
    let rebuildRecurring =
      prevFp.map {
        $0.recurring != fingerprints.recurring
          || $0.category != fingerprints.category
          || $0.preferences != fingerprints.preferences
          || previous?.ratesDate != ratesDate
      } ?? true
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
          let amountCurrency = tx.currency ?? prefs.currency.rawValue
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
              defaultCurrency: prefs.currency.rawValue,
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
        return Recurring(
          id: rec.id,
          name: rec.name,
          category: cat?.name ?? "",
          due: DateHelpers.recurringDueLabel(anchorDate: rec.anchorDate, frequency: rec.frequency),
          amount: ExchangeRates.toMajorUnits(rec.amountMinor, rec.currency ?? prefs.currency.rawValue),
          paused: rec.paused,
          green: cat?.tint == .green,
          emoji: cat?.emoji,
          amountMinor: rec.amountMinor,
          categoryId: rec.categoryId,
          paymentMethodId: rec.paymentMethodId,
          anchorDate: rec.anchorDate,
          frequency: rec.frequency,
          currency: rec.currency
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
