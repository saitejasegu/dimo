package app.dimo.android.domain

import app.dimo.android.data.PayloadSanitizer
import app.dimo.android.data.SeedData
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.PreferencesEntity
import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.Transaction
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart
import app.dimo.android.data.model.compareVersions
import app.dimo.android.data.model.Lend as LendModel
import app.dimo.android.sync.isPermanentSyncError
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Ports of the in-scope cases in `ios-native/DimoTests/DomainTests.swift`.
 *
 * The Swift file has 129 tests, but roughly two thirds cover the Email / Gemma /
 * OpenRouter subsystem, which Android v1 does not ship. Everything below is the
 * core-parity subset: version ordering, greetings, exchange rates, stats, date
 * math, recurring bills, CSV, transaction filtering, the sanitizer, budget
 * suggestions, lending, and permanent sync-error classification.
 */

/** All date math is zone-sensitive; pin the zone so results are reproducible. */
abstract class ZonedTest {
  private lateinit var previous: TimeZone

  @Before
  fun pinTimeZone() {
    previous = TimeZone.getDefault()
    TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    Locale.setDefault(Locale.US)
  }

  @After
  fun restoreTimeZone() {
    TimeZone.setDefault(previous)
  }

  protected fun zone(): ZoneId = ZoneId.of("UTC")

  protected fun stamp(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0): Long =
    LocalDate.of(year, month, day)
      .atTime(hour, minute)
      .atZone(zone())
      .toInstant()
      .toEpochMilli()
}

class LogicalVersionTests {
  @Test
  fun ordersByTimestampCounterThenDeviceId() {
    val base = LogicalVersion(timestamp = 100, counter = 1, deviceId = "a")
    assertTrue(compareVersions(LogicalVersion(101, 1, "a"), base) > 0)
    assertTrue(compareVersions(LogicalVersion(100, 2, "a"), base) > 0)
    assertTrue(compareVersions(LogicalVersion(100, 1, "b"), base) > 0)
    assertEquals(0, compareVersions(base, base))
  }
}

class GreetingTests {
  @Test
  fun greetingHours() {
    assertEquals("Good morning", Greeting.greetingFor(LocalTime.of(0, 0)))
    assertEquals("Good morning", Greeting.greetingFor(LocalTime.of(11, 0)))
    assertEquals("Good afternoon", Greeting.greetingFor(LocalTime.of(12, 0)))
    assertEquals("Good afternoon", Greeting.greetingFor(LocalTime.of(16, 0)))
    assertEquals("Good evening", Greeting.greetingFor(LocalTime.of(17, 0)))
  }
}

class ExchangeRateTests : ZonedTest() {
  private val rates = RateTable(
    date = "2026-07-21",
    base = "EUR",
    rates = mapOf("USD" to 1.0, "INR" to 100.0),
  )

  @Test
  fun buildsMajorUnitRatioForConversionCalculation() {
    assertEquals(100.0, ExchangeRates.rateBetween("USD", "INR", rates)!!, 0.0)
    assertEquals("23.6", Formatting.decimal(23.6, maximumFractionDigits = 2))
  }

  @Test
  fun convertsForeignMinorUnitsIntoDefaultCurrency() {
    val converted = ExchangeRates.convertMinor(2360, "USD", "INR", rates)
    assertEquals(236_000L, converted)
    assertEquals(2360.0, ExchangeRates.toMajorUnits(converted!!, "INR"), 0.0)
  }

  @Test
  fun foreignRecurringDisplaysInSourceCurrencyButTotalsInDefaultCurrency() {
    val recurring = Recurring(
      id = "usd-recurring",
      name = "Subscription",
      category = "Subscriptions",
      due = "",
      amount = 23.6,
      paused = false,
      amountMinor = 2_360,
      anchorDate = "2026-07-21",
      frequency = RecurringFrequency.MONTHLY,
      currency = "USD",
    )

    assertEquals("$23.60", Formatting.money(recurring.amount, recurring.currency!!))
    val total = RecurringSelectors.monthlyRecurringTotal(listOf(recurring)) {
      ExchangeRates.recurringAmountInDefault(it, defaultCurrency = "INR", rates = rates)
    }
    assertEquals(2360.0, total, 0.0001)
  }

  @Test
  fun recurringFieldsAlwaysRecordTheirDenomination() {
    val (foreignMinor, foreignCurrency) = ExchangeRates.recurringFields(23.6, "USD")
    assertEquals(2_360L, foreignMinor)
    assertEquals("USD", foreignCurrency)

    val (defaultMinor, defaultCurrency) = ExchangeRates.recurringFields(500.0, "INR")
    assertEquals(50_000L, defaultMinor)
    assertEquals("INR", defaultCurrency)
  }
}

class StatsHydrationTests {
  @Test
  fun pulledDefaultReplacesUntouchedBootstrapRange() {
    assertEquals(
      StatsRange.THREE_MONTHS,
      StatsConstants.hydratedRange(
        current = StatsRange.ONE_YEAR,
        previousDefault = StatsRange.ONE_YEAR,
        nextDefault = StatsRange.THREE_MONTHS,
        dataReady = true,
      ),
    )
  }

  @Test
  fun pulledDefaultPreservesUserSelectedRange() {
    assertEquals(
      StatsRange.SIX_MONTHS,
      StatsConstants.hydratedRange(
        current = StatsRange.SIX_MONTHS,
        previousDefault = StatsRange.ONE_YEAR,
        nextDefault = StatsRange.THREE_MONTHS,
        dataReady = true,
      ),
    )
  }
}

