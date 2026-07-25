package app.dimo.android.domain

import app.dimo.android.data.model.CategoryLimits
import app.dimo.android.data.model.Transaction
import java.time.LocalDate

/** Port of `ios-native/Dimo/Domain/TransactionSelectors.swift`. */

data class TransactionFilter(
  val categories: List<String> = emptyList(),
  val paymentMethod: String = "All",
  val query: String = "",
  val startDate: LocalDate? = null,
  val endDate: LocalDate? = null,
)

data class DayGroup(
  val label: String,
  val total: Double,
  val items: List<Transaction>,
)

data class TransactionsSummary(
  val total: Double,
  val count: Int,
  val largest: Double,
  val topCategory: String?,
)

data class MerchantSuggestion(
  val name: String,
  val category: String,
  val paymentMethod: String?,
  val count: Int,
)

object TransactionSelectors {
  const val HOME_PAGE_SIZE = 50

  fun categoryNames(limits: CategoryLimits): List<String> = limits.keys.toList()

  fun filterOptions(limits: CategoryLimits): List<String> = listOf("All") + categoryNames(limits)

  fun paymentMethodFilterOptions(transactions: List<Transaction>): List<String> =
    transactions.mapNotNull { it.paymentMethod }.toSet().sorted()

  fun filterTransactions(
    transactions: List<Transaction>,
    filter: TransactionFilter,
  ): List<Transaction> {
    val q = filter.query.trim().lowercase()
    val startKey = filter.startDate?.let { DateHelpers.localDateKey(it) }
    val endKey = filter.endDate?.let { DateHelpers.localDateKey(it) }
    return transactions.filter { t ->
      val matchesCategory = filter.categories.isEmpty() || filter.categories.contains(t.category)
      val matchesPayment = filter.paymentMethod == "All" || t.paymentMethod == filter.paymentMethod
      val matchesQuery = q.isEmpty() ||
        t.name.lowercase().contains(q) ||
        t.category.lowercase().contains(q)
      val matchesDate: Boolean = if (startKey == null && endKey == null) {
        true
      } else {
        val occurredAt = t.occurredAt
        if (occurredAt == null) {
          false
        } else {
          val day = DateHelpers.localDateKey(occurredAt)
          val afterStart = startKey?.let { day >= it } ?: true
          val beforeEnd = endKey?.let { day <= it } ?: true
          afterStart && beforeEnd
        }
      }
      matchesCategory && matchesPayment && matchesQuery && matchesDate
    }
  }

  fun groupByDay(transactions: List<Transaction>): List<DayGroup> {
    val order = mutableListOf<String>()
    val byDay = mutableMapOf<String, MutableList<Transaction>>()
    for (t in transactions) {
      if (byDay[t.day] == null) {
        byDay[t.day] = mutableListOf()
        order.add(t.day)
      }
      byDay.getValue(t.day).add(t)
    }
    return order.map { day ->
      val items = byDay[day].orEmpty()
      DayGroup(label = day, total = items.sumOf { it.amount }, items = items)
    }
  }

  /** Extends the page to a day boundary so a day is never split across pages. */
  fun paginateTransactionsByDay(
    transactions: List<Transaction>,
    limit: Int,
  ): Pair<List<Transaction>, Boolean> {
    if (limit <= 0) return Pair(emptyList(), transactions.isNotEmpty())
    if (transactions.size <= limit) return Pair(transactions, false)
    var end = limit
    val oldestDay = transactions[limit - 1].day
    while (end < transactions.size && transactions[end].day == oldestDay) {
      end += 1
    }
    return Pair(transactions.take(end), end < transactions.size)
  }

  fun summarize(transactions: List<Transaction>): TransactionsSummary {
    val byCategory = mutableMapOf<String, Double>()
    var total = 0.0
    var largest = 0.0
    for (t in transactions) {
      total += t.amount
      largest = maxOf(largest, t.amount)
      byCategory[t.category] = (byCategory[t.category] ?: 0.0) + t.amount
    }
    val top = byCategory.maxByOrNull { it.value }?.key
    return TransactionsSummary(
      total = total,
      count = transactions.size,
      largest = largest,
      topCategory = top,
    )
  }

  fun totalSpent(transactions: List<Transaction>): Double = transactions.sumOf { it.amount }

  fun merchantSuggestions(
    transactions: List<Transaction>,
    query: String,
    limit: Int = 6,
  ): List<MerchantSuggestion> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return emptyList()

    data class Acc(
      var name: String,
      var category: String,
      var paymentMethod: String?,
      var count: Int,
      var occurredAt: Long,
    )

    val byKey = mutableMapOf<String, Acc>()
    for (t in transactions) {
      val name = t.name.trim()
      if (name.isEmpty()) continue
      val key = name.lowercase()
      if (!key.contains(q)) continue
      val occurredAt = t.occurredAt ?: 0L
      val existing = byKey[key]
      if (existing != null) {
        existing.count += 1
        if (occurredAt >= existing.occurredAt) {
          existing.name = name
          existing.category = t.category
          existing.paymentMethod = t.paymentMethod
          existing.occurredAt = occurredAt
        }
      } else {
        byKey[key] = Acc(name, t.category, t.paymentMethod, 1, occurredAt)
      }
    }

    return byKey.values
      .sortedWith(
        compareByDescending<Acc> { if (it.name.lowercase().startsWith(q)) 1 else 0 }
          .thenByDescending { it.count }
          .thenByDescending { it.occurredAt },
      )
      .take(limit)
      .map { MerchantSuggestion(it.name, it.category, it.paymentMethod, it.count) }
  }
}
