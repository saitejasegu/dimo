import GRDB
import XCTest
@testable import Dimo

final class LogicalVersionTests: XCTestCase {
  func testOrdersByTimestampCounterThenDeviceId() {
    let base = LogicalVersion(timestamp: 100, counter: 1, deviceId: "a")
    XCTAssertGreaterThan(
      compareVersions(LogicalVersion(timestamp: 101, counter: 1, deviceId: "a"), base),
      0
    )
    XCTAssertGreaterThan(
      compareVersions(LogicalVersion(timestamp: 100, counter: 2, deviceId: "a"), base),
      0
    )
    XCTAssertGreaterThan(
      compareVersions(LogicalVersion(timestamp: 100, counter: 1, deviceId: "b"), base),
      0
    )
    XCTAssertEqual(compareVersions(base, base), 0)
  }
}

final class GreetingTests: XCTestCase {
  func testGreetingHours() {
    let cal = Calendar(identifier: .gregorian)
    func date(hour: Int) -> Date {
      cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour))!
    }
    XCTAssertEqual(Greeting.greetingFor(date(hour: 0), calendar: cal), "Good morning")
    XCTAssertEqual(Greeting.greetingFor(date(hour: 11), calendar: cal), "Good morning")
    XCTAssertEqual(Greeting.greetingFor(date(hour: 12), calendar: cal), "Good afternoon")
    XCTAssertEqual(Greeting.greetingFor(date(hour: 16), calendar: cal), "Good afternoon")
    XCTAssertEqual(Greeting.greetingFor(date(hour: 17), calendar: cal), "Good evening")
  }
}

final class StatsHydrationTests: XCTestCase {
  func testPulledDefaultReplacesUntouchedBootstrapRange() {
    XCTAssertEqual(
      StatsConstants.hydratedRange(
        current: .oneYear,
        previousDefault: .oneYear,
        nextDefault: .threeMonths,
        dataReady: true
      ),
      .threeMonths
    )
  }

  func testPulledDefaultPreservesUserSelectedRange() {
    XCTAssertEqual(
      StatsConstants.hydratedRange(
        current: .sixMonths,
        previousDefault: .oneYear,
        nextDefault: .threeMonths,
        dataReady: true
      ),
      .sixMonths
    )
  }
}

final class DateHelpersTests: XCTestCase {
  func testClampsMonthlyDayToShortMonth() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 2, day: 1))!
    let next = DateHelpers.nextOccurrence(
      anchorDate: "2026-01-31",
      frequency: .monthly,
      now: now,
      calendar: cal
    )
    let parts = cal.dateComponents([.year, .month, .day], from: next)
    XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 2, 28])
  }

  func testLeapDayYearlyUsesFeb28() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    let next = DateHelpers.nextOccurrence(
      anchorDate: "2024-02-29",
      frequency: .yearly,
      now: now,
      calendar: cal
    )
    let parts = cal.dateComponents([.year, .month, .day], from: next)
    XCTAssertEqual([parts.year, parts.month, parts.day], [2025, 2, 28])
  }

  func testOccurrencesThroughMonthly() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
    let dates = DateHelpers.occurrencesThrough(
      anchorDate: "2026-01-15",
      frequency: .monthly,
      now: now,
      calendar: cal
    )
    let mapped = dates.map {
      let c = cal.dateComponents([.year, .month, .day], from: $0)
      return [c.year!, c.month!, c.day!]
    }
    XCTAssertEqual(mapped, [[2026, 1, 15], [2026, 2, 15], [2026, 3, 15], [2026, 4, 15]])
  }

  func testFutureAnchorReturnsEmpty() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
    let dates = DateHelpers.occurrencesThrough(
      anchorDate: "2026-08-01",
      frequency: .monthly,
      now: now,
      calendar: cal
    )
    XCTAssertTrue(dates.isEmpty)
  }
}

