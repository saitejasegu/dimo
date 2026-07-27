import Foundation
import Observation

/// Domain entities + cached screen projections. Tab screens bind to this so
/// sync/toast/nav updates on other slices do not invalidate their bodies.
@Observable
@MainActor
final class EntitiesStore {
  var transactions: [Transaction] = []
  var recurring: [Recurring] = []
  var lends: [Lend] = []
  var categories: [CategoryEntity] = []
  var paymentMethods: [PaymentMethodOption] = []
  var limits: CategoryLimits = [:]
  var currency: Currency = .INR
  /// Latest ECB rates for foreign-currency display; nil until first fetch.
  var rates: RateTable? = RatesService.loadCached()
  var theme: ThemePreference = .light
  var navGlassOpacity: Double = 40
  var defaultStatsRange: StatsRange = .oneYear
  var notifications = NotificationSettings(bills: true, budget: true, weekly: false, large: true)
  var profileName = ""
  var profileEmail = ""
  var profilePhotoUrl: String?
  var dataReady = false

  /// Bumps whenever entity projections change; used as cache key input.
  private(set) var revision: UInt64 = 0

  // MARK: Cached projections

  private(set) var monthBudgetTotals = BudgetTotals(
    totalSpent: 0, totalLimit: 0, pct: 0, left: 0, over: false, transactionCount: 0
  )
  private(set) var categoryBudgets: [CategoryBudget] = []
  private(set) var suggestedBudgetUpdates: [SuggestedCategoryBudgetUpdate] = []
  private(set) var lendSummaries: [LendContactSummary] = []
  private(set) var lendTotalOutstanding: Double = 0
  private(set) var upcomingThisMonth: [Recurring] = []
  private(set) var upcomingAll: [Recurring] = []
  private(set) var statsScope = StatsScope(
    rangeMonths: 12,
    scopeTotal: 0,
    scopePast: 0,
    spentLabel: "",
    averageLabel: "",
    transactions: []
  )
  private(set) var statsTrendBars = MonthBars(visible: false, title: "", caption: "", bars: [])
  private(set) var statsCategories: (categories: [StatCategory], total: Int) = ([], 0)
  private(set) var statsMerchants: (merchants: [MerchantStat], total: Int) = ([], 0)

  @ObservationIgnored
  private var lastSnapshot: EntitySnapshot?
  @ObservationIgnored
  private var cachedFilter = TransactionFilter()
  @ObservationIgnored
  private var cachedStatsRange: StatsRange = .oneYear
  @ObservationIgnored
  private var cachedSelectedMonth: String?
  @ObservationIgnored
  private var cachedCategoriesExpanded = false
  @ObservationIgnored
  private var cachedMerchantsExpanded = false
  /// Stats are the most expensive projection and are useless off the Stats tab, so
  /// they are computed only while it is on screen and cached against their inputs.
  @ObservationIgnored
  private var statsVisible = false
  @ObservationIgnored
  private var statsInputs: StatsInputs?
  @ObservationIgnored
  private var statsTask: Task<Void, Never>?
  @ObservationIgnored
  private var categoryEmojiById: [String: String] = [:]
  @ObservationIgnored
  private var categoryEmojiByName: [String: String] = [:]
  @ObservationIgnored
  private var cachedFilteredFilter = TransactionFilter()
  @ObservationIgnored
  private var cachedFilteredRevision: UInt64 = 0
  @ObservationIgnored
  private var cachedFiltered: [Transaction] = []
  @ObservationIgnored
  private var homeListFilter = TransactionFilter()
  @ObservationIgnored
  private var homeListLimit = 0
  @ObservationIgnored
  private var homeListRevision: UInt64 = 0
  @ObservationIgnored
  private var homeListGroups: [DayGroup] = []
  @ObservationIgnored
  private var homeListHasMore = false
  @ObservationIgnored
  private var homeListFilteredCount = 0

  var lastEntitySnapshot: EntitySnapshot? { lastSnapshot }

