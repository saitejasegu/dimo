package app.dimo.android.domain

import app.dimo.android.data.model.HOME_PAGE_SIZE
import app.dimo.android.store.UiTransaction

data class DayGroup(
  val label: String,
  val total: Double,
  val items: List<UiTransaction>,
)

data class TransactionSummary(
  val total: Double,
  val count: Int,
  val largest: Double,
  val topCategory: String?,
)

data class FilterState(
  val category: String = "All",
  val paymentMethod: String = "All",
  val query: String = "",
  val startDateKey: String? = null,
  val endDateKey: String? = null,
)

object TransactionSelectors {
  const val homePageSize: Int = HOME_PAGE_SIZE
  const val merchantSuggestionLimit: Int = 6

  fun categoryNames(limits: Map<String, Double>): List<String> =
    limits.keys.sorted()

  fun filterOptions(limits: Map<String, Double>): List<String> =
    listOf("All") + categoryNames(limits)

  fun paymentMethodFilterOptions(txs: List<UiTransaction>): List<String> =
    listOf("All") + txs.mapNotNull { it.paymentMethod }.distinct().sorted()

  fun filterTransactions(txs: List<UiTransaction>, filter: FilterState): List<UiTransaction> {
    val q = filter.query.trim().lowercase()
    return txs.filter { tx ->
      val catOk = filter.category == "All" || tx.category == filter.category
      val pmOk = filter.paymentMethod == "All" || tx.paymentMethod == filter.paymentMethod
      val queryOk = q.isEmpty() ||
        tx.name.lowercase().contains(q) ||
        tx.category.lowercase().contains(q)
      val key = DateHelpers.localDateKey(tx.occurredAt)
      val startOk = filter.startDateKey == null || key >= filter.startDateKey
      val endOk = filter.endDateKey == null || key <= filter.endDateKey
      catOk && pmOk && queryOk && startOk && endOk
    }
  }

  fun groupByDay(txs: List<UiTransaction>): List<DayGroup> {
    val order = linkedMapOf<String, MutableList<UiTransaction>>()
    for (tx in txs) {
      val label = DateHelpers.formatTransactionDay(tx.occurredAt)
      order.getOrPut(label) { mutableListOf() }.add(tx)
    }
    return order.map { (label, items) ->
      DayGroup(label = label, total = items.sumOf { it.amount }, items = items)
    }
  }

  fun paginateTransactionsByDay(
    txs: List<UiTransaction>,
    limit: Int = homePageSize,
  ): Pair<List<UiTransaction>, Boolean> {
    if (txs.size <= limit) return txs to false
    var end = limit
    if (end < txs.size) {
      val lastDay = DateHelpers.localDateKey(txs[end - 1].occurredAt)
      while (end < txs.size && DateHelpers.localDateKey(txs[end].occurredAt) == lastDay) {
        end++
      }
    }
    return txs.take(end) to (end < txs.size)
  }

  fun summarize(txs: List<UiTransaction>): TransactionSummary {
    if (txs.isEmpty()) return TransactionSummary(0.0, 0, 0.0, null)
    val total = txs.sumOf { it.amount }
    val largest = txs.maxOf { it.amount }
    val top = txs.groupBy { it.category }.maxByOrNull { it.value.sumOf { t -> t.amount } }?.key
    return TransactionSummary(total, txs.size, largest, top)
  }

  fun totalSpent(txs: List<UiTransaction>): Double = txs.sumOf { it.amount }

  data class MerchantSuggestion(
    val name: String,
    val category: String,
    val paymentMethod: String?,
    val count: Int,
    val occurredAt: Long,
  )

  fun merchantSuggestions(
    txs: List<UiTransaction>,
    query: String,
    limit: Int = merchantSuggestionLimit,
  ): List<MerchantSuggestion> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return emptyList()
    val grouped = linkedMapOf<String, MerchantSuggestion>()
    for (tx in txs) {
      val key = tx.name.lowercase()
      if (!key.contains(q)) continue
      val existing = grouped[key]
      if (existing == null || tx.occurredAt > existing.occurredAt) {
        grouped[key] = MerchantSuggestion(
          name = tx.name,
          category = tx.category,
          paymentMethod = tx.paymentMethod,
          count = (existing?.count ?: 0) + 1,
          occurredAt = tx.occurredAt,
        )
      } else {
        grouped[key] = existing.copy(count = existing.count + 1)
      }
    }
    return grouped.values.sortedWith(
      compareByDescending<MerchantSuggestion> { it.name.lowercase().startsWith(q) }
        .thenByDescending { it.count }
        .thenByDescending { it.occurredAt },
    ).take(limit)
  }
}
