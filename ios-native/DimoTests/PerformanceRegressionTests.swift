import GRDB
import XCTest
@testable import Dimo

/// Behaviour guards for the hydration, selector and storage shortcuts that keep work
/// off the main thread or out of per-row loops. Each shortcut must produce exactly
/// what the slow path produced.
final class EntityBatchTests: XCTestCase {
  func testBatchFingerprintsMatchFlatComputation() {
    let entities = HydrationFixture.entities(transactionCount: 20)
    XCTAssertEqual(EntityBatch(entities).fingerprints, EntityTypeFingerprints.compute(entities))
    XCTAssertEqual(EntityBatch(entities).all.count, entities.count)
  }

  func testReplacingOneTypeChangesOnlyThatFingerprint() {
    var batch = EntityBatch(HydrationFixture.entities(transactionCount: 5))
    let before = batch.fingerprints
    batch.replace(.lend, with: [HydrationFixture.lend("lend-1", minor: 5_000)])
    let after = batch.fingerprints
    XCTAssertNotEqual(before.lend, after.lend)
    XCTAssertEqual(before.transaction, after.transaction)
    XCTAssertEqual(before.category, after.category)
    XCTAssertEqual(before.preferencesProjection, after.preferencesProjection)
  }

  func testBatchIsCompleteOnlyAfterEveryTypeDelivered() {
    var batch = EntityBatch()
    XCTAssertFalse(batch.isComplete)
    for type in EntityBatch.types.dropLast() { batch.replace(type, with: []) }
    XCTAssertFalse(batch.isComplete)
    batch.replace(EntityBatch.types.last!, with: [])
    XCTAssertTrue(batch.isComplete)
  }
}

final class IncrementalHydrationTests: XCTestCase {
  private let calendar = Calendar.current

  private func project(
    _ batch: EntityBatch,
    previous: EntitySnapshot?,
    now: Date = Date()
  ) async -> EntitySnapshot? {
    await EntityHydrator.project(
      batch: batch,
      rates: nil,
      currentStatsRange: .oneYear,
      previousDefaultStatsRange: .oneYear,
      dataReady: previous != nil,
      profileName: "",
      profileEmail: "",
      previous: previous,
      now: now
    )
  }

  func testUnchangedBatchOnSameDaySkipsRebuild() async throws {
    let batch = EntityBatch(HydrationFixture.entities(transactionCount: 3))
    let first = try await XCTUnwrapAsync(await project(batch, previous: nil))
    let second = await project(batch, previous: first)
    XCTAssertNil(second)
  }

  func testEditingOneTransactionReusesEveryOtherBuiltRow() async throws {
    var entities = HydrationFixture.entities(transactionCount: 4)
    let first = try await XCTUnwrapAsync(await project(EntityBatch(entities), previous: nil))

    // Poison the cached rows. A reused row keeps the poisoned name; a rebuilt row
    // does not, which is how this test tells the two paths apart.
    var poisoned = first
    for (id, cached) in poisoned.transactionRows {
      var row = cached.row
      row.name = "cached-\(id)"
      poisoned.transactionRows[id] = CachedTransactionRow(entity: cached.entity, row: row)
    }

    let index = entities.firstIndex { $0.entityId == "tx-2" }!
    entities[index] = HydrationFixture.transaction("tx-2", name: "Edited", minor: 99_900, counter: 50)
    let second = try await XCTUnwrapAsync(await project(EntityBatch(entities), previous: poisoned))

    let names = Dictionary(uniqueKeysWithValues: second.transactions.map { ($0.id, $0.name) })
    XCTAssertEqual(names["tx-2"], "Edited")
    XCTAssertEqual(second.transactions.first { $0.id == "tx-2" }?.amount, 999)
    XCTAssertEqual(names["tx-0"], "cached-tx-0")
    XCTAssertEqual(names["tx-3"], "cached-tx-3")
    XCTAssertEqual(second.transactions.map(\.id), ["tx-0", "tx-1", "tx-2", "tx-3"])
  }

