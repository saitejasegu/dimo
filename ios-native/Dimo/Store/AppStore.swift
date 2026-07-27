import Combine
import ConvexMobile
import Foundation
import GRDB
import Observation
import SwiftUI

@Observable
@MainActor
final class AppStore {
  let userId: String
  let entities = EntitiesStore()
  let syncStatus = SyncStatusStore()
  let nav = NavStore()
  let drafts = DraftsStore()

  /// Device-local daily expense reminder (not synced).
  var expenseReminder = ExpenseReminderSettings.default
  var expenseReminderAuthorization: ExpenseReminderAuthorization = .notDetermined
  var emailFeatureStore = EmailFeatureStore()

  private var toastTask: Task<Void, Never>?
  private let authProvider: WorkOSAuthProvider
  private var repository: Repository?
  private var coordinator: SyncCoordinator?
  private var emailController: EmailFeatureController?
  private var convexClient: ConvexClientWithAuth<WorkOSSession>?
  private var entityObservation: DatabaseCancellable?
  private var syncObservation: DatabaseCancellable?
  private var writeListener: UUID?
  private var idCounter = 0
  /// Network/email follow-up after local hydrate. Cancelled on tearDown so a
  /// slow OpenRouter/Convex call cannot outlive the signed-in session.
  private var remoteStartTask: Task<Void, Never>?
  private var hydrateTask: Task<Void, Never>?
  private var pendingHydrateEntities: [StoredEntity]?

  // MARK: Forwarders — keep mutation call sites and sheets compiling while
  // tab screens bind directly to `entities` / `nav` / `syncStatus` / `drafts`.

  var profileName: String {
    get { entities.profileName }
    set { entities.profileName = newValue }
  }
  var profileEmail: String {
    get { entities.profileEmail }
    set { entities.profileEmail = newValue }
  }
  var profilePhotoUrl: String? {
    get { entities.profilePhotoUrl }
    set { entities.profilePhotoUrl = newValue }
  }
  var view: ViewKey {
    get { nav.view }
    set { nav.view = newValue }
  }
  var accountReturnView: ViewKey? {
    get { nav.accountReturnView }
    set { nav.accountReturnView = newValue }
  }
  var overlay: OverlayKey? {
    get { nav.overlay }
    set { nav.overlay = newValue }
  }
  var detailId: String? {
    get { nav.detailId }
    set { nav.detailId = newValue }
  }
  var toast: String? {
    get { nav.toast }
    set { nav.toast = newValue }
  }
  var transactions: [Transaction] {
    get { entities.transactions }
    set { entities.transactions = newValue }
  }
  var recurring: [Recurring] {
    get { entities.recurring }
    set { entities.recurring = newValue }
  }
  var lends: [Lend] {
    get { entities.lends }
    set { entities.lends = newValue }
  }
  var categories: [CategoryEntity] {
    get { entities.categories }
    set { entities.categories = newValue }
  }
  var paymentMethods: [PaymentMethodOption] {
    get { entities.paymentMethods }
    set { entities.paymentMethods = newValue }
  }
  var limits: CategoryLimits {
    get { entities.limits }
    set { entities.limits = newValue }
  }
  var filter: TransactionFilter {
    get { nav.filter }
    set {
      nav.filter = newValue
      scheduleProjectionRefresh()
    }
  }
  var statsRange: StatsRange {
    get { nav.statsRange }
    set {
      nav.statsRange = newValue
      scheduleProjectionRefresh()
    }
  }
  var selectedMonth: String? {
    get { nav.selectedMonth }
    set {
      nav.selectedMonth = newValue
      scheduleProjectionRefresh()
    }
  }
  var merchantsExpanded: Bool {
    get { nav.merchantsExpanded }
    set {
      nav.merchantsExpanded = newValue
      scheduleProjectionRefresh()
    }
  }
  var categoriesExpanded: Bool {
    get { nav.categoriesExpanded }
    set {
      nav.categoriesExpanded = newValue
      scheduleProjectionRefresh()
    }
  }
  var currency: Currency {
    get { entities.currency }
    set { entities.currency = newValue }
  }
  var rates: RateTable? {
    get { entities.rates }
    set { entities.rates = newValue }
  }
  var theme: ThemePreference {
    get { entities.theme }
    set { entities.theme = newValue }
  }
  var navGlassOpacity: Double {
    get { entities.navGlassOpacity }
    set { entities.navGlassOpacity = newValue }
  }
  var defaultStatsRange: StatsRange {
    get { entities.defaultStatsRange }
    set { entities.defaultStatsRange = newValue }
  }
  var notifications: NotificationSettings {
    get { entities.notifications }
    set { entities.notifications = newValue }
  }
  var dataReady: Bool {
    get { entities.dataReady }
    set { entities.dataReady = newValue }
  }
  var syncMeta: SyncMeta? {
    get { syncStatus.syncMeta }
    set { syncStatus.syncMeta = newValue }
  }
  var pendingCount: Int {
    get { syncStatus.pendingCount }
    set { syncStatus.pendingCount = newValue }
  }
  var blockedCount: Int {
    get { syncStatus.blockedCount }
    set { syncStatus.blockedCount = newValue }
  }
  var deletingHistory: Bool {
    get { syncStatus.deletingHistory }
    set { syncStatus.deletingHistory = newValue }
  }
  var expenseDraft: ExpenseDraft {
    get { drafts.expenseDraft }
    set { drafts.expenseDraft = newValue }
  }
  var recurringDraft: RecurringDraft {
    get { drafts.recurringDraft }
    set { drafts.recurringDraft = newValue }
  }
  var categoryDraft: CategoryDraft {
    get { drafts.categoryDraft }
    set { drafts.categoryDraft = newValue }
  }
  var lendDraft: LendDraft {
    get { drafts.lendDraft }
    set { drafts.lendDraft = newValue }
  }

