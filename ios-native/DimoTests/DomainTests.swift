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
    XCTAssertEqual(all.map(\.id), ["first", "paused", "second", "next-month"])
  }

  func testPausedOnlyAccountsRemainAvailableInExpandedHomeResults() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 12))!
    let paused = recurring(id: "paused", name: "Paused", anchorDate: "2026-09-01", paused: true)

    XCTAssertTrue(RecurringSelectors.upcomingBills([paused], now: now, calendar: cal).isEmpty)
    XCTAssertEqual(
      RecurringSelectors.allUpcomingBills([paused], now: now, calendar: cal).map(\.id),
      ["paused"]
    )
  }

  func testRecurringTransactionDatesSupportsAllSelectedAndFuture() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 18))!
    let all = DateHelpers.recurringTransactionDates(
      anchorDate: "2026-01-15", frequency: .monthly, selection: .all, now: now, calendar: cal
    )
    let selected = DateHelpers.recurringTransactionDates(
      anchorDate: "2026-01-15", frequency: .monthly, selection: .selected, now: now, calendar: cal
    )
    let future = DateHelpers.recurringTransactionDates(
      anchorDate: "2026-08-01", frequency: .yearly, selection: .selected, now: now, calendar: cal
    )
    XCTAssertEqual(all.map { cal.component(.month, from: $0) }, [1, 2, 3, 4])
    XCTAssertEqual(selected.map { cal.component(.month, from: $0) }, [1])
    XCTAssertTrue(future.isEmpty)
  }

  func testMonthlyAndYearlySchedulesStartingTodayCreateOneTransaction() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 18))!
    for frequency in [RecurringFrequency.monthly, .yearly] {
      let dates = DateHelpers.recurringTransactionDates(
        anchorDate: "2026-07-15",
        frequency: frequency,
        selection: .selected,
        now: now,
        calendar: cal
      )
      XCTAssertEqual(dates.map { DateHelpers.localDateKey($0, calendar: cal) }, ["2026-07-15"])
    }
  }

  func testPastYearlyScheduleListsEveryOccurrence() {
    let cal = Calendar(identifier: .gregorian)
    let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    let dates = DateHelpers.recurringTransactionDates(
      anchorDate: "2024-02-29",
      frequency: .yearly,
      selection: .all,
      now: now,
      calendar: cal
    )
    XCTAssertEqual(
      dates.map { DateHelpers.localDateKey($0, calendar: cal) },
      ["2024-02-29", "2025-02-28", "2026-02-28"]
    )
  }

  func testOccurrenceTimestampPreservesSelectedTime() {
    let cal = Calendar(identifier: .gregorian)
    let date = cal.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    let time = cal.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 9, minute: 45))!
    let timestamp = DateHelpers.occurrenceTimestamp(date, time: time, calendar: cal)
    let combined = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    XCTAssertEqual(cal.component(.hour, from: combined), 9)
    XCTAssertEqual(cal.component(.minute, from: combined), 45)
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