  func testCategoryRenameRebuildsEveryRowLabel() async throws {
    var entities = HydrationFixture.entities(transactionCount: 3)
    let first = try await XCTUnwrapAsync(await project(EntityBatch(entities), previous: nil))
    let index = entities.firstIndex { $0.entityType == .category }!
    entities[index] = HydrationFixture.category(name: "Dining out", counter: 9)
    let second = try await XCTUnwrapAsync(await project(EntityBatch(entities), previous: first))
    XCTAssertEqual(Set(second.transactions.map(\.category)), ["Dining out"])
    XCTAssertTrue(second.transactions.allSatisfy { $0.searchText.contains("dining out") })
  }

  func testNewCalendarDayRelabelsTodayAsYesterdayWithoutDataChange() async throws {
    let day1 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 20))!
    let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
    let at = Int(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day1)!.timeIntervalSince1970 * 1000)
    let batch = EntityBatch(HydrationFixture.entities(transactionCount: 1, occurredAt: at))

    let first = try await XCTUnwrapAsync(await project(batch, previous: nil, now: day1))
    XCTAssertEqual(first.transactions.first?.day, "Today")

    let second = try await XCTUnwrapAsync(await project(batch, previous: first, now: day2))
    XCTAssertEqual(second.transactions.first?.day, "Yesterday")
    XCTAssertNotEqual(first.todayKey, second.todayKey)
  }

  func testDayChangeMarksEveryDerivedSliceDirty() async throws {
    let day1 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 20))!
    let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
    let batch = EntityBatch(HydrationFixture.entities(transactionCount: 1))
    let first = try await XCTUnwrapAsync(await project(batch, previous: nil, now: day1))
    let second = try await XCTUnwrapAsync(await project(batch, previous: first, now: day2))
    let dirty = DeriveDirtyFlags.from(previous: first, next: second)
    XCTAssertTrue(dirty.budgets && dirty.lends && dirty.upcoming)
  }

  func testRowsCarryPreformattedSpendLabel() async throws {
    let batch = EntityBatch(HydrationFixture.entities(transactionCount: 1))
    let snapshot = try await XCTUnwrapAsync(await project(batch, previous: nil))
    let row = try XCTUnwrap(snapshot.transactions.first)
    XCTAssertEqual(row.spentLabel, Formatting.spent(row.amount, currency: .INR))
    var bare = row
    bare.spentLabel = ""
    XCTAssertEqual(bare.spentText(currency: .INR), row.spentLabel)
  }

  func testRecurringOrderedByNextOccurrence() async throws {
    var entities = HydrationFixture.entities(transactionCount: 0)
    let today = Date()
    func anchor(_ days: Int) -> String {
      DateHelpers.localDateKey(calendar.date(byAdding: .day, value: days, to: today)!)
    }
    entities += [
      HydrationFixture.recurring("late", anchorDate: anchor(20)),
      HydrationFixture.recurring("soon", anchorDate: anchor(2)),
      HydrationFixture.recurring("mid", anchorDate: anchor(9)),
    ]
    let snapshot = try await XCTUnwrapAsync(await project(EntityBatch(entities), previous: nil))
    XCTAssertEqual(snapshot.recurring.map(\.id), ["soon", "mid", "late"])
  }
}

final class SelectorShortcutTests: XCTestCase {
  private func rows() -> [Transaction] {
    let base = 1_758_000_000_000
    return (0..<40).map { index in
      Transaction(
        id: "t\(index)",
        name: index.isMultiple(of: 3) ? "Zepto" : "Cafe \(index)",
        category: index.isMultiple(of: 2) ? "Food" : "Travel",
        time: "",
        day: "",
        amount: Double(index),
        paymentMethod: index.isMultiple(of: 5) ? "Card" : "Cash",
        occurredAt: index == 7 ? nil : base - index * 86_400_000
      )
    }
  }

  func testCountMatchesFilteredCountForEveryFilterShape() {
    let transactions = rows()
    let base = Date(timeIntervalSince1970: 1_758_000_000)
    let filters = [
      TransactionFilter(),
      TransactionFilter(categories: ["Food"]),
      TransactionFilter(paymentMethod: "Card"),
      TransactionFilter(query: "  ZEP "),
      TransactionFilter(startDate: base.addingTimeInterval(-10 * 86_400)),
      TransactionFilter(endDate: base.addingTimeInterval(-20 * 86_400)),
      TransactionFilter(
        categories: ["Food", "Travel"],
        paymentMethod: "Cash",
        query: "cafe",
        startDate: base.addingTimeInterval(-30 * 86_400),
        endDate: base
      ),
    ]
    for filter in filters {
      XCTAssertEqual(
        TransactionSelectors.countTransactions(transactions, filter: filter),
        TransactionSelectors.filterTransactions(transactions, filter: filter).count,
        "\(filter)"
      )
    }
  }