final class RecurringSelectorsTests: XCTestCase {
  func testUpcomingBillsSortedByDueDateAscending() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 12))!
    let recs = [
      recurring(id: "late", name: "Rent", anchorDate: "2026-07-28"),
      recurring(id: "early", name: "Netflix", anchorDate: "2026-07-15"),
      recurring(id: "mid", name: "Gym", anchorDate: "2026-07-20"),
      recurring(id: "paused", name: "Paused", anchorDate: "2026-07-13", paused: true),
      recurring(id: "next-month", name: "Later", anchorDate: "2026-08-01"),
    ]

    let upcoming = RecurringSelectors.upcomingBills(recs, limit: 3, now: now, calendar: cal)
    XCTAssertEqual(upcoming.map(\.id), ["early", "mid", "late"])
  }

  func testUpcomingBillsReturnsEntireCurrentMonthWithoutLimit() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 12))!
    let recs = [
      recurring(id: "fifth", name: "Fifth", anchorDate: "2026-07-28"),
      recurring(id: "first", name: "First", anchorDate: "2026-07-13"),
      recurring(id: "fourth", name: "Fourth", anchorDate: "2026-07-24"),
      recurring(id: "second", name: "Second", anchorDate: "2026-07-15"),
      recurring(id: "third", name: "Third", anchorDate: "2026-07-20"),
      recurring(id: "paused", name: "Paused", anchorDate: "2026-07-14", paused: true),
      recurring(id: "next-month", name: "Later", anchorDate: "2026-08-01"),
    ]

    let upcoming = RecurringSelectors.upcomingBills(recs, now: now, calendar: cal)
    XCTAssertEqual(upcoming.map(\.id), ["first", "second", "third", "fourth", "fifth"])
  }

  func testAllUpcomingBillsIncludesFutureMonths() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 12))!
    let recs = [
      recurring(id: "next-month", name: "Later", anchorDate: "2026-08-01"),
      recurring(id: "first", name: "First", anchorDate: "2026-07-13"),
      recurring(id: "paused", name: "Paused", anchorDate: "2026-07-14", paused: true),
      recurring(id: "second", name: "Second", anchorDate: "2026-07-15"),
    ]

    let all = RecurringSelectors.allUpcomingBills(recs, now: now, calendar: cal)
    XCTAssertEqual(all.map(\.id), ["first", "second", "next-month"])
  }

  private func recurring(
    id: String,
    name: String,
    anchorDate: String,
    paused: Bool = false
  ) -> Recurring {
    Recurring(
      id: id,
      name: name,
      category: "Subscriptions",
      due: "",
      amount: 10,
      paused: paused,
      anchorDate: anchorDate,
      frequency: .monthly
    )
  }
}

final class PermanentSyncErrorTests: XCTestCase {
  func testPermanentMessages() {
    XCTAssertTrue(isPermanentSyncError("ArgumentValidationError: bad"))
    XCTAssertTrue(isPermanentSyncError("Payload does not match"))
    XCTAssertFalse(isPermanentSyncError("Not authenticated"))
    XCTAssertFalse(isPermanentSyncError("NetworkError"))
  }
}

final class TransactionCSVTests: XCTestCase {
  func testParseAndRoundTrip() throws {
    let csv = "Date,Note,Amount,Category,Type\r\n2026-07-11 11:38:08 +0000,\"Coffee, shop\",12.50,Cafe,Expense\r\n"
    let rows = try TransactionCSV.parse(csv)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0].merchant, "Coffee, shop")
    XCTAssertEqual(rows[0].amountMinor, 1250)
    XCTAssertEqual(TransactionCSV.categoryEmojiForName("Movie snacks"), "☕")
    XCTAssertEqual(TransactionCSV.categoryEmojiForName("Utilities"), "💡")
  }

  func testParsesDateOnlyAsUTCMidnight() throws {
    let csv = "Date,Note,Amount,Category,Type\n2026-07-11,Coffee,3.54,Snacks,Expense\n"
    let rows = try TransactionCSV.parse(csv)
    XCTAssertEqual(rows[0].occurredAt, 1_783_728_000_000)
  }

  func testRejectsIncome() {
    let csv = "Date,Note,Amount,Category,Type\n2026-07-11 11:38:08 +0000,Pay,10.00,Work,Income\n"
    XCTAssertThrowsError(try TransactionCSV.parse(csv))
  }
}