final class LegacyNavigationTests: XCTestCase {
  func testRecurringViewKeyStillDecodes() throws {
    let data = try XCTUnwrap("\"recurring\"".data(using: .utf8))
    XCTAssertEqual(try JSONDecoder().decode(ViewKey.self, from: data), .recurring)
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

final class EmailFeatureStoreTests: XCTestCase {
  @MainActor
  func testGemmaDownloadCopyReflects270MArtifact() {
    let store = EmailFeatureStore()

    XCTAssertEqual(store.modelDownloadSizeDescription, "about 304 MB")
    XCTAssertEqual(store.modelStorageRequirementDescription, "1 GB free storage required")
  }

  @MainActor
  func testPurchasesIsTheDefaultFilterAndAllIsLast() {
    let store = EmailFeatureStore(allEmails: [
      emailMessage(id: "pending", analysisState: .pending),
      emailMessage(id: "analyzed", analysisState: .analyzed),
    ])

    XCTAssertEqual(store.selectedFilter, .purchases)
    XCTAssertTrue(store.filteredEmails.isEmpty)
    XCTAssertEqual(EmailSuggestionFilter.allCases.last, .all)
    XCTAssertEqual(
      EmailSuggestionFilter.allCases,
      [.purchases, .refunds, .reviewed, .all]
    )

    store.selectedFilter = .all
    XCTAssertEqual(store.filteredEmails.map(\.id), ["pending", "analyzed"])
  }

  @MainActor
  func testFailedAnalysisVisibilityTracksMessageFeed() {
    let store = EmailFeatureStore(allEmails: [
      emailMessage(id: "pending", analysisState: .pending),
      emailMessage(id: "failed", analysisState: .failed),
    ])

    XCTAssertTrue(store.hasFailedAnalyses)

    store.allEmails = [emailMessage(id: "analyzed", analysisState: .analyzed)]
    XCTAssertFalse(store.hasFailedAnalyses)
  }

  func testOpenRouterProvenanceBadgeIncludesModelName() {
    XCTAssertEqual(
      EmailUIAnalyzer.openRouter.provenanceTitle(
        modelVersion: "openai/gpt-5.6-luna"
      ),
      "OpenRouter · gpt-5.6-luna"
    )
    XCTAssertEqual(
      EmailUIAnalyzer.openRouter.provenanceTitle(modelVersion: nil),
      "OpenRouter"
    )
    XCTAssertEqual(
      EmailUIAnalyzer.gemma.provenanceTitle(modelVersion: "gemma-3-270m"),
      "Gemma"
    )
  }

  private func emailMessage(
    id: String,
    analysisState: EmailUIMessageAnalysisState
  ) -> EmailUIMessage {
    EmailUIMessage(
      id: id,
      accountEmail: "person@example.com",
      sender: "sender@example.com",
      subject: "Receipt",
      snippet: "Thanks for your purchase",
      receivedAt: Date(timeIntervalSince1970: 1_000),
      analysisState: analysisState
    )
  }

  private func suggestion(
    id: String,
    kind: EmailUISuggestionKind,
    status: EmailUISuggestionStatus
  ) -> EmailUISuggestion {
    EmailUISuggestion(
      id: id,
      accountID: "gmail-subject",
      accountEmail: "person@example.com",
      kind: kind,
      status: status,
      sender: "merchant@example.com",
      subject: "Receipt",
      snippet: "Purchase receipt",
      receivedAt: Date(timeIntervalSince1970: 1_000),
      analyzer: .gemma
    )
  }
}

final class EmailStructuredOutputValidatorTests: XCTestCase {
  func testAcceptsFencedJSONMissingOptionalKeysAndNumericAmount() throws {
    let response = """
    Here is the result:
    ```json
    {"schemaVersion":"1","kind":"PURCHASE","merchant":"Acme Store","amount":123.45,"currency":"inr"}
    ```
    """

    let result = try EmailStructuredOutputValidator.validate(
      response: response,
      request: request(),
      now: date("2026-07-11T00:00:00Z")
    )

    XCTAssertEqual(result.kind, .purchase)
    XCTAssertEqual(result.amount, Decimal(string: "123.45"))
    XCTAssertEqual(result.currency, .INR)
    XCTAssertEqual(result.merchant, "Acme Store")
    XCTAssertEqual(result.analyzer, .gemma)
  }

  func testReplacesUnevidencedOptionalValuesWithDeterministicEvidence() throws {
    let response = """
    {"schemaVersion":1,"kind":"purchase","merchant":"Invented Merchant","amount":"999.99","currency":"INR","occurredAt":"2099-01-01T00:00:00Z","categoryId":"invented-category","paymentMethodId":"invented-method","paymentLastFour":"9999","reference":"BADBAD99"}
    """

    let result = try EmailStructuredOutputValidator.validate(
      response: response,
      request: request(),
      now: date("2026-07-11T00:00:00Z")
    )

    XCTAssertEqual(result.amount, Decimal(string: "123.45"))
    XCTAssertEqual(result.currency, .INR)
    XCTAssertEqual(result.merchant, "Acme Store")
    XCTAssertNil(result.categoryId)
    XCTAssertEqual(result.paymentMethodId, "card-1")
    XCTAssertEqual(result.paymentLastFour, "1234")
    XCTAssertEqual(result.reference, "ABCDEF12")
    XCTAssertEqual(result.confidence, .low)
    XCTAssertLessThan(try XCTUnwrap(result.occurredAt), date("2026-07-11T00:00:00Z"))
  }

  func testStillRejectsAnInvalidClassification() {
    XCTAssertThrowsError(try EmailStructuredOutputValidator.validate(
      response: #"{"schemaVersion":1,"kind":"purchase | debit"}"#,
      request: request(),
      now: date("2026-07-11T00:00:00Z")
    ))
  }

  func testAcceptsOpenRouterDebitWhenAmountAndCurrencyAreSeparateFields() throws {
    let response = #"{"amount":"3178.00","paymentLastFour":"4476","kind":"debit","reference":"797829712833","merchant":"MAB.037348042370037@AXISBANK","currency":"INR","occurredAt":"2026-07-14","categoryId":null,"schemaVersion":1,"paymentMethodId":null}"#
    let request = EmailAnalysisRequest(
      messageId: "axis-debit",
      accountSubject: "gmail-subject",
      senderName: "Axis Bank",
      senderAddress: "alerts@axisbank.example",
      subject: "Debit transaction alert",
      receivedAt: date("2026-07-14T12:00:00Z"),
      normalizedBody: """
      Amount: 3,178.00
      Currency: INR
      Card ending 4476
      Date: 2026-07-14
      Merchant: MAB.037348042370037@AXISBANK
      Reference: 797829712833
      """,
      categories: [],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )

    let result = try EmailStructuredOutputValidator.validate(
      response: response,
      request: request,
      analyzer: .openRouter,
      now: date("2026-07-17T00:00:00Z")
    )

    XCTAssertEqual(result.kind, .debit)
    XCTAssertEqual(result.amount, Decimal(string: "3178.00"))
    XCTAssertEqual(result.currency, .INR)
    XCTAssertEqual(result.paymentLastFour, "4476")
    XCTAssertEqual(result.reference, "797829712833")
    XCTAssertEqual(result.merchant, "MAB.037348042370037@AXISBANK")
    XCTAssertEqual(result.occurredAt, date("2026-07-14T00:00:00Z"))
    XCTAssertEqual(result.analyzer, .openRouter)
  }

  func testAcceptsOpenRouterCurrencyWhenOnlyAmountIsEvidenced() throws {
    let response = #"{"occurredAt":"2026-07-16T19:40:00+05:30","merchant":"The Odyssey","kind":"purchase","categoryId":"978ec30d-35d2-41ea-ad6b-ea2a63e9d91d","amount":"512.48","reference":"T9A9HCT","paymentLastFour":null,"paymentMethodId":null,"schemaVersion":1,"currency":"INR"}"#
    let receivedAt = date("2026-07-16T14:10:00Z")
    let request = EmailAnalysisRequest(
      messageId: "odyssey-purchase",
      accountSubject: "gmail-subject",
      senderName: "The Odyssey",
      senderAddress: "tickets@theodyssey.example",
      subject: "The Odyssey booking confirmed",
      receivedAt: receivedAt,
      normalizedBody: "Your booking is confirmed. Total: 512.48. Reference T9A9HCT.",
      categories: [EmailCategoryOption(
        id: "978ec30d-35d2-41ea-ad6b-ea2a63e9d91d",
        name: "Entertainment"
      )],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )

    let result = try EmailStructuredOutputValidator.validate(
      response: response,
      request: request,
      analyzer: .openRouter,
      now: date("2026-07-17T00:00:00Z")
    )

    XCTAssertEqual(result.kind, .purchase)
    XCTAssertEqual(result.merchant, "The Odyssey")
    XCTAssertEqual(result.amount, Decimal(string: "512.48"))
    XCTAssertEqual(result.currency, .INR)
    XCTAssertEqual(result.occurredAt, receivedAt)
    XCTAssertEqual(result.categoryId, "978ec30d-35d2-41ea-ad6b-ea2a63e9d91d")
    XCTAssertEqual(result.reference, "T9A9HCT")
    XCTAssertEqual(result.analyzer, .openRouter)
    XCTAssertEqual(result.confidence, .high)
  }

  private func request() -> EmailAnalysisRequest {
    EmailAnalysisRequest(
      messageId: "message-1",
      accountSubject: "gmail-subject",
      senderName: "Acme Store",
      senderAddress: "receipts@acme.example",
      subject: "Payment successful",
      receivedAt: date("2026-07-10T10:30:00Z"),
      normalizedBody: "You paid ₹123.45 to Acme Store on 10 July 2026. Card ending 1234. Ref ABCDEF12.",
      categories: [EmailCategoryOption(id: "shopping", name: "Shopping")],
      paymentMethods: [EmailPaymentMethodHint(
        id: "card-1",
        label: "Visa card",
        lastFour: "1234",
        archived: false
      )],
      merchantHistory: [],
      activeCurrency: .INR
    )
  }

  private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }
}

final class EmailReanalysisTests: XCTestCase {
  func testResetRequeuesUnreviewedEmailsWithoutChangingReviewedEmails() throws {
    let userId = "email-reanalysis-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))

    let messages = ["eligible", "recoverable-terminal", "reviewed"].map { id in
      PendingEmailMessage(
        accountId: "gmail-subject",
        gmailMessageId: id,
        threadId: "thread-\(id)",
        senderAddress: "merchant@example.com",
        subject: "Receipt",
        snippet: "Purchase receipt",
        internalDate: 1_000,
        normalizedBodyText: "A retained email body"
      )
    }
    XCTAssertEqual(try repository.insertPendingEmailMessages(messages), 3)

    let analysis = PersistedEmailAnalysis(
      analyzerType: .gemma,
      modelVersion: "test-gemma",
      promptVersion: 1,
      classification: .purchase,
      merchant: "Merchant",
      amount: "10.00",
      currency: .INR,
      occurredAt: nil,
      categoryId: nil,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil
    )
    let eligibleKey = emailMessageKey(accountId: "gmail-subject", gmailMessageId: "eligible")
    let recoverableKey = emailMessageKey(
      accountId: "gmail-subject",
      gmailMessageId: "recoverable-terminal"
    )
    let reviewedKey = emailMessageKey(accountId: "gmail-subject", gmailMessageId: "reviewed")
    try repository.saveEmailAnalysis(messageKey: eligibleKey, analysis: analysis)
    try repository.saveEmailAnalysis(messageKey: reviewedKey, analysis: analysis)
    try repository.dismissEmailSuggestion(messageKey: reviewedKey)
    try repository.markEmailAnalysisFailed(messageKey: recoverableKey)

    let failed = try XCTUnwrap(repository.emailMessage(key: recoverableKey))
    XCTAssertEqual(failed.state, .analysisFailed)
    XCTAssertNotNil(failed.normalizedBodyText)

    XCTAssertEqual(try repository.resetEmailMessagesForReanalysis(), 2)

    let eligible = try XCTUnwrap(repository.emailMessage(key: eligibleKey))
    XCTAssertEqual(eligible.state, .pendingAnalysis)
    XCTAssertNil(eligible.analyzerType)
    XCTAssertNil(eligible.classification)
    XCTAssertNil(eligible.merchant)
    XCTAssertNil(eligible.amount)
    XCTAssertNil(eligible.currency)
    XCTAssertNil(eligible.analyzedAt)
    XCTAssertNotNil(eligible.normalizedBodyText)

    let recoverable = try XCTUnwrap(repository.emailMessage(key: recoverableKey))
    XCTAssertEqual(recoverable.state, .pendingAnalysis)
    XCTAssertNotNil(recoverable.normalizedBodyText)

    let eligibleSummary = try XCTUnwrap(
      repository.emailMessageSummaries().first { $0.id == eligibleKey }
    )
    XCTAssertEqual(eligibleSummary.state, .pendingAnalysis)
    XCTAssertNil(eligibleSummary.analyzerType)
    XCTAssertNil(eligibleSummary.classification)
    XCTAssertNil(eligibleSummary.analyzedAt)

    let reviewed = try XCTUnwrap(repository.emailMessage(key: reviewedKey))
    XCTAssertEqual(reviewed.state, .dismissed)
    XCTAssertNotNil(reviewed.normalizedBodyText)
  }
}

final class EmailDuplicateMatchTests: XCTestCase {
  private func tx(
    id: String,
    name: String,
    amountMinor: Int,
    occurredAt: Int
  ) -> Transaction {
    Transaction(
      id: id,
      name: name,
      category: "Food",
      time: "10:00 AM",
      day: "Today",
      amount: Double(amountMinor) / 100,
      paymentMethod: "Cash",
      amountMinor: amountMinor,
      occurredAt: occurredAt,
      categoryId: "category-food",
      paymentMethodId: "pm-cash"
    )
  }