class StatsSelectorTests : ZonedTest() {
  @Test
  fun averageStartsAtOldestTransactionDateInSelectedRange() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)

    fun transaction(id: String, amount: Double, occurredAt: Long) = Transaction(
      id = id,
      name = "Merchant",
      category = "Dining",
      time = "",
      day = "",
      amount = amount,
      occurredAt = occurredAt,
    )

    val transactions = listOf(
      transaction("oldest", 100.0, stamp(2026, 7, 7, hour = 23)),
      transaction("today", 400.0, stamp(2026, 7, 11, hour = 10)),
      transaction("outside-range", 999.0, stamp(2025, 7, 1, hour = 10)),
    )

    val scope = StatsSelectors.statsScope(
      range = StatsRange.ONE_YEAR,
      transactions = transactions,
      now = now,
      nowMillis = nowMillis,
    )

    assertEquals("₹100 avg per day", scope.averageLabel)
  }

  private fun transaction(id: String, amount: Double, occurredAt: Long) = Transaction(
    id = id,
    name = "Merchant",
    category = "Dining",
    time = "",
    day = "",
    amount = amount,
    occurredAt = occurredAt,
  )

  @Test
  fun currentPeriodAnchorsToNow() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)

    val anchor = StatsSelectors.statsAnchor(StatsRange.MONTH, 0, now, nowMillis)

    assertEquals(now, anchor.date)
    assertEquals(nowMillis, anchor.millis)
  }

  @Test
  fun previousMonthPeriodCoversThatWholeMonth() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)
    val transactions = listOf(
      transaction("june-first", 100.0, stamp(2026, 6, 1, hour = 1)),
      transaction("june-last", 200.0, stamp(2026, 6, 30, hour = 23)),
      transaction("july", 999.0, stamp(2026, 7, 2, hour = 10)),
      transaction("may", 999.0, stamp(2026, 5, 31, hour = 10)),
    )

    val scope = StatsSelectors.statsScope(
      range = StatsRange.MONTH,
      transactions = transactions,
      now = now,
      nowMillis = nowMillis,
      offset = -1,
    )

    assertEquals(listOf("june-first", "june-last"), scope.transactions.map { it.id })
    assertEquals(300.0, scope.scopeTotal, 0.0001)
    assertEquals("Jun 2026", scope.periodLabel)
    assertEquals("Spent in Jun 2026", scope.spentLabel)
  }

  @Test
  fun currentPeriodKeepsItsOwnLabels() {
    val scope = StatsSelectors.statsScope(
      range = StatsRange.MONTH,
      transactions = emptyList(),
      now = LocalDate.of(2026, 7, 11),
      nowMillis = stamp(2026, 7, 11, hour = 15),
    )

    assertEquals("This month", scope.periodLabel)
    assertEquals("Spent this month", scope.spentLabel)
  }

  @Test
  fun previousWeekLabelSpansTheShiftedWindow() {
    val label = StatsSelectors.periodLabel(
      range = StatsRange.ONE_WEEK,
      offset = -1,
      now = LocalDate.of(2026, 7, 11),
      nowMillis = stamp(2026, 7, 11, hour = 15),
      locale = Locale.US,
    )

    assertEquals("Jun 28 – Jul 4", label)
  }

  @Test
  fun multiMonthLabelSpansStartAndEndMonths() {
    val label = StatsSelectors.periodLabel(
      range = StatsRange.ONE_YEAR,
      offset = -1,
      now = LocalDate.of(2026, 7, 11),
      nowMillis = stamp(2026, 7, 11, hour = 15),
      locale = Locale.US,
    )

    assertEquals("Aug 2024 – Jul 2025", label)
  }

  @Test
  fun periodsAreContiguousAndDoNotOverlap() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)
    // One per month across the last three months, plus the current partial one.
    val transactions = listOf(
      transaction("may", 10.0, stamp(2026, 5, 15)),
      transaction("june", 20.0, stamp(2026, 6, 15)),
      transaction("july", 30.0, stamp(2026, 7, 5)),
    )

    fun idsAt(offset: Int) = StatsSelectors.statsScope(
      range = StatsRange.MONTH,
      transactions = transactions,
      now = now,
      nowMillis = nowMillis,
      offset = offset,
    ).transactions.map { it.id }

    assertEquals(listOf("july"), idsAt(0))
    assertEquals(listOf("june"), idsAt(-1))
    assertEquals(listOf("may"), idsAt(-2))
  }

  @Test
  fun hasEarlierDataStopsWhenNothingPrecedesTheWindow() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)
    val transactions = listOf(transaction("oldest", 100.0, stamp(2025, 7, 1, hour = 10)))

    // The current year window starts 2025-08-01, so the 2025-07-01 row precedes it.
    assertTrue(
      StatsSelectors.hasEarlierData(transactions, StatsRange.ONE_YEAR, 0, now, nowMillis),
    )
    // One period back starts 2024-08-01, which nothing precedes.
    assertFalse(
      StatsSelectors.hasEarlierData(transactions, StatsRange.ONE_YEAR, -1, now, nowMillis),
    )
  }

  @Test
  fun trendBarsFollowTheSelectedPeriod() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11, hour = 15)

    val bars = StatsSelectors.trendBars(
      range = StatsRange.MONTH,
      transactions = emptyList(),
      selectedKey = null,
      now = now,
      locale = Locale.US,
      nowMillis = nowMillis,
      offset = -1,
    )

    // June has 30 days and the shifted window runs to month end.
    assertEquals(30, bars.bars.size)
    assertEquals("2026-06-01", bars.bars.first().key)
    assertEquals("2026-06-30", bars.bars.last().key)
  }
}

class DateHelpersTests : ZonedTest() {
  @Test
  fun clampsMonthlyDayToShortMonth() {
    val next = DateHelpers.nextOccurrence(
      anchorDate = "2026-01-31",
      frequency = RecurringFrequency.MONTHLY,
      now = LocalDate.of(2026, 2, 1),
    )
    assertEquals(LocalDate.of(2026, 2, 28), next)
  }

  @Test
  fun leapDayYearlyUsesFeb28() {
    val next = DateHelpers.nextOccurrence(
      anchorDate = "2024-02-29",
      frequency = RecurringFrequency.YEARLY,
      now = LocalDate.of(2025, 1, 1),
    )
    assertEquals(LocalDate.of(2025, 2, 28), next)
  }

  @Test
  fun occurrencesThroughMonthly() {
    val dates = DateHelpers.occurrencesThrough(
      anchorDate = "2026-01-15",
      frequency = RecurringFrequency.MONTHLY,
      now = LocalDate.of(2026, 4, 20),
    )
    assertEquals(
      listOf(
        LocalDate.of(2026, 1, 15),
        LocalDate.of(2026, 2, 15),
        LocalDate.of(2026, 3, 15),
        LocalDate.of(2026, 4, 15),
      ),
      dates,
    )
  }

  @Test
  fun futureAnchorReturnsEmpty() {
    val dates = DateHelpers.occurrencesThrough(
      anchorDate = "2026-08-01",
      frequency = RecurringFrequency.MONTHLY,
      now = LocalDate.of(2026, 4, 20),
    )
    assertTrue(dates.isEmpty())
  }
}

class RecurringSelectorsTests : ZonedTest() {
  private fun recurring(
    id: String,
    name: String,
    anchorDate: String,
    paused: Boolean = false,
  ) = Recurring(
    id = id,
    name = name,
    category = "Subscriptions",
    due = "",
    amount = 10.0,
    paused = paused,
    anchorDate = anchorDate,
    frequency = RecurringFrequency.MONTHLY,
  )

  @Test
  fun upcomingBillsSortedByDueDateAscending() {
    val now = LocalDate.of(2026, 7, 12)
    val recs = listOf(
      recurring("late", "Rent", "2026-07-28"),
      recurring("early", "Netflix", "2026-07-15"),
      recurring("mid", "Gym", "2026-07-20"),
      recurring("paused", "Paused", "2026-07-13", paused = true),
      recurring("next-month", "Later", "2026-08-01"),
    )
    val upcoming = RecurringSelectors.upcomingBills(recs, emptyList(), limit = 3, now = now)
    assertEquals(listOf("early", "mid", "late"), upcoming.map { it.id })
  }

