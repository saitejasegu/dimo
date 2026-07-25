package app.dimo.android.domain

import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.Transaction
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

/** Port of `ios-native/Dimo/Domain/StatsSelectors.swift`. */

object StatsConstants {
  val ranges: List<StatsRange> = listOf(
    StatsRange.ONE_WEEK,
    StatsRange.MONTH,
    StatsRange.THREE_MONTHS,
    StatsRange.SIX_MONTHS,
    StatsRange.ONE_YEAR,
    StatsRange.TWO_YEARS,
  )

  val rangeLabel: Map<StatsRange, String> = mapOf(
    StatsRange.ONE_WEEK to "1 week",
    StatsRange.MONTH to "1 month",
    StatsRange.THREE_MONTHS to "3 months",
    StatsRange.SIX_MONTHS to "6 months",
    StatsRange.ONE_YEAR to "1 year",
    StatsRange.TWO_YEARS to "2 years",
  )

  val rangeMonths: Map<StatsRange, Int> = mapOf(
    StatsRange.MONTH to 1,
    StatsRange.THREE_MONTHS to 3,
    StatsRange.SIX_MONTHS to 6,
    StatsRange.ONE_YEAR to 12,
    StatsRange.TWO_YEARS to 24,
  )

  fun isDayStatsRange(range: StatsRange): Boolean =
    range == StatsRange.ONE_WEEK || range == StatsRange.MONTH

  fun hydratedRange(
    current: StatsRange,
    previousDefault: StatsRange,
    nextDefault: StatsRange,
    dataReady: Boolean,
  ): StatsRange = if (!dataReady || current == previousDefault) nextDefault else current
}

data class StatsScope(
  val rangeMonths: Int,
  val scopeTotal: Double,
  val scopePast: Double,
  val spentLabel: String,
  val averageLabel: String,
  val transactions: List<Transaction>,
)

data class MonthBar(
  val key: String,
  val label: String,
  val amount: Double,
  val display: String,
  val selected: Boolean,
  val heightRatio: Double,
  val wide: Boolean,
) {
  val id: String get() = key
}

data class MonthBars(
  val visible: Boolean,
  val title: String,
  val caption: String,
  val bars: List<MonthBar>,
)

data class StatCategory(
  val category: String,
  val amount: Double,
  val caption: String,
  val relative: Int,
  val primary: Boolean,
) {
  val id: String get() = category
}

data class MerchantStat(
  val name: String,
  val count: Int,
  val amount: Double,
  val green: Boolean,
  val emoji: String?,
  val sub: String,
  val relative: Int,
) {
  val id: String get() = name
}

object StatsSelectors {
  private fun monthStart(date: LocalDate, offset: Int = 0): LocalDate =
    date.withDayOfMonth(1).plusMonths(offset.toLong())

  fun rangeStart(
    range: StatsRange,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
  ): LocalDate {
    if (range == StatsRange.ONE_WEEK) return now.minusDays(6)
    val months = StatsConstants.rangeMonths[range] ?: 1
    return monthStart(now, -(months - 1))
  }

  private fun inRange(
    transactions: List<Transaction>,
    range: StatsRange,
    now: LocalDate,
    nowMillis: Long,
  ): List<Transaction> {
    val start = DateHelpers.startOfDayMillis(rangeStart(range, now))
    return transactions.filter {
      val at = it.occurredAt ?: 0L
      at >= start && at <= nowMillis
    }
  }

  fun statsScope(
    range: StatsRange,
    transactions: List<Transaction>,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    nowMillis: Long = System.currentTimeMillis(),
  ): StatsScope {
    val scoped = inRange(transactions, range, now, nowMillis)
    val scopeTotal = scoped.sumOf { it.amount }
    val oldestTimestamp = scoped.mapNotNull { it.occurredAt }.minOrNull()
    val days: Int = if (oldestTimestamp != null) {
      val oldestDay = DateHelpers.localDate(oldestTimestamp)
      max(1, ChronoUnit.DAYS.between(oldestDay, now).toInt() + 1)
    } else {
      1
    }
    val spentLabel = when (range) {
      StatsRange.ONE_WEEK -> "Spent this week"
      StatsRange.MONTH -> "Spent this month"
      else -> "Spent in the last ${StatsConstants.rangeMonths[range] ?: 1} months"
    }
    return StatsScope(
      rangeMonths = if (range == StatsRange.ONE_WEEK) 0 else (StatsConstants.rangeMonths[range] ?: 0),
      scopeTotal = scopeTotal,
      scopePast = 0.0,
      spentLabel = spentLabel,
      averageLabel = "${Formatting.money(scopeTotal / days)} avg per day",
      transactions = scoped,
    )
  }

  private data class BarEntry(
    val key: String,
    val label: String,
    val captionLabel: String,
    val amount: Double,
  )

  private fun buildBars(
    title: String,
    entries: List<BarEntry>,
    selectedKey: String?,
    wide: Boolean,
  ): MonthBars {
    if (entries.isEmpty()) {
      return MonthBars(visible = false, title = title, caption = "", bars = emptyList())
    }
    val resolvedKey = entries.firstOrNull { it.key == selectedKey }?.key ?: entries.last().key
    val selected = entries.first { it.key == resolvedKey }
    val maxAmount = max(1.0, entries.maxOf { it.amount })
    return MonthBars(
      visible = true,
      title = title,
      caption = "${selected.captionLabel}: ${Formatting.money(selected.amount)}",
      bars = entries.map { entry ->
        MonthBar(
          key = entry.key,
          label = entry.label,
          amount = entry.amount,
          display = if (!wide || entry.key == resolvedKey) {
            Formatting.compactMoney(entry.amount)
          } else {
            ""
          },
          selected = entry.key == resolvedKey,
          heightRatio = entry.amount / maxAmount,
          wide = wide,
        )
      },
    )
  }