  func testEarlierDataShortcutMatchesFullScan() {
    let transactions = rows().filter { $0.occurredAt != nil }
    let now = Date(timeIntervalSince1970: 1_758_000_000)
    let oldest = transactions.compactMap(\.occurredAt).min()
    for range in StatsConstants.ranges {
      for offset in [0, -1, -2, -6] {
        XCTAssertEqual(
          StatsSelectors.hasEarlierData(oldestOccurredAt: oldest, range: range, offset: offset, now: now),
          StatsSelectors.hasEarlierData(transactions, range: range, offset: offset, now: now),
          "\(range) \(offset)"
        )
      }
    }
    XCTAssertFalse(StatsSelectors.hasEarlierData(oldestOccurredAt: nil, range: .month, offset: 0))
  }

  func testPartialStatsRecomputeEqualsFullRecompute() {
    let now = Date()
    let transactions = (0..<60).map { index in
      Transaction(
        id: "s\(index)", name: "Merchant \(index % 9)", category: "Cat \(index % 7)",
        time: "", day: "", amount: Double(10 + index),
        occurredAt: Int(now.addingTimeInterval(Double(-index) * 86_400 * 5).timeIntervalSince1970 * 1000)
      )
    }
    let base = StatsInputs(
      revision: 3, range: .oneYear, periodOffset: 0, selectedMonth: nil,
      categoriesExpanded: false, merchantsExpanded: false
    )
    let first = EntityHydrator.buildStats(transactions: transactions, inputs: base, reusing: nil)
    let bar = first.trendBars.bars.dropLast(2).last?.key
    var variants = [base]
    var selected = base; selected.selectedMonth = bar; variants.append(selected)
    var cats = base; cats.categoriesExpanded = true; variants.append(cats)
    var merchants = base; merchants.merchantsExpanded = true; variants.append(merchants)
    for inputs in variants {
      let partial = EntityHydrator.buildStats(
        transactions: transactions, inputs: inputs, reusing: (base, first)
      )
      let full = EntityHydrator.buildStats(transactions: transactions, inputs: inputs, reusing: nil)
      XCTAssertEqual(partial, full, "\(inputs)")
    }
  }

  func testDaysRemainingCountsToday() {
    let calendar = Calendar(identifier: .gregorian)
    let sep25 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
    let sep30 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!
    XCTAssertEqual(BudgetSelectors.daysRemainingInMonth(now: sep25, calendar: calendar), 6)
    XCTAssertEqual(BudgetSelectors.daysRemainingInMonth(now: sep30, calendar: calendar), 1)
  }
}

@MainActor
final class EntitiesStoreShortcutTests: XCTestCase {
  func testOldestTransactionTracksAssignments() {
    let store = EntitiesStore()
    XCTAssertNil(store.oldestTransactionAt)
    store.transactions = [
      Transaction(id: "a", name: "", category: "", time: "", day: "", amount: 1, occurredAt: 500),
      Transaction(id: "b", name: "", category: "", time: "", day: "", amount: 1, occurredAt: 200),
    ]
    XCTAssertEqual(store.oldestTransactionAt, 200)
    store.transactions.append(
      Transaction(id: "c", name: "", category: "", time: "", day: "", amount: 1, occurredAt: nil)
    )
    XCTAssertEqual(store.oldestTransactionAt, 0)
  }

  func testMatchCountAgreesWithFilteredRows() {
    let store = EntitiesStore()
    store.transactions = (0..<10).map {
      Transaction(id: "\($0)", name: "N\($0)", category: $0 < 4 ? "Food" : "Bills", time: "", day: "", amount: 1)
    }
    let food = TransactionFilter(categories: ["Food"])
    XCTAssertEqual(store.matchCount(matching: food), 4)
    XCTAssertEqual(store.filteredTransactions(matching: TransactionFilter()).count, 10)
    XCTAssertEqual(store.matchCount(matching: TransactionFilter()), 10)
    XCTAssertEqual(store.matchCount(matching: food), 4)
  }
}