  @Test
  fun upcomingBillsReturnsEntireCurrentMonthWithoutLimit() {
    val now = LocalDate.of(2026, 7, 12)
    val recs = listOf(
      recurring("fifth", "Fifth", "2026-07-28"),
      recurring("first", "First", "2026-07-13"),
      recurring("fourth", "Fourth", "2026-07-24"),
      recurring("second", "Second", "2026-07-15"),
      recurring("third", "Third", "2026-07-20"),
      recurring("paused", "Paused", "2026-07-14", paused = true),
      recurring("next-month", "Later", "2026-08-01"),
    )
    val upcoming = RecurringSelectors.upcomingBills(recs, emptyList(), now = now)
    assertEquals(listOf("first", "second", "third", "fourth", "fifth"), upcoming.map { it.id })
  }

  @Test
  fun chargedBillDropsOutOfUpcoming() {
    // "today" is the bill's own anchor day, so nextOccurrence is today.
    val now = LocalDate.of(2026, 7, 24)
    val bill = recurring("icloud", "iCloud Plus", "2026-07-24")
    val charged = Transaction(
      id = "recurring:icloud:2026-07-24",
      name = "iCloud Plus",
      category = "Subscriptions",
      time = "12:00 PM",
      day = "Today",
      amount = 10.0,
    )

    assertEquals(
      listOf("icloud"),
      RecurringSelectors.upcomingBills(listOf(bill), emptyList(), now = now).map { it.id },
    )
    assertTrue(
      RecurringSelectors.upcomingBills(listOf(bill), listOf(charged), now = now).isEmpty(),
    )
  }

  @Test
  fun allUpcomingBillsIncludesFutureMonths() {
    val now = LocalDate.of(2026, 7, 12)
    val recs = listOf(
      recurring("next-month", "Later", "2026-08-01"),
      recurring("first", "First", "2026-07-13"),
      recurring("paused", "Paused", "2026-07-14", paused = true),
      recurring("second", "Second", "2026-07-15"),
    )
    val all = RecurringSelectors.allUpcomingBills(recs, emptyList(), now = now)
    assertEquals(listOf("first", "paused", "second", "next-month"), all.map { it.id })
  }

  @Test
  fun pausedOnlyAccountsRemainAvailableInExpandedHomeResults() {
    val now = LocalDate.of(2026, 7, 12)
    val paused = recurring("paused", "Paused", "2026-09-01", paused = true)

    assertTrue(RecurringSelectors.upcomingBills(listOf(paused), emptyList(), now = now).isEmpty())
    assertEquals(
      listOf("paused"),
      RecurringSelectors.allUpcomingBills(listOf(paused), emptyList(), now = now).map { it.id },
    )
  }

  @Test
  fun recurringTransactionDatesSupportsAllSelectedAndFuture() {
    val now = LocalDate.of(2026, 4, 20)
    val all = DateHelpers.recurringTransactionDates(
      "2026-01-15",
      RecurringFrequency.MONTHLY,
      RecurringOccurrenceSelection.ALL,
      now,
    )
    val selected = DateHelpers.recurringTransactionDates(
      "2026-01-15",
      RecurringFrequency.MONTHLY,
      RecurringOccurrenceSelection.SELECTED,
      now,
    )
    val future = DateHelpers.recurringTransactionDates(
      "2026-08-01",
      RecurringFrequency.YEARLY,
      RecurringOccurrenceSelection.SELECTED,
      now,
    )
    assertEquals(listOf(1, 2, 3, 4), all.map { it.monthValue })
    assertEquals(listOf(1), selected.map { it.monthValue })
    assertTrue(future.isEmpty())
  }

  @Test
  fun monthlyAndYearlySchedulesStartingTodayCreateOneTransaction() {
    val now = LocalDate.of(2026, 7, 15)
    for (frequency in listOf(RecurringFrequency.MONTHLY, RecurringFrequency.YEARLY)) {
      val dates = DateHelpers.recurringTransactionDates(
        "2026-07-15",
        frequency,
        RecurringOccurrenceSelection.SELECTED,
        now,
      )
      assertEquals(listOf("2026-07-15"), dates.map { DateHelpers.localDateKey(it) })
    }
  }

  @Test
  fun pastYearlyScheduleListsEveryOccurrence() {
    val dates = DateHelpers.recurringTransactionDates(
      "2024-02-29",
      RecurringFrequency.YEARLY,
      RecurringOccurrenceSelection.ALL,
      LocalDate.of(2026, 3, 1),
    )
    assertEquals(
      listOf("2024-02-29", "2025-02-28", "2026-02-28"),
      dates.map { DateHelpers.localDateKey(it) },
    )
  }

  @Test
  fun occurrenceTimestampPreservesSelectedTime() {
    val timestamp = DateHelpers.occurrenceTimestamp(
      LocalDate.of(2026, 4, 15),
      LocalTime.of(9, 45),
      zone(),
    )
    val combined = java.time.Instant.ofEpochMilli(timestamp).atZone(zone())
    assertEquals(9, combined.hour)
    assertEquals(45, combined.minute)
  }
}

class LegacyNavigationTests {
  @Test
  fun recurringViewKeyStillDecodes() {
    // `recurring` is a legacy nav destination that must keep decoding even though
    // Android reaches recurring bills from Home rather than a tab.
    assertEquals(ViewKey.RECURRING, ViewKey.fromWire("recurring"))
  }
}

class PermanentSyncErrorTests {
  @Test
  fun permanentMessages() {
    assertTrue(isPermanentSyncError("ArgumentValidationError: bad"))
    assertTrue(isPermanentSyncError("Payload does not match"))
    assertTrue(!isPermanentSyncError("Not authenticated"))
    assertTrue(!isPermanentSyncError("NetworkError"))
  }
}

class TransactionCSVTests : ZonedTest() {
  @Test
  fun parseAndRoundTrip() {
    val csv = "Date,Note,Amount,Category,Type\r\n" +
      "2026-07-11 11:38:08 +0000,\"Coffee, shop\",12.50,Cafe,Expense\r\n"
    val rows = TransactionCSV.parse(csv)
    assertEquals(1, rows.size)
    assertEquals("Coffee, shop", rows[0].merchant)
    assertEquals(1250L, rows[0].amountMinor)
    assertEquals("☕", TransactionCSV.categoryEmojiForName("Movie snacks"))
    assertEquals("💡", TransactionCSV.categoryEmojiForName("Utilities"))
  }

  @Test
  fun parsesDateOnlyAsUTCMidnight() {
    val csv = "Date,Note,Amount,Category,Type\n2026-07-11,Coffee,3.54,Snacks,Expense\n"
    val rows = TransactionCSV.parse(csv)
    assertEquals(1_783_728_000_000L, rows[0].occurredAt)
  }

