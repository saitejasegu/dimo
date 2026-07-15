package app.dimo.android.domain

import app.dimo.android.data.model.LEND_BALANCE_EPSILON
import app.dimo.android.data.model.LendKind
import app.dimo.android.store.UiLend
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

data class ContactSummary(
  val contactId: String,
  val contactName: String,
  val total: Double,
)

object LendSelectors {
  fun signedAmount(lend: UiLend): Double =
    if (lend.kind == LendKind.repaid) -lend.amount else lend.amount

  fun totalLent(lends: List<UiLend>): Double = lends.sumOf { signedAmount(it) }

  fun outstandingAmount(
    lends: List<UiLend>,
    contactId: String,
    excludingLendId: String? = null,
  ): Double {
    val sum = lends
      .filter { it.contactId == contactId && it.id != excludingLendId }
      .sumOf { signedAmount(it) }
    return maxOf(0.0, sum)
  }

  fun unsettledTransactions(lends: List<UiLend>, contactId: String): List<UiLend> {
    val ordered = lends
      .filter { it.contactId == contactId }
      .sortedWith(compareBy({ it.occurredAt }, { it.id }))
    var balance = 0.0
    var start = 0
    ordered.forEachIndexed { index, lend ->
      balance += signedAmount(lend)
      if (abs(balance) < LEND_BALANCE_EPSILON) start = index + 1
    }
    return ordered.drop(start)
  }

  fun contactSummaries(lends: List<UiLend>): List<ContactSummary> {
    val groups = lends.groupBy { it.contactId }
    return groups.mapNotNull { (contactId, items) ->
      val total = items.sumOf { signedAmount(it) }
      if (total <= LEND_BALANCE_EPSILON) return@mapNotNull null
      val name = items.maxByOrNull { it.occurredAt }?.contactName ?: contactId
      ContactSummary(contactId, name, total)
    }.sortedWith(compareByDescending<ContactSummary> { it.total }.thenBy { it.contactName })
  }

  fun recentContacts(lends: List<UiLend>, limit: Int = 6): List<Pair<String, String>> {
    val seen = linkedMapOf<String, String>()
    for (lend in lends.sortedByDescending { it.occurredAt }) {
      if (lend.contactId !in seen) seen[lend.contactId] = lend.contactName
      if (seen.size >= limit) break
    }
    return seen.entries.map { it.key to it.value }
  }

  fun shareText(lends: List<UiLend>, contactName: String, currencySymbol: String): String {
    val unsettled = unsettledTransactions(lends, lends.firstOrNull()?.contactId ?: "")
      .ifEmpty { emptyList() }
    // caller should pass contact-filtered list; recompute from contactId of first
    val contactId = lends.firstOrNull()?.contactId ?: return ""
    val rows = unsettledTransactions(lends, contactId)
    val fmt = DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.ENGLISH)
    val zone = java.time.ZoneId.systemDefault()
    val body = rows.joinToString("\n") { lend ->
      val sign = if (lend.kind == LendKind.repaid) "-" else "+"
      val date = java.time.Instant.ofEpochMilli(lend.occurredAt).atZone(zone).toLocalDate().format(fmt)
      "$date  $sign$currencySymbol${"%.2f".format(Locale.US, lend.amount)}"
    }
    val total = outstandingAmount(lends, contactId)
    return "Dimo · $contactName\n$body\nOutstanding: $currencySymbol${"%.2f".format(Locale.US, total)}"
  }
}
