package app.dimo.android.domain

import app.dimo.android.data.model.Lend
import kotlin.math.abs

/** Port of `ios-native/Dimo/Domain/LendSelectors.swift`. */

data class LendContactSummary(
  val contactName: String,
  /** Address-book identifier of the contact this group belongs to. */
  val contactId: String,
  /**
   * Net outstanding (lent minus repaid). Only contacts with a positive balance
   * appear in the summary list.
   */
  val total: Double,
  val count: Int,
  val lastOccurredAt: Long,
) {
  val id: String get() = contactId
}

data class LendDayGroup(
  val label: String,
  val total: Double,
  val items: List<Lend>,
)

data class LendContactSuggestion(
  val contactName: String,
  val contactId: String,
) {
  val id: String get() = contactId
}

object LendSelectors {
  /** Net amount still out: money lent minus money got back. */
  fun totalLent(lends: List<Lend>): Double = lends.sumOf { it.signedAmount }

  /**
   * Amount that can still be recorded as repaid for a contact. When editing a
   * repayment, exclude it so its current amount remains eligible.
   */
  fun outstandingAmount(
    contactId: String,
    lends: List<Lend>,
    excludingLendId: String? = null,
  ): Double = maxOf(
    0.0,
    lends.sumOf { lend ->
      if (lend.contactId == contactId && lend.id != excludingLendId) lend.signedAmount else 0.0
    },
  )

  /**
   * Chronological transactions in the contact's current unsettled cycle. Entries
   * before the most recent zero balance belong to an earlier, completed settlement
   * and are omitted.
   */
  fun unsettledTransactions(contactId: String, lends: List<Lend>): List<Lend> {
    val contactLends = lends
      .filter { it.contactId == contactId }
      .sortedWith(compareBy({ it.occurredAt }, { it.id }))

    var balance = 0.0
    var unsettledStartIndex = 0
    contactLends.forEachIndexed { index, lend ->
      balance += lend.signedAmount
      if (abs(balance) < 0.0001) {
        unsettledStartIndex = index + 1
      }
    }
    return contactLends.drop(unsettledStartIndex)
  }

  /**
   * Groups lends per person by address-book identifier, keeping the name casing of
   * the most recent entry, sorted by highest outstanding total; settled contacts
   * are omitted.
   */
  fun contactSummaries(lends: List<Lend>): List<LendContactSummary> {
    val byContact = linkedMapOf<String, LendContactSummary>()
    for (lend in lends.sortedByDescending { it.occurredAt }) {
      val existing = byContact[lend.contactId]
      byContact[lend.contactId] = if (existing != null) {
        existing.copy(
          total = existing.total + lend.signedAmount,
          count = existing.count + 1,
          lastOccurredAt = maxOf(existing.lastOccurredAt, lend.occurredAt),
        )
      } else {
        LendContactSummary(
          contactName = lend.contactName,
          contactId = lend.contactId,
          total = lend.signedAmount,
          count = 1,
          lastOccurredAt = lend.occurredAt,
        )
      }
    }
    return byContact.values
      .filter { it.total > 0.0001 }
      .sortedWith(compareByDescending<LendContactSummary> { it.total }.thenBy { it.contactName })
  }

  /**
   * Most recently used contacts across lend history, deduped per person, for the
   * suggestion chips on the add-lend sheet.
   */
  fun recentContacts(lends: List<Lend>, limit: Int = 6): List<LendContactSuggestion> {
    val seen = mutableSetOf<String>()
    val result = mutableListOf<LendContactSuggestion>()
    for (lend in lends.sortedByDescending { it.occurredAt }) {
      if (!seen.add(lend.contactId)) continue
      result.add(LendContactSuggestion(lend.contactName, lend.contactId))
      if (result.size == limit) break
    }
    return result
  }

  /** Groups lends by their day label, preserving newest-first order. */
  fun groupByDay(lends: List<Lend>): List<LendDayGroup> {
    val order = mutableListOf<String>()
    val byDay = mutableMapOf<String, MutableList<Lend>>()
    for (lend in lends) {
      if (byDay[lend.day] == null) {
        byDay[lend.day] = mutableListOf()
        order.add(lend.day)
      }
      byDay.getValue(lend.day).add(lend)
    }
    return order.map { day ->
      val items = byDay[day].orEmpty()
      LendDayGroup(label = day, total = items.sumOf { it.signedAmount }, items = items)
    }
  }
}
