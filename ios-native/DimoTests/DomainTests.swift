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
    XCTAssertEqual(first.filter { !$0.deleted }.count, 7)
    try repo.initializeLocalDatabase()
    let second = try repo.allEntities()
    XCTAssertEqual(second.filter { !$0.deleted }.count, 7)
    let cash = try repo.activeEntities(type: .paymentMethod)
      .contains { $0.entityId == SeedData.cashPaymentMethod.id }
    XCTAssertTrue(cash)
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