  @Test(expected = TransactionCSV.CSVException::class)
  fun rejectsIncome() {
    val csv = "Date,Note,Amount,Category,Type\n2026-07-11 11:38:08 +0000,Pay,10.00,Work,Income\n"
    TransactionCSV.parse(csv)
  }

  @Test
  fun formatRoundTripsThroughParse() {
    val exported = TransactionCSV.format(
      listOf(
        TransactionCSV.Source(
          name = "Coffee, shop",
          category = "Cafe",
          amount = 12.5,
          amountMinor = 1250,
          occurredAt = 1_783_728_000_000,
        ),
      ),
    )
    val rows = TransactionCSV.parse(exported)
    assertEquals(1, rows.size)
    assertEquals("Coffee, shop", rows[0].merchant)
    assertEquals(1250L, rows[0].amountMinor)
    assertEquals(1_783_728_000_000L, rows[0].occurredAt)
  }
}

class TransactionSelectorTests : ZonedTest() {
  private fun tx(
    id: String,
    name: String,
    category: String,
    day: String,
    amount: Double,
    payment: String? = null,
    occurredAt: Long? = null,
  ) = Transaction(
    id = id,
    name = name,
    category = category,
    time = "10:00 AM",
    day = day,
    amount = amount,
    paymentMethod = payment,
    occurredAt = occurredAt,
  )

  @Test
  fun filterAndPaginateByDay() {
    val items = listOf(
      tx("1", "A", "Dining", "Today", 10.0, "Cash"),
      tx("2", "B", "Bills", "Today", 20.0, "UPI"),
      tx("3", "C", "Dining", "Yesterday", 30.0, "Cash"),
      tx("4", "D", "Dining", "Yesterday", 40.0, "Cash"),
    )
    val filtered = TransactionSelectors.filterTransactions(
      items,
      TransactionFilter(categories = listOf("Dining"), paymentMethod = "Cash"),
    )
    assertEquals(listOf("1", "3", "4"), filtered.map { it.id })

    val (page, hasMore) = TransactionSelectors.paginateTransactionsByDay(items, limit = 1)
    assertEquals(listOf("1", "2"), page.map { it.id })
    assertTrue(hasMore)
  }

  @Test
  fun suggestionCategoryRequiresActiveOriginalCategory() {
    val categories = listOf(
      CategoryEntity("old", "Dining", "🍽️", null, CategoryTint.NEUTRAL, 0, false, archived = true),
      CategoryEntity("new", "Dining", "🍽️", null, CategoryTint.NEUTRAL, 1, false),
      CategoryEntity("bills", "Bills", "🧾", null, CategoryTint.NEUTRAL, 2, false),
    )
    val earlier = tx("1", "Cafe", "Dining", "Today", 1.0).copy(categoryId = "new", occurredAt = 1L)
    val later = earlier.copy(id = "2", categoryId = "old", occurredAt = 2L)
    val suggestion = TransactionSelectors.merchantSuggestions(listOf(earlier, later), "caf").first()
    assertEquals("old", suggestion.categoryId)
    assertEquals(2, suggestion.count)
    assertNull(TransactionSelectors.suggestionCategory(suggestion, categories))
    assertEquals("Dining", TransactionSelectors.suggestionCategory(suggestion.copy(categoryId = "new", category = "Old name"), categories))
    assertNull(TransactionSelectors.suggestionCategory(suggestion.copy(categoryId = "missing"), categories))
    assertEquals("Bills", TransactionSelectors.suggestionCategory(suggestion.copy(categoryId = null, category = "Bills"), categories))
    assertNull(TransactionSelectors.suggestionCategory(suggestion.copy(categoryId = null), categories))
  }

  @Test
  fun merchantSuggestionsPreferPrefix() {
    val items = listOf(
      tx("1", "Cafe Coffee", "Dining", "Today", 1.0),
      tx("2", "Coffee House", "Dining", "Today", 1.0),
      tx("3", "Coffee House", "Dining", "Today", 1.0),
    )
    val suggestions = TransactionSelectors.merchantSuggestions(items, "cof")
    assertEquals("Coffee House", suggestions.first().name)
    assertEquals(2, suggestions.first().count)
  }

  @Test
  fun dateRangeIncludesBothBoundaryDays() {
    val items = listOf(
      tx("9", "Before", "Dining", "", 1.0, occurredAt = stamp(2026, 7, 9, hour = 12)),
      tx("10", "Start", "Dining", "", 1.0, occurredAt = stamp(2026, 7, 10, hour = 0)),
      tx("12", "End", "Dining", "", 1.0, occurredAt = stamp(2026, 7, 12, hour = 23)),
      tx("13", "After", "Dining", "", 1.0, occurredAt = stamp(2026, 7, 13, hour = 12)),
    )

    val filtered = TransactionSelectors.filterTransactions(
      items,
      TransactionFilter(
        startDate = LocalDate.of(2026, 7, 10),
        endDate = LocalDate.of(2026, 7, 12),
      ),
    )

    assertEquals(listOf("10", "12"), filtered.map { it.id })
  }

  @Test
  fun pickerOmitsArchivedUnlessSelected() {
    val categories = listOf(
      CategoryEntity("dining", "Dining", "🍽️", null, CategoryTint.NEUTRAL, 0, false),
      CategoryEntity("travel", "Travel", "✈️", null, CategoryTint.NEUTRAL, 1, false, archived = true),
      CategoryEntity("bills", "Bills", "🧾", null, CategoryTint.NEUTRAL, 2, false),
    )
    assertEquals(
      listOf("Dining", "Bills"),
      TransactionSelectors.pickerCategories(categories, "").map { it.name },
    )
    assertEquals(
      listOf("Dining", "Bills", "Travel"),
      TransactionSelectors.pickerCategories(categories, "Travel").map { it.name },
    )
  }

  @Test
  fun categoryBudgetRowsDropArchivedCategorySpend() {
    val categories = listOf(
      CategoryEntity("dining", "Dining", "🍽️", null, CategoryTint.NEUTRAL, 0, false),
      CategoryEntity("travel", "Travel", "✈️", null, CategoryTint.NEUTRAL, 1, false, archived = true),
    )
    val rows = listOf(
      tx("1", "A", "Dining", "", 10.0).copy(categoryId = "dining"),
      tx("2", "B", "Travel", "", 20.0).copy(categoryId = "travel"),
    )
    assertEquals(
      listOf("1"),
      TransactionSelectors.transactionsForActiveCategories(rows, categories).map { it.id },
    )
  }
}