final class RepositoryBootstrapTests: XCTestCase {
  func testBootstrapSeedsDefaultsOnce() throws {
    let userId = "test-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }

    let repo = Repository(db: queue)
    try repo.initializeLocalDatabase()
    let first = try repo.allEntities()
    XCTAssertEqual(first.filter { !$0.deleted }.count, 2)
    XCTAssertEqual(try repo.pendingOutbox(limit: 100).count, 0)
    XCTAssertEqual(try repo.activeEntities(type: .category).count, 0)
    try repo.initializeLocalDatabase()
    let second = try repo.allEntities()
    XCTAssertEqual(second.filter { !$0.deleted }.count, 2)
    let cash = try repo.activeEntities(type: .paymentMethod)
      .contains { $0.entityId == SeedData.cashPaymentMethod.id }
    XCTAssertTrue(cash)
  }

  func testEnqueueUnsyncedDefaultsOnlyWhenNeverPulled() throws {
    let userId = "test-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repo = Repository(db: queue)
    try repo.initializeLocalDatabase()
    XCTAssertEqual(try repo.pendingOutbox(limit: 100).count, 0)

    try repo.enqueueUnsyncedDefaults()
    XCTAssertEqual(try repo.pendingOutbox(limit: 100).count, 2)

    let cashKey = entityKey(type: .paymentMethod, id: SeedData.cashPaymentMethod.id)
    try queue.write { db in
      guard var record = try EntityRecord.fetchOne(db, key: cashKey) else {
        return XCTFail("missing cash seed")
      }
      record.serverRevision = 10
      try record.update(db)
      try OutboxRecord.deleteAll(db)
    }
    try repo.enqueueUnsyncedDefaults()
    let pending = try repo.pendingOutbox(limit: 100)
    XCTAssertFalse(pending.contains { $0.entityId == SeedData.cashPaymentMethod.id })
    XCTAssertEqual(pending.count, 1)
  }

  func testOutboxReplaceOnResave() throws {
    let userId = "test-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repo = Repository(db: queue)
    try repo.initializeLocalDatabase()
    let pendingBefore = try repo.pendingOutbox(limit: 100).count

    let category = CategoryEntity(
      id: "category-custom",
      name: "Custom",
      emoji: "✨",
      monthlyBudgetMinor: nil,
      tint: .neutral,
      sortOrder: 10,
      system: false
    )
    try repo.saveEntity(entityType: .category, payload: .category(category))
    var updated = category
    updated.name = "Custom 2"
    try repo.saveEntity(entityType: .category, payload: .category(updated))

    let pending = try repo.pendingOutbox(limit: 200)
    let customOps = pending.filter { $0.entityId == "category-custom" }
    XCTAssertEqual(customOps.count, 1)
    if case .category(let payload) = customOps[0].payload {
      XCTAssertEqual(payload.name, "Custom 2")
    } else {
      XCTFail("expected category payload")
    }
    XCTAssertEqual(try repo.pendingOutbox(limit: 200).count, pendingBefore + 1)
  }
}

final class TransactionSelectorTests: XCTestCase {
  private func tx(
    id: String,
    name: String,
    category: String,
    day: String,
    amount: Double,
    payment: String? = nil,
    occurredAt: Int = 1
  ) -> Transaction {
    Transaction(
      id: id, name: name, category: category, time: "10:00 AM", day: day,
      amount: amount, paymentMethod: payment, occurredAt: occurredAt
    )
  }