  fun dayBars(
    range: StatsRange,
    transactions: List<Transaction>,
    selectedDay: String?,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    locale: Locale = Locale.getDefault(),
  ): MonthBars {
    if (!StatsConstants.isDayStatsRange(range)) {
      return MonthBars(visible = false, title = "By day", caption = "", bars = emptyList())
    }
    val start = rangeStart(range, now)
    val amounts = mutableMapOf<String, Double>()
    for (t in transactions) {
      val key = DateHelpers.localDateKey(t.occurredAt ?: 0L)
      amounts[key] = (amounts[key] ?: 0.0) + t.amount
    }
    val weekdayFormatter = DateTimeFormatter.ofPattern("EEE", locale)
    val captionFormatter = DateTimeFormatter.ofPattern("MMM d", locale)
    val entries = mutableListOf<BarEntry>()
    var cursor = start
    while (!cursor.isAfter(now)) {
      val key = DateHelpers.localDateKey(cursor)
      val label = if (range == StatsRange.ONE_WEEK) {
        cursor.format(weekdayFormatter)
      } else {
        cursor.dayOfMonth.toString()
      }
      entries.add(BarEntry(key, label, cursor.format(captionFormatter), amounts[key] ?: 0.0))
      cursor = cursor.plusDays(1)
    }
    return buildBars("By day", entries, selectedDay, wide = entries.size > 7)
  }

  fun monthBars(
    range: StatsRange,
    transactions: List<Transaction>,
    selectedMonth: String?,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    locale: Locale = Locale.getDefault(),
  ): MonthBars {
    if (StatsConstants.isDayStatsRange(range)) {
      return MonthBars(visible = false, title = "By month", caption = "", bars = emptyList())
    }
    val count = StatsConstants.rangeMonths[range] ?: 1
    val formatter = DateTimeFormatter.ofPattern("MMM", locale)
    val entries = (0 until count).map { index ->
      val date = monthStart(now, index - count + 1)
      // Zero-based month index in the key, matching the Swift and web bar keys.
      val key = "${date.year}-${date.monthValue - 1}"
      val amount = transactions.filter { t ->
        val d = DateHelpers.localDate(t.occurredAt ?: 0L)
        "${d.year}-${d.monthValue - 1}" == key
      }.sumOf { it.amount }
      val label = date.format(formatter)
      BarEntry(key, label, label, amount)
    }
    return buildBars("By month", entries, selectedMonth, wide = count > 6)
  }

  fun trendBars(
    range: StatsRange,
    transactions: List<Transaction>,
    selectedKey: String?,
    now: LocalDate = LocalDate.now(DateHelpers.zone()),
    locale: Locale = Locale.getDefault(),
  ): MonthBars = if (StatsConstants.isDayStatsRange(range)) {
    dayBars(range, transactions, selectedKey, now, locale)
  } else {
    monthBars(range, transactions, selectedKey, now, locale)
  }

  fun statCategories(scope: StatsScope, limit: Int): Pair<List<StatCategory>, Int> {
    val totals = mutableMapOf<String, Double>()
    for (t in scope.transactions) {
      totals[t.category] = (totals[t.category] ?: 0.0) + t.amount
    }
    val entries = totals.entries.sortedByDescending { it.value }
    val maxAmount = entries.firstOrNull()?.value ?: 1.0
    val sliced = if (limit == Int.MAX_VALUE) entries else entries.take(limit)
    return Pair(
      sliced.mapIndexed { index, pair ->
        StatCategory(
          category = pair.key,
          amount = pair.value,
          caption = "${Formatting.money(pair.value)} · ${Formatting.percent(pair.value, scope.scopeTotal)}%",
          relative = max(4, (pair.value / maxAmount * 100).roundToInt()),
          primary = index == 0,
        )
      },
      entries.size,
    )
  }

  fun topMerchants(scope: StatsScope, limit: Int): Pair<List<MerchantStat>, Int> {
    data class Acc(
      var amount: Double,
      var count: Int,
      var green: Boolean,
      var category: String,
      var categoryEmoji: String?,
      var mixedCategories: Boolean,
    )

    val totals = linkedMapOf<String, Acc>()
    for (t in scope.transactions) {
      val current = totals[t.name] ?: Acc(0.0, 0, false, t.category, t.emoji, false)
      current.amount += t.amount
      current.count += 1
      current.green = current.green || (t.green ?: false)
      current.mixedCategories = current.mixedCategories || current.category != t.category
      if (current.categoryEmoji == null) current.categoryEmoji = t.emoji
      totals[t.name] = current
    }
    val sorted = totals.entries.sortedByDescending { it.value.amount }
    val maxAmount = sorted.firstOrNull()?.value?.amount ?: 1.0
    val sliced = if (limit == Int.MAX_VALUE) sorted else sorted.take(limit)
    return Pair(
      sliced.map { (name, value) ->
        MerchantStat(
          name = name,
          count = value.count,
          amount = value.amount,
          green = value.green,
          emoji = if (value.mixedCategories) null else value.categoryEmoji,
          sub = "${value.count} ${if (value.count == 1) "transaction" else "transactions"} · " +
            "${Formatting.percent(value.amount, scope.scopeTotal)}%",
          relative = max(6, (value.amount / maxAmount * 100).roundToInt()),
        )
      },
      sorted.size,
    )
  }
}