class SanitizerTests : ZonedTest() {
  @Test
  fun sanitizePreferencesDefaults() {
    val prefs = PreferencesEntity(
      id = "preferences",
      profileName = "A",
      profileEmail = "a@b.com",
      currency = Currency.INR,
      weekStart = WeekStart.MON,
      theme = ThemePreference.LIGHT,
      navGlassOpacity = 10,
      defaultView = ViewKey.STATS,
      defaultStatsRange = StatsRange.ONE_YEAR,
      notifications = NotificationSettings(bills = true, budget = false, weekly = false, large = true),
      defaultPaymentMethodId = "",
    )
    val clean = PayloadSanitizer.sanitize(EntityPayload.Preferences(prefs))
    val value = (clean as EntityPayload.Preferences).value
    assertEquals(40, value.navGlassOpacity)
    assertEquals(ViewKey.HOME, value.defaultView)
    assertEquals(SeedData.CASH_PAYMENT_METHOD.id, value.defaultPaymentMethodId)
  }

  @Test
  fun sanitizeCategoryPreservesArchived() {
    val category = CategoryEntity(
      id = "c1",
      name = "Travel",
      emoji = "",
      monthlyBudgetMinor = null,
      tint = CategoryTint.GREEN,
      sortOrder = 1,
      system = false,
      archived = true,
    )
    val value = (PayloadSanitizer.sanitize(EntityPayload.Category(category)) as EntityPayload.Category).value
    assertTrue(value.archived)
    assertEquals(app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI, value.emoji)
  }

  @Test
  fun sanitizeTransactionAmount() {
    val tx = TransactionEntity(
      id = "t1",
      name = "x",
      amountMinor = 0,
      occurredAt = 0,
      categoryId = "c",
      paymentMethodId = null,
    )
    val clean = PayloadSanitizer.sanitize(EntityPayload.Transaction(tx))
    val value = (clean as EntityPayload.Transaction).value
    assertEquals(1L, value.amountMinor)
    assertTrue(value.occurredAt > 0)
    assertEquals(SeedData.CASH_PAYMENT_METHOD.id, value.paymentMethodId)
  }

  @Test
  fun sanitizeDropsSourceCurrencyFieldsWhenSourceIsAbsent() {
    val tx = TransactionEntity(
      id = "t2",
      name = "x",
      amountMinor = 500,
      occurredAt = 1_000,
      categoryId = "c",
      paymentMethodId = "payment-method-cash",
      currency = "INR",
      sourceCurrency = "  ",
      sourceAmountMinor = 400,
      exchangeRate = 1.2,
    )
    val value = (PayloadSanitizer.sanitize(EntityPayload.Transaction(tx)) as EntityPayload.Transaction).value
    assertEquals("INR", value.currency)
    assertNull(value.sourceCurrency)
    assertNull(value.sourceAmountMinor)
    assertNull(value.exchangeRate)
  }

  @Test
  fun sanitizeRepairsInvalidRecurringAnchorDate() {
    val recurring = app.dimo.android.data.model.RecurringEntity(
      id = "r1",
      name = "Rent",
      amountMinor = 0,
      categoryId = "c",
      paymentMethodId = "",
      frequency = RecurringFrequency.MONTHLY,
      anchorDate = "not-a-date",
      paused = false,
      currency = null,
    )
    val value = (PayloadSanitizer.sanitize(EntityPayload.Recurring(recurring)) as EntityPayload.Recurring).value
    assertEquals(1L, value.amountMinor)
    assertEquals(SeedData.CASH_PAYMENT_METHOD.id, value.paymentMethodId)
    assertTrue(Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(value.anchorDate))
  }

  @Test
  fun sanitizeFallsBackLendContactIdToName() {
    val lend = app.dimo.android.data.model.LendEntity(
      id = "l1",
      contactName = "Aakash",
      contactId = "   ",
      amountMinor = 0,
      occurredAt = 0,
      comment = "",
      kind = null,
    )
    val value = (PayloadSanitizer.sanitize(EntityPayload.Lend(lend)) as EntityPayload.Lend).value
    assertEquals("Aakash", value.contactId)
    assertEquals(1L, value.amountMinor)
    assertEquals(LendKind.LENT, value.kind)
    assertTrue(value.occurredAt > 0)
  }
}

class BudgetSelectorTests : ZonedTest() {
  @Test
  fun budgetOnlyTurnsRedAboveLimit() {
    val now = LocalDate.of(2026, 8, 9)
    for (spent in listOf(90.0, 99.99, 100.0, 100.01)) {
      val rows = listOf(Transaction(id = "a", name = "Item", category = "Dining", time = "", day = "", amount = spent, occurredAt = stamp(2026, 8, 8)))
      assertEquals(spent > 100, BudgetSelectors.categoryBudgets(rows, mapOf("Dining" to 100.0), now).first().over)
      assertEquals(spent > 100, BudgetSelectors.budgetTotals(rows, mapOf("Dining" to 100.0), now).over)
      assertFalse(BudgetSelectors.categoryBudgets(rows, mapOf("Dining" to null), now).first().over)
      assertFalse(BudgetSelectors.budgetTotals(rows, mapOf("Dining" to null), now).over)
    }
  }

  @Test
  fun categoryBudgetsSortByUtilizationThenSpend() {
    fun row(id: String, category: String, amount: Double) = Transaction(
      id = id,
      name = "Item",
      category = category,
      time = "",
      day = "",
      amount = amount,
      occurredAt = stamp(2026, 8, 8),
    )

    val budgets = BudgetSelectors.categoryBudgets(
      transactions = listOf(
        row("rent", "Rent", 1_000.0),
        row("games", "Games", 200.0),
        row("snacks", "Snacks", 100.0),
      ),
      limits = mapOf(
        "Rent" to 2_000.0,
        "Games" to 100.0,
        "Snacks" to 200.0,
      ),
      now = LocalDate.of(2026, 8, 9),
    )

    assertEquals(listOf("Games", "Rent", "Snacks"), budgets.map { it.category })
  }

  @Test
  fun monthlyTotalsIncludeTransactionCount() {
    fun row(id: String, amount: Double, at: Long) = Transaction(
      id = id,
      name = "Item",
      category = "Dining",
      time = "",
      day = "",
      amount = amount,
      occurredAt = at,
    )

    val totals = BudgetSelectors.budgetTotals(
      transactions = listOf(
        row("current-a", 100.0, stamp(2026, 8, 2)),
        row("current-b", 200.0, stamp(2026, 8, 8)),
        row("previous", 900.0, stamp(2026, 7, 31)),
      ),
      limits = mapOf("Dining" to 1_000.0),
      now = LocalDate.of(2026, 8, 9),
    )

    assertEquals(2, totals.transactionCount)
    assertEquals(300.0, totals.totalSpent, 0.0001)
  }