  init(
    userId: String,
    profileName: String,
    profileEmail: String,
    profilePhotoUrl: String? = nil,
    authProvider: WorkOSAuthProvider
  ) {
    self.userId = userId
    self.authProvider = authProvider
    entities.profileName = profileName
    entities.profileEmail = profileEmail
    entities.profilePhotoUrl = profilePhotoUrl
  }

  func start() async {
    do {
      let db = try AppDatabase.activate(userId: userId)
      let repo = Repository(db: db)
      try repo.initializeLocalDatabase()
      repository = repo

      entityObservation = repo.observeEntities { [weak self] batch in
        Task { @MainActor in self?.scheduleHydrate(batch) }
      }
      syncObservation = repo.observeSyncMeta { [weak self] meta in
        Task { @MainActor in
          self?.syncStatus.syncMeta = meta
          await self?.refreshOutboxCounts(repository: repo)
        }
      }
      writeListener = repo.onLocalWrite { [weak self] in
        Task { @MainActor in
          await self?.refreshOutboxCounts(repository: repo)
        }
      }
      // Two synchronous SQLite reads per write would otherwise land on the main actor.
      let batch = try await Task.detached { try repo.allEntities() }.value
      await hydrateNow(batch)
      expenseReminder = ExpenseReminderStore.load(userId: userId)
      ExpenseReminderRouter.store = self
      await refreshExpenseReminderAuthorization()
      await refreshExpenseReminderSchedule()

      // Start Convex before email so OpenRouter work cannot delay sync.
      remoteStartTask?.cancel()
      remoteStartTask = Task { [weak self] in
        await self?.startRemoteServices(repository: repo)
      }

      // Email wiring is not required for Home/Stats — do not block signed-in UI.
      let emailController = EmailFeatureController(
        userId: userId,
        repository: repo,
        store: emailFeatureStore
      )
      self.emailController = emailController
      let cats = entities.categories
      let methods = entities.paymentMethods
      let txs = entities.transactions
      let currency = entities.currency
      Task { [weak self] in
        guard let self else { return }
        await emailController.start(
          categories: cats,
          paymentMethods: methods,
          transactions: txs,
          currency: currency
        )
        await self.refreshExpenseReminderSchedule()
      }
    } catch {
      showToast(error.localizedDescription)
    }
  }

  /// Convex auth, sync, and rates — runs after local data is visible.
  private func startRemoteServices(repository repo: Repository) async {
    do {
      try Task.checkCancellation()
      let client = ConvexClientWithAuth(
        deploymentUrl: AppConfig.convexURL,
        authProvider: authProvider
      )
      let login = await client.loginFromCache()
      try Task.checkCancellation()
      switch login {
      case .success:
        break
      case .failure(let error):
        try? repo.updateSyncMeta {
          $0.syncing = false
          $0.error = error.localizedDescription
        }
        showToast(error.localizedDescription)
        return
      }
      convexClient = client
      emailController?.attachOpenRouterConvexTransport(
        OpenRouterConvexTransport(client: client)
      )

      let transport = ConvexSyncTransport(client: client)
      let coordinator = SyncCoordinator(repository: repo, transport: transport)
      await coordinator.setProfile(name: profileName, email: profileEmail)
      try Task.checkCancellation()
      self.coordinator = coordinator
      await coordinator.start()
      await refreshExchangeRates()
    } catch is CancellationError {
      return
    } catch {
      showToast(error.localizedDescription)
    }
  }

  func tearDown() async {
    remoteStartTask?.cancel()
    remoteStartTask = nil
    hydrateTask?.cancel()
    hydrateTask = nil
    pendingHydrateEntities = nil
    emailController?.attachOpenRouterConvexTransport(nil)
    await emailController?.tearDown()
    emailController = nil
    entityObservation?.cancel()
    syncObservation?.cancel()
    if let writeListener { repository?.removeLocalWriteListener(writeListener) }
    await coordinator?.stop()
    coordinator = nil
    repository = nil
    convexClient = nil
    if ExpenseReminderRouter.store === self {
      ExpenseReminderRouter.store = nil
    }
    ExpenseReminderScheduler.cancel()
  }

  func sceneBecameActive() {
    emailController?.sceneBecameActive()
    Task {
      await refreshExpenseReminderAuthorization()
      await refreshExpenseReminderSchedule()
      await coordinator?.request()
      await refreshExchangeRates()
    }
  }

