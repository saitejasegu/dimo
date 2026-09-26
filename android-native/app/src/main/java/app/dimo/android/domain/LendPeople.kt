package app.dimo.android.domain

import app.dimo.android.sync.OutgoingLendInvite
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

/** Someone on the Lending screen: anyone recorded, or invited before any entries. */
data class LendPerson(
  val contactId: String,
  val contactName: String,
  /** Positive when they owe you. */
  val balance: Double,
  val currency: String?,
  val lastOccurredAt: Long,
  val entryCount: Int,
) {
  val isSettled: Boolean get() = abs(balance) <= 0.0001
}

/** Port of `LendPeople` in `ios-native/Dimo/Features/Lending/LendingScreen.swift`. */
object LendPeople {
  data class Split(val active: List<LendPerson>, val settled: List<LendPerson>) {
    val all: List<LendPerson> get() = active + settled
  }

  /**
   * Everyone recorded plus people invited before any entries, split into
   * those with a balance (largest first) and those settled (most recent first).
   */
  fun split(summaries: List<LendContactSummary>, outgoingInvites: List<OutgoingLendInvite>): Split {
    val people = summaries.map {
      LendPerson(
        contactId = it.contactId,
        contactName = it.contactName,
        balance = it.total,
        currency = it.currency,
        lastOccurredAt = it.lastOccurredAt,
        entryCount = it.count,
      )
    }.toMutableList()
    for (invite in outgoingInvites) {
      val contactId = invite.contactId ?: continue
      if (people.any { it.contactId == contactId }) continue
      people += LendPerson(
        contactId = contactId,
        contactName = invite.contactName,
        balance = 0.0,
        currency = null,
        lastOccurredAt = invite.createdAt.toLong(),
        entryCount = 0,
      )
    }
    return Split(
      active = people.filter { !it.isSettled }.sortedByDescending { abs(it.balance) },
      settled = people.filter { it.isSettled }.sortedByDescending { it.lastOccurredAt },
    )
  }

  /** "Today", "Yesterday", "Aug 22", or "Aug 22, 2025" for other years. */
  fun shortDay(
    timestamp: Long,
    today: LocalDate = LocalDate.now(DateHelpers.zone()),
    zone: ZoneId = DateHelpers.zone(),
  ): String {
    val date = Instant.ofEpochMilli(timestamp).atZone(zone).toLocalDate()
    return when {
      date == today -> "Today"
      date == today.minusDays(1) -> "Yesterday"
      date.year == today.year -> date.format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()))
      else -> date.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()))
    }
  }
}