  func testFilterAndPaginateByDay() {
    let items = [
      tx(id: "1", name: "A", category: "Dining", day: "Today", amount: 10, payment: "Cash"),
      tx(id: "2", name: "B", category: "Bills", day: "Today", amount: 20, payment: "UPI"),
      tx(id: "3", name: "C", category: "Dining", day: "Yesterday", amount: 30, payment: "Cash"),
      tx(id: "4", name: "D", category: "Dining", day: "Yesterday", amount: 40, payment: "Cash"),
    ]
    let filtered = TransactionSelectors.filterTransactions(
      items,
      filter: TransactionFilter(categories: ["Dining"], paymentMethod: "Cash", query: "")
    )
    XCTAssertEqual(filtered.map(\.id), ["1", "3", "4"])

    let page = TransactionSelectors.paginateTransactionsByDay(items, limit: 1)
    XCTAssertEqual(page.items.map(\.id), ["1", "2"])
    XCTAssertTrue(page.hasMore)
  }

  func testMerchantSuggestionsPreferPrefix() {
    let items = [
      tx(id: "1", name: "Cafe Coffee", category: "Dining", day: "Today", amount: 1),
      tx(id: "2", name: "Coffee House", category: "Dining", day: "Today", amount: 1),
      tx(id: "3", name: "Coffee House", category: "Dining", day: "Today", amount: 1),
    ]
    let suggestions = TransactionSelectors.merchantSuggestions(items, query: "cof")
    XCTAssertEqual(suggestions.first?.name, "Coffee House")
    XCTAssertEqual(suggestions.first?.count, 2)
  }

  func testDateRangeIncludesBothBoundaryDays() {
    let calendar = Calendar.current
    func date(_ day: Int, hour: Int = 12) -> Date {
      calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }
    func timestamp(_ day: Int, hour: Int = 12) -> Int {
      Int(date(day, hour: hour).timeIntervalSince1970 * 1000)
    }

    let items = [
      tx(id: "9", name: "Before", category: "Dining", day: "", amount: 1, occurredAt: timestamp(9)),
      tx(id: "10", name: "Start", category: "Dining", day: "", amount: 1, occurredAt: timestamp(10, hour: 0)),
      tx(id: "12", name: "End", category: "Dining", day: "", amount: 1, occurredAt: timestamp(12, hour: 23)),
      tx(id: "13", name: "After", category: "Dining", day: "", amount: 1, occurredAt: timestamp(13)),
    ]

    let filtered = TransactionSelectors.filterTransactions(
      items,
      filter: TransactionFilter(startDate: date(10), endDate: date(12))
    )

    XCTAssertEqual(filtered.map(\.id), ["10", "12"])
  }
}

final class SanitizerTests: XCTestCase {
  func testSanitizePreferencesDefaults() {
    let prefs = PreferencesEntity(
      id: "preferences",
      profileName: "A",
      profileEmail: "a@b.com",
      currency: .INR,
      weekStart: .Mon,
      theme: .light,
      navGlassOpacity: 10,
      defaultView: .stats,
      defaultStatsRange: .oneYear,
      notifications: NotificationSettings(bills: true, budget: false, weekly: false, large: true),
      defaultPaymentMethodId: ""
    )
    let clean = PayloadSanitizer.sanitize(entityType: .preferences, payload: .preferences(prefs))
    guard case .preferences(let value) = clean else {
      return XCTFail("expected preferences")
    }
    XCTAssertEqual(value.navGlassOpacity, 40)
    XCTAssertEqual(value.defaultView, .home)
    XCTAssertEqual(value.defaultPaymentMethodId, SeedData.cashPaymentMethod.id)
  }

  func testSanitizeTransactionAmount() {
    let tx = TransactionEntity(
      id: "t1", name: "x", amountMinor: 0, occurredAt: 0,
      categoryId: "c", paymentMethodId: nil
    )
    let clean = PayloadSanitizer.sanitize(entityType: .transaction, payload: .transaction(tx))
    guard case .transaction(let value) = clean else {
      return XCTFail("expected transaction")
    }
    XCTAssertEqual(value.amountMinor, 1)
    XCTAssertGreaterThan(value.occurredAt, 0)
  }
}

