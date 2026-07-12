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
  private(set) var profileName: String
  private(set) var profileEmail: String
  private(set) var profilePhotoUrl: String?

  var view: ViewKey = .home
  var accountReturnView: ViewKey?
  var overlay: OverlayKey?
  var detailId: String?
  var toast: String?
  private var toastTask: Task<Void, Never>?

  var transactions: [Transaction] = []
  var recurring: [Recurring] = []
  var categories: [CategoryEntity] = []
  var paymentMethods: [PaymentMethodOption] = []
  var limits: CategoryLimits = [:]
  var filter = TransactionFilter()
  var statsRange: StatsRange = .oneYear
  var selectedMonth: String?
  var merchantsExpanded = false
  var categoriesExpanded = false
  var currency: Currency = .INR
  var theme: ThemePreference = .light
  var navGlassOpacity: Double = 40
  var defaultStatsRange: StatsRange = .oneYear
  var notifications = NotificationSettings(bills: true, budget: true, weekly: false, large: true)
  var dataReady = false
  var syncMeta: SyncMeta?
  var pendingCount = 0
  var blockedCount = 0

  var expenseDraft = ExpenseDraft()
  var recurringDraft = RecurringDraft()
  var categoryDraft = CategoryDraft()

  private let authProvider: WorkOSAuthProvider
  private var repository: Repository?
  private var coordinator: SyncCoordinator?
  private var convexClient: ConvexClientWithAuth<WorkOSSession>?
  private var entityObservation: DatabaseCancellable?
  private var syncObservation: DatabaseCancellable?
  private var writeListener: UUID?
  private var idCounter = 0

  init(
    userId: String,
    profileName: String,
    profileEmail: String,
    profilePhotoUrl: String? = nil,
    authProvider: WorkOSAuthProvider
  ) {
    self.userId = userId
    self.profileName = profileName
    self.profileEmail = profileEmail
    self.profilePhotoUrl = profilePhotoUrl
    self.authProvider = authProvider
  }

  func start() async {
    do {
      let db = try AppDatabase.activate(userId: userId)
      let repo = Repository(db: db)
      try repo.initializeLocalDatabase()
      repository = repo

      let client = ConvexClientWithAuth(
        deploymentUrl: AppConfig.convexURL,
        authProvider: authProvider
      )
      _ = await client.loginFromCache()
      convexClient = client

      let transport = ConvexSyncTransport(client: client)
      let coordinator = SyncCoordinator(repository: repo, transport: transport)
      self.coordinator = coordinator
      await coordinator.start()

      entityObservation = repo.observeEntities { [weak self] entities in
        Task { @MainActor in self?.hydrate(entities: entities) }
      }
      syncObservation = repo.observeSyncMeta { [weak self] meta in
        Task { @MainActor in
          self?.syncMeta = meta
          if let counts = try? self?.repository?.outboxCounts() {
            self?.pendingCount = counts.pending
            self?.blockedCount = counts.blocked
          }
        }
      }
      writeListener = repo.onLocalWrite { [weak self] in
        Task { @MainActor in
          if let counts = try? self?.repository?.outboxCounts() {
            self?.pendingCount = counts.pending
            self?.blockedCount = counts.blocked
          }
        }
      }
      let entities = try repo.allEntities()
      hydrate(entities: entities)
      dataReady = true
    } catch {
      showToast(error.localizedDescription)
    }
  }

  func tearDown() {
    entityObservation?.cancel()
    syncObservation?.cancel()
    if let writeListener { repository?.removeLocalWriteListener(writeListener) }
    Task { await coordinator?.stop() }
    coordinator = nil
    repository = nil
    convexClient = nil
  }

  func sceneBecameActive() {
    Task { await coordinator?.request() }
  }

  func syncNow() {
    Task { await coordinator?.request() }
  }

  func requestFullSync() {
    Task { await coordinator?.requestFullSync() }
  }

  func clearCloudWorkspace() async throws {
    try await coordinator?.clearCloudWorkspace()
  }

  // MARK: - Navigation

  func setView(_ view: ViewKey) {
    self.view = view == .tx ? .home : view
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
        category: categories.first?.name ?? "Dining",
        paymentMethodId: preferredPaymentMethodId()
      )
    case .recurring:
      recurringDraft = RecurringDraft(
        category: categories.first(where: { $0.name == "Bills" })?.name ?? categories.first?.name ?? "Bills",
        paymentMethodId: preferredPaymentMethodId(),
        anchorDate: DateHelpers.localDateKey(Date())
      )
    case .category:
      categoryDraft = CategoryDraft()
    }
    overlay = key
  }

  func closeOverlay() { overlay = nil }
  func openDetail(_ id: String) { detailId = id }
  func closeDetail() { detailId = nil }

  // MARK: - Mutations

  func saveExpense() {
    guard let amount = Double(expenseDraft.amount), amount > 0 else { return }
    guard let category = categories.first(where: { $0.name == expenseDraft.category }) else { return }
    let id = makeId(prefix: "tx_")
    let entity = TransactionEntity(
      id: id,
      name: expenseDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "Expense" : expenseDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
      amountMinor: Int((amount * 100).rounded()),
      occurredAt: Int(Date().timeIntervalSince1970 * 1000),
      categoryId: category.id,
      paymentMethodId: expenseDraft.paymentMethodId
    )
    try? repository?.saveEntity(entityType: .transaction, payload: .transaction(entity))
    try? repository?.setLastPaymentMethod(expenseDraft.paymentMethodId)
    filter = TransactionFilter()
    closeOverlay()
    setView(.home)
    showToast("Expense saved")
  }

  func deleteTransaction(_ id: String) {
    try? repository?.removeEntity(entityType: .transaction, id: id)
    closeDetail()
    showToast("Transaction deleted")
  }

  func saveTransactionEdits(
    id: String,
    name: String,
    amount: Double,
    categoryName: String,
    paymentMethodId: String?
  ) {
    guard amount > 0,
          let category = categories.first(where: { $0.name == categoryName }),
          let existing = transactions.first(where: { $0.id == id }) else { return }
    let entity = TransactionEntity(
      id: id,
      name: name,
      amountMinor: Int((amount * 100).rounded()),
      occurredAt: existing.occurredAt ?? Int(Date().timeIntervalSince1970 * 1000),
      categoryId: category.id,
      paymentMethodId: paymentMethodId
    )
    try? repository?.saveEntity(entityType: .transaction, payload: .transaction(entity))
    closeDetail()
    showToast("Transaction updated")
  }

  func saveRecurring() {
    guard let amount = Double(recurringDraft.amount), amount > 0 else { return }
    guard let category = categories.first(where: { $0.name == recurringDraft.category }) else { return }
    let name = recurringDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let id = recurringDraft.editingId ?? makeId(prefix: "rec_")
    let entity = RecurringEntity(
      id: id,
      name: name,
      amountMinor: Int((amount * 100).rounded()),
      categoryId: category.id,
      paymentMethodId: recurringDraft.paymentMethodId,
      frequency: recurringDraft.frequency,
      anchorDate: recurringDraft.anchorDate,
      paused: recurringDraft.paused
    )
    var batch: [(EntityType, EntityPayload)] = [(.recurring, .recurring(entity))]
    if recurringDraft.editingId == nil {
      let tx = TransactionEntity(
        id: makeId(prefix: "tx_"),
        name: name,
        amountMinor: entity.amountMinor,
        occurredAt: DateHelpers.occurrenceTimestamp(DateHelpers.parseLocalDate(entity.anchorDate)),
        categoryId: category.id,
        paymentMethodId: entity.paymentMethodId
      )
      batch.append((.transaction, .transaction(tx)))
    }
    try? repository?.saveEntities(batch)
    closeOverlay()
    showToast(recurringDraft.editingId == nil ? "Recurring added" : "Recurring updated")
  }

  func openEditRecurring(_ id: String) {
    guard let rec = recurring.first(where: { $0.id == id }) else { return }
    recurringDraft = RecurringDraft(
      editingId: id,
      name: rec.name,
      amount: String(format: "%.2f", rec.amount),
      category: rec.category,
      paymentMethodId: rec.paymentMethodId,
      frequency: rec.frequency ?? .monthly,
      anchorDate: rec.anchorDate ?? DateHelpers.localDateKey(Date()),
      paused: rec.paused
    )
    overlay = .recurring
  }

  func toggleRecurring(_ id: String) {
    guard let existing = try? repository?.activeEntities(type: .recurring)
      .first(where: { $0.entityId == id }),
      case .recurring(var payload) = existing.payload else { return }
    payload.paused.toggle()
    try? repository?.saveEntity(entityType: .recurring, payload: .recurring(payload))
    showToast(payload.paused ? "Paused" : "Resumed")
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
    try? repository?.saveEntity(entityType: .category, payload: .category(entity))
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
    let suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
      transactions,
      categories: categories.map { ($0.id, $0.name, $0.monthlyBudgetMinor) }
    )
    var batch: [(EntityType, EntityPayload)] = []
    for suggestion in suggestions where ids.contains(suggestion.id) {
      guard var cat = categories.first(where: { $0.id == suggestion.id }) else { continue }
      cat.monthlyBudgetMinor = Int((suggestion.suggestedLimit * 100).rounded())
      batch.append((.category, .category(cat)))
    }
    try? repository?.saveEntities(batch)
    showToast("Budgets updated")
  }

  func updatePreferences(mutate: (inout PreferencesEntity) -> Void) {
    var prefs = currentPreferences()
    mutate(&prefs)
    try? repository?.saveEntity(entityType: .preferences, payload: .preferences(prefs))
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

  func importCSV(_ text: String) throws {
    let rows = try TransactionCSV.parse(text)
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
        paymentMethodId: defaultPM
      )
      batch.append((.transaction, .transaction(tx)))
    }
    try repository?.saveEntities(batch)
    showToast("Imported \(rows.count) transactions")
  }

  func deleteHistory() {
    let txs = (try? repository?.activeEntities(type: .transaction)) ?? []
    for tx in txs {
      try? repository?.removeEntity(entityType: .transaction, id: tx.entityId)
    }
    showToast("History deleted")
  }

  func deleteTransactions(_ ids: [String]) {
    guard !ids.isEmpty else { return }
    for id in ids {
      try? repository?.removeEntity(entityType: .transaction, id: id)
    }
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
    try? repository?.saveEntity(entityType: .paymentMethod, payload: .paymentMethod(entity))
    showToast(id == nil ? "Payment method added" : "Payment method updated")
    return nil
  }

  func setDefaultPaymentMethod(_ id: String) {
    updatePreferences { $0.defaultPaymentMethodId = id }
    showToast("Default payment updated")
  }

  func setPaymentMethodArchived(_ id: String, archived: Bool) {
    guard var method = paymentMethods.first(where: { $0.id == id }) else { return }
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
    try? repository?.saveEntities(batch)
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

  private func hydrate(entities: [StoredEntity]) {
    let active = entities.filter { !$0.deleted }
    var nextCategories: [CategoryEntity] = []
    var nextPaymentMethods: [PaymentMethodEntity] = []
    var nextTransactions: [TransactionEntity] = []
    var nextRecurring: [RecurringEntity] = []
    var prefs = SeedData.defaultPreferences

    for entity in active {
      switch entity.payload {
      case .category(let c): nextCategories.append(c)
      case .paymentMethod(let p): nextPaymentMethods.append(p)
      case .transaction(let t): nextTransactions.append(t)
      case .recurring(let r): nextRecurring.append(r)
      case .preferences(let p): prefs = p
      }
    }

    nextCategories.sort { $0.sortOrder < $1.sortOrder }
    categories = nextCategories
    limits = Dictionary(uniqueKeysWithValues: nextCategories.map {
      ($0.name, $0.monthlyBudgetMinor.map { Double($0) / 100 })
    })
    let defaultPM = prefs.defaultPaymentMethodId
    paymentMethods = nextPaymentMethods
      .sorted { $0.name < $1.name }
      .map {
        PaymentMethodOption(
          id: $0.id, name: $0.name, type: $0.type, detail: $0.detail,
          isDefault: $0.id == defaultPM, archived: $0.archived
        )
      }

    let categoryById = Dictionary(uniqueKeysWithValues: nextCategories.map { ($0.id, $0) })
    let pmById = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0) })

    transactions = nextTransactions
      .sorted { $0.occurredAt > $1.occurredAt }
      .map { tx in
        let cat = categoryById[tx.categoryId]
        let pm = tx.paymentMethodId.flatMap { pmById[$0] }
        return Transaction(
          id: tx.id,
          name: tx.name,
          category: cat?.name ?? "Unknown",
          time: DateHelpers.formatTransactionTime(tx.occurredAt),
          day: DateHelpers.formatTransactionDay(tx.occurredAt),
          amount: Double(tx.amountMinor) / 100,
          paymentMethod: pm?.label,
          green: cat?.tint == .green,
          emoji: cat?.emoji,
          amountMinor: tx.amountMinor,
          occurredAt: tx.occurredAt,
          categoryId: tx.categoryId,
          paymentMethodId: tx.paymentMethodId
        )
      }

    recurring = nextRecurring.map { rec in
      let cat = categoryById[rec.categoryId]
      return Recurring(
        id: rec.id,
        name: rec.name,
        category: cat?.name ?? "",
        due: DateHelpers.recurringDueLabel(anchorDate: rec.anchorDate, frequency: rec.frequency),
        amount: Double(rec.amountMinor) / 100,
        paused: rec.paused,
        green: cat?.tint == .green,
        emoji: cat?.emoji,
        amountMinor: rec.amountMinor,
        categoryId: rec.categoryId,
        paymentMethodId: rec.paymentMethodId,
        anchorDate: rec.anchorDate,
        frequency: rec.frequency
      )
    }

    currency = prefs.currency
    theme = prefs.theme
    navGlassOpacity = Double(prefs.navGlassOpacity)
    defaultStatsRange = prefs.defaultStatsRange
    notifications = prefs.notifications
    if !dataReady {
      statsRange = prefs.defaultStatsRange
    }
    profileName = profileName.isEmpty ? prefs.profileName : profileName
    profileEmail = profileEmail.isEmpty ? prefs.profileEmail : profileEmail
    dataReady = true
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

  private func preferredPaymentMethodId() -> String? {
    if let last = try? repository?.deviceMeta()?.lastPaymentMethodId,
       paymentMethods.contains(where: { $0.id == last && !$0.archived }) {
      return last
    }
    return paymentMethods.first(where: { $0.isDefault && !$0.archived })?.id
      ?? paymentMethods.first(where: { !$0.archived })?.id
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
  var category = "Dining"
  var paymentMethodId: String?
}

struct RecurringDraft: Equatable {
  var editingId: String?
  var name = ""
  var amount = ""
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

extension AppStore {
  /// Resolves a row emoji the same way the web does: explicit value, then the
  /// category looked up by id, then by name, then the default.
  func categoryEmoji(explicit: String?, categoryId: String?, category: String) -> String {
    explicit
      ?? categories.first(where: { $0.id == categoryId })?.emoji
      ?? categories.first(where: { $0.name == category })?.emoji
      ?? "🙂"
  }
}
