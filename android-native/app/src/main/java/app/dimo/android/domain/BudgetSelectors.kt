package app.dimo.android.domain

import app.dimo.android.data.model.CategoryLimits
import app.dimo.android.data.model.Transaction
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.floor
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
  val transactionCount: Int,
)

data class DailyBudgetAllowance(
  val amount: Double,
  val daysRemaining: Int,
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

data class GlobalBudgetCategoryInput(
  val id: String,
  val name: String,
  val sortOrder: Int,
  val monthlyBudgetMinor: Long?,
)

data class GlobalBudgetLookbackWindow(
  val start: Long,
  val end: Long,
  val monthCount: Int,
)

data class GlobalBudgetCategoryAllocation(
  val id: String,
  val name: String,
  val sortOrder: Int,
  val sixMonthSpend: Double,
  val monthlyAverage: Double,
  val share: Int,
  /** Whole major currency units. Only categories without history receive null. */
  val allocatedLimit: Long?,
  val currentLimit: Double?,
  val changed: Boolean,
)

data class GlobalBudgetLimitUpdate(
  val id: String,
  val allocatedLimit: Long?,
)

enum class GlobalBudgetAllocationIssue {
  INVALID_TOTAL,
  NO_CATEGORIES,
  NO_HISTORY,
}

data class GlobalBudgetAllocation(
  val window: GlobalBudgetLookbackWindow,
  val totalBudget: Long,
  val totalAllocated: Long,
  val sixMonthSpend: Double,
  val monthlyAverage: Double,
  val allocations: List<GlobalBudgetCategoryAllocation>,
  val issue: GlobalBudgetAllocationIssue?,
) {
  val canApply: Boolean get() = issue == null
}

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
      over = hasLimit && spent > (limit ?: 0.0),
    )
  }.sortedWith(
    compareByDescending<CategoryBudget> { it.pct }
      .thenByDescending { it.spent },
  )

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
      over = totalLimit > 0 && totalSpent > totalLimit,
      transactionCount = current.size,
    )
  }

  /** Average available spend for each remaining local calendar day, including today. */
  fun dailyBudgetAllowance(
    totals: BudgetTotals,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    upcomingTotal: Double = 0.0,
  ): DailyBudgetAllowance? {
    if (totals.totalLimit <= 0 || totals.left < 0) return null
    val daysRemaining = now.lengthOfMonth() - now.dayOfMonth + 1
    return DailyBudgetAllowance(
      amount = (totals.left - upcomingTotal).coerceAtLeast(0.0) / daysRemaining,
      daysRemaining = daysRemaining,
    )
  }

  /**
   * Splits one monthly total using spending from the six completed local calendar
   * months. Largest-remainder rounding makes the whole-unit allocations sum exactly.
   */
  fun globalBudgetAllocation(
    transactions: List<Transaction>,
    categories: List<GlobalBudgetCategoryInput>,
    totalBudget: Long,
    monthCount: Int = 6,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): GlobalBudgetAllocation {
    val safeMonthCount = if (monthCount > 0) monthCount else 6
    val currentStart = now.withDayOfMonth(1)
    val lookbackStart = currentStart.minusMonths(safeMonthCount.toLong())
    val window = GlobalBudgetLookbackWindow(
      start = DateHelpers.startOfDayMillis(lookbackStart),
      end = DateHelpers.startOfDayMillis(currentStart),
      monthCount = safeMonthCount,
    )
    val spendByCategoryId = mutableMapOf<String, Double>()
    for (transaction in transactions) {
      val categoryId = transaction.categoryId ?: continue
      val occurredAt = transaction.occurredAt ?: continue
      if (occurredAt < window.start || occurredAt >= window.end) continue
      spendByCategoryId[categoryId] = (spendByCategoryId[categoryId] ?: 0.0) + transaction.amount
    }
    val eligibleSpend = categories.sumOf { max(0.0, spendByCategoryId[it.id] ?: 0.0) }
    val validTotal = totalBudget > 0 && totalBudget <= Long.MAX_VALUE / 100
    val issue = when {
      categories.isEmpty() -> GlobalBudgetAllocationIssue.NO_CATEGORIES
      eligibleSpend <= 0 -> GlobalBudgetAllocationIssue.NO_HISTORY
      !validTotal -> GlobalBudgetAllocationIssue.INVALID_TOTAL
      else -> null
    }

    data class Draft(
      val category: GlobalBudgetCategoryInput,
      val spend: Double,
      val raw: Double,
      var allocation: Long?,
    )

    val drafts = categories.map { category ->
      val spend = max(0.0, spendByCategoryId[category.id] ?: 0.0)
      val raw = if (validTotal && eligibleSpend > 0) totalBudget * spend / eligibleSpend else 0.0
      Draft(
        category = category,
        spend = spend,
        raw = raw,
        allocation = if (spend > 0 && validTotal) floor(raw).toLong() else null,
      )
    }
    if (issue == null) {
      val floorTotal = drafts.sumOf { it.allocation ?: 0L }
      val remainderOrder = drafts.indices.filter { drafts[it].spend > 0 }.sortedWith { left, right ->
        val leftFraction = drafts[left].raw - floor(drafts[left].raw)
        val rightFraction = drafts[right].raw - floor(drafts[right].raw)
        val difference = rightFraction - leftFraction
        when {
          abs(difference) > 1e-12 -> if (difference > 0) 1 else -1
          drafts[left].category.sortOrder != drafts[right].category.sortOrder ->
            drafts[left].category.sortOrder.compareTo(drafts[right].category.sortOrder)
          else -> drafts[left].category.id.compareTo(drafts[right].category.id)
        }
      }
      val unitsLeft = totalBudget - floorTotal
      if (remainderOrder.isNotEmpty() && unitsLeft > 0) {
        for (position in 0 until unitsLeft) {
          val index = remainderOrder[(position % remainderOrder.size).toInt()]
          drafts[index].allocation = (drafts[index].allocation ?: 0) + 1
        }
      }
    }

    val allocations = drafts.map { draft ->
      val current = draft.category.monthlyBudgetMinor?.toDouble()?.div(100)
      GlobalBudgetCategoryAllocation(
        id = draft.category.id,
        name = draft.category.name,
        sortOrder = draft.category.sortOrder,
        sixMonthSpend = draft.spend,
        monthlyAverage = draft.spend / safeMonthCount,
        share = if (eligibleSpend > 0) Formatting.percent(draft.spend, eligibleSpend) else 0,
        allocatedLimit = draft.allocation,
        currentLimit = current,
        changed = current != draft.allocation?.toDouble(),
      )
    }
    return GlobalBudgetAllocation(
      window = window,
      totalBudget = totalBudget,
      totalAllocated = allocations.sumOf { it.allocatedLimit ?: 0 },
      sixMonthSpend = eligibleSpend,
      monthlyAverage = eligibleSpend / safeMonthCount,
      allocations = allocations,
      issue = issue,
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