  func apply(
    snapshot: EntitySnapshot,
    derived: DerivedSnapshot,
    filter: TransactionFilter,
    selectedMonth: String?,
    categoriesExpanded: Bool,
    merchantsExpanded: Bool
  ) {
    lastSnapshot = snapshot
    var changed = false

    if categories != snapshot.categories {
      categories = snapshot.categories
      categoryEmojiById = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.emoji) })
      categoryEmojiByName = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.name, $0.emoji) })
      changed = true
    }
    if paymentMethods != snapshot.paymentMethods {
      paymentMethods = snapshot.paymentMethods
      changed = true
    }
    if limits != snapshot.limits {
      limits = snapshot.limits
      changed = true
    }
    if transactions != snapshot.transactions {
      transactions = snapshot.transactions
      changed = true
    }
    if recurring != snapshot.recurring {
      recurring = snapshot.recurring
      changed = true
    }
    if lends != snapshot.lends {
      lends = snapshot.lends
      changed = true
    }
    if currency != snapshot.preferences.currency {
      currency = snapshot.preferences.currency
      changed = true
    }
    if theme != snapshot.preferences.theme {
      theme = snapshot.preferences.theme
      changed = true
    }
    let nextOpacity = Double(snapshot.preferences.navGlassOpacity)
    if navGlassOpacity != nextOpacity {
      navGlassOpacity = nextOpacity
      changed = true
    }
    if defaultStatsRange != snapshot.preferences.defaultStatsRange {
      defaultStatsRange = snapshot.preferences.defaultStatsRange
      changed = true
    }
    if notifications != snapshot.preferences.notifications {
      notifications = snapshot.preferences.notifications
      changed = true
    }
    if profileName.isEmpty, !snapshot.profileName.isEmpty {
      profileName = snapshot.profileName
      changed = true
    }
    if profileEmail.isEmpty, !snapshot.profileEmail.isEmpty {
      profileEmail = snapshot.profileEmail
      changed = true
    }
    if !dataReady {
      dataReady = true
      changed = true
    }

    cachedFilter = filter
    cachedStatsRange = snapshot.statsRange
    cachedSelectedMonth = selectedMonth
    cachedCategoriesExpanded = categoriesExpanded
    cachedMerchantsExpanded = merchantsExpanded

    if applyDerived(derived) {
      changed = true
    }

    if changed {
      revision &+= 1
      invalidateListCaches()
      // New entity data invalidates the stats projection; recompute only if showing.
      refreshStatsIfNeeded(
        StatsInputs(
          revision: revision,
          range: snapshot.statsRange,
          selectedMonth: selectedMonth,
          categoriesExpanded: categoriesExpanded,
          merchantsExpanded: merchantsExpanded
        )
      )
    }
  }

  /// Called by the Stats screen as it appears and disappears. Appearing recomputes
  /// immediately if the cached projection is stale.
  func setStatsVisible(_ visible: Bool, inputs: StatsInputs) {
    statsVisible = visible
    if visible {
      refreshStatsIfNeeded(inputs)
    } else {
      statsTask?.cancel()
      statsTask = nil
    }
  }

  /// Recomputes the stats projection when its inputs changed and the tab is showing.
  func refreshStatsIfNeeded(_ inputs: StatsInputs) {
    guard statsVisible, inputs != statsInputs else { return }
    statsInputs = inputs
    let rows = transactions
    statsTask?.cancel()
    statsTask = Task { [weak self] in
      let stats = await EntityHydrator.deriveStats(
        transactions: rows,
        statsRange: inputs.range,
        selectedMonth: inputs.selectedMonth,
        categoriesExpanded: inputs.categoriesExpanded,
        merchantsExpanded: inputs.merchantsExpanded
      )
      guard !Task.isCancelled else { return }
      await MainActor.run {
        guard let self else { return }
        self.applyStats(stats)
      }
    }
  }

  @discardableResult
  func applyStats(_ stats: StatsSnapshot) -> Bool {
    var changed = false
    if statsScope != stats.scope {
      statsScope = stats.scope
      changed = true
    }
    if statsTrendBars != stats.trendBars {
      statsTrendBars = stats.trendBars
      changed = true
    }
    if statsCategories.categories != stats.categories
      || statsCategories.total != stats.categoriesTotal {
      statsCategories = (stats.categories, stats.categoriesTotal)
      changed = true
    }
    if statsMerchants.merchants != stats.merchants
      || statsMerchants.total != stats.merchantsTotal {
      statsMerchants = (stats.merchants, stats.merchantsTotal)
      changed = true
    }
    return changed
  }

  @discardableResult
  func applyDerived(_ derived: DerivedSnapshot) -> Bool {
    var changed = false
    if monthBudgetTotals != derived.monthBudgetTotals {
      monthBudgetTotals = derived.monthBudgetTotals
      changed = true
    }
    if categoryBudgets != derived.categoryBudgets {
      categoryBudgets = derived.categoryBudgets
      changed = true
    }
    if suggestedBudgetUpdates != derived.suggestedBudgetUpdates {
      suggestedBudgetUpdates = derived.suggestedBudgetUpdates
      changed = true
    }
    if lendSummaries != derived.lendSummaries {
      lendSummaries = derived.lendSummaries
      changed = true
    }
    if lendTotalOutstanding != derived.lendTotalOutstanding {
      lendTotalOutstanding = derived.lendTotalOutstanding
      changed = true
    }
    if upcomingThisMonth != derived.upcomingThisMonth {
      upcomingThisMonth = derived.upcomingThisMonth
      changed = true
    }
    if upcomingAll != derived.upcomingAll {
      upcomingAll = derived.upcomingAll
      changed = true
    }
    return changed
  }

  func setRates(_ table: RateTable?) {
    rates = table
  }

  /// Reacts to nav filter / stats chrome changes without a full entity hydrate.
  ///
  /// Budget, lending and upcoming projections depend only on entity data, so a filter
  /// or range change no longer re-derives them; the filtered and Home list caches are
  /// keyed by filter and recompute lazily on read, and stats recompute only while the
  /// Stats tab is visible.
  func refreshProjections(
    filter: TransactionFilter,
    statsRange: StatsRange,
    selectedMonth: String?,
    categoriesExpanded: Bool,
    merchantsExpanded: Bool
  ) {
    cachedFilter = filter
    cachedStatsRange = statsRange
    cachedSelectedMonth = selectedMonth
    cachedCategoriesExpanded = categoriesExpanded
    cachedMerchantsExpanded = merchantsExpanded

    refreshStatsIfNeeded(
      StatsInputs(
        revision: revision,
        range: statsRange,
        selectedMonth: selectedMonth,
        categoriesExpanded: categoriesExpanded,
        merchantsExpanded: merchantsExpanded
      )
    )
  }

  func filteredTransactions(matching filter: TransactionFilter) -> [Transaction] {
    if filter == cachedFilteredFilter, revision == cachedFilteredRevision {
      return cachedFiltered
    }
    let result = TransactionSelectors.filterTransactions(transactions, filter: filter)
    cachedFiltered = result
    cachedFilteredFilter = filter
    cachedFilteredRevision = revision
    return result
  }

  /// Cached Home list projection: filter → paginate → groupByDay.
  func homeList(
    filter: TransactionFilter,
    limit: Int
  ) -> (groups: [DayGroup], hasMore: Bool, filteredCount: Int) {
    if filter == homeListFilter,
       limit == homeListLimit,
       revision == homeListRevision {
      return (homeListGroups, homeListHasMore, homeListFilteredCount)
    }
    let filtered = filteredTransactions(matching: filter)
    let page = TransactionSelectors.paginateTransactionsByDay(filtered, limit: limit)
    let groups = TransactionSelectors.groupByDay(page.items)
    homeListFilter = filter
    homeListLimit = limit
    homeListRevision = revision
    homeListGroups = groups
    homeListHasMore = page.hasMore
    homeListFilteredCount = filtered.count
    return (groups, page.hasMore, filtered.count)
  }

  func categoryEmoji(explicit: String?, categoryId: String?, category: String) -> String {
    explicit
      ?? categoryId.flatMap { categoryEmojiById[$0] }
      ?? categoryEmojiByName[category]
      ?? "🙂"
  }

  private func invalidateListCaches() {
    cachedFilteredRevision = 0
    homeListRevision = 0
  }
}

@Observable
@MainActor
final class SyncStatusStore {
  var syncMeta: SyncMeta?
  var pendingCount = 0
  var blockedCount = 0
  var deletingHistory = false
}

@Observable
@MainActor
final class NavStore {
  var view: ViewKey = .home
  var accountReturnView: ViewKey?
  var overlay: OverlayKey?
  var detailId: String?
  var toast: String?
  var filter = TransactionFilter()
  var statsRange: StatsRange = .oneYear
  var selectedMonth: String?
  var merchantsExpanded = false
  var categoriesExpanded = false
}

@Observable
@MainActor
final class DraftsStore {
  var expenseDraft = ExpenseDraft()
  var recurringDraft = RecurringDraft()
  var categoryDraft = CategoryDraft()
  var lendDraft = LendDraft()
}
