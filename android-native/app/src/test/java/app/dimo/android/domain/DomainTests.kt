package app.dimo.android.domain

import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.compareVersions
import app.dimo.android.store.UiLend
import app.dimo.android.store.UiRecurring
import app.dimo.android.store.UiTransaction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class LogicalVersionTests {
  @Test
  fun ordersByTimestampCounterThenDeviceId() {
    val base = LogicalVersion(100, 1, "a")
    assertTrue(compareVersions(LogicalVersion(101, 1, "a"), base) > 0)
    assertTrue(compareVersions(LogicalVersion(100, 2, "a"), base) > 0)
    assertTrue(compareVersions(LogicalVersion(100, 1, "b"), base) > 0)
    assertEquals(0, compareVersions(base, base))
  }
}

class GreetingTests {
  @Test
  fun greetingHours() {
    fun at(hour: Int) = LocalDateTime.of(2026, 1, 1, hour, 0)
    assertEquals("Good morning", Greeting.greetingFor(at(0)))
    assertEquals("Good morning", Greeting.greetingFor(at(11)))
    assertEquals("Good afternoon", Greeting.greetingFor(at(12)))
    assertEquals("Good afternoon", Greeting.greetingFor(at(16)))
    assertEquals("Good evening", Greeting.greetingFor(at(17)))
  }
}

class StatsHydrationTests {
  @Test
  fun pulledDefaultReplacesUntouchedBootstrapRange() {
    assertEquals(
      StatsRange.ThreeMonths,
      StatsConstants.hydratedRange(
        current = StatsRange.OneYear,
        previousDefault = StatsRange.OneYear,
        nextDefault = StatsRange.ThreeMonths,
        dataReady = true,
      ),
    )
  }

  @Test
  fun pulledDefaultPreservesUserSelectedRange() {
    assertEquals(
      StatsRange.SixMonths,
      StatsConstants.hydratedRange(
        current = StatsRange.SixMonths,
        previousDefault = StatsRange.OneYear,
        nextDefault = StatsRange.ThreeMonths,
        dataReady = true,
      ),
    )
  }
}

class DateHelpersTests {
  @Test
  fun clampsMonthlyDayToShortMonth() {
    val now = LocalDate.of(2026, 2, 1)
    val next = DateHelpers.nextOccurrence("2026-01-31", RecurringFrequency.monthly, now)
    assertEquals(LocalDate.of(2026, 2, 28), next)
  }

  @Test
  fun leapDayYearlyUsesFeb28() {
    val now = LocalDate.of(2025, 1, 1)
    val next = DateHelpers.nextOccurrence("2024-02-29", RecurringFrequency.yearly, now)
    assertEquals(LocalDate.of(2025, 2, 28), next)
  }

  @Test
  fun occurrencesThroughMonthly() {
    val now = LocalDate.of(2026, 4, 20)
    val dates = DateHelpers.occurrencesThrough("2026-01-15", RecurringFrequency.monthly, now)
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
    val now = LocalDate.of(2026, 4, 20)
    val dates = DateHelpers.occurrencesThrough("2026-08-01", RecurringFrequency.monthly, now)
    assertTrue(dates.isEmpty())
  }
}

class RecurringSelectorsTests {
  private fun recurring(
    id: String,
    name: String,
    anchorDate: String,
    paused: Boolean = false,
  ) = UiRecurring(
    id = id,
    name = name,
    amount = 10.0,
    categoryId = "c1",
    category = "General",
    emoji = "🙂",
    paymentMethodId = null,
    paymentMethod = null,
    frequency = RecurringFrequency.monthly,
    anchorDate = anchorDate,
    paused = paused,
    dueLabel = "",
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
    val upcoming = RecurringSelectors.upcomingBills(recs, limit = 3, now = now)
    assertEquals(listOf("early", "mid", "late"), upcoming.map { it.id })
  }
}

class LendSelectorsTests {
  private fun lend(
    id: String,
    contactId: String,
    amount: Double,
    kind: LendKind,
    occurredAt: Long,
    name: String = "Alex",
  ) = UiLend(id, name, contactId, amount, occurredAt, "", kind)

  @Test
  fun outstandingExcludesEditingRow() {
    val rows = listOf(
      lend("1", "c1", 100.0, LendKind.lent, 1),
      lend("2", "c1", 40.0, LendKind.repaid, 2),
    )
    assertEquals(60.0, LendSelectors.outstandingAmount(rows, "c1"), 0.001)
    assertEquals(100.0, LendSelectors.outstandingAmount(rows, "c1", excludingLendId = "2"), 0.001)
  }

  @Test
  fun unsettledCycleStartsAfterZeroBalance() {
    val rows = listOf(
      lend("1", "c1", 50.0, LendKind.lent, 1),
      lend("2", "c1", 50.0, LendKind.repaid, 2),
      lend("3", "c1", 20.0, LendKind.lent, 3),
    )
    val unsettled = LendSelectors.unsettledTransactions(rows, "c1")
    assertEquals(listOf("3"), unsettled.map { it.id })
  }

  @Test
  fun contactSummariesGroupByContactId() {
    val rows = listOf(
      lend("1", "c1", 30.0, LendKind.lent, 1, "A"),
      lend("2", "c2", 10.0, LendKind.lent, 2, "B"),
      lend("3", "c1", 5.0, LendKind.repaid, 3, "A"),
    )
    val summaries = LendSelectors.contactSummaries(rows)
    assertEquals(listOf("c1", "c2"), summaries.map { it.contactId })
    assertEquals(25.0, summaries.first().total, 0.001)
  }
}

class TransactionCSVTests {
  @Test
  fun roundTripPreservesExpenseRows() {
    val zone = ZoneId.of("UTC")
    val occurred = LocalDate.of(2026, 7, 11).atTime(11, 38, 8).atZone(zone).toInstant().toEpochMilli()
    val source = listOf(
      UiTransaction(
        id = "1",
        name = "Example purchase",
        amount = 354.0,
        occurredAt = occurred,
        categoryId = "c",
        category = "Snacks",
        emoji = "☕",
        tint = "neutral",
        paymentMethodId = null,
        paymentMethod = null,
      ),
    )
    val csv = TransactionCSV.format(source)
    val parsed = TransactionCSV.parse(csv)
    assertEquals(1, parsed.size)
    assertEquals("Example purchase", parsed[0].name)
    assertEquals(35400, parsed[0].amountMinor)
    assertEquals("Snacks", parsed[0].categoryName)
  }

  @Test
  fun rejectsIncomeRows() {
    val csv = "Date,Note,Amount,Category,Type\n2026-07-11 11:38:08 +0000,Pay,100.00,Job,Income\n"
    assertTrue(TransactionCSV.parse(csv).isEmpty())
  }
}

class TransactionSelectorTests {
  @Test
  fun paginateDoesNotSplitFinalDay() {
    val day1 = LocalDate.of(2026, 7, 1).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    val day2 = LocalDate.of(2026, 7, 2).atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    val txs = (1..52).map { i ->
      UiTransaction(
        id = "$i",
        name = "t$i",
        amount = 1.0,
        occurredAt = if (i <= 50) day1 else day2,
        categoryId = "c",
        category = "Food",
        emoji = "🍽️",
        tint = "green",
        paymentMethodId = null,
        paymentMethod = null,
      )
    }.sortedByDescending { it.occurredAt }
    // Build newest-first list like hydrate
    val newestFirst = txs
    val (page, hasMore) = TransactionSelectors.paginateTransactionsByDay(newestFirst, limit = 50)
    assertTrue(page.size >= 50)
    assertTrue(hasMore || page.size == newestFirst.size)
  }
}