  /// 2026-07-16 in UTC, matching the fixed calendar used below.
  private let noon = 1_784_203_200_000
  private var utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  func testMatchesSameAmountOnSameDayRegardlessOfTimeOrMerchant() {
    let matches = EmailSuggestionSelectors.duplicateTransactionMatches(
      amountMinor: 17_000,
      dayKey: "2026-07-16",
      merchant: "Thalairaj Biryani",
      transactions: [
        tx(id: "same-day-other-merchant", name: "Swiggy", amountMinor: 17_000, occurredAt: noon),
        tx(id: "same-day-early", name: "Thalairaj Biryani", amountMinor: 17_000, occurredAt: noon - 11 * 3_600_000),
      ],
      calendar: utc
    )
    // The closer merchant name ranks first; a different name still matches.
    XCTAssertEqual(matches.map(\.transactionId), ["same-day-early", "same-day-other-merchant"])
  }

  func testIgnoresDifferentAmountOrDifferentDay() {
    let matches = EmailSuggestionSelectors.duplicateTransactionMatches(
      amountMinor: 17_000,
      dayKey: "2026-07-16",
      merchant: "Thalairaj Biryani",
      transactions: [
        tx(id: "other-amount", name: "Thalairaj Biryani", amountMinor: 17_001, occurredAt: noon),
        tx(id: "previous-day", name: "Thalairaj Biryani", amountMinor: 17_000, occurredAt: noon - 13 * 3_600_000),
        tx(id: "next-day", name: "Thalairaj Biryani", amountMinor: 17_000, occurredAt: noon + 13 * 3_600_000),
      ],
      calendar: utc
    )
    XCTAssertTrue(matches.isEmpty)
  }
}

final class EmailLinkedTransactionRetentionTests: XCTestCase {
  func testAcceptedSuggestionKeepsEmailForReferenceUntilTransactionDeleted() throws {
    let userId = "email-link-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let category = CategoryEntity(
      id: "category-food",
      name: "Food",
      emoji: "🍜",
      monthlyBudgetMinor: nil,
      tint: .neutral,
      sortOrder: 1,
      system: false
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
      analyzerType: .gemma,
      modelVersion: "test-gemma",
      promptVersion: 1,
      classification: .purchase,
      merchant: "Merchant",
      amount: "10.00",
      currency: .INR,
      occurredAt: nil,
      categoryId: category.id,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil
    ))

    let transaction = TransactionEntity(
      id: "tx_email",
      name: "Merchant",
      amountMinor: 1_000,
      occurredAt: 1_000,
      categoryId: category.id,
      paymentMethodId: nil
    )
    try repository.acceptEmailSuggestion(messageKey: message.key, transaction: transaction)

    let linked = try XCTUnwrap(repository.emailMessage(linkedTransactionId: transaction.id))
    XCTAssertEqual(linked.key, message.key)
    XCTAssertEqual(linked.state, .added)
    XCTAssertNotNil(linked.normalizedBodyText)
    let synced = try XCTUnwrap(
      repository.activeEntities(type: .emailMessage).first { $0.entityId == message.key }
    )
    guard case .emailMessage(let emailEntity) = synced.payload else {
      return XCTFail("Expected emailMessage entity payload")
    }
    XCTAssertEqual(emailEntity.state, EmailSuggestionState.added.rawValue)
    XCTAssertEqual(emailEntity.linkedTransactionId, transaction.id)

