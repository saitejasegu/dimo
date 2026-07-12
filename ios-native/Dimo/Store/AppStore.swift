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
  var lends: [Lend] = []
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
  var deletingHistory = false

  var expenseDraft = ExpenseDraft()
  var recurringDraft = RecurringDraft()
  var categoryDraft = CategoryDraft()
  var lendDraft = LendDraft()

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
      await coordinator.setProfile(name: profileName, email: profileEmail)
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
        category: "",
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
    case .lend:
      lendDraft = LendDraft()
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

  func saveLend() {
    guard let amount = Double(lendDraft.amount), amount > 0 else { return }
    let contact = lendDraft.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !contact.isEmpty else { return }
    let existing = lendDraft.editingId.flatMap { id in lends.first { $0.id == id } }
    guard let contactId = lendDraft.contactId ?? existing?.contactId else { return }
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
    try? repository?.saveEntity(entityType: .lend, payload: .lend(entity))
    closeOverlay()
    let kind = existing?.kind ?? lendDraft.kind
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

  func openAddRepayment(contactName: String, contactId: String, outstanding: Double = 0) {
    let amount: String
    if outstanding > 0 {
      amount = outstanding.rounded() == outstanding
        ? String(Int(outstanding))
        : String(format: "%.2f", outstanding)
    } else {
      amount = ""
    }
    lendDraft = LendDraft(kind: .repaid, contactName: contactName, contactId: contactId, amount: amount)
    overlay = .lend
  }

  func deleteLend(_ id: String) {
    try? repository?.removeEntity(entityType: .lend, id: id)
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

  func deleteTransaction(_ id: String) {
    try? repository?.removeEntity(entityType: .transaction, id: id)
    closeDetail()
    showToast("Transaction deleted")
  }

  func deleteRecurring(_ id: String) {
    try? repository?.removeEntity(entityType: .recurring, id: id)
    closeOverlay()
    showToast("Recurring transaction deleted")
  }

  func deleteCategoryAndTransactions(_ categoryId: String) {
    let transactionIds = transactions.filter { $0.categoryId == categoryId }.map(\.id)
    for id in transactionIds {
      try? repository?.removeEntity(entityType: .transaction, id: id)
    }
    try? repository?.removeEntity(entityType: .category, id: categoryId)
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

  func saveRecurring(includeHistoricalTransactions: Bool = false) {
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
        let transaction = TransactionEntity(
          id: makeId(prefix: "tx_"),
          name: name,
          amountMinor: entity.amountMinor,
          occurredAt: DateHelpers.occurrenceTimestamp(date),
          categoryId: category.id,
          paymentMethodId: entity.paymentMethodId
        )
        return (.transaction, .transaction(transaction))
      })
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
    guard let method = paymentMethods.first(where: { $0.id == id }) else { return }
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
    var nextLends: [LendEntity] = []
    var prefs = SeedData.defaultPreferences

    for entity in active {
      switch entity.payload {
      case .category(let c): nextCategories.append(c)
      case .paymentMethod(let p): nextPaymentMethods.append(p)
      case .transaction(let t): nextTransactions.append(t)
      case .recurring(let r): nextRecurring.append(r)
      case .lend(let l): nextLends.append(l)
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

    lends = nextLends
      .sorted { $0.occurredAt > $1.occurredAt }
      .map { lend in
        Lend(
          id: lend.id,
          contactName: lend.contactName,
          contactId: lend.contactId,
          amount: Double(lend.amountMinor) / 100,
          comment: lend.comment,
          time: DateHelpers.formatTransactionTime(lend.occurredAt),
          day: DateHelpers.formatTransactionDay(lend.occurredAt),
          amountMinor: lend.amountMinor,
          occurredAt: lend.occurredAt,
          kind: lend.kind ?? .lent
        )
      }

    nextRecurring.sort {
      DateHelpers.nextOccurrence(anchorDate: $0.anchorDate, frequency: $0.frequency)
        < DateHelpers.nextOccurrence(anchorDate: $1.anchorDate, frequency: $1.frequency)
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
  var category = ""
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
    explicit
      ?? categories.first(where: { $0.id == categoryId })?.emoji
      ?? categories.first(where: { $0.name == category })?.emoji
      ?? "🙂"
  }
}