  @Test
  fun suggestedBudgetsFromLookback() {
    val now = LocalDate.of(2026, 7, 11)
    val nowMillis = stamp(2026, 7, 11)

    fun row(id: String, category: String, categoryId: String, amount: Double, at: Long) = Transaction(
      id = id,
      name = "Item",
      category = category,
      time = "",
      day = "",
      amount = amount,
      occurredAt = at,
      categoryId = categoryId,
    )

    val rows = listOf(
      row("a", "Dining", "dining", 300.0, stamp(2026, 7, 2)),
      row("b", "Dining", "dining", 900.0, stamp(2026, 2, 10)),
      row("c", "Dining", "dining", 50.0, stamp(2025, 12, 20)),
      row("d", "Other", "other", 999.0, stamp(2026, 7, 2)),
    )
    val lookback = BudgetSelectors.categoryLookbackSpend(
      rows,
      categoryId = "dining",
      monthCount = 6,
      now = now,
      nowMillis = nowMillis,
    )
    assertEquals(1200.0, lookback.total, 0.0001)
    assertEquals(200.0, lookback.monthlyAverage, 0.0001)

    val suggestionRows = listOf(
      row("a", "Dining", "dining", 300.0, stamp(2026, 7, 2)),
      row("b", "Dining", "dining", 900.0, stamp(2026, 2, 10)),
      row("c", "Bills", "bills", 600.0, stamp(2026, 7, 2)),
    )
    val suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
      suggestionRows,
      categories = listOf(
        BudgetCategoryInput("dining", "Dining", null),
        BudgetCategoryInput("bills", "Bills", 50_000),
        BudgetCategoryInput("empty", "Groceries", null),
      ),
      monthCount = 6,
      now = now,
      nowMillis = nowMillis,
    )
    assertEquals(
      listOf(
        SuggestedCategoryBudgetUpdate("dining", "Dining", 200.0, null),
        SuggestedCategoryBudgetUpdate("bills", "Bills", 100.0, 500.0),
      ),
      suggestions,
    )
  }

  @Test
  fun dailyBudgetAllowanceIncludesTodayAndHidesWhenOverBudget() {
    val totals = BudgetTotals(
      totalSpent = 700.0,
      totalLimit = 1_000.0,
      pct = 70,
      left = 300.0,
      over = false,
      transactionCount = 4,
    )

    assertEquals(
      DailyBudgetAllowance(amount = 17.5, daysRemaining = 10),
      BudgetSelectors.dailyBudgetAllowance(totals, LocalDate.of(2026, 8, 22), upcomingTotal = 125.0),
    )
    for (upcoming in listOf(300.0, 400.0)) {
      assertEquals(
        DailyBudgetAllowance(amount = 0.0, daysRemaining = 10),
        BudgetSelectors.dailyBudgetAllowance(totals, LocalDate.of(2026, 8, 22), upcomingTotal = upcoming),
      )
    }
    assertEquals(
      DailyBudgetAllowance(amount = 30.0, daysRemaining = 10),
      BudgetSelectors.dailyBudgetAllowance(totals, LocalDate.of(2026, 8, 22)),
    )
    assertEquals(
      0.0,
      BudgetSelectors.dailyBudgetAllowance(
        totals.copy(totalSpent = 1_000.0, left = 0.0),
        LocalDate.of(2026, 8, 31),
      )!!.amount,
      0.0001,
    )
    assertNull(
      BudgetSelectors.dailyBudgetAllowance(
        totals.copy(totalSpent = 1_001.0, left = -1.0),
        LocalDate.of(2026, 8, 22),
      ),
    )
    assertNull(
      BudgetSelectors.dailyBudgetAllowance(
        totals.copy(totalSpent = 0.0, totalLimit = 0.0, left = 0.0),
        LocalDate.of(2026, 8, 22),
      ),
    )
  }

  @Test
  fun globalBudgetUsesSixCompletedMonthsAndStableCategoryIds() {
    fun row(id: String, categoryId: String, amount: Double, at: Long, name: String) = Transaction(
      id = id,
      name = "Item",
      category = name,
      time = "",
      day = "",
      amount = amount,
      occurredAt = at,
      categoryId = categoryId,
    )
    val categories = listOf(
      GlobalBudgetCategoryInput("dining", "Dining", 0, null),
      GlobalBudgetCategoryInput("bills", "Bills", 1, 50_000),
      GlobalBudgetCategoryInput("empty", "Groceries", 2, 20_000),
    )
    val result = BudgetSelectors.globalBudgetAllocation(
      transactions = listOf(
        row("start", "dining", 200.0, stamp(2026, 2, 1), "Old dining name"),
        row("end", "dining", 200.0, stamp(2026, 7, 31), "Dining"),
        row("bills", "bills", 200.0, stamp(2026, 7, 1), "Bills"),
        row("previous", "dining", 9_999.0, stamp(2026, 1, 31), "Dining"),
        row("current", "dining", 9_999.0, stamp(2026, 8, 1), "Dining"),
      ),
      categories = categories,
      totalBudget = 100,
      now = LocalDate.of(2026, 8, 10),
    )

    assertEquals(DateHelpers.startOfDayMillis(LocalDate.of(2026, 2, 1)), result.window.start)
    assertEquals(DateHelpers.startOfDayMillis(LocalDate.of(2026, 8, 1)), result.window.end)
    assertEquals(600.0, result.sixMonthSpend, 0.0001)
    assertEquals(100, result.totalAllocated)
    assertEquals(listOf(67L, 33L, null), result.allocations.map { it.allocatedLimit })
    assertEquals(listOf(67, 33, 0), result.allocations.map { it.share })
  }

  @Test
  fun globalBudgetRoundingTiesAreDeterministicAndZeroHistoryIsNull() {
    fun row(id: String) = Transaction(
      id = id,
      name = "Item",
      category = id,
      time = "",
      day = "",
      amount = 1.0,
      occurredAt = stamp(2026, 7, 1),
      categoryId = id,
    )
    val result = BudgetSelectors.globalBudgetAllocation(
      transactions = listOf(row("a"), row("b"), row("c")),
      categories = listOf(
        GlobalBudgetCategoryInput("b", "B", 1, null),
        GlobalBudgetCategoryInput("a", "A", 1, null),
        GlobalBudgetCategoryInput("c", "C", 0, null),
        GlobalBudgetCategoryInput("empty", "Empty", 2, 100),
      ),
      totalBudget = 2,
      now = LocalDate.of(2026, 8, 10),
    )
    val byId = result.allocations.associate { it.id to it.allocatedLimit }
    assertEquals(1L, byId["a"])
    assertEquals(0L, byId["b"])
    assertEquals(1L, byId["c"])
    assertNull(byId["empty"])
  }

  @Test
  fun globalBudgetRejectsUnavailableInputsAndHandlesLeapYearBoundary() {
    val now = LocalDate.of(2024, 3, 15)
    val categories = listOf(GlobalBudgetCategoryInput("dining", "Dining", 0, null))
    val leap = Transaction(
      id = "leap",
      name = "Item",
      category = "Dining",
      time = "",
      day = "",
      amount = 290.0,
      occurredAt = stamp(2024, 2, 29),
      categoryId = "dining",
    )
    val valid = BudgetSelectors.globalBudgetAllocation(
      listOf(leap), categories, 290, now = now,
    )

    assertEquals(DateHelpers.startOfDayMillis(LocalDate.of(2023, 9, 1)), valid.window.start)
    assertEquals(290L, valid.allocations.first().allocatedLimit)
    assertEquals(
      GlobalBudgetAllocationIssue.INVALID_TOTAL,
      BudgetSelectors.globalBudgetAllocation(listOf(leap), categories, 0, now = now).issue,
    )
    assertEquals(
      GlobalBudgetAllocationIssue.NO_HISTORY,
      BudgetSelectors.globalBudgetAllocation(emptyList(), categories, 100, now = now).issue,
    )
    assertEquals(
      GlobalBudgetAllocationIssue.NO_CATEGORIES,
      BudgetSelectors.globalBudgetAllocation(emptyList(), emptyList(), 100, now = now).issue,
    )
  }
}

