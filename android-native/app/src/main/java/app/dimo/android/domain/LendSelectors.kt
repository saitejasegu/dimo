package app.dimo.android.domain

import app.dimo.android.data.model.Lend
import app.dimo.android.data.model.LendKind
import kotlin.math.abs

/** Port of `ios-native/Dimo/Domain/LendSelectors.swift`. */

/** Which way an unsettled balance runs. */
enum class LendDirection {
  /** The contact still owes the user money. */
  OWED_TO_ME,
  /** The user still owes the contact money. */
  I_OWE;

  /** The entry kind that settles a balance running this way. */
  val settlementKind: LendKind
    get() = when (this) {
      OWED_TO_ME -> LendKind.REPAID
      I_OWE -> LendKind.RETURNED
    }
}

data class LendContactSummary(
  val contactName: String,
  /** Address-book identifier of the contact this group belongs to. */
  val contactId: String,
  /**
   * Signed net balance: positive when the contact owes the user, negative when
   * the user owes the contact. Only contacts with a non-zero balance appear in
   * the summary list.
   */
  val total: Double,
  val count: Int,
  val lastOccurredAt: Long,
) {
  val id: String get() = contactId

  val direction: LendDirection get() = if (total > 0) LendDirection.OWED_TO_ME else LendDirection.I_OWE

  /** Balance without its sign, for display next to a direction label. */
  val magnitude: Double get() = abs(total)
}

/**
 * Both sides of the ledger, netted per contact so someone the user has both
 * lent to and borrowed from lands on one side only.
 */
data class LendTotals(
  val owedToMe: Double,
  val iOwe: Double,
) {
  val net: Double get() = owedToMe - iOwe

  companion object {
    val ZERO = LendTotals(owedToMe = 0.0, iOwe = 0.0)
  }
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
  const val historyPageSize = 50

  /**
   * Both sides of the ledger. Takes already-netted contact summaries rather
   * than raw entries, so a contact the user has both lent to and borrowed from
   * is not counted on both sides.
   */
  fun totals(summaries: List<LendContactSummary>): LendTotals =
    summaries.fold(LendTotals.ZERO) { totals, summary ->
      when (summary.direction) {
        LendDirection.OWED_TO_ME -> totals.copy(owedToMe = totals.owedToMe + summary.total)
        LendDirection.I_OWE -> totals.copy(iOwe = totals.iOwe + summary.magnitude)
      }
    }

  /**
   * Signed balance with one contact: positive when they owe the user, negative
   * when the user owes them. When editing an entry, exclude it so its current
   * amount remains eligible.
   */
  fun netBalance(
    contactId: String,
    lends: List<Lend>,
    excludingLendId: String? = null,
  ): Double = lends.sumOf { lend ->
    if (lend.contactId == contactId && lend.id != excludingLendId) lend.signedAmount else 0.0
  }

  /** Amount that can still be recorded as repaid by a contact. */
  fun outstandingAmount(
    contactId: String,
    lends: List<Lend>,
    excludingLendId: String? = null,
  ): Double = maxOf(0.0, netBalance(contactId, lends, excludingLendId))

  /**
   * Amount the user can still record paying back to a contact they borrowed
   * from — the mirror image of [outstandingAmount].
   */
  fun borrowedBalance(
    contactId: String,
    lends: List<Lend>,
    excludingLendId: String? = null,
  ): Double = maxOf(0.0, -netBalance(contactId, lends, excludingLendId))

  /**
   * How much a settlement of [kind] may be for without overshooting zero.
   * Entries that open a balance rather than close one are uncapped.
   */
  fun settlementLimit(
    kind: LendKind,
    contactId: String,
    lends: List<Lend>,
    excludingLendId: String? = null,
  ): Double? = when (kind) {
    LendKind.LENT, LendKind.BORROWED -> null
    LendKind.REPAID -> outstandingAmount(contactId, lends, excludingLendId)
    LendKind.RETURNED -> borrowedBalance(contactId, lends, excludingLendId)
  }

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
   * Groups lends per person by address-book identifier, keeping the name casing
   * of the most recent entry, sorted by largest balance in either direction;
   * contacts whose balance nets to zero are omitted.
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
      .filter { it.magnitude > 0.0001 }
      .sortedWith(
        compareByDescending<LendContactSummary> { it.magnitude }.thenBy { it.contactName },
      )
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