final class BudgetSelectorTests: XCTestCase {
  func testSuggestedBudgetsFromLookback() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 11))!
    func stamp(_ y: Int, _ m: Int, _ d: Int) -> Int {
      Int(cal.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970 * 1000)
    }
    let rows = [
      Transaction(
        id: "a", name: "Item", category: "Dining", time: "", day: "", amount: 300,
        occurredAt: stamp(2026, 7, 2), categoryId: "dining"
      ),
      Transaction(
        id: "b", name: "Item", category: "Dining", time: "", day: "", amount: 900,
        occurredAt: stamp(2026, 2, 10), categoryId: "dining"
      ),
      Transaction(
        id: "c", name: "Item", category: "Dining", time: "", day: "", amount: 50,
        occurredAt: stamp(2025, 12, 20), categoryId: "dining"
      ),
      Transaction(
        id: "d", name: "Item", category: "Other", time: "", day: "", amount: 999,
        occurredAt: stamp(2026, 7, 2), categoryId: "other"
      ),
    ]
    let lookback = BudgetSelectors.categoryLookbackSpend(
      rows, categoryId: "dining", monthCount: 6, now: now, calendar: cal
    )
    XCTAssertEqual(lookback.total, 1200)
    XCTAssertEqual(lookback.monthlyAverage, 200)

    let suggestionRows = [
      Transaction(
        id: "a", name: "Item", category: "Dining", time: "", day: "", amount: 300,
        occurredAt: stamp(2026, 7, 2), categoryId: "dining"
      ),
      Transaction(
        id: "b", name: "Item", category: "Dining", time: "", day: "", amount: 900,
        occurredAt: stamp(2026, 2, 10), categoryId: "dining"
      ),
      Transaction(
        id: "c", name: "Item", category: "Bills", time: "", day: "", amount: 600,
        occurredAt: stamp(2026, 7, 2), categoryId: "bills"
      ),
    ]
    let suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
      suggestionRows,
      categories: [
        (id: "dining", name: "Dining", monthlyBudgetMinor: nil),
        (id: "bills", name: "Bills", monthlyBudgetMinor: 50_000),
        (id: "empty", name: "Groceries", monthlyBudgetMinor: nil),
      ],
      monthCount: 6,
      now: now,
      calendar: cal
    )
    XCTAssertEqual(
      suggestions,
      [
        SuggestedCategoryBudgetUpdate(id: "dining", name: "Dining", suggestedLimit: 200, currentLimit: nil),
        SuggestedCategoryBudgetUpdate(id: "bills", name: "Bills", suggestedLimit: 100, currentLimit: 500),
      ]
    )
  }
}

final class LendSelectorsTests: XCTestCase {
  private func lend(
    _ id: String,
    name: String,
    contactId: String,
    amount: Double,
    kind: LendKind = .lent,
    occurredAt: Int = 1_000
  ) -> Lend {
    Lend(
      id: id,
      contactName: name,
      contactId: contactId,
      amount: amount,
      comment: "",
      time: "",
      day: "",
      amountMinor: Int(amount * 100),
      occurredAt: occurredAt,
      kind: kind
    )
  }

  func testSummariesSplitSameNameByContactId() {
    let summaries = LendSelectors.contactSummaries([
      lend("1", name: "Aakash", contactId: "cn-a", amount: 100),
      lend("2", name: "Aakash", contactId: "cn-b", amount: 50),
    ])
    XCTAssertEqual(summaries.count, 2)
    XCTAssertEqual(summaries[0].total, 100)
    XCTAssertEqual(summaries[0].contactId, "cn-a")
    XCTAssertEqual(summaries[1].total, 50)
    XCTAssertEqual(summaries[1].contactId, "cn-b")
  }