    XCTAssertEqual(try repository.expireEmailMessages(olderThan: 2_000), 0)
    XCTAssertEqual(try repository.purgeEmailMessages(olderThan: 2_000), 0)
    _ = try repository.purgeReviewedEmailBodies()
    XCTAssertNotNil(try repository.emailMessage(key: message.key)?.normalizedBodyText)

    try repository.removeEntity(entityType: .transaction, id: transaction.id)
    XCTAssertNil(try repository.emailMessage(linkedTransactionId: transaction.id))
    let dismissed = try XCTUnwrap(repository.emailMessage(key: message.key))
    XCTAssertEqual(dismissed.state, .dismissed)
    XCTAssertNil(dismissed.linkedTransactionId)
    XCTAssertEqual(dismissed.normalizedBodyText, "Paid ₹10.00 at Merchant")
    guard case .emailMessage(let dismissedEntity) = try XCTUnwrap(
      repository.activeEntities(type: .emailMessage).first { $0.entityId == message.key }
    ).payload else {
      return XCTFail("Expected dismissed emailMessage entity")
    }
    XCTAssertEqual(dismissedEntity.normalizedBodyText, "Paid ₹10.00 at Merchant")
    // Reviewed/dismissed rows survive the rolling-window purge so Restore works.
    XCTAssertEqual(try repository.purgeEmailMessages(olderThan: 2_000), 0)

    try repository.restoreDismissedEmailSuggestion(messageKey: message.key)
    let restored = try XCTUnwrap(repository.emailMessage(key: message.key))
    XCTAssertEqual(restored.state, .pendingPurchase)
    XCTAssertNil(restored.reviewedAt)
    XCTAssertEqual(restored.normalizedBodyText, "Paid ₹10.00 at Merchant")
  }

  func testDisconnectRemovesLocalEmailDataAndReconnectMaterializesSyncedReview() throws {
    let userId = "email-disconnect-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let category = CategoryEntity(
      id: "category-food",
      name: "Food",
      emoji: "🍜",
      monthlyBudgetMinor: nil,
      tint: .neutral,
      sortOrder: 1,
      system: false
    )
    try repository.saveEntity(entityType: .category, payload: .category(category))

    let pending = PendingEmailMessage(
      accountId: "gmail-subject",
      gmailMessageId: "pending-msg",
      threadId: "thread-pending",
      senderAddress: "merchant@example.com",
      subject: "Pending",
      snippet: "Pending",
      internalDate: 1_000,
      normalizedBodyText: "Pending body"
    )
    let accepted = PendingEmailMessage(
      accountId: "gmail-subject",
      gmailMessageId: "accepted-msg",
      threadId: "thread-accepted",
      senderAddress: "merchant@example.com",
      subject: "Accepted",
      snippet: "Accepted",
      internalDate: 1_000,
      normalizedBodyText: "Accepted body"
    )
    _ = try repository.insertPendingEmailMessages([pending, accepted])
    try repository.saveEmailAnalysis(messageKey: accepted.key, analysis: PersistedEmailAnalysis(
      analyzerType: .gemma,
      modelVersion: "test-gemma",
      promptVersion: 1,
      classification: .purchase,
      merchant: "Merchant",
      amount: "10.00",
      currency: .INR,
      occurredAt: nil,
      categoryId: category.id,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil
    ))
    try repository.acceptEmailSuggestion(
      messageKey: accepted.key,
      transaction: TransactionEntity(
        id: "tx_keep",
        name: "Merchant",
        amountMinor: 1_000,
        occurredAt: 1_000,
        categoryId: category.id,
        paymentMethodId: nil
      )
    )
    XCTAssertFalse(try repository.activeEntities(type: .emailMessage).isEmpty)

    XCTAssertTrue(try repository.deleteEmailAccount(id: "gmail-subject"))
    XCTAssertNil(try repository.emailAccount(id: "gmail-subject"))
    XCTAssertNil(try repository.emailMessage(key: pending.key))
    XCTAssertNil(try repository.emailMessage(key: accepted.key))
    // Synced entity survives local disconnect wipe.
    XCTAssertEqual(try repository.activeEntities(type: .emailMessage).count, 1)

    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    try repository.materializeSyncedEmailMessages(accountId: "gmail-subject")
    let restored = try XCTUnwrap(repository.emailMessage(key: accepted.key))
    XCTAssertEqual(restored.state, .added)
    XCTAssertEqual(restored.linkedTransactionId, "tx_keep")
    XCTAssertEqual(restored.normalizedBodyText, "Accepted body")
    XCTAssertNil(try repository.emailMessage(key: pending.key))

    // Re-inserting the same Gmail id must not reset the reviewed row.
    XCTAssertEqual(try repository.insertPendingEmailMessages([accepted]), 0)
    XCTAssertEqual(try repository.emailMessage(key: accepted.key)?.state, .added)
  }

  func testLinkingToExistingTransactionReviewsEmailWithoutCreatingAnExpense() throws {
    let userId = "email-link-existing-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let category = CategoryEntity(
      id: "category-food",
      name: "Food",
      emoji: "🍜",
      monthlyBudgetMinor: nil,
      tint: .neutral,
      sortOrder: 1,
      system: false
    )
    try repository.saveEntity(entityType: .category, payload: .category(category))
    let existing = TransactionEntity(
      id: "tx_manual",
      name: "Dinner",
      amountMinor: 1_000,
      occurredAt: 1_000,
      categoryId: category.id,
      paymentMethodId: nil
    )
    try repository.saveEntity(entityType: .transaction, payload: .transaction(existing))

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
      analyzerType: .gemma,
      modelVersion: "test-gemma",
      promptVersion: 1,
      classification: .purchase,
      merchant: "Merchant",
      amount: "10.00",
      currency: .INR,
      occurredAt: nil,
      categoryId: category.id,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil
    ))
    let transactionsBefore = try repository.allEntities()
      .filter { $0.entityType == .transaction }.count

    try repository.linkEmailSuggestionToTransaction(
      messageKey: message.key,
      transactionId: existing.id
    )

    let linked = try XCTUnwrap(repository.emailMessage(key: message.key))
    XCTAssertEqual(linked.state, .added)
    XCTAssertEqual(linked.linkedTransactionId, existing.id)
    XCTAssertNotNil(linked.reviewedAt)
    XCTAssertNotNil(linked.normalizedBodyText)
    XCTAssertEqual(
      try repository.allEntities().filter { $0.entityType == .transaction }.count,
      transactionsBefore
    )
    XCTAssertEqual(
      try repository.emailMessage(linkedTransactionId: existing.id)?.key,
      message.key
    )

    // A second review of the same email must not resolve twice.
    XCTAssertThrowsError(
      try repository.linkEmailSuggestionToTransaction(
        messageKey: message.key,
        transactionId: existing.id
      )
    )
  }

  func testLinkingRejectsDeletedTransaction() throws {
    let userId = "email-link-deleted-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let category = CategoryEntity(
      id: "category-food",
      name: "Food",
      emoji: "🍜",
      monthlyBudgetMinor: nil,
      tint: .neutral,
      sortOrder: 1,
      system: false
    )
    try repository.saveEntity(entityType: .category, payload: .category(category))
    let removed = TransactionEntity(
      id: "tx_removed",
      name: "Dinner",
      amountMinor: 1_000,
      occurredAt: 1_000,
      categoryId: category.id,
      paymentMethodId: nil
    )
    try repository.saveEntity(entityType: .transaction, payload: .transaction(removed))
    try repository.removeEntity(entityType: .transaction, id: removed.id)

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
      analyzerType: .gemma,
      modelVersion: "test-gemma",
      promptVersion: 1,
      classification: .purchase,
      merchant: "Merchant",
      amount: "10.00",
      currency: .INR,
      occurredAt: nil,
      categoryId: category.id,
      paymentMethodId: nil,
      paymentLastFour: nil,
      reference: nil
    ))

    XCTAssertThrowsError(
      try repository.linkEmailSuggestionToTransaction(
        messageKey: message.key,
        transactionId: removed.id
      )
    ) { error in
      XCTAssertEqual(error as? EmailRepositoryError, .transactionNotFound)
    }
    XCTAssertEqual(try repository.emailMessage(key: message.key)?.state, .pendingPurchase)
  }
}