  func updateExpenseReminder(mutate: (inout ExpenseReminderSettings) -> Void) async {
    var next = expenseReminder
    mutate(&next)
    next = next.clamped
    if next.enabled, expenseReminderAuthorization != .authorized {
      let allowed = await ExpenseReminderScheduler.requestAuthorizationIfNeeded()
      await refreshExpenseReminderAuthorization()
      if !allowed {
        next.enabled = false
        expenseReminder = next
        ExpenseReminderStore.save(next, userId: userId)
        ExpenseReminderScheduler.cancel()
        showToast("Enable notifications for Dimo in Settings to get reminders.")
        return
      }
    }
    expenseReminder = next
    ExpenseReminderStore.save(next, userId: userId)
    await refreshExpenseReminderSchedule()
  }

  func refreshExpenseReminderSchedule() async {
    await ExpenseReminderScheduler.apply(
      settings: expenseReminder,
      pendingPurchaseCount: emailFeatureStore.pendingPurchaseCount
    )
  }

  func refreshExpenseReminderAuthorization() async {
    expenseReminderAuthorization = await ExpenseReminderScheduler.authorizationStatus()
  }

  /// Pull the latest ECB rates from Convex into state (and the offline cache).
  private func refreshExchangeRates() async {
    do {
      guard let table = try await coordinator?.latestExchangeRates() else { return }
      RatesService.store(table)
      let previousDate = entities.rates?.date
      entities.setRates(table)
      // FX changes require remapping transaction amounts in the default currency.
      if previousDate != table.date, let repository {
        let batch = try? await Task.detached { try repository.allEntities() }.value
        scheduleHydrate(batch ?? [])
      }
    } catch {
      // Offline / auth — keep the UserDefaults cache already seeded into `rates`.
    }
  }

  func syncNow() {
    Task { await coordinator?.request(cancelInFlight: true) }
  }

  func requestFullSync() {
    Task { await coordinator?.requestFullSync() }
  }

  func clearCloudWorkspace() async throws {
    try await coordinator?.clearCloudWorkspace()
  }

  // MARK: - Navigation

  func setView(_ view: ViewKey) {
    self.view = view == .tx || view == .recurring ? .home : view
  }

  func openAccount() {
    accountReturnView = view
    view = .account
  }

  func closeAccount() {
    view = accountReturnView ?? .home
    accountReturnView = nil
  }

  func openOverlay(_ key: OverlayKey) {
    switch key {
    case .add:
      expenseDraft = ExpenseDraft(
        category: "",
        paymentMethodId: preferredPaymentMethodId()
      )
    case .recurring:
      recurringDraft = RecurringDraft(
        currency: currency.rawValue,
        category: categories.first(where: { $0.name == "Bills" })?.name ?? categories.first?.name ?? "Bills",
        paymentMethodId: preferredPaymentMethodId(),
        anchorDate: DateHelpers.localDateKey(Date())
      )
    case .category:
      categoryDraft = CategoryDraft()
    case .lend:
      lendDraft = LendDraft()
    }
    overlay = key
  }

  func closeOverlay() { overlay = nil }
  func openDetail(_ id: String) { detailId = id }
  func closeDetail() { detailId = nil }

  // MARK: - Mutations

  private typealias TransactionCurrencyFields = (
    amountMinor: Int,
    currency: String,
    sourceCurrency: String?,
    sourceAmountMinor: Int?,
    exchangeRate: Double?
  )

  /// Converts a one-off expense into the account currency while retaining its
  /// original amount and rate for later display and editing. Always stamps
  /// `currency` with the account default at write time.
  private func transactionCurrencyFields(
    amount: Double,
    entryCurrency: String
  ) -> TransactionCurrencyFields? {
    let sourceMinor = max(1, ExchangeRates.toMinorUnits(amount, entryCurrency))
    let defaultCurrency = currency.rawValue
    guard entryCurrency != defaultCurrency else {
      return (sourceMinor, defaultCurrency, nil, nil, nil)
    }
    guard let convertedMinor = ExchangeRates.convertMinor(
      sourceMinor,
      from: entryCurrency,
      to: defaultCurrency,
      rates: rates
    ), let rate = ExchangeRates.rateBetween(entryCurrency, defaultCurrency, rates) else {
      return nil
    }
    return (max(1, convertedMinor), defaultCurrency, entryCurrency, sourceMinor, rate)
  }

  func saveExpense() {
    guard let amount = Double(expenseDraft.amount), amount > 0 else { return }
    guard let category = categories.first(where: { $0.name == expenseDraft.category }) else { return }
    let id = makeId(prefix: "tx_")
    let paymentMethodId = resolvedPaymentMethodId(expenseDraft.paymentMethodId)
    let entity = TransactionEntity(
      id: id,
      name: expenseDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? category.name : expenseDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      amountMinor: Int((amount * 100).rounded()),
      occurredAt: Int(expenseDraft.date.timeIntervalSince1970 * 1000),
      categoryId: category.id,
      paymentMethodId: paymentMethodId,
      currency: currency.rawValue
    )
    write { repository in
      try repository.saveEntity(entityType: .transaction, payload: .transaction(entity))
      try repository.setLastPaymentMethod(paymentMethodId)
    }
    filter = TransactionFilter()
    closeOverlay()
    setView(.home)
    showToast("Expense saved")
  }