class LendSelectorsTests {
  private fun lend(
    id: String,
    name: String,
    contactId: String,
    amount: Double,
    kind: LendKind = LendKind.LENT,
    occurredAt: Long = 1_000,
  ) = LendModel(
    id = id,
    contactName = name,
    contactId = contactId,
    amount = amount,
    comment = "",
    time = "",
    day = "",
    amountMinor = (amount * 100).toLong(),
    occurredAt = occurredAt,
    kind = kind,
  )

  @Test
  fun paginationKeepsWholeDaysTogether() {
    // 50 on one day, then three more on the next: the page must not split day 2.
    val page1 = (1..50).map { lend("a$it", "Aakash", "cn-a", 10.0).copy(day = "Mon") }
    val page2 = (1..3).map { lend("b$it", "Aakash", "cn-a", 10.0).copy(day = "Sun") }

    val (items, hasMore) = LendSelectors.paginateByDay(
      page1 + page2,
      LendSelectors.historyPageSize,
    )

    assertEquals(50, items.size)
    assertTrue(hasMore)
  }

  @Test
  fun paginationExtendsPastTheLimitToFinishADay() {
    val sameDay = (1..53).map { lend("a$it", "Aakash", "cn-a", 10.0).copy(day = "Mon") }

    val (items, hasMore) = LendSelectors.paginateByDay(sameDay, LendSelectors.historyPageSize)

    assertEquals(53, items.size)
    assertFalse(hasMore)
  }

  @Test
  fun paginationReportsNoMoreWhenEverythingFits() {
    val lends = (1..5).map { lend("a$it", "Aakash", "cn-a", 10.0).copy(day = "Mon") }

    val (items, hasMore) = LendSelectors.paginateByDay(lends, LendSelectors.historyPageSize)

    assertEquals(5, items.size)
    assertFalse(hasMore)
  }

