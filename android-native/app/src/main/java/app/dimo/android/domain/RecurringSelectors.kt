package app.dimo.android.domain

import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.store.UiRecurring
import java.time.LocalDate
import java.time.ZoneId

object RecurringSelectors {
  private val zone = ZoneId.systemDefault()

  fun activeRecurring(items: List<UiRecurring>): List<UiRecurring> = items.filter { !it.paused }

  fun monthlyRecurringTotal(items: List<UiRecurring>): Double =
    activeRecurring(items).sumOf {
      if (it.frequency == RecurringFrequency.yearly) it.amount / 12.0 else it.amount
    }

  fun upcomingBills(
    items: List<UiRecurring>,
    limit: Int? = null,
    now: LocalDate = LocalDate.now(zone),
  ): List<UiRecurring> {
    val month = now.monthValue
    val year = now.year
    val upcoming = activeRecurring(items)
      .map { it to DateHelpers.nextOccurrence(it.anchorDate, it.frequency, now) }
      .filter { (_, due) -> due.year == year && due.monthValue == month }
      .sortedBy { it.second }
      .map { it.first }
    return if (limit == null) upcoming else upcoming.take(limit)
  }

  fun allUpcomingBills(items: List<UiRecurring>, now: LocalDate = LocalDate.now(zone)): List<UiRecurring> =
    items.map { it to DateHelpers.nextOccurrence(it.anchorDate, it.frequency, now) }
      .sortedBy { it.second }
      .map { it.first }

  fun recurringSubtitle(item: UiRecurring, now: LocalDate = LocalDate.now(zone)): String {
    val due = DateHelpers.nextOccurrence(item.anchorDate, item.frequency, now)
    val status = if (item.paused) "Paused" else DateHelpers.recurringDueLabel(due, now)
    return "${item.category} · $status"
  }
}