final class TypedKeyLookupTests: XCTestCase {
  func testEntityTypeParsesFromKey() {
    XCTAssertEqual(TypedEntityStoreCompat.entityType(fromKey: entityKey(type: .lend, id: "a:b")), .lend)
    XCTAssertNil(TypedEntityStoreCompat.entityType(fromKey: "not-a-key"))
    XCTAssertNil(TypedEntityStoreCompat.entityType(fromKey: "global:bogus:id"))
  }

  func testFetchAndBulkDeleteThroughTypedLookup() throws {
    let userId = "typed-\(UUID().uuidString)"
    let pool = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: pool)
    try repository.initializeLocalDatabase()
    let ids = (0..<5).map { "tx-typed-\($0)" }
    try repository.saveEntities(ids.map { id in
      (.transaction, .transaction(TransactionEntity(
        id: id, name: id, amountMinor: 100, occurredAt: 1_700_000_000_000,
        categoryId: "category-food", paymentMethodId: SeedData.cashPaymentMethod.id, currency: "INR"
      )))
    })
    try pool.read { db in
      let found = try EntityRecord.fetchOne(db, key: entityKey(type: .transaction, id: ids[0]))
      XCTAssertEqual(found?.entityId, ids[0])
      XCTAssertNil(try EntityRecord.fetchOne(db, key: entityKey(type: .lend, id: ids[0])))
    }
    XCTAssertEqual(try repository.removeEntities(entityType: .transaction, ids: ids + ["missing"]), 5)
    XCTAssertTrue(try repository.activeEntities(type: .transaction).filter { ids.contains($0.entityId) }.isEmpty)
  }

  func testLinkedTransactionIndexExists() throws {
    let userId = "index-\(UUID().uuidString)"
    let pool = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let rows = try pool.read { db in
      try Row.fetchAll(
        db,
        sql: "EXPLAIN QUERY PLAN SELECT * FROM emailMessages WHERE linkedTransactionId = ?",
        arguments: ["tx"]
      ).map { $0["detail"] as String? ?? "" }
    }
    XCTAssertTrue(
      rows.contains { $0.contains("email_messages_linked_transaction") },
      "plan: \(rows)"
    )
  }
}

final class PulsePublisherOrderingTests: XCTestCase {
  func testClearWinsOverEarlierBackgroundPublish() throws {
    guard FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: PulseStorage.groupID
    ) != nil else {
      throw XCTSkip("App group container unavailable in this test host")
    }
    let rows = [Transaction(
      id: "p", name: "", category: "Food", time: "", day: "", amount: 10,
      amountMinor: 1_000, occurredAt: Int(Date().timeIntervalSince1970 * 1000), currency: "INR"
    )]
    PulsePublisher.activate(owner: "pulse-test")
    PulsePublisher.publishInBackground(transactions: rows, currency: "INR", rates: nil)
    PulsePublisher.clear()
    XCTAssertNil(PulseStorage.read())

    PulsePublisher.activate(owner: "pulse-test")
    PulsePublisher.publishInBackground(transactions: rows, currency: "INR", rates: nil)
    PulsePublisher.activate(owner: "pulse-test") // drains the queue
    XCTAssertEqual(PulseStorage.read()?.expenses.count, 1)
    PulsePublisher.clear()
  }
}

// MARK: - Fixtures

enum HydrationFixture {
  static func stored(_ type: EntityType, id: String, payload: EntityPayload, counter: Int = 1) -> StoredEntity {
    StoredEntity(
      key: entityKey(type: type, id: id),
      workspaceId: workspaceID,
      entityType: type,
      entityId: id,
      version: LogicalVersion(timestamp: 1_700_000_000_000, counter: counter, deviceId: "test"),
      payload: payload,
      deleted: false,
      serverRevision: 0
    )
  }

  static func category(name: String = "Food", counter: Int = 1) -> StoredEntity {
    stored(.category, id: "category-food", payload: .category(CategoryEntity(
      id: "category-food", name: name, emoji: "🍜", monthlyBudgetMinor: 100_000,
      tint: .neutral, sortOrder: 0, system: false
    )), counter: counter)
  }