final class EmailGemmaPacingTests: XCTestCase {
  func testPacingAllowsAtMostTenStartsPerMinuteAtNominalTemperature() {
    XCTAssertEqual(
      EmailGemmaPacing.minimumStartInterval(for: .nominal),
      .seconds(6)
    )
  }

  func testPacingSlowsToOneStartPerMinuteWhenDeviceIsWarm() {
    XCTAssertEqual(
      EmailGemmaPacing.minimumStartInterval(for: .fair),
      .seconds(60)
    )
  }

  func testOpenRouterPacingAllowsUpToTwentyStartsPerMinute() {
    XCTAssertEqual(
      EmailOpenRouterPacing.minimumStartInterval,
      .seconds(3)
    )
  }
}

final class EmailSyncWindowTests: XCTestCase {
  func testDefaultWindowIsOneDay() {
    XCTAssertEqual(EmailSyncWindow.defaultValue, .oneDay)
  }

  func testEveryWindowUsesItsCalendarCutoff() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let now = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))
    )
    let expected: [(EmailSyncWindow, DateComponents)] = [
      (.oneDay, DateComponents(year: 2026, month: 7, day: 30, hour: 12)),
      (.oneWeek, DateComponents(year: 2026, month: 7, day: 24, hour: 12)),
      (.oneMonth, DateComponents(year: 2026, month: 6, day: 30, hour: 12)),
      (.threeMonths, DateComponents(year: 2026, month: 4, day: 30, hour: 12)),
    ]

    for (window, components) in expected {
      let cutoff = try XCTUnwrap(calendar.date(from: components))
      XCTAssertEqual(window.cutoff(from: now, calendar: calendar), cutoff)
      XCTAssertTrue(window.contains(cutoff, now: now, calendar: calendar))
      XCTAssertFalse(
        window.contains(
          cutoff.addingTimeInterval(-1),
          now: now,
          calendar: calendar
        )
      )
    }
  }
}

final class EmailGemmaOnlyRouterTests: XCTestCase {
  func testGemmaFailureIsPropagatedWithoutFallback() async throws {
    let router = EmailLanguageModelRouter(gemma: FailingGemmaLanguageModel())
    try await router.load()

    do {
      _ = try await router.analyze(EmailAnalysisRequest(
        messageId: "message",
        accountSubject: "account",
        senderAddress: "merchant@example.com",
        subject: "Receipt",
        receivedAt: .now,
        normalizedBody: "Receipt",
        categories: [],
        paymentMethods: [],
        merchantHistory: [],
        activeCurrency: .INR
      ))
      XCTFail("Expected Gemma failure to be propagated")
    } catch let error as EmailLanguageModelError {
      guard case .generationFailed = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }

    let failureReason = await router.failureReason()
    XCTAssertEqual(failureReason, "Analysis failed")
    XCTAssertEqual(EmailUIMessageAnalysisState.failed.title, "Analysis failed")
  }
}

final class GmailMessageParserTests: XCTestCase {
  func testStoresFullBodyFetchedViaAttachmentId() throws {
    let fullBody = String(repeating: "line of receipt detail\n", count: 8_000)
    let attachmentId = "ANGjdJ_body_part"
    let resource = GmailMessageResource(
      id: "msg-1",
      threadId: "thread-1",
      labelIds: ["INBOX"],
      snippet: "truncated only",
      historyId: "1",
      internalDate: "1700000000000",
      payload: GmailMessagePart(
        partId: "0",
        mimeType: "text/plain",
        filename: "",
        headers: [
          GmailMessageHeader(name: "From", value: "Store <store@example.com>"),
          GmailMessageHeader(name: "Subject", value: "Your receipt"),
        ],
        body: GmailMessageBody(attachmentId: attachmentId, size: fullBody.utf8.count, data: nil),
        parts: nil
      )
    )

    XCTAssertEqual(
      GmailMessageParser.unresolvedBodyAttachmentIds(from: resource),
      [attachmentId]
    )

    let parsed = try GmailMessageParser.parse(
      resource,
      resolvedBodies: [attachmentId: Data(fullBody.utf8)]
    )
    XCTAssertEqual(parsed.normalizedBody, GmailMessageParser.normalizePlainText(fullBody))
    XCTAssertGreaterThan(parsed.normalizedBody.count, 100_000)
  }

