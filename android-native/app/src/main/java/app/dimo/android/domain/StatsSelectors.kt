package app.dimo.android.domain

import app.dimo.android.data.model.DAY_MS
import app.dimo.android.data.model.StatsRange
import app.dimo.android.store.UiTransaction
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

object StatsConstants {
  fun months(range: StatsRange): Int? = when (range) {
    StatsRange.OneWeek -> null
    StatsRange.Month -> 1
    StatsRange.ThreeMonths -> 3
    StatsRange.SixMonths -> 6
    StatsRange.OneYear -> 12
    StatsRange.TwoYears -> 24
  }

  fun isDayStatsRange(range: StatsRange): Boolean =
    range == StatsRange.OneWeek || range == StatsRange.Month

  fun hydratedRange(
    current: StatsRange,
    previousDefault: StatsRange,
    nextDefault: StatsRange,
    dataReady: Boolean,
  ): StatsRange {
    if (!dataReady) return current
    return if (current == previousDefault) nextDefault else current
  }
}

data class StatsScope(
  val transactions: List<UiTransaction>,
  val scopeTotal: Double,
  val days: Int,
  val averagePerDay: Double,
  val startMs: Long,
  val nowMs: Long,
)

data class StatBar(
  val key: String,
  val label: String,
  val amount: Double,
  val heightRatio: Float,
  val selected: Boolean,
  val compact: Boolean,
)

data class StatCategory(
  val name: String,
  val emoji: String,
  val amount: Double,
  val relative: Int,
)

data class StatMerchant(
  val name: String,
  val amount: Double,
  val relative: Int,
  val emoji: String?,
  val green: Boolean,
)

object StatsSelectors {
  private val zone = ZoneId.systemDefault()

  fun rangeStart(range: StatsRange, now: LocalDate = LocalDate.now(zone)): LocalDate {
    return if (range == StatsRange.OneWeek) {
      now.minusDays(6)
    } else {
      val months = StatsConstants.months(range) ?: 1
      DateHelpers.monthStart(now, -(months - 1L).toLong())
    }
  }

  fun inRange(tx: UiTransaction, startMs: Long, nowMs: Long): Boolean =
    tx.occurredAt in startMs..nowMs

  fun statsScope(
    txs: List<UiTransaction>,
    range: StatsRange,
    nowMs: Long = System.currentTimeMillis(),
  ): StatsScope {
    val nowDate = java.time.Instant.ofEpochMilli(nowMs).atZone(zone).toLocalDate()
    val start = rangeStart(range, nowDate)
    val startMs = DateHelpers.startOfDayMs(start)
    val scoped = txs.filter { inRange(it, startMs, nowMs) }
    val scopeTotal = scoped.sumOf { it.amount }
    val days = max(1, (floor((nowMs - startMs).toDouble() / DAY_MS) + 1).toInt())
    return StatsScope(scoped, scopeTotal, days, scopeTotal / days, startMs, nowMs)
  }

  fun buildBars(scope: StatsScope, range: StatsRange, selectedKey: String?): List<StatBar> {
    val nowDate = java.time.Instant.ofEpochMilli(scope.nowMs).atZone(zone).toLocalDate()
    val start = java.time.Instant.ofEpochMilli(scope.startMs).atZone(zone).toLocalDate()
    val buckets = linkedMapOf<String, Double>()
    if (StatsConstants.isDayStatsRange(range)) {
      var d = start
      while (!d.isAfter(nowDate)) {
        buckets[DateHelpers.localDateKey(d)] = 0.0
        d = d.plusDays(1)
      }
      for (tx in scope.transactions) {
        val key = DateHelpers.localDateKey(tx.occurredAt)
        buckets[key] = (buckets[key] ?: 0.0) + tx.amount
      }
    } else {
      var m = DateHelpers.monthStart(start)
      val end = DateHelpers.monthStart(nowDate)
      while (!m.isAfter(end)) {
        buckets["${m.year}-${m.monthValue - 1}"] = 0.0
        m = m.plusMonths(1)
      }
      for (tx in scope.transactions) {
        val d = java.time.Instant.ofEpochMilli(tx.occurredAt).atZone(zone).toLocalDate()
        val key = "${d.year}-${d.monthValue - 1}"
        buckets[key] = (buckets[key] ?: 0.0) + tx.amount
      }
    }
    val maxAmount = max(1.0, buckets.values.maxOrNull() ?: 1.0)
    val wide = buckets.size > if (StatsConstants.isDayStatsRange(range)) 7 else 6
    val selected = selectedKey ?: buckets.keys.lastOrNull()
    return buckets.entries.map { (key, amount) ->
      val label = if (StatsConstants.isDayStatsRange(range)) {
        val date = DateHelpers.parseLocalDate(key)
        if (range == StatsRange.OneWeek) {
          date.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())
        } else date.dayOfMonth.toString()
      } else {
        val parts = key.split("-")
        val month = parts[1].toInt() + 1
        LocalDate.of(parts[0].toInt(), month, 1)
          .format(DateTimeFormatter.ofPattern("MMM", Locale.getDefault()))
      }
      val isSelected = key == selected
      StatBar(
        key = key,
        label = label,
        amount = amount,
        heightRatio = (amount / maxAmount).toFloat(),
        selected = isSelected,
        compact = isSelected || !wide,
      )
    }
  }

  fun statCategories(scope: StatsScope, limit: Int = 8): List<StatCategory> {
    val grouped = scope.transactions.groupBy { it.category }
      .map { (name, items) ->
        StatCategory(
          name = name,
          emoji = items.firstOrNull()?.emoji ?: "🙂",
          amount = items.sumOf { it.amount },
          relative = 0,
        )
      }
      .sortedByDescending { it.amount }
      .take(limit)
    val maxAmount = grouped.firstOrNull()?.amount ?: 1.0
    return grouped.map {
      it.copy(relative = max(4, ((it.amount / maxAmount) * 100).roundToInt()))
    }
  }

  fun topMerchants(scope: StatsScope, limit: Int = 8): List<StatMerchant> {
    val grouped = scope.transactions.groupBy { it.name }
      .map { (name, items) ->
        val cats = items.map { it.category }.distinct()
        StatMerchant(
          name = name,
          amount = items.sumOf { it.amount },
          relative = 0,
          emoji = if (cats.size == 1) items.first().emoji else null,
          green = items.any { it.tint == "green" },
        )
      }
      .sortedByDescending { it.amount }
      .take(limit)
    val maxAmount = grouped.firstOrNull()?.amount ?: 1.0
    return grouped.map {
      it.copy(relative = max(6, ((it.amount / maxAmount) * 100).roundToInt()))
    }
  }
}