  func saveExpense(
    name: String,
    amount: Double,
    categoryName: String,
    paymentMethodId: String?,
    date: Date,
    recurringFrequency: RecurringFrequency?,
    occurrenceSelection: RecurringOccurrenceSelection = .selected,
    entryCurrency: String? = nil
  ) {
    guard amount > 0,
          let category = categories.first(where: { $0.name == categoryName }) else { return }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let entryCurrency = entryCurrency ?? currency.rawValue
    guard let converted = transactionCurrencyFields(amount: amount, entryCurrency: entryCurrency) else {
      showToast("Exchange rates unavailable — try again once online")
      return
    }

    let resolvedMethodId = resolvedPaymentMethodId(paymentMethodId)
    guard let recurringFrequency else {
      let transaction = TransactionEntity(
        id: makeId(prefix: "tx_"),
        name: trimmedName.isEmpty ? category.name : trimmedName,
        amountMinor: converted.amountMinor,
        occurredAt: min(Int(date.timeIntervalSince1970 * 1000), Int(Date().timeIntervalSince1970 * 1000)),
        categoryId: category.id,
        paymentMethodId: resolvedMethodId,
        currency: converted.currency,
        sourceCurrency: converted.sourceCurrency,
        sourceAmountMinor: converted.sourceAmountMinor,
        exchangeRate: converted.exchangeRate
      )
      write { repository in
        try repository.saveEntity(entityType: .transaction, payload: .transaction(transaction))
        try repository.setLastPaymentMethod(resolvedMethodId)
      }
      closeOverlay()
      setView(.home)
      showToast("Expense saved")
      return
    }

    guard !trimmedName.isEmpty else { return }
    let anchorDate = DateHelpers.localDateKey(date)
    let recurringFields = ExchangeRates.recurringFields(amount, currency: entryCurrency)
    let recurring = RecurringEntity(
      id: makeId(prefix: "rec_"),
      name: trimmedName,
      amountMinor: recurringFields.amountMinor,
      categoryId: category.id,
      paymentMethodId: resolvedMethodId,
      frequency: recurringFrequency,
      anchorDate: anchorDate,
      paused: false,
      currency: recurringFields.currency
    )
    let dates = DateHelpers.recurringTransactionDates(
      anchorDate: anchorDate,
      frequency: recurringFrequency,
      selection: occurrenceSelection
    )
    var batch: [(EntityType, EntityPayload)] = [(.recurring, .recurring(recurring))]
    batch.append(contentsOf: dates.map { occurrence in
      let transaction = TransactionEntity(
        id: makeId(prefix: "tx_"),
        name: trimmedName,
        amountMinor: converted.amountMinor,
        occurredAt: DateHelpers.occurrenceTimestamp(occurrence, time: date),
        categoryId: category.id,
        paymentMethodId: resolvedMethodId,
        currency: converted.currency,
        sourceCurrency: converted.sourceCurrency,
        sourceAmountMinor: converted.sourceAmountMinor,
        exchangeRate: converted.exchangeRate
      )
      return (.transaction, .transaction(transaction))
    })
    write { repository in
      try repository.saveEntities(batch)
      try repository.setLastPaymentMethod(resolvedMethodId)
    }
    closeOverlay()
    setView(.home)
    showToast(
      dates.isEmpty
        ? "Recurring expense added"
        : "Recurring expense added · \(dates.count) transaction\(dates.count == 1 ? "" : "s")"
    )
  }

  func saveLend() {
    guard let amount = Double(lendDraft.amount), amount > 0 else { return }
    let contact = lendDraft.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !contact.isEmpty else { return }
    let existing = lendDraft.editingId.flatMap { id in lends.first { $0.id == id } }
    guard let contactId = lendDraft.contactId ?? existing?.contactId else { return }
    let kind = existing?.kind ?? lendDraft.kind
    if kind == .repaid {
      let outstanding = LendSelectors.outstandingAmount(
        for: contactId,
        in: lends,
        excludingLendId: existing?.id
      )
      guard amount <= outstanding + 0.000_001 else { return }
    }
    let occurredAt: Int
    if let existing,
       Calendar.current.isDate(
         Date(timeIntervalSince1970: TimeInterval(existing.occurredAt) / 1000),
         inSameDayAs: lendDraft.date
       ) {
      occurredAt = existing.occurredAt
    } else {
      occurredAt = lendTimestamp(for: lendDraft.date)
    }
    let entity = LendEntity(
      id: existing?.id ?? makeId(prefix: "lend_"),
      contactName: contact,
      contactId: contactId,
      amountMinor: Int((amount * 100).rounded()),
      occurredAt: occurredAt,
      comment: lendDraft.comment.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: existing?.kind ?? lendDraft.kind
    )
    write { try $0.saveEntity(entityType: .lend, payload: .lend(entity)) }
    closeOverlay()
    let noun = kind == .repaid ? "Repayment" : "Lend"
    showToast(existing == nil ? "\(noun) saved" : "\(noun) updated")
  }

  func openEditLend(_ id: String) {
    guard let lend = lends.first(where: { $0.id == id }) else { return }
    lendDraft = LendDraft(
      editingId: id,
      kind: lend.kind,
      contactName: lend.contactName,
      contactId: lend.contactId,
      amount: lend.amount.rounded() == lend.amount
        ? String(Int(lend.amount))
        : String(format: "%.2f", lend.amount),
      date: Date(timeIntervalSince1970: TimeInterval(lend.occurredAt) / 1000),
      comment: lend.comment
    )
    overlay = .lend
  }

  func openAddRepayment(contactName: String, contactId: String) {
    lendDraft = LendDraft(kind: .repaid, contactName: contactName, contactId: contactId)
    overlay = .lend
  }