  static func transaction(
    _ id: String,
    name: String? = nil,
    minor: Int = 12_500,
    occurredAt: Int? = nil,
    counter: Int = 1
  ) -> StoredEntity {
    let index = Int(id.split(separator: "-").last ?? "0") ?? 0
    return stored(.transaction, id: id, payload: .transaction(TransactionEntity(
      id: id,
      name: name ?? "Merchant \(id)",
      amountMinor: minor,
      occurredAt: occurredAt ?? (1_758_000_000_000 - index * 3_600_000),
      categoryId: "category-food",
      paymentMethodId: SeedData.cashPaymentMethod.id,
      currency: "INR"
    )), counter: counter)
  }

  static func lend(_ id: String, minor: Int) -> StoredEntity {
    stored(.lend, id: id, payload: .lend(LendEntity(
      id: id, contactName: "Asha", contactId: "c1", amountMinor: minor,
      occurredAt: 1_758_000_000_000, comment: "", kind: .lent
    )))
  }

  static func recurring(_ id: String, anchorDate: String) -> StoredEntity {
    stored(.recurring, id: id, payload: .recurring(RecurringEntity(
      id: id, name: id, amountMinor: 10_000, categoryId: "category-food",
      paymentMethodId: nil, frequency: .monthly, anchorDate: anchorDate, paused: false,
      currency: "INR"
    )))
  }

  static func entities(transactionCount: Int, occurredAt: Int? = nil) -> [StoredEntity] {
    [
      category(),
      stored(.paymentMethod, id: SeedData.cashPaymentMethod.id, payload: .paymentMethod(SeedData.cashPaymentMethod)),
      stored(.preferences, id: "preferences", payload: .preferences(SeedData.defaultPreferences)),
    ] + (0..<transactionCount).map { transaction("tx-\($0)", occurredAt: occurredAt) }
  }
}

func XCTUnwrapAsync<T>(
  _ value: @autoclosure () async throws -> T?,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws -> T {
  let resolved = try await value()
  return try XCTUnwrap(resolved, file: file, line: line)
}

@MainActor
final class SourceEmailLoadingTests: XCTestCase {
  func testBackgroundLoadMatchesSynchronousLookup() async throws {
    let userId = "source-email-\(UUID().uuidString)"
    let pool = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: pool)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let category = CategoryEntity(
      id: "category-food", name: "Food", emoji: "🍜", monthlyBudgetMinor: nil,
      tint: .neutral, sortOrder: 1, system: false
    )
    try repository.saveEntity(entityType: .category, payload: .category(category))
    let message = PendingEmailMessage(
      accountId: "gmail-subject",
      gmailMessageId: "receipt",
      threadId: "thread",
      senderAddress: "merchant@example.com",
      subject: "Receipt",
      snippet: "Purchase receipt",
      internalDate: 1_000,
      normalizedBodyText: "Paid ₹10.00 at Merchant"
    )
    _ = try repository.insertPendingEmailMessages([message])
    try repository.saveEmailAnalysis(messageKey: message.key, analysis: PersistedEmailAnalysis(
      analyzerType: .gemma, modelVersion: "test-gemma", promptVersion: 1,
      classification: .purchase, merchant: "Merchant", amount: "10.00", currency: .INR,
      occurredAt: nil, categoryId: category.id, paymentMethodId: nil,
      paymentLastFour: nil, reference: nil
    ))
    let transaction = TransactionEntity(
      id: "tx_email", name: "Merchant", amountMinor: 1_000, occurredAt: 1_000,
      categoryId: category.id, paymentMethodId: nil
    )
    try repository.acceptEmailSuggestion(messageKey: message.key, transaction: transaction)

    let controller = EmailFeatureController(
      userId: userId, repository: repository, store: EmailFeatureStore()
    )
    let sync = controller.sourceEmailDetails(forTransactionId: transaction.id)
    let loaded = await controller.loadSourceEmailDetails(forTransactionId: transaction.id)
    XCTAssertEqual(loaded.map(\.id), sync.map(\.id))
    XCTAssertEqual(loaded.first?.subject, "Receipt")
    XCTAssertEqual(loaded.first?.bodyText, "Paid ₹10.00 at Merchant")
    let none = await controller.loadSourceEmailDetails(forTransactionId: "missing")
    XCTAssertTrue(none.isEmpty)
  }
}
