package app.dimo.android.domain

import app.dimo.android.store.UiCategory
import app.dimo.android.store.UiTransaction
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToInt

data class CategoryBudget(
  val id: String,
  val name: String,
  val emoji: String,
  val limit: Double,
  val spent: Double,
  val pct: Int,
  val over: Boolean,
)

data class BudgetTotals(
  val spent: Double,
  val limit: Double,
  val left: Double,
  val over: Boolean,
)

data class SuggestedBudget(
  val categoryId: String,
  val name: String,
  val emoji: String,
  val currentLimit: Double,
  val suggestedLimit: Double,
)

object BudgetSelectors {
  private val zone = ZoneId.systemDefault()
  private const val LOOKBACK = 6
  private const val OVER = 0.9

  fun categoryBudgets(
    categories: List<UiCategory>,
    txs: List<UiTransaction>,
    now: LocalDate = LocalDate.now(zone),
  ): List<CategoryBudget> {
    val startMs = DateHelpers.startOfDayMs(DateHelpers.monthStart(now))
    val monthTxs = txs.filter { it.occurredAt >= startMs }
    return categories.map { cat ->
      val spent = monthTxs.filter { it.categoryId == cat.id }.sumOf { it.amount }
      val limit = cat.monthlyBudget ?: 0.0
      val pct = Formatting.percent(spent, limit)
      CategoryBudget(
        id = cat.id,
        name = cat.name,
        emoji = cat.emoji,
        limit = limit,
        spent = spent,
        pct = pct,
        over = limit > 0 && pct >= 90,
      )
    }.sortedByDescending { it.spent }
  }

  fun budgetTotals(categories: List<UiCategory>, txs: List<UiTransaction>, now: LocalDate = LocalDate.now(zone)): BudgetTotals {
    val startMs = DateHelpers.startOfDayMs(DateHelpers.monthStart(now))
    val spent = txs.filter { it.occurredAt >= startMs }.sumOf { it.amount }
    val limit = categories.sumOf { it.monthlyBudget ?: 0.0 }
    val over = limit > 0 && spent / limit >= OVER
    return BudgetTotals(spent = spent, limit = limit, left = limit - spent, over = over)
  }

  fun suggestedCategoryBudgetUpdates(
    categories: List<UiCategory>,
    txs: List<UiTransaction>,
    now: LocalDate = LocalDate.now(zone),
  ): List<SuggestedBudget> {
    val start = DateHelpers.monthStart(now, -(LOOKBACK - 1L))
    val startMs = DateHelpers.startOfDayMs(start)
    val nowMs = System.currentTimeMillis()
    return categories.mapNotNull { cat ->
      val lookback = txs.filter { it.categoryId == cat.id && it.occurredAt in startMs..nowMs }
      val total = lookback.sumOf { it.amount }
      if (total <= 0) return@mapNotNull null
      val avg = (total / LOOKBACK)
      val suggested = avg.roundToInt().toDouble()
      val current = cat.monthlyBudget ?: 0.0
      if (suggested.roundToInt() == current.roundToInt()) return@mapNotNull null
      SuggestedBudget(cat.id, cat.name, cat.emoji, current, suggested)
    }
  }

  fun topCategories(
    categories: List<UiCategory>,
    txs: List<UiTransaction>,
    limit: Int = 5,
    now: LocalDate = LocalDate.now(zone),
  ): List<Triple<UiCategory, Double, Int>> {
    val startMs = DateHelpers.startOfDayMs(DateHelpers.monthStart(now))
    val month = txs.filter { it.occurredAt >= startMs }
    val total = month.sumOf { it.amount }.coerceAtLeast(0.0001)
    return categories.map { cat ->
      val spent = month.filter { it.categoryId == cat.id }.sumOf { it.amount }
      Triple(cat, spent, Formatting.percent(spent, total))
    }.filter { it.second > 0 }
      .sortedByDescending { it.second }
      .take(limit)
  }
}
