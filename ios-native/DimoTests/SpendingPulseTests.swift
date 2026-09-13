import XCTest
@testable import Dimo

final class SpendingPulseTests: XCTestCase {
  private var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    return cal
  }
  private func date(_ day: Int, hour: Int = 12, month: Int = 9) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
  }
  private func snapshot(_ rows: [(Date, Int, String)]) -> PulseSnapshot {
    .init(updatedAt: date(16), currency: "INR", minorUnitDigits: 2,
          expenses: rows.map { .init(date: $0.0, amountMinor: $0.1, categoryID: $0.2, categoryName: $0.2) })
  }
  func testDayUsesSameElapsedTimeAndExcludesFutureExpenses() {
    let data = snapshot([(date(16, hour: 9), 840, "Food"), (date(16, hour: 16), 500, "Future"),
                         (date(15, hour: 9), 1000, "Food"), (date(15, hour: 18), 2000, "Food")])
    let result = PulseSelectors.summarize(data, period: .day, now: date(16), calendar: calendar)
    XCTAssertEqual(result.totalMinor, 840)
    XCTAssertEqual(result.previousMinor, 1000)
    XCTAssertEqual(result.bars.reduce(0, +), 840)
    XCTAssertEqual(result.bars[3], 840)
    XCTAssertEqual(result.comparison, "16% less than yesterday")
  }
  func testWeekStartsMondayAndComparesSameWeekdayTime() {
    let data = snapshot([(date(13), 900, "Prior Sunday"), (date(14), 100, "Food"),
                         (date(16, hour: 9), 200, "Food"), (date(7), 400, "Food"),
                         (date(9, hour: 18), 600, "Late"), (date(17), 900, "Future")])
    let result = PulseSelectors.summarize(data, period: .week, now: date(16), calendar: calendar)
    XCTAssertEqual(result.totalMinor, 300)
    XCTAssertEqual(result.previousMinor, 400)
    XCTAssertEqual(result.bars, [100, 0, 200, 0, 0, 0, 0])
    XCTAssertEqual(result.topCategory, "Food")
  }
  func testMidnightRollsDayAndWeekToZero() {
    let data = snapshot([(date(13, hour: 23), 100, "Food")])
    for period in PulsePeriod.allCases {
      let result = PulseSelectors.summarize(data, period: period, now: date(14, hour: 0), calendar: calendar)
      XCTAssertEqual(result.totalMinor, 0)
      XCTAssertNil(result.topCategory)
      XCTAssertEqual(result.comparison, "No spending yet")
    }
  }
  func testDSTUsesLocalClockForPreviousDay() {
    let data = snapshot([(date(8, hour: 9, month: 3), 100, "Food"),
                         (date(7, hour: 11, month: 3), 200, "Food"),
                         (date(7, hour: 13, month: 3), 300, "Food")])
    let result = PulseSelectors.summarize(data, period: .day, now: date(8, hour: 12, month: 3), calendar: calendar)
    XCTAssertEqual(result.previousMinor, 200)
    XCTAssertEqual(result.totalMinor, 100)
  }
  func testZeroBaselineAndCategoryIDs() {
    let data = snapshot([(date(16), 100, "a"), (date(16), 200, "b")])
    let result = PulseSelectors.summarize(data, period: .day, now: date(16), calendar: calendar)
    XCTAssertEqual(result.comparison, "No spending yesterday")
    XCTAssertEqual(result.topCategory, "b")
    XCTAssertEqual(try JSONDecoder().decode(PulseSnapshot.self, from: JSONEncoder().encode(data)), data)
  }

  func testPublisherConvertsOriginalMinorUnitsAndDoesNotDoubleConvertDisplayAmount() {
    let tx = Transaction(id: "1", name: "Lunch", category: "Food", time: "", day: "", amount: 90,
      amountMinor: 100, occurredAt: Int(date(16).timeIntervalSince1970 * 1000), categoryId: "food", currency: "USD")
    let rates = RateTable(date: "2026-09-16", base: "USD", rates: ["INR": 90])
    let result = PulsePublisher.makeSnapshot(transactions: [tx], currency: "INR", rates: rates, now: date(16))
    XCTAssertEqual(result.expenses.first?.amountMinor, 9000)
    XCTAssertFalse(result.missingRates)
    let missing = PulsePublisher.makeSnapshot(transactions: [tx], currency: "INR", rates: nil, now: date(16))
    XCTAssertTrue(missing.missingRates)
    XCTAssertTrue(missing.expenses.isEmpty)
  }

  func testPublisherDropsOldRowsAndReflectsDeletion() {
    let tx = Transaction(id: "1", name: "Lunch", category: "Food", time: "", day: "", amount: 1,
      amountMinor: 100, occurredAt: Int(date(1, month: 8).timeIntervalSince1970 * 1000), currency: "INR")
    let result = PulsePublisher.makeSnapshot(transactions: [tx], currency: "INR", rates: nil, now: date(16))
    XCTAssertTrue(result.expenses.isEmpty)
    let deleted = PulsePublisher.makeSnapshot(transactions: [], currency: "INR", rates: nil, now: date(16))
    XCTAssertTrue(deleted.expenses.isEmpty)
  }
}
