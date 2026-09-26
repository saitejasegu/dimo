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

  /// Fingerprints a whole flat entity list. Observation delivers an `EntityBatch`,
  /// which keeps these per type so an edit re-hashes only the type it touched.
  static func compute(_ entities: [StoredEntity]) -> EntityTypeFingerprints {
    EntityBatch(entities).fingerprints
  }

  /// Hash of one type's rows. Category and preference *content* feeds other types'
  /// projections, so their payloads participate; the rest change their logical version.
  static func hash(_ type: EntityType, rows: [StoredEntity]) -> Int {
    var hasher = Hasher()
    var count = 0
    for entity in rows where entity.entityType == type {
      count += 1
      hasher.combine(entity.entityId)
      hasher.combine(entity.version.timestamp)
      hasher.combine(entity.version.counter)
      hasher.combine(entity.deleted)
      if type == .preferences || type == .category {
        hasher.combine(entity.payload)
      }
    }
    hasher.combine(count)
    return hasher.finalize()
  }

  /// Currency + default payment method of the preferences rows.
  static func preferencesProjectionHash(_ rows: [StoredEntity]) -> Int {
    var hasher = Hasher()
    var count = 0
    for entity in rows where entity.entityType == .preferences {
      count += 1
      if case .preferences(let prefs) = entity.payload {
        hasher.combine(prefs.currency)
        hasher.combine(prefs.defaultPaymentMethodId)
      }
    }
    hasher.combine(count)
    return hasher.finalize()
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

/// Live UI entities grouped by type, each with its own fingerprint.
///
/// The six per-type observations each replace only their own slice, so a lend edit
/// neither copies nor re-hashes every transaction before the hydrator can tell that
/// transactions did not change.
struct EntityBatch: Sendable {
  static let types: [EntityType] = [
    .category, .paymentMethod, .transaction, .recurring, .lend, .preferences,
  ]

  private(set) var rowsByType: [EntityType: [StoredEntity]] = [:]
  private var hashes: [EntityType: Int] = [:]
  private var preferencesProjection = EntityTypeFingerprints.preferencesProjectionHash([])

  init() {}

  init(_ entities: [StoredEntity]) {
    var grouped: [EntityType: [StoredEntity]] = [:]
    for entity in entities where Self.types.contains(entity.entityType) {
      grouped[entity.entityType, default: []].append(entity)
    }
    for type in Self.types {
      replace(type, with: grouped[type] ?? [])
    }
  }

  mutating func replace(_ type: EntityType, with rows: [StoredEntity]) {
    rowsByType[type] = rows
    hashes[type] = EntityTypeFingerprints.hash(type, rows: rows)
    if type == .preferences {
      preferencesProjection = EntityTypeFingerprints.preferencesProjectionHash(rows)
    }
  }

  /// True once every observed type has delivered at least once.
  var isComplete: Bool { Self.types.allSatisfy { rowsByType[$0] != nil } }

  func rows(_ type: EntityType) -> [StoredEntity] { rowsByType[type] ?? [] }

  /// Every row, in type order. For tests and diagnostics; hydration reads by type.
  var all: [StoredEntity] { Self.types.flatMap { rows($0) } }

  var fingerprints: EntityTypeFingerprints {
    func hash(_ type: EntityType) -> Int {
      hashes[type] ?? EntityTypeFingerprints.hash(type, rows: [])
    }
    return EntityTypeFingerprints(
      category: hash(.category),
      paymentMethod: hash(.paymentMethod),
      transaction: hash(.transaction),
      recurring: hash(.recurring),
      lend: hash(.lend),
      preferences: hash(.preferences),
      preferencesProjection: preferencesProjection
    )
  }
}

/// A built display row and the payload it was built from, reused while that payload
/// and the row's display context (labels, currency, rates, calendar day) are unchanged.
struct CachedTransactionRow: Sendable {
  var entity: TransactionEntity
  var row: Transaction
}

/// UI-ready entity projections produced off the main actor.
struct EntitySnapshot: Sendable {
  var fingerprints: EntityTypeFingerprints
  var ratesDate: String?
  /// Local day the relative labels ("Today", "Yesterday", "Due in 3 days") were built
  /// for. A new day invalidates them even when no entity changed.
  var todayKey: String
  /// Built transaction rows by id, so a single edit rebuilds one row instead of all.
  var transactionRows: [String: CachedTransactionRow]
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
    guard let previous, previous.todayKey == next.todayKey else { return .all }
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
      periodLabel: "",
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
  /// Load-bearing: without it `refreshStatsIfNeeded` short-circuits and paging
  /// to another period would recompute nothing.
  var periodOffset: Int
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
    previous: EntitySnapshot?,
    now: Date = Date()
  ) async -> EntitySnapshot? {
    await project(
      batch: EntityBatch(entities),
      rates: rates,
      currentStatsRange: currentStatsRange,
      previousDefaultStatsRange: previousDefaultStatsRange,
      dataReady: dataReady,
      profileName: profileName,
      profileEmail: profileEmail,
      previous: previous,
      now: now
    )
  }

  static func project(
    batch: EntityBatch,
    rates: RateTable?,
    currentStatsRange: StatsRange,
    previousDefaultStatsRange: StatsRange,
    dataReady: Bool,
    profileName: String,
    profileEmail: String,
    previous: EntitySnapshot?,
    now: Date = Date()
  ) async -> EntitySnapshot? {
    await withCheckedContinuation { continuation in
      queue.async {
        let fingerprints = batch.fingerprints
        let ratesDate = rates?.date
        let todayKey = DateHelpers.localDateKey(now)
        // Skip rebuild when entity content, FX table and calendar day are unchanged.
        if let previous,
           previous.fingerprints == fingerprints,
           previous.ratesDate == ratesDate,
           previous.todayKey == todayKey {
          continuation.resume(returning: nil)
          return
        }

        let snapshot = build(
          batch: batch,
          fingerprints: fingerprints,
          rates: rates,
          ratesDate: ratesDate,
          now: now,
          todayKey: todayKey,
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
    inputs: StatsInputs,
    reusing previous: (inputs: StatsInputs, stats: StatsSnapshot)?
  ) async -> StatsSnapshot {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(
          returning: buildStats(transactions: transactions, inputs: inputs, reusing: previous)
        )
      }
    }
  }

  /// Recomputes only what `inputs` invalidated. The scope (range filter, totals,
  /// average) depends on data and window alone; selecting a bar or expanding a list
  /// used to redo it, plus both rankings, on every tap.
  static func buildStats(
    transactions: [Transaction],
    inputs: StatsInputs,
    reusing previous: (inputs: StatsInputs, stats: StatsSnapshot)?
  ) -> StatsSnapshot {
    guard let previous,
      previous.inputs.revision == inputs.revision,
      previous.inputs.range == inputs.range,
      previous.inputs.periodOffset == inputs.periodOffset
    else {
      return buildStats(
        transactions: transactions,
        statsRange: inputs.range,
        periodOffset: inputs.periodOffset,
        selectedMonth: inputs.selectedMonth,
        categoriesExpanded: inputs.categoriesExpanded,
        merchantsExpanded: inputs.merchantsExpanded
      )
    }
    var result = previous.stats
    if previous.inputs.selectedMonth != inputs.selectedMonth {
      result.trendBars = StatsSelectors.trendBars(
        range: inputs.range,
        transactions: result.scope.transactions,
        selectedKey: inputs.selectedMonth,
        offset: inputs.periodOffset
      )
    }
    if previous.inputs.categoriesExpanded != inputs.categoriesExpanded {
      let cats = StatsSelectors.statCategories(
        scope: result.scope,
        limit: inputs.categoriesExpanded ? expandedStatsLimit : 5
      )
      result.categories = cats.categories
      result.categoriesTotal = cats.total
    }
    if previous.inputs.merchantsExpanded != inputs.merchantsExpanded {
      let merchants = StatsSelectors.topMerchants(
        scope: result.scope,
        limit: inputs.merchantsExpanded ? expandedStatsLimit : 5
      )
      result.merchants = merchants.merchants
      result.merchantsTotal = merchants.total
    }
    return result
  }

  static func buildStats(
    transactions: [Transaction],
    statsRange: StatsRange,
    periodOffset: Int,
    selectedMonth: String?,
    categoriesExpanded: Bool,
    merchantsExpanded: Bool
  ) -> StatsSnapshot {
    let scope = StatsSelectors.statsScope(
      range: statsRange,
      transactions: transactions,
      offset: periodOffset
    )
    let trendBars = StatsSelectors.trendBars(
      range: statsRange,
      transactions: scope.transactions,
      selectedKey: selectedMonth,
      offset: periodOffset
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
      let activeLimits = TransactionSelectors.activeCategoryLimits(categories)
      let budgetTransactions = TransactionSelectors.transactionsForActiveCategories(
        transactions,
        categories: categories
      )
      // Spent is every transaction in the month, so the hero total and count agree
      // with the transaction list under it and with the Stats tab. Archiving a
      // category stops it earning a budget, it does not erase what it already spent.
      result.monthBudgetTotals = BudgetSelectors.budgetTotals(transactions, limits: activeLimits)
      // Per-category rows stay scoped: they group by name, so an archived category
      // would otherwise donate its spend to a new active one sharing its name.
      result.categoryBudgets = BudgetSelectors.categoryBudgets(budgetTransactions, limits: activeLimits)
      result.suggestedBudgetUpdates = BudgetSelectors.suggestedCategoryBudgetUpdates(
        budgetTransactions,
        categories: categories.filter { !$0.archived }.map { ($0.id, $0.name, $0.monthlyBudgetMinor) }
      )
    }

    if dirty.lends || previous == nil {
      // Everyone, settled people included; Lending splits them into sections.
      let summaries = LendSelectors.allContactSummaries(lends)
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
    batch: EntityBatch,
    fingerprints: EntityTypeFingerprints,
    rates: RateTable?,
    ratesDate: String?,
    now: Date,
    todayKey: String,
    currentStatsRange: StatsRange,
    previousDefaultStatsRange: StatsRange,
    dataReady: Bool,
    profileName: String,
    profileEmail: String,
    previous: EntitySnapshot?
  ) -> EntitySnapshot {
    let prevFp = previous?.fingerprints
    // Relative labels are calendar-day dependent, so a new day rebuilds every row type
    // that carries one, exactly like an FX change rebuilds money labels.
    let dayChanged = previous?.todayKey != todayKey
    let contextChanged = previous?.ratesDate != ratesDate || dayChanged
    let rebuildCategories = prevFp.map { $0.category != fingerprints.category } ?? true
    let rebuildPaymentMethods =
      prevFp.map { fingerprints.paymentMethodsNeedRebuild(from: $0) } ?? true
    let rebuildTransactions =
      prevFp.map { fingerprints.transactionsNeedRebuild(from: $0, ratesDateChanged: contextChanged) }
      ?? true
    let rebuildRecurring =
      prevFp.map { fingerprints.recurringNeedsRebuild(from: $0, ratesDateChanged: contextChanged) }
      ?? true
    let rebuildLends = prevFp.map { $0.lend != fingerprints.lend || dayChanged } ?? true
    let rebuildPreferences = prevFp.map { $0.preferences != fingerprints.preferences } ?? true

    func live<T>(_ type: EntityType, _ extract: (EntityPayload) -> T?) -> [T] {
      batch.rows(type).compactMap { $0.deleted ? nil : extract($0.payload) }
    }

    var prefs = previous?.preferences ?? SeedData.defaultPreferences
    if rebuildPreferences {
      let rows = live(.preferences) { payload -> PreferencesEntity? in
        if case .preferences(let value) = payload { return value }
        return nil
      }
      if let last = rows.last { prefs = last }
    }

    let categories: [CategoryEntity]
    let limits: CategoryLimits
    if rebuildCategories {
      categories = live(.category) { payload -> CategoryEntity? in
        if case .category(let value) = payload { return value }
        return nil
      }
      .sorted { $0.sortOrder < $1.sortOrder }
      limits = Dictionary(categories.map {
        ($0.name, $0.monthlyBudgetMinor.map { Double($0) / 100 })
      }, uniquingKeysWith: { first, _ in first })
    } else {
      categories = previous?.categories ?? []
      limits = previous?.limits ?? [:]
    }

    let paymentMethods: [PaymentMethodOption]
    if rebuildPaymentMethods {
      let defaultPM = prefs.defaultPaymentMethodId
      paymentMethods = live(.paymentMethod) { payload -> PaymentMethodEntity? in
        if case .paymentMethod(let value) = payload { return value }
        return nil
      }
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

    let categoryById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let pmById = Dictionary(paymentMethods.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let formatters = Formatters(now: now)
    let defaultCurrency = prefs.currency.rawValue

    let transactions: [Transaction]
    let transactionRows: [String: CachedTransactionRow]
    if rebuildTransactions {
      // Rows only need rebuilding when their own payload changed, unless something
      // every row reads (category labels, payment labels, currency, FX, day) did.
      let rowContextChanged = prevFp.map {
        $0.category != fingerprints.category
          || $0.paymentMethod != fingerprints.paymentMethod
          || $0.preferencesProjection != fingerprints.preferencesProjection
      } ?? true
      let reusable = rowContextChanged || contextChanged ? [:] : (previous?.transactionRows ?? [:])
      var rows: [String: CachedTransactionRow] = [:]
      let entities = live(.transaction) { payload -> TransactionEntity? in
        if case .transaction(let value) = payload { return value }
        return nil
      }
      rows.reserveCapacity(entities.count)
      transactions = entities
        .sorted { $0.occurredAt > $1.occurredAt }
        .map { tx -> Transaction in
          if let cached = reusable[tx.id], cached.entity == tx {
            rows[tx.id] = cached
            return cached.row
          }
          let row = makeTransactionRow(
            tx,
            category: categoryById[tx.categoryId],
            paymentMethod: tx.paymentMethodId.flatMap { pmById[$0] },
            defaultCurrency: defaultCurrency,
            rates: rates,
            formatters: formatters
          )
          rows[tx.id] = CachedTransactionRow(entity: tx, row: row)
          return row
        }
      transactionRows = rows
    } else {
      transactions = previous?.transactions ?? []
      transactionRows = previous?.transactionRows ?? [:]
    }

    let lends: [Lend]
    if rebuildLends {
      lends = live(.lend) { payload -> LendEntity? in
        if case .lend(let value) = payload { return value }
        return nil
      }
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
            kind: lend.kind ?? .lent,
            currency: lend.currency,
            createdBy: lend.createdBy,
            lastEditedBy: lend.lastEditedBy
          )
        }
    } else {
      lends = previous?.lends ?? []
    }

    let recurring: [Recurring]
    if rebuildRecurring {
      // Resolve each next occurrence once; computing it inside the comparator repeated
      // the date walk O(n log n) times.
      let ordered = live(.recurring) { payload -> RecurringEntity? in
        if case .recurring(let value) = payload { return value }
        return nil
      }
        .map { (next: DateHelpers.nextOccurrence(anchorDate: $0.anchorDate, frequency: $0.frequency), rec: $0) }
        .sorted { $0.next < $1.next }
        .map(\.rec)
      recurring = ordered.map { rec -> Recurring in
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
      todayKey: todayKey,
      transactionRows: transactionRows,
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

  private static func makeTransactionRow(
    _ tx: TransactionEntity,
    category cat: CategoryEntity?,
    paymentMethod pm: PaymentMethodOption?,
    defaultCurrency: String,
    rates: RateTable?,
    formatters: Formatters
  ) -> Transaction {
    let sourceAmount = tx.sourceCurrency.flatMap { code in
      tx.sourceAmountMinor.map { ExchangeRates.toMajorUnits($0, code) }
    }
    let amountCurrency = tx.currency ?? defaultCurrency
    let categoryName = cat?.name ?? "Unknown"
    let amount = ExchangeRates.transactionAmountInDefault(
      amountMinor: tx.amountMinor,
      currency: tx.currency,
      defaultCurrency: defaultCurrency,
      rates: rates
    )
    return Transaction(
      id: tx.id,
      name: tx.name,
      category: categoryName,
      time: formatters.time(tx.occurredAt),
      day: formatters.day(tx.occurredAt),
      amount: amount,
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
      dayKey: formatters.dayKey(tx.occurredAt),
      spentLabel: Formatting.spent(amount, currency: Currency(rawValue: defaultCurrency) ?? .INR)
    )
  }

  /// Per-build formatters. "Today", "Yesterday" and the current year are resolved
  /// once per build instead of once per row.
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
    let calendar: Calendar
    let todayKey: String
    let yesterdayKey: String?
    let currentYear: Int

    init(now: Date, calendar: Calendar = .current) {
      self.calendar = calendar
      todayKey = DateHelpers.localDateKey(now, calendar: calendar)
      yesterdayKey = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        .map { DateHelpers.localDateKey($0, calendar: calendar) }
      currentYear = calendar.component(.year, from: now)
    }

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

    func day(_ timestamp: Int) -> String {
      let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
      let key = DateHelpers.localDateKey(date, calendar: calendar)
      if key == todayKey { return "Today" }
      guard let yesterdayKey else { return key }
      if key == yesterdayKey { return "Yesterday" }
      let sameYear = calendar.component(.year, from: date) == currentYear
      return (sameYear ? daySameYear : dayOtherYear).string(from: date)
    }
  }
}
