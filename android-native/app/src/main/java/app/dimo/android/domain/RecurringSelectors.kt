package app.dimo.android.domain

import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.Transaction
import java.time.LocalDate

/** Port of `ios-native/Dimo/Domain/RecurringSelectors.swift`. */
object RecurringSelectors {
  fun activeRecurring(recs: List<Recurring>): List<Recurring> = recs.filter { !it.paused }

  /**
   * Sum active bills in a single currency. Foreign-currency callers provide
   * [amountOf] to convert each bill before it is added to the total.
   */
  fun monthlyRecurringTotal(
    recs: List<Recurring>,
    amountOf: (Recurring) -> Double = { it.amount },
  ): Double = activeRecurring(recs).sumOf { r ->
    val amount = amountOf(r)
    if (r.frequency == RecurringFrequency.YEARLY) amount / 12 else amount
  }

  /**
   * The bill's next due date that hasn't already been charged. The backend cron
   * materializes each occurrence as a transaction keyed `recurring:<id>:<dateKey>`
   * on its due day, so an occurrence whose transaction already exists is skipped —
   * otherwise a bill charged today would linger in "upcoming" until day's end.
   */
  private fun nextDueUnrecorded(
    rec: Recurring,
    anchor: String,
    frequency: RecurringFrequency,
    recordedIDs: Set<String>,
    now: LocalDate,
  ): LocalDate {
    var due = DateHelpers.nextOccurrence(anchor, frequency, now)
    repeat(24) {
      val key = DateHelpers.localDateKey(due)
      if (!recordedIDs.contains("recurring:${rec.id}:$key")) return due
      // Advance past the recorded occurrence to the following one.
      due = DateHelpers.nextOccurrence(anchor, frequency, due.plusDays(1))
    }
    return due
  }

  private fun withNextDue(
    recs: List<Recurring>,
    transactions: List<Transaction>,
    now: LocalDate,
    includePaused: Boolean = false,
  ): List<Pair<Recurring, LocalDate>> {
    val recordedIDs = transactions.map { it.id }.toSet()
    return (if (includePaused) recs else activeRecurring(recs))
      .mapNotNull { rec ->
        val anchor = rec.anchorDate ?: return@mapNotNull null
        val frequency = rec.frequency ?: return@mapNotNull null
        rec to nextDueUnrecorded(rec, anchor, frequency, recordedIDs, now)
      }
      .sortedBy { it.second }
  }

  fun upcomingBills(
    recs: List<Recurring>,
    transactions: List<Transaction>,
    limit: Int? = null,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): List<Recurring> {
    val dueThisMonth = withNextDue(recs, transactions, now)
      .filter { (_, due) -> due.year == now.year && due.monthValue == now.monthValue }
      .map { it.first }
    return if (limit == null) dueThisMonth else dueThisMonth.take(limit)
  }

  /** All bills, including paused bills, sorted by next unpaid due date (any month). */
  fun allUpcomingBills(
    recs: List<Recurring>,
    transactions: List<Transaction>,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): List<Recurring> =
    withNextDue(recs, transactions, now, includePaused = true).map { it.first }

  fun recurringSubtitle(rec: Recurring): String {
    val prefix = if (rec.category.isEmpty()) "" else "${rec.category} · "
    return prefix + (if (rec.paused) "Paused" else rec.due)
  }
}