  @Test
  fun summariesSplitSameNameByContactId() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Aakash", "cn-a", 100.0),
        lend("2", "Aakash", "cn-b", 50.0),
      ),
    )
    assertEquals(2, summaries.size)
    assertEquals(100.0, summaries[0].total, 0.0001)
    assertEquals("cn-a", summaries[0].contactId)
    assertEquals(50.0, summaries[1].total, 0.0001)
    assertEquals("cn-b", summaries[1].contactId)
  }

  @Test
  fun sameContactMergesAcrossNameCasing() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "aakash", "cn-a", 100.0, occurredAt = 1_000),
        lend("2", "Aakash", "cn-a", 50.0, occurredAt = 2_000),
        lend("3", "Aakash", "cn-a", 30.0, LendKind.REPAID, occurredAt = 3_000),
      ),
    )
    assertEquals(1, summaries.size)
    assertEquals("cn-a", summaries[0].contactId)
    assertEquals("Aakash", summaries[0].contactName)
    assertEquals(120.0, summaries[0].total, 0.0001)
    assertEquals(3, summaries[0].count)
  }

  @Test
  fun recentContactsDedupesPerPersonNewestFirst() {
    val suggestions = LendSelectors.recentContacts(
      listOf(
        lend("1", "Ravi", "cn-r", 10.0, occurredAt = 1_000),
        lend("2", "Aakash", "cn-a", 10.0, occurredAt = 4_000),
        lend("3", "aakash", "cn-a", 10.0, LendKind.REPAID, occurredAt = 2_000),
        lend("4", "Aakash", "cn-b", 10.0, occurredAt = 3_000),
      ),
    )
    assertEquals(
      listOf(
        LendContactSuggestion("Aakash", "cn-a"),
        LendContactSuggestion("Aakash", "cn-b"),
        LendContactSuggestion("Ravi", "cn-r"),
      ),
      suggestions,
    )
  }

  @Test
  fun recentContactsHonorsLimit() {
    val lends = (1..8).map { i ->
      lend("$i", "Person $i", "cn-$i", 10.0, occurredAt = i * 1_000L)
    }
    assertEquals(6, LendSelectors.recentContacts(lends).size)
    assertEquals("Person 8", LendSelectors.recentContacts(lends).first().contactName)
  }

  @Test
  fun repaymentsWithIdOnlyReduceThatContact() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Aakash", "cn-a", 100.0),
        lend("2", "Aakash", "cn-b", 100.0),
        lend("3", "Aakash", "cn-a", 100.0, LendKind.REPAID),
      ),
    )
    assertEquals(1, summaries.size)
    assertEquals("cn-b", summaries[0].contactId)
    assertEquals(100.0, summaries[0].total, 0.0001)
  }

  @Test
  fun outstandingAmountExcludesRepaymentBeingEdited() {
    val lends = listOf(
      lend("lend", "Aakash", "cn-a", 100.0),
      lend("repaid", "Aakash", "cn-a", 30.0, LendKind.REPAID),
    )

    assertEquals(70.0, LendSelectors.outstandingAmount("cn-a", lends), 0.0001)
    assertEquals(
      100.0,
      LendSelectors.outstandingAmount("cn-a", lends, excludingLendId = "repaid"),
      0.0001,
    )
  }

  @Test
  fun unsettledTransactionsStartAfterMostRecentSettlement() {
    val lends = listOf(
      lend("old-lend", "Aakash", "cn-a", 100.0, occurredAt = 1_000),
      lend("old-repayment", "Aakash", "cn-a", 100.0, LendKind.REPAID, occurredAt = 2_000),
      lend("current-lend", "Aakash", "cn-a", 70.0, occurredAt = 3_000),
      lend("partial-repayment", "Aakash", "cn-a", 20.0, LendKind.REPAID, occurredAt = 4_000),
      lend("other-contact", "Ravi", "cn-r", 25.0, occurredAt = 5_000),
    )

    assertEquals(
      listOf("current-lend", "partial-repayment"),
      LendSelectors.unsettledTransactions("cn-a", lends).map { it.id },
    )
    assertNotNull(LendSelectors.unsettledTransactions("cn-r", lends))
  }

  @Test
  fun borrowingNetsNegativeAndStaysInSummaries() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Anil", "cn-n", 100.0, LendKind.BORROWED),
        lend("2", "Anil", "cn-n", 40.0, LendKind.RETURNED),
      ),
    )

    assertEquals(1, summaries.size)
    assertEquals(-60.0, summaries[0].total, 0.0001)
    assertEquals(60.0, summaries[0].magnitude, 0.0001)
    assertEquals(LendDirection.I_OWE, summaries[0].direction)
  }

  @Test
  fun summariesOmitContactsThatNetToZeroInEitherDirection() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Anil", "cn-n", 100.0, LendKind.BORROWED),
        lend("2", "Anil", "cn-n", 100.0, LendKind.RETURNED),
        lend("3", "Ravi", "cn-r", 50.0),
        lend("4", "Ravi", "cn-r", 50.0, LendKind.REPAID),
      ),
    )

    assertTrue(summaries.isEmpty())
  }

  @Test
  fun summariesSortByBalanceSizeRegardlessOfDirection() {
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Ravi", "cn-r", 20.0),
        lend("2", "Anil", "cn-n", 90.0, LendKind.BORROWED),
        lend("3", "Priya", "cn-p", 50.0),
      ),
    )

    assertEquals(listOf("cn-n", "cn-p", "cn-r"), summaries.map { it.contactId })
  }

  @Test
  fun settlementLimitCapsEachDirectionAndLeavesOpeningEntriesFree() {
    val lends = listOf(
      lend("lent", "Ravi", "cn-r", 100.0),
      lend("borrowed", "Anil", "cn-n", 80.0, LendKind.BORROWED),
    )

    assertEquals(
      100.0,
      LendSelectors.settlementLimit(LendKind.REPAID, "cn-r", lends)!!,
      0.0001,
    )
    assertEquals(
      80.0,
      LendSelectors.settlementLimit(LendKind.RETURNED, "cn-n", lends)!!,
      0.0001,
    )
    // A contact who owes the user cannot be paid back, and vice versa.
    assertEquals(
      0.0,
      LendSelectors.settlementLimit(LendKind.RETURNED, "cn-r", lends)!!,
      0.0001,
    )
    assertEquals(
      0.0,
      LendSelectors.settlementLimit(LendKind.REPAID, "cn-n", lends)!!,
      0.0001,
    )
    assertNull(LendSelectors.settlementLimit(LendKind.LENT, "cn-r", lends))
    assertNull(LendSelectors.settlementLimit(LendKind.BORROWED, "cn-n", lends))
  }

  @Test
  fun borrowedBalanceExcludesThePaymentBeingEdited() {
    val lends = listOf(
      lend("borrowed", "Anil", "cn-n", 100.0, LendKind.BORROWED),
      lend("returned", "Anil", "cn-n", 30.0, LendKind.RETURNED),
    )

    assertEquals(-70.0, LendSelectors.netBalance("cn-n", lends), 0.0001)
    assertEquals(70.0, LendSelectors.borrowedBalance("cn-n", lends), 0.0001)
    assertEquals(
      100.0,
      LendSelectors.borrowedBalance("cn-n", lends, excludingLendId = "returned"),
      0.0001,
    )
  }

  @Test
  fun totalsNetPerContactSoOneContactLandsOnOneSide() {
    // Lent 100 and borrowed 30 from the same person: 70 owed to the user, and
    // nothing on the other side.
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("1", "Ravi", "cn-r", 100.0),
        lend("2", "Ravi", "cn-r", 30.0, LendKind.BORROWED),
        lend("3", "Anil", "cn-n", 45.0, LendKind.BORROWED),
      ),
    )

    assertEquals(LendTotals(owedToMe = 70.0, iOwe = 45.0), LendSelectors.totals(summaries))
    assertEquals(25.0, LendSelectors.totals(summaries).net, 0.0001)
  }

  @Test
  fun unsettledTransactionsRestartAfterABorrowingIsCleared() {
    val lends = listOf(
      lend("old-borrow", "Anil", "cn-n", 100.0, LendKind.BORROWED, occurredAt = 1_000),
      lend("old-payment", "Anil", "cn-n", 100.0, LendKind.RETURNED, occurredAt = 2_000),
      lend("current-borrow", "Anil", "cn-n", 60.0, LendKind.BORROWED, occurredAt = 3_000),
      lend("partial-payment", "Anil", "cn-n", 25.0, LendKind.RETURNED, occurredAt = 4_000),
    )

    assertEquals(
      listOf("current-borrow", "partial-payment"),
      LendSelectors.unsettledTransactions("cn-n", lends).map { it.id },
    )
  }

  @Test
  fun signedAmountDirectionPerKind() {
    assertEquals(10.0, lend("1", "R", "c", 10.0, LendKind.LENT).signedAmount, 0.0001)
    assertEquals(-10.0, lend("2", "R", "c", 10.0, LendKind.REPAID).signedAmount, 0.0001)
    assertEquals(-10.0, lend("3", "R", "c", 10.0, LendKind.BORROWED).signedAmount, 0.0001)
    assertEquals(10.0, lend("4", "R", "c", 10.0, LendKind.RETURNED).signedAmount, 0.0001)

    assertFalse(lend("1", "R", "c", 10.0, LendKind.LENT).isIncoming)
    assertTrue(lend("2", "R", "c", 10.0, LendKind.REPAID).isIncoming)
    assertTrue(lend("3", "R", "c", 10.0, LendKind.BORROWED).isIncoming)
    assertFalse(lend("4", "R", "c", 10.0, LendKind.RETURNED).isIncoming)
  }
}

class ExpenseReminderTests {
  @Test
  fun copyWithoutPendingPurchases() {
    assertEquals("Log today's expenses", ExpenseReminderCopy.title(0))
    assertEquals(
      "Take a moment to add anything you spent today.",
      ExpenseReminderCopy.body(0),
    )
  }

  @Test
  fun copyWithPendingPurchasesUsesSingularAndPlural() {
    assertEquals("Expenses and reviews waiting", ExpenseReminderCopy.title(1))
    assertEquals(
      "Take a moment to add anything you spent today. You also have 1 purchase waiting for review.",
      ExpenseReminderCopy.body(1),
    )
    assertEquals(
      "Take a moment to add anything you spent today. You also have 3 purchases waiting for review.",
      ExpenseReminderCopy.body(3),
    )
  }

  @Test
  fun settingsClampHourAndMinute() {
    val settings = ExpenseReminderSettings(enabled = true, hour = 30, minute = 99).clamped
    assertEquals(23, settings.hour)
    assertEquals(59, settings.minute)
  }
}
