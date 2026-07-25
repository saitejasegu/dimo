package app.dimo.android.domain

import app.dimo.android.data.model.CategoryLimits
import app.dimo.android.data.model.Transaction
import java.time.LocalDate
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** Port of `ios-native/Dimo/Domain/BudgetSelectors.swift`. */

data class CategoryBudget(
  val category: String,
  val spent: Double,
  val limit: Double?,
  val hasLimit: Boolean,
  val pct: Int,
  val over: Boolean,
) {
  val id: String get() = category
}

data class BudgetTotals(
  val totalSpent: Double,
  val totalLimit: Double,
  val pct: Int,
  val left: Double,
  val over: Boolean,
)

data class CategoryLookbackSpend(
  val total: Double,
  val monthlyAverage: Double,
  val monthCount: Int,
)

data class SuggestedCategoryBudgetUpdate(
  val id: String,
  val name: String,
  val suggestedLimit: Double,
  val currentLimit: Double?,
)

data class TopCategory(
  val category: String,
  val amount: Double,
  val share: Int,
  val relative: Int,
) {
  val id: String get() = category
}

/** Category identity for suggestion input, mirroring the Swift tuple parameter. */
data class BudgetCategoryInput(
  val id: String,
  val name: String,
  val monthlyBudgetMinor: Long?,
)

object BudgetSelectors {
  private fun isCurrentMonth(timestamp: Long?, now: LocalDate): Boolean {
    if (timestamp == null) return false
    val date = DateHelpers.localDate(timestamp)
    return date.year == now.year && date.monthValue == now.monthValue
  }

  private fun spentByCategory(
    transactions: List<Transaction>,
    category: String,
    now: LocalDate,
  ): Double = transactions
    .filter { isCurrentMonth(it.occurredAt, now) && it.category == category }
    .sumOf { it.amount }

  fun categoryBudgets(
    transactions: List<Transaction>,
    limits: CategoryLimits,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): List<CategoryBudget> = limits.keys.map { category ->
    val limit = limits[category]
    val hasLimit = (limit ?: 0.0) > 0
    val spent = spentByCategory(transactions, category, now)
    val pct = if (hasLimit) Formatting.percent(spent, limit ?: 0.0) else 0
    CategoryBudget(
      category = category,
      spent = spent,
      limit = limit,
      hasLimit = hasLimit,
      pct = pct,
      over = pct >= 90,
    )
  }.sortedByDescending { it.spent }

  fun budgetTotals(
    transactions: List<Transaction>,
    limits: CategoryLimits,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): BudgetTotals {
    val current = transactions.filter { isCurrentMonth(it.occurredAt, now) }
    val totalSpent = current.sumOf { it.amount }
    val totalLimit = limits.values.sumOf { it ?: 0.0 }
    val pct = Formatting.percent(totalSpent, totalLimit)
    return BudgetTotals(
      totalSpent = totalSpent,
      totalLimit = totalLimit,
      pct = pct,
      left = totalLimit - totalSpent,
      over = totalLimit > 0 && totalSpent / totalLimit >= 0.9,
    )
  }

  fun categoryLookbackSpend(
    transactions: List<Transaction>,
    categoryId: String,
    monthCount: Int = 6,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    nowMillis: Long = System.currentTimeMillis(),
  ): CategoryLookbackSpend {
    val startDate = now.withDayOfMonth(1).minusMonths((monthCount - 1).toLong())
    val start = DateHelpers.startOfDayMillis(startDate)
    val total = transactions
      .filter {
        val at = it.occurredAt ?: 0L
        it.categoryId == categoryId && at >= start && at <= nowMillis
      }
      .sumOf { it.amount }
    return CategoryLookbackSpend(
      total = total,
      monthlyAverage = total / monthCount,
      monthCount = monthCount,
    )
  }

  fun suggestedCategoryBudgetUpdates(
    transactions: List<Transaction>,
    categories: List<BudgetCategoryInput>,
    monthCount: Int = 6,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    nowMillis: Long = System.currentTimeMillis(),
  ): List<SuggestedCategoryBudgetUpdate> = categories.mapNotNull { category ->
    val lookback = categoryLookbackSpend(
      transactions,
      categoryId = category.id,
      monthCount = monthCount,
      now = now,
      nowMillis = nowMillis,
    )
    if (lookback.total <= 0) return@mapNotNull null
    val suggestedLimit = lookback.monthlyAverage.roundToLong().toDouble()
    val currentLimit = category.monthlyBudgetMinor?.let { it.toDouble() / 100 }
    if (currentLimit == suggestedLimit) return@mapNotNull null
    SuggestedCategoryBudgetUpdate(
      id = category.id,
      name = category.name,
      suggestedLimit = suggestedLimit,
      currentLimit = currentLimit,
    )
  }

  fun topCategories(
    transactions: List<Transaction>,
    limit: Int,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): List<TopCategory> {
    val current = transactions.filter { isCurrentMonth(it.occurredAt, now) }
    val byCategory = mutableMapOf<String, Double>()
    var total = 0.0
    for (t in current) {
      byCategory[t.category] = (byCategory[t.category] ?: 0.0) + t.amount
      total += t.amount
    }
    val sorted = byCategory.entries.sortedByDescending { it.value }
    val maxAmount = sorted.firstOrNull()?.value ?: 1.0
    return sorted.take(limit).map { (category, amount) ->
      TopCategory(
        category = category,
        amount = amount,
        share = Formatting.percent(amount, total),
        relative = max(6, (amount / maxAmount * 100).roundToInt()),
      )
    }
  }
}