  func deleteLend(_ id: String) {
    write { try $0.removeEntity(entityType: .lend, id: id) }
    closeOverlay()
    showToast("Lend deleted")
  }

  /// Today keeps the current time so entries order naturally; past dates pin to noon
  /// like recurring occurrences.
  private func lendTimestamp(for date: Date) -> Int {
    if Calendar.current.isDate(date, inSameDayAs: Date()) {
      return Int(Date().timeIntervalSince1970 * 1000)
    }
    return DateHelpers.occurrenceTimestamp(date)
  }

  /// The retained source email for a transaction added from an email
  /// suggestion, used by the expense editor's reference row.
  func sourceEmail(forTransactionId id: String) -> EmailUIEmailDetail? {
    emailController?.sourceEmailDetail(forTransactionId: id)
  }

  func sourceEmails(forTransactionId id: String) -> [EmailUIEmailDetail] {
    emailController?.sourceEmailDetails(forTransactionId: id) ?? []
  }

  func deleteTransaction(_ id: String) {
    write { try $0.removeEntity(entityType: .transaction, id: id) }
    closeDetail()
    showToast("Transaction deleted")
  }

  func deleteRecurring(_ id: String) {
    write { try $0.removeEntity(entityType: .recurring, id: id) }
    closeOverlay()
    showToast("Recurring transaction deleted")
  }

  func deleteCategoryAndTransactions(_ categoryId: String) {
    let transactionIds = transactions.filter { $0.categoryId == categoryId }.map(\.id)
    write { repository in
      try repository.removeEntities(entityType: .transaction, ids: transactionIds)
      try repository.removeEntity(entityType: .category, id: categoryId)
    }
    closeOverlay()
    showToast(
      transactionIds.isEmpty
        ? "Category deleted"
        : "Category and \(transactionIds.count) transaction\(transactionIds.count == 1 ? "" : "s") deleted"
    )
  }

  func saveTransactionEdits(
    id: String,
    name: String,
    amount: Double,
    categoryName: String,
    paymentMethodId: String?,
    date: Date,
    entryCurrency: String? = nil
  ) {
    guard amount > 0,
          let category = categories.first(where: { $0.name == categoryName }),
          transactions.contains(where: { $0.id == id }) else { return }
    guard let converted = transactionCurrencyFields(
      amount: amount,
      entryCurrency: entryCurrency ?? currency.rawValue
    ) else {
      showToast("Exchange rates unavailable — try again once online")
      return
    }
    let entity = TransactionEntity(
      id: id,
      name: name,
      amountMinor: converted.amountMinor,
      occurredAt: Int(date.timeIntervalSince1970 * 1000),
      categoryId: category.id,
      paymentMethodId: resolvedPaymentMethodId(paymentMethodId),
      currency: converted.currency,
      sourceCurrency: converted.sourceCurrency,
      sourceAmountMinor: converted.sourceAmountMinor,
      exchangeRate: converted.exchangeRate
    )
    write { try $0.saveEntity(entityType: .transaction, payload: .transaction(entity)) }
    closeDetail()
    showToast("Transaction updated")
  }

  func saveRecurring(includeHistoricalTransactions: Bool = false) {
    guard let amount = Double(recurringDraft.amount), amount > 0 else { return }
    guard let category = categories.first(where: { $0.name == recurringDraft.category }) else { return }
    let name = recurringDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let id = recurringDraft.editingId ?? makeId(prefix: "rec_")
    let entryCurrency = recurringDraft.currency ?? currency.rawValue
    let converted = transactionCurrencyFields(amount: amount, entryCurrency: entryCurrency)
    if recurringDraft.editingId == nil && converted == nil {
      showToast("Exchange rates unavailable — try again once online")
      return
    }
    let recurringFields = ExchangeRates.recurringFields(amount, currency: entryCurrency)
    let paymentMethodId = resolvedPaymentMethodId(recurringDraft.paymentMethodId)
    let entity = RecurringEntity(
      id: id,
      name: name,
      amountMinor: recurringFields.amountMinor,
      categoryId: category.id,
      paymentMethodId: paymentMethodId,
      frequency: recurringDraft.frequency,
      anchorDate: recurringDraft.anchorDate,
      paused: recurringDraft.paused,
      currency: recurringFields.currency
    )
    var batch: [(EntityType, EntityPayload)] = [(.recurring, .recurring(entity))]
    if recurringDraft.editingId == nil {
      let anchor = DateHelpers.parseLocalDate(entity.anchorDate)
      let today = Calendar.current.startOfDay(for: Date())
      let occurrenceDates: [Date]
      if includeHistoricalTransactions {
        occurrenceDates = DateHelpers.occurrencesThrough(
          anchorDate: entity.anchorDate,
          frequency: entity.frequency
        )
      } else if Calendar.current.isDate(anchor, inSameDayAs: today) {
        occurrenceDates = [anchor]
      } else {
        occurrenceDates = []
      }

      batch.append(contentsOf: occurrenceDates.map { date in
        let converted = converted!
        let transaction = TransactionEntity(
          id: makeId(prefix: "tx_"),
          name: name,
          amountMinor: converted.amountMinor,
          occurredAt: DateHelpers.occurrenceTimestamp(date),
          categoryId: category.id,
          paymentMethodId: entity.paymentMethodId,
          currency: converted.currency,
          sourceCurrency: converted.sourceCurrency,
          sourceAmountMinor: converted.sourceAmountMinor,
          exchangeRate: converted.exchangeRate
        )
        return (.transaction, .transaction(transaction))
      })
    }
    write { try $0.saveEntities(batch) }
    closeOverlay()
    showToast(recurringDraft.editingId == nil ? "Recurring added" : "Recurring updated")
  }