  func testSameContactMergesAcrossNameCasing() {
    let summaries = LendSelectors.contactSummaries([
      lend("1", name: "aakash", contactId: "cn-a", amount: 100, occurredAt: 1_000),
      lend("2", name: "Aakash", contactId: "cn-a", amount: 50, occurredAt: 2_000),
      lend("3", name: "Aakash", contactId: "cn-a", amount: 30, kind: .repaid, occurredAt: 3_000),
    ])
    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries[0].contactId, "cn-a")
    XCTAssertEqual(summaries[0].contactName, "Aakash")
    XCTAssertEqual(summaries[0].total, 120)
    XCTAssertEqual(summaries[0].count, 3)
  }

  func testRecentContactsDedupesPerPersonNewestFirst() {
    let suggestions = LendSelectors.recentContacts([
      lend("1", name: "Ravi", contactId: "cn-r", amount: 10, occurredAt: 1_000),
      lend("2", name: "Aakash", contactId: "cn-a", amount: 10, occurredAt: 4_000),
      lend("3", name: "aakash", contactId: "cn-a", amount: 10, kind: .repaid, occurredAt: 2_000),
      lend("4", name: "Aakash", contactId: "cn-b", amount: 10, occurredAt: 3_000),
    ])
    XCTAssertEqual(
      suggestions,
      [
        LendContactSuggestion(contactName: "Aakash", contactId: "cn-a"),
        LendContactSuggestion(contactName: "Aakash", contactId: "cn-b"),
        LendContactSuggestion(contactName: "Ravi", contactId: "cn-r"),
      ]
    )
  }

  func testRecentContactsHonorsLimit() {
    let lends = (1...8).map { i in
      lend("\(i)", name: "Person \(i)", contactId: "cn-\(i)", amount: 10, occurredAt: i * 1_000)
    }
    XCTAssertEqual(LendSelectors.recentContacts(lends).count, 6)
    XCTAssertEqual(LendSelectors.recentContacts(lends).first?.contactName, "Person 8")
  }

  func testRepaymentsWithIdOnlyReduceThatContact() {
    let summaries = LendSelectors.contactSummaries([
      lend("1", name: "Aakash", contactId: "cn-a", amount: 100),
      lend("2", name: "Aakash", contactId: "cn-b", amount: 100),
      lend("3", name: "Aakash", contactId: "cn-a", amount: 100, kind: .repaid),
    ])
    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries[0].contactId, "cn-b")
    XCTAssertEqual(summaries[0].total, 100)
  }

  func testOutstandingAmountExcludesRepaymentBeingEdited() {
    let lends = [
      lend("lend", name: "Aakash", contactId: "cn-a", amount: 100),
      lend("repaid", name: "Aakash", contactId: "cn-a", amount: 30, kind: .repaid),
    ]

    XCTAssertEqual(LendSelectors.outstandingAmount(for: "cn-a", in: lends), 70)
    XCTAssertEqual(
      LendSelectors.outstandingAmount(for: "cn-a", in: lends, excludingLendId: "repaid"),
      100
    )
  }

  func testUnsettledTransactionsStartAfterMostRecentSettlement() {
    let lends = [
      lend("old-lend", name: "Aakash", contactId: "cn-a", amount: 100, occurredAt: 1_000),
      lend("old-repayment", name: "Aakash", contactId: "cn-a", amount: 100, kind: .repaid, occurredAt: 2_000),
      lend("current-lend", name: "Aakash", contactId: "cn-a", amount: 70, occurredAt: 3_000),
      lend("partial-repayment", name: "Aakash", contactId: "cn-a", amount: 20, kind: .repaid, occurredAt: 4_000),
      lend("other-contact", name: "Ravi", contactId: "cn-r", amount: 25, occurredAt: 5_000),
    ]

    XCTAssertEqual(
      LendSelectors.unsettledTransactions(for: "cn-a", in: lends).map(\.id),
      ["current-lend", "partial-repayment"]
    )
  }
}