  func testDoesNotTruncateInlineBodiesOverFormerCap() throws {
    let fullBody = String(repeating: "x", count: 120_000)
    let encoded = Data(fullBody.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let resource = GmailMessageResource(
      id: "msg-2",
      threadId: "thread-2",
      labelIds: ["INBOX"],
      snippet: "short",
      historyId: "1",
      internalDate: "1700000000000",
      payload: GmailMessagePart(
        partId: "0",
        mimeType: "text/plain",
        filename: nil,
        headers: [
          GmailMessageHeader(name: "From", value: "a@b.com"),
          GmailMessageHeader(name: "Subject", value: "Receipt"),
        ],
        body: GmailMessageBody(attachmentId: nil, size: fullBody.utf8.count, data: encoded),
        parts: nil
      )
    )

    let parsed = try GmailMessageParser.parse(resource)
    XCTAssertEqual(parsed.normalizedBody.count, 120_000)
  }

  func testExtractsReadableTextFromHTMLInsteadOfMarkup() throws {
    let html = """
    <html><head><style>.x{color:#fff;font-size:14px;}</style></head>
    <body>
      <div>Thanks for your order</div>
      <p>Total paid: &#8377;1,234.50</p>
      <script type="application/ld+json">{"@type":"Order"}</script>
    </body></html>
    """
    let encoded = Data(html.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let resource = GmailMessageResource(
      id: "msg-html",
      threadId: "thread-html",
      labelIds: ["INBOX"],
      snippet: "Thanks for your order",
      historyId: "1",
      internalDate: "1700000000000",
      payload: GmailMessagePart(
        partId: "0",
        mimeType: "text/html; charset=utf-8",
        filename: nil,
        headers: [
          GmailMessageHeader(name: "From", value: "store@example.com"),
          GmailMessageHeader(name: "Subject", value: "Order receipt"),
        ],
        body: GmailMessageBody(attachmentId: nil, size: html.utf8.count, data: encoded),
        parts: nil
      )
    )

    let parsed = try GmailMessageParser.parse(resource)
    XCTAssertTrue(parsed.normalizedBody.contains("Thanks for your order"))
    XCTAssertTrue(parsed.normalizedBody.contains("Total paid:"))
    XCTAssertTrue(parsed.normalizedBody.contains("1,234.50"))
    XCTAssertFalse(parsed.normalizedBody.contains("<div"))
    XCTAssertFalse(parsed.normalizedBody.contains("font-size"))
    XCTAssertFalse(parsed.normalizedBody.contains("@type"))
  }

  func testPrefersHTMLTextWhenPlainPartIsMarkup() throws {
    let plainHTML = "<html><body><div>broken plain</div></body></html>"
    let richHTML = """
    <html><body><p>Uber trip receipt</p><p>Amount: $18.40</p></body></html>
    """
    func encode(_ value: String) -> String {
      Data(value.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
    let resource = GmailMessageResource(
      id: "msg-alt",
      threadId: "thread-alt",
      labelIds: ["INBOX"],
      snippet: "Uber trip receipt",
      historyId: "1",
      internalDate: "1700000000000",
      payload: GmailMessagePart(
        partId: "0",
        mimeType: "multipart/alternative",
        filename: nil,
        headers: [
          GmailMessageHeader(name: "From", value: "uber@example.com"),
          GmailMessageHeader(name: "Subject", value: "Trip receipt"),
        ],
        body: nil,
        parts: [
          GmailMessagePart(
            partId: "0",
            mimeType: "text/plain",
            filename: nil,
            headers: nil,
            body: GmailMessageBody(attachmentId: nil, size: plainHTML.utf8.count, data: encode(plainHTML)),
            parts: nil
          ),
          GmailMessagePart(
            partId: "1",
            mimeType: "text/html",
            filename: nil,
            headers: nil,
            body: GmailMessageBody(attachmentId: nil, size: richHTML.utf8.count, data: encode(richHTML)),
            parts: nil
          ),
        ]
      )
    )

    let parsed = try GmailMessageParser.parse(resource)
    XCTAssertTrue(parsed.normalizedBody.contains("Uber trip receipt"))
    XCTAssertTrue(parsed.normalizedBody.contains("$18.40"))
    XCTAssertFalse(parsed.normalizedBody.contains("<html"))
  }
}

final class EmailGemmaResponseTextTests: XCTestCase {
  func testSelectsJSONFromFinalChannelWhenOrdinaryContentIsEmpty() {
    let json = #"{"schemaVersion":1,"kind":"irrelevant"}"#

    XCTAssertEqual(
      EmailGemmaResponseText.select(
        content: "",
        channels: ["analysis": "I should classify this email.", "final": json]
      ),
      json
    )
  }

  func testPrefersTheCandidateContainingJSON() {
    let json = #"{"schemaVersion":1,"kind":"purchase"}"#

    XCTAssertEqual(
      EmailGemmaResponseText.select(
        content: "No structured response here.",
        channels: ["answer": "Result: \(json)"]
      ),
      "Result: \(json)"
    )
  }

  func testPromptReservesContextForOneRepairTurn() {
    XCTAssertGreaterThanOrEqual(
      EmailPromptBuilder.reservedOutputTokens,
      EmailPromptBuilder.maximumGeneratedTokens * 2
    )
    XCTAssertTrue(EmailPromptBuilder.jsonRepairPrompt.contains("first character must be {"))
  }

  func testPromptIncludesTheFullEmailBody() {
    let body = String(repeating: "purchase detail ", count: 1_000)
    let request = EmailAnalysisRequest(
      messageId: "message",
      accountSubject: "account",
      senderAddress: "merchant@example.com",
      subject: "Receipt",
      receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
      normalizedBody: body,
      categories: [],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )
    let prompt = EmailPromptBuilder.build(request)

    XCTAssertTrue(prompt.contains(body))
    XCTAssertTrue(prompt.hasPrefix("You are a JSON extraction function."))
    XCTAssertTrue(prompt.hasSuffix("Return only the JSON object now."))
  }
}

private actor FailingGemmaLanguageModel: EmailLanguageModel {
  func load() async throws {}

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisResult {
    throw EmailLanguageModelError.generationFailed("test failure")
  }

  func unload() async {}
}

final class GemmaModelManifestTests: XCTestCase {
  func testAcceptsStorageBudgetAtLeastTwiceTheArtifactSize() throws {
    var manifest = manifest(exactByteCount: 100, minimumFreeStorageBytes: 200)
    try manifest.validate()

    manifest.minimumFreeStorageBytes = 199
    XCTAssertThrowsError(try manifest.validate())
  }

  func testRefreshRemovesLegacyOneBModelAndRecognizes270MDirectory() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(
      path: "dimo-gemma-model-test-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    defer { try? fileManager.removeItem(at: root) }

    let legacy = root.appending(path: "Gemma3-1B/old", directoryHint: .isDirectory)
    try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)

    let current = root.appending(
      path: "Gemma3-270M/test-version",
      directoryHint: .isDirectory
    )
    try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
    let expectedModelURL = current.appending(path: "model.litertlm")
    try Data(repeating: 0, count: 100).write(to: expectedModelURL)

    let manager = GemmaModelManager(
      manifest: manifest(exactByteCount: 100, minimumFreeStorageBytes: 200),
      rootURL: root,
      fileManager: fileManager
    ) { _, _ in }

    await manager.refreshState()

    XCTAssertFalse(fileManager.fileExists(atPath: legacy.path))
    let installedURLs = await manager.installedURLs()
    XCTAssertEqual(installedURLs?.model, expectedModelURL)
  }

  private func manifest(
    exactByteCount: Int64,
    minimumFreeStorageBytes: Int64
  ) -> GemmaModelManifest {
    GemmaModelManifest(
      modelName: "Gemma 3 270M IT",
      version: "test-version",
      runtimeFormatVersion: "LiteRT-LM test",
      downloadURL: URL(string: "https://example.com/model.litertlm")!,
      exactByteCount: exactByteCount,
      sha256: String(repeating: "a", count: 64),
      minimumFreeStorageBytes: minimumFreeStorageBytes,
      promptSchemaVersion: EmailAnalysisResult.schemaVersion,
      termsURL: URL(string: "https://example.com/terms")!,
      attributionURL: URL(string: "https://example.com/model")!
    )
  }
}

final class EmailAnalysisProviderPersistenceTests: XCTestCase {
  func testProviderDefaultsToUnconfiguredAndRoundTripsDeviceSettings() throws {
    let queue = try AppDatabase.activate(userId: "provider-settings-\(UUID().uuidString)")
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()

    XCTAssertNil(try repository.emailAnalysisSettings().selectedProvider)
    XCTAssertEqual(try repository.emailAnalysisSettings().syncWindow, .oneDay)

    var settings = try repository.emailAnalysisSettings()
    settings.selectedProvider = .openRouter
    settings.openRouterModelID = OpenRouterClient.defaultModelID
    settings.openRouterPrivacyMode = .allowNonZDR
    settings.nonZDRConsentVersion = 1
    settings.syncWindow = .threeMonths
    try repository.saveEmailAnalysisSettings(settings)

    let restored = try repository.emailAnalysisSettings()
    XCTAssertEqual(restored.selectedProvider, .openRouter)
    XCTAssertEqual(restored.openRouterModelID, OpenRouterClient.defaultModelID)
    XCTAssertEqual(restored.openRouterPrivacyMode, .allowNonZDR)
    XCTAssertEqual(restored.nonZDRConsentVersion, 1)
    XCTAssertEqual(restored.syncWindow, .threeMonths)
  }

  func testExplicitProviderOverrideIsClearedByReanalyseAll() throws {
    let queue = try AppDatabase.activate(userId: "provider-override-\(UUID().uuidString)")
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    try repository.saveEmailAccount(EmailAccountRecordModel(
      id: "gmail-subject",
      emailAddress: "person@example.com"
    ))
    let message = PendingEmailMessage(
      accountId: "gmail-subject",
      gmailMessageId: "message",
      threadId: "thread",
      senderAddress: "merchant@example.com",
      subject: "Receipt",
      snippet: "Receipt",
      internalDate: 1_000,
      normalizedBodyText: "Paid ₹10.00"
    )
    _ = try repository.insertPendingEmailMessages([message])
    try repository.setEmailAnalysisProviderOverride(messageKey: message.key, provider: .openRouter)
    XCTAssertEqual(try repository.emailMessage(key: message.key)?.analysisProviderOverride, .openRouter)

    _ = try repository.resetEmailMessagesForReanalysis()
    XCTAssertNil(try repository.emailMessage(key: message.key)?.analysisProviderOverride)
  }

  func testRetryStateRoundTripsAndClears() throws {
    let queue = try AppDatabase.activate(userId: "provider-retry-\(UUID().uuidString)")
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repository = Repository(db: queue)
    try repository.initializeLocalDatabase()
    let state = EmailAnalysisRetryState(
      attempt: 3,
      notBefore: 10_000,
      reason: "Waiting",
      lastHTTPStatus: 429,
      updatedAt: 1
    )
    try repository.saveEmailAnalysisRetryState(state)
    XCTAssertEqual(try repository.emailAnalysisRetryState()?.attempt, 3)
    XCTAssertEqual(try repository.emailAnalysisRetryState()?.lastHTTPStatus, 429)
    try repository.clearEmailAnalysisRetryState()
    XCTAssertNil(try repository.emailAnalysisRetryState())
  }
}

final class OpenRouterPolicyTests: XCTestCase {
  func testRetryAfterParsesSecondsAndHTTPDate() {
    let now = Date(timeIntervalSince1970: 0)
    XCTAssertEqual(OpenRouterClient.parseRetryAfter("60", now: now), 60)
    XCTAssertEqual(
      OpenRouterClient.parseRetryAfter("Thu, 01 Jan 1970 00:02:00 GMT", now: now),
      120
    )
  }

  func testModelPricingAndStructuredOutputSupport() {
    let model = OpenRouterModel(
      id: OpenRouterClient.defaultModelID,
      name: "GPT OSS 20B Free",
      contextLength: 131_072,
      pricing: .init(prompt: "0", completion: "0"),
      supportedParameters: ["structured_outputs", "response_format", "max_tokens"],
      hasZDREndpoint: false
    )
    XCTAssertTrue(model.isFree)
    XCTAssertTrue(model.supports("structured_outputs"))
    XCTAssertFalse(model.hasZDREndpoint)
  }

  func testCatalogKeepsStructuredModelsAndAddsLiveZDRAvailability() async throws {
    let client = OpenRouterClient(session: Self.stubbedSession { request in
      switch request.url?.path {
      case "/api/v1/models/user":
        return Self.response(
          for: request,
          json: #"{"data":[{"id":"paid/structured","name":"Paid","context_length":8192,"pricing":{"prompt":"0.000001","completion":"0.000002"},"supported_parameters":["structured_outputs","response_format"]},{"id":"free/structured","name":"Free","context_length":4096,"pricing":{"prompt":"0","completion":"0"},"supported_parameters":["structured_outputs","response_format"]},{"id":"free/plain","name":"Plain","context_length":4096,"pricing":{"prompt":"0","completion":"0"},"supported_parameters":[]}] }"#
        )
      case "/api/v1/endpoints/zdr":
        return Self.response(
          for: request,
          json: #"{"data":[{"model_id":"paid/structured","supported_parameters":["structured_outputs","response_format","max_completion_tokens"]}]}"#
        )
      default:
        throw URLError(.unsupportedURL)
      }
    })

    let models = try await client.models(apiKey: "secret-test-key")

    XCTAssertEqual(models.map(\.id), ["free/structured", "paid/structured"])
    XCTAssertFalse(try XCTUnwrap(models.first).hasZDREndpoint)
    XCTAssertTrue(try XCTUnwrap(models.last).hasZDREndpoint)
    XCTAssertEqual(try XCTUnwrap(models.last).zdrSupportedParameters, [
      "max_completion_tokens", "response_format", "structured_outputs",
    ])
  }

  func testAnalysisUsesBearerKeyAndStrictStructuredOutputRequest() async throws {
    let key = "secret-test-key"
    let client = OpenRouterClient(session: Self.stubbedSession { request in
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.url?.path, "/api/v1/chat/completions")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(key)")
      XCTAssertFalse(request.url?.absoluteString.contains(key) ?? true)

      let body = try XCTUnwrap(Self.bodyData(from: request))
      let payload = try XCTUnwrap(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      XCTAssertNil(String(data: body, encoding: .utf8)?.range(of: key))
      XCTAssertEqual(payload["stream"] as? Bool, false)
      XCTAssertNil(payload["max_tokens"])
      XCTAssertEqual(payload["max_completion_tokens"] as? Int, 512)
      XCTAssertNil(payload["temperature"])
      let provider = try XCTUnwrap(payload["provider"] as? [String: Any])
      XCTAssertEqual(provider["require_parameters"] as? Bool, true)
      XCTAssertEqual(provider["zdr"] as? Bool, true)
      let responseFormat = try XCTUnwrap(payload["response_format"] as? [String: Any])
      XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
      let jsonSchema = try XCTUnwrap(responseFormat["json_schema"] as? [String: Any])
      XCTAssertEqual(jsonSchema["strict"] as? Bool, true)

      let analysis = #"{"schemaVersion":1,"kind":"irrelevant","merchant":null,"amount":null,"currency":null,"occurredAt":null,"categoryId":null,"paymentMethodId":null,"paymentLastFour":null,"reference":null}"#
      let escaped = try JSONSerialization.data(withJSONObject: [
        "id": "request-1",
        "model": "resolved/model",
        "choices": [["message": ["content": analysis]]],
      ])
      return (
        try XCTUnwrap(HTTPURLResponse(
          url: try XCTUnwrap(request.url),
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )),
        escaped
      )
    })
    let model = OpenRouterModel(
      id: "requested/model",
      name: "Requested model",
      contextLength: 8_192,
      pricing: .init(prompt: "0", completion: "0"),
      supportedParameters: ["structured_outputs", "response_format", "max_tokens", "temperature"],
      hasZDREndpoint: true,
      zdrSupportedParameters: [
        "structured_outputs", "response_format", "max_completion_tokens",
      ]
    )
    let request = EmailAnalysisRequest(
      messageId: "message",
      accountSubject: "account",
      senderAddress: "newsletter@example.com",
      subject: "Weekly newsletter",
      receivedAt: .now,
      normalizedBody: "This is a newsletter without a transaction.",
      categories: [],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )

    let envelope = try await client.analyze(
      request,
      model: model,
      privacyMode: .zdrOnly,
      apiKey: key
    )

    XCTAssertEqual(envelope.analyzer, .openRouter)
    XCTAssertEqual(envelope.modelID, "resolved/model")
    XCTAssertEqual(envelope.requestID, "request-1")
  }

  func testIncompleteStructuredOutputRetriesOnceWithLargerTokenLimit() async throws {
    let requests = OpenRouterRequestLog()
    let client = OpenRouterClient(session: Self.stubbedSession { request in
      let body = try XCTUnwrap(Self.bodyData(from: request))
      let payload = try XCTUnwrap(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let attempt = requests.record(
        outputTokenLimit: try XCTUnwrap(payload["max_completion_tokens"] as? Int)
      )
      let content = attempt == 1
        ? #"{"schemaVersion":1,"kind":"purchase""#
        : #"{"schemaVersion":1,"kind":"irrelevant","merchant":null,"amount":null,"currency":null,"occurredAt":null,"categoryId":null,"paymentMethodId":null,"paymentLastFour":null,"reference":null}"#
      let data = try JSONSerialization.data(withJSONObject: [
        "id": "request-\(attempt)",
        "model": "resolved/model",
        "choices": [["message": ["content": content]]],
      ])
      return (
        try XCTUnwrap(HTTPURLResponse(
          url: try XCTUnwrap(request.url),
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )),
        data
      )
    })
    let analyzer = OpenRouterEmailAnalyzer(
      client: client,
      model: OpenRouterModel(
        id: "requested/model",
        name: "Requested model",
        contextLength: 8_192,
        pricing: .init(prompt: "0", completion: "0"),
        supportedParameters: [
          "structured_outputs", "response_format", "max_completion_tokens",
        ],
        hasZDREndpoint: false
      ),
      privacyMode: .allowNonZDR,
      apiKey: "secret-test-key"
    )
    let request = EmailAnalysisRequest(
      messageId: "message",
      accountSubject: "account",
      senderAddress: "newsletter@example.com",
      subject: "Weekly newsletter",
      receivedAt: .now,
      normalizedBody: "This is a newsletter without a transaction.",
      categories: [],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )

    let envelope = try await analyzer.analyze(request)

    XCTAssertEqual(envelope.result.kind, .irrelevant)
    XCTAssertEqual(requests.outputTokenLimits, [
      OpenRouterClient.standardOutputTokenLimit,
      OpenRouterClient.incompleteOutputRetryTokenLimit,
    ])
  }

  func testMissingModelResponseRequiresAReplacementInsteadOfSchedulingRetry() async throws {
    let client = OpenRouterClient(session: Self.stubbedSession { request in
      (
        try XCTUnwrap(HTTPURLResponse(
          url: try XCTUnwrap(request.url),
          statusCode: 404,
          httpVersion: nil,
          headerFields: nil
        )),
        Data(#"{"error":{"message":"No endpoints found for this model"}}"#.utf8)
      )
    })
    let model = OpenRouterModel(
      id: "missing/model",
      name: "Missing model",
      contextLength: 8_192,
      pricing: .init(prompt: "0", completion: "0"),
      supportedParameters: ["structured_outputs", "response_format"],
      hasZDREndpoint: true,
      zdrSupportedParameters: ["structured_outputs", "response_format"]
    )
    let request = EmailAnalysisRequest(
      messageId: "message",
      accountSubject: "account",
      senderAddress: "merchant@example.com",
      subject: "Receipt",
      receivedAt: .now,
      normalizedBody: "Receipt",
      categories: [],
      paymentMethods: [],
      merchantHistory: [],
      activeCurrency: .INR
    )

    do {
      _ = try await client.analyze(
        request,
        model: model,
        privacyMode: .zdrOnly,
        apiKey: "secret-test-key"
      )
      XCTFail("Expected the missing model to be rejected")
    } catch let error as OpenRouterClientError {
      guard case .modelUnavailable = error else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertFalse(error.isTransient)
    }
  }

  private static func stubbedSession(
    _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  ) -> URLSession {
    OpenRouterStubURLProtocol.handler = handler
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OpenRouterStubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private static func response(
    for request: URLRequest,
    json: String
  ) -> (HTTPURLResponse, Data) {
    (
      HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!,
      Data(json.utf8)
    )
  }

  private static func bodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { return nil }
      if count == 0 { break }
      result.append(buffer, count: count)
    }
    return result
  }
}

private final class OpenRouterStubURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class OpenRouterRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var storedOutputTokenLimits: [Int] = []

  func record(outputTokenLimit: Int) -> Int {
    lock.lock()
    defer { lock.unlock() }
    storedOutputTokenLimits.append(outputTokenLimit)
    return storedOutputTokenLimits.count
  }

  var outputTokenLimits: [Int] {
    lock.lock()
    defer { lock.unlock() }
    return storedOutputTokenLimits
  }
}