  func openEditRecurring(_ id: String) {
    guard let rec = recurring.first(where: { $0.id == id }) else { return }
    recurringDraft = RecurringDraft(
      editingId: id,
      name: rec.name,
      amount: String(format: "%.2f", rec.amount),
      currency: rec.currency,
      category: rec.category,
      paymentMethodId: rec.paymentMethodId,
      frequency: rec.frequency ?? .monthly,
      anchorDate: rec.anchorDate ?? DateHelpers.localDateKey(Date()),
      paused: rec.paused
    )
    overlay = .recurring
  }

  func toggleRecurring(_ id: String) {
    // The projection already knows the current state, so the toast can be optimistic
    // while the read-modify-write runs off the main actor.
    guard let current = recurring.first(where: { $0.id == id }) else { return }
    let fallbackCurrency = currency.rawValue
    write { repository in
      guard let existing = try repository.activeEntities(type: .recurring)
        .first(where: { $0.entityId == id }),
        case .recurring(var payload) = existing.payload else { return }
      if payload.currency == nil { payload.currency = fallbackCurrency }
      payload.paused.toggle()
      try repository.saveEntity(entityType: .recurring, payload: .recurring(payload))
    }
    showToast(current.paused ? "Resumed" : "Paused")
  }

  func saveCategory() {
    let name = categoryDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let id = categoryDraft.editingId ?? makeId(prefix: "category_")
    let limit = Double(categoryDraft.limitText).flatMap { $0 > 0 ? Int(($0 * 100).rounded()) : nil }
    let existing = categories.first(where: { $0.id == id })
    let entity = CategoryEntity(
      id: id,
      name: name,
      emoji: categoryDraft.emoji.isEmpty ? defaultCategoryEmoji : categoryDraft.emoji,
      monthlyBudgetMinor: limit,
      tint: categoryDraft.tint,
      sortOrder: existing?.sortOrder ?? categories.count,
      system: existing?.system ?? false
    )
    write { try $0.saveEntity(entityType: .category, payload: .category(entity)) }
    closeOverlay()
    showToast(categoryDraft.editingId == nil ? "Category created" : "Category updated")
  }

  func openEditCategory(_ id: String) {
    guard let cat = categories.first(where: { $0.id == id }) else { return }
    categoryDraft = CategoryDraft(
      editingId: id,
      name: cat.name,
      emoji: cat.emoji,
      limitText: cat.monthlyBudgetMinor.map { String(format: "%.0f", Double($0) / 100) } ?? "",
      tint: cat.tint
    )
    overlay = .category
  }

  func applySuggestedBudgets(_ ids: Set<String>) {
    let suggestions = entities.suggestedBudgetUpdates
    var batch: [(EntityType, EntityPayload)] = []
    for suggestion in suggestions where ids.contains(suggestion.id) {
      guard var cat = categories.first(where: { $0.id == suggestion.id }) else { continue }
      cat.monthlyBudgetMinor = Int((suggestion.suggestedLimit * 100).rounded())
      batch.append((.category, .category(cat)))
    }
    write { try $0.saveEntities(batch) }
    showToast("Budgets updated")
  }

  func updatePreferences(mutate: (inout PreferencesEntity) -> Void) {
    var prefs = currentPreferences()
    mutate(&prefs)
    write { try $0.saveEntity(entityType: .preferences, payload: .preferences(prefs)) }
  }

  func pressAmountKey(_ key: String) {
    expenseDraft.amount = applyKeypad(expenseDraft.amount, key: key)
  }

  func exportCSV() -> String {
    let sources = transactions.map {
      TransactionCSV.Source(
        name: $0.name,
        category: $0.category,
        amount: $0.amount,
        amountMinor: $0.amountMinor,
        occurredAt: $0.occurredAt
      )
    }
    return TransactionCSV.format(sources)
  }

  /// Parsing and the batch write both run off the main actor; only id assignment and
  /// category de-duplication (which read main-actor state) stay here.
  func importCSV(_ text: String) async throws {
    let rows = try await Task.detached(priority: .userInitiated) {
      try TransactionCSV.parse(text)
    }.value
    let defaultPM = TransactionCSV.defaultPaymentMethodIdForImport(paymentMethods)
    var categoryByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name.lowercased(), $0) })
    var batch: [(EntityType, EntityPayload)] = []
    for row in rows {
      let key = row.category.lowercased()
      let category: CategoryEntity
      if let existing = categoryByName[key] {
        category = existing
      } else {
        let created = CategoryEntity(
          id: makeId(prefix: "category_"),
          name: row.category,
          emoji: TransactionCSV.categoryEmojiForName(row.category),
          monthlyBudgetMinor: nil,
          tint: .neutral,
          sortOrder: categories.count + batch.count,
          system: false
        )
        categoryByName[key] = created
        batch.append((.category, .category(created)))
        category = created
      }
      let tx = TransactionEntity(
        id: makeId(prefix: "tx_"),
        name: row.merchant,
        amountMinor: row.amountMinor,
        occurredAt: row.occurredAt,
        categoryId: category.id,
        paymentMethodId: defaultPM,
        currency: currency.rawValue
      )
      batch.append((.transaction, .transaction(tx)))
    }
    write { try $0.saveEntities(batch) }
    showToast("Imported \(rows.count) transactions")
  }

  func deleteHistory() {
    guard !deletingHistory, let repository else { return }
    deletingHistory = true
    Task {
      do {
        let count = try await Task.detached {
          try repository.removeActiveEntities(entityType: .transaction)
        }.value
        showToast(count == 1 ? "Transaction deleted" : "\(count) transactions deleted")
      } catch {
        showToast("Could not delete history")
      }
      deletingHistory = false
    }
  }

  func deleteTransactions(_ ids: [String]) {
    guard !ids.isEmpty else { return }
    write { try $0.removeEntities(entityType: .transaction, ids: ids) }
    showToast(ids.count == 1 ? "Transaction deleted" : "\(ids.count) transactions deleted")
  }

  @discardableResult
  func savePaymentMethod(
    id: String?,
    name: String,
    type: PaymentMethodType,
    detail: String
  ) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      showToast("Enter a name for this payment method.")
      return "Enter a name for this payment method."
    }
    let duplicate = paymentMethods.contains {
      $0.id != id && $0.name.lowercased() == trimmed.lowercased()
    }
    if duplicate {
      showToast("That payment method already exists.")
      return "That payment method already exists."
    }
    let methodId = id ?? makeId(prefix: "payment-method_")
    let entity = PaymentMethodEntity(
      id: methodId,
      name: trimmed,
      type: type,
      detail: type == .Cash ? "" : detail.trimmingCharacters(in: .whitespacesAndNewlines),
      archived: paymentMethods.first(where: { $0.id == methodId })?.archived ?? false
    )
    write { try $0.saveEntity(entityType: .paymentMethod, payload: .paymentMethod(entity)) }
    showToast(id == nil ? "Payment method added" : "Payment method updated")
    return nil
  }

  func setDefaultPaymentMethod(_ id: String) {
    updatePreferences { $0.defaultPaymentMethodId = id }
    showToast("Default payment updated")
  }

  func setPaymentMethodArchived(_ id: String, archived: Bool) {
    guard let method = paymentMethods.first(where: { $0.id == id }) else { return }
    if archived && id == SeedData.cashPaymentMethod.id {
      showToast("Cash can't be archived")
      return
    }
    let activeCount = paymentMethods.filter { !$0.archived }.count
    if archived && activeCount <= 1 {
      showToast("Keep at least one payment method")
      return
    }
    let entity = PaymentMethodEntity(
      id: method.id,
      name: method.name,
      type: method.type,
      detail: method.detail,
      archived: archived
    )
    var batch: [(EntityType, EntityPayload)] = [(.paymentMethod, .paymentMethod(entity))]
    if archived && method.isDefault {
      if let next = paymentMethods.first(where: { !$0.archived && $0.id != id }) {
        var prefs = currentPreferences()
        prefs.defaultPaymentMethodId = next.id
        batch.append((.preferences, .preferences(prefs)))
      }
    }
    write { try $0.saveEntities(batch) }
    showToast(archived ? "Payment method archived" : "Payment method restored")
  }

  func showToast(_ message: String) {
    toast = message
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      toast = nil
    }
  }

  // MARK: - Hydration

  /// Coalesce GRDB bursts (sync merges) so we project once per frame window.
  private func scheduleHydrate(_ batch: [StoredEntity]) {
    pendingHydrateEntities = batch
    hydrateTask?.cancel()
    hydrateTask = Task { @MainActor [weak self] in
      // ~1 frame at 60fps — enough to fold multi-page sync writes together.
      try? await Task.sleep(nanoseconds: 16_000_000)
      guard let self, !Task.isCancelled else { return }
      guard let pending = self.pendingHydrateEntities else { return }
      self.pendingHydrateEntities = nil
      await self.hydrateNow(pending)
    }
  }

  private func hydrateNow(_ batch: [StoredEntity]) async {
    let previousDefault = entities.defaultStatsRange
    let previousSnapshot = entities.lastEntitySnapshot
    let snapshot = await EntityHydrator.project(
      entities: batch,
      rates: entities.rates,
      currentStatsRange: nav.statsRange,
      previousDefaultStatsRange: previousDefault,
      dataReady: entities.dataReady,
      profileName: entities.profileName,
      profileEmail: entities.profileEmail,
      previous: previousSnapshot
    )
    guard let snapshot else { return }
    let derived = await EntityHydrator.derive(
      transactions: snapshot.transactions,
      recurring: snapshot.recurring,
      lends: snapshot.lends,
      limits: snapshot.limits,
      categories: snapshot.categories
    )
    entities.apply(
      snapshot: snapshot,
      derived: derived,
      filter: nav.filter,
      selectedMonth: nav.selectedMonth,
      categoriesExpanded: nav.categoriesExpanded,
      merchantsExpanded: nav.merchantsExpanded
    )
    nav.statsRange = snapshot.statsRange

    let emailRelevant: Bool
    if let previousSnapshot {
      emailRelevant =
        snapshot.fingerprints.emailRelevantChanges(from: previousSnapshot.fingerprints)
        || previousSnapshot.preferences.currency != snapshot.preferences.currency
    } else {
      emailRelevant = true
    }
    if emailRelevant {
      emailController?.updateDomain(
        categories: entities.categories,
        paymentMethods: entities.paymentMethods,
        transactions: entities.transactions,
        currency: entities.currency
      )
    }
  }

  /// Soft-pauses on-device email analysis while the user is actively scrolling.
  func setUIScrolling(_ scrolling: Bool) {
    emailController?.setUIScrolling(scrolling)
  }

  /// Serial queue for store mutations. A detached task per write would let two rapid
  /// edits of the same entity reach SQLite out of submission order, and the loser
  /// would take the higher logical version. FIFO keeps last-write-wins matching what
  /// the user actually did last.
  private static let writeQueue = DispatchQueue(
    label: "app.dimo.store-writes",
    qos: .userInitiated
  )

  /// Runs a repository mutation off the main actor.
  ///
  /// SQLite commits block the calling thread. Performed inline from a `@MainActor`
  /// mutation they cost a frame on every save; the caller updates the UI
  /// optimistically and the durable result arrives through the entity observation.
  private func write(
    _ operation: @escaping @Sendable (Repository) throws -> Void
  ) {
    guard let repository else { return }
    Self.writeQueue.async { [weak self] in
      do {
        try operation(repository)
      } catch {
        Task { @MainActor in self?.showToast(error.localizedDescription) }
      }
    }
  }

  /// Counts the outbox off the main actor — this runs after every local write and on
  /// every syncMeta change, so it must not put SQLite reads on the UI thread.
  private func refreshOutboxCounts(repository repo: Repository) async {
    guard let counts = try? await Task.detached(priority: .utility, operation: {
      try repo.outboxCounts()
    }).value else { return }
    syncStatus.pendingCount = counts.pending
    syncStatus.blockedCount = counts.blocked
  }

  private func scheduleProjectionRefresh() {
    entities.refreshProjections(
      filter: nav.filter,
      statsRange: nav.statsRange,
      selectedMonth: nav.selectedMonth,
      categoriesExpanded: nav.categoriesExpanded,
      merchantsExpanded: nav.merchantsExpanded
    )
  }

  private func currentPreferences() -> PreferencesEntity {
    PreferencesEntity(
      id: "preferences",
      profileName: profileName,
      profileEmail: profileEmail,
      currency: currency,
      weekStart: .Mon,
      theme: theme,
      navGlassOpacity: Int(navGlassOpacity),
      defaultView: .home,
      defaultStatsRange: defaultStatsRange,
      notifications: notifications,
      defaultPaymentMethodId: paymentMethods.first(where: \.isDefault)?.id
        ?? SeedData.cashPaymentMethod.id
    )
  }

  private func preferredPaymentMethodId() -> String {
    if let last = try? repository?.deviceMeta()?.lastPaymentMethodId,
       paymentMethods.contains(where: { $0.id == last && !$0.archived }) {
      return last
    }
    return paymentMethods.first(where: { $0.isDefault && !$0.archived })?.id
      ?? paymentMethods.first(where: { !$0.archived })?.id
      ?? SeedData.cashPaymentMethod.id
  }

  private func resolvedPaymentMethodId(_ requested: String?) -> String {
    if let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines),
       !requested.isEmpty,
       paymentMethods.contains(where: { $0.id == requested }) {
      return requested
    }
    return preferredPaymentMethodId()
  }

  private func makeId(prefix: String) -> String {
    idCounter += 1
    return "\(prefix)\(Int(Date().timeIntervalSince1970 * 1000))_\(idCounter)"
  }

  private func applyKeypad(_ current: String, key: String) -> String {
    if key == "⌫" {
      return current.isEmpty ? "" : String(current.dropLast())
    }
    if key == "." {
      return current.contains(".") ? current : (current.isEmpty ? "0." : current + ".")
    }
    let digits = current.filter { $0.isNumber }
    if digits.count >= 7 { return current }
    if current == "0" && key != "." { return key }
    return current + key
  }
}

struct ExpenseDraft: Equatable {
  var name = ""
  var amount = ""
  var category = ""
  var paymentMethodId: String?
  var date = Date()
}

struct RecurringDraft: Equatable {
  var editingId: String?
  var name = ""
  var amount = ""
  var currency: String?
  var category = "Bills"
  var paymentMethodId: String?
  var frequency: RecurringFrequency = .monthly
  var anchorDate = DateHelpers.localDateKey(Date())
  var paused = false
}

struct CategoryDraft: Equatable {
  var editingId: String?
  var name = ""
  var emoji = "🙂"
  var limitText = ""
  var tint: CategoryTint = .neutral
}

struct LendDraft: Equatable {
  var editingId: String?
  var kind: LendKind = .lent
  var contactName = ""
  var contactId: String?
  var amount = ""
  var date = Date()
  var comment = ""
}

extension AppStore {
  /// Resolves a row emoji the same way the web does: explicit value, then the
  /// category looked up by id, then by name, then the default.
  func categoryEmoji(explicit: String?, categoryId: String?, category: String) -> String {
    entities.categoryEmoji(explicit: explicit, categoryId: categoryId, category: category)
  }
}
