package app.dimo.android.domain

import app.dimo.android.data.model.RecurringFrequency
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.roundToLong

object DateHelpers {
  private val zone: ZoneId get() = ZoneId.systemDefault()
  private val keyFormatter = DateTimeFormatter.ISO_LOCAL_DATE

  fun localDateKey(date: LocalDate = LocalDate.now(zone)): String = date.format(keyFormatter)

  fun localDateKey(epochMs: Long): String =
    Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate().format(keyFormatter)

  fun parseLocalDate(value: String): LocalDate = try {
    LocalDate.parse(value, keyFormatter)
  } catch (_: Exception) {
    LocalDate.now(zone)
  }

  fun daysInMonth(year: Int, month: Int): Int = LocalDate.of(year, month, 1).lengthOfMonth()

  fun formatTransactionDay(epochMs: Long, now: LocalDate = LocalDate.now(zone)): String {
    val date = Instant.ofEpochMilli(epochMs).atZone(zone).toLocalDate()
    return when (date) {
      now -> "Today"
      now.minusDays(1) -> "Yesterday"
      else -> {
        val day = date.dayOfWeek.getDisplayName(TextStyle.FULL, Locale.getDefault())
        val monthDay = date.format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()))
        if (date.year == now.year) "$day $monthDay" else "$day $monthDay, ${date.year}"
      }
    }
  }

  fun formatTransactionTime(epochMs: Long): String {
    val time = Instant.ofEpochMilli(epochMs).atZone(zone).toLocalTime()
    return time.format(DateTimeFormatter.ofPattern("h:mm a", Locale.getDefault()))
  }

  fun nextOccurrence(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: LocalDate = LocalDate.now(zone),
  ): LocalDate {
    val anchor = parseLocalDate(anchorDate)
    val today = now
    return when (frequency) {
      RecurringFrequency.monthly -> {
        var candidate = clampDay(today.year, today.monthValue, anchor.dayOfMonth)
        if (candidate.isBefore(today)) {
          val next = today.plusMonths(1)
          candidate = clampDay(next.year, next.monthValue, anchor.dayOfMonth)
        }
        candidate
      }
      RecurringFrequency.yearly -> {
        var candidate = clampDay(today.year, anchor.monthValue, anchor.dayOfMonth)
        if (candidate.isBefore(today)) {
          candidate = clampDay(today.year + 1, anchor.monthValue, anchor.dayOfMonth)
        }
        candidate
      }
    }
  }

  fun occurrencesThrough(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: LocalDate = LocalDate.now(zone),
  ): List<LocalDate> {
    val anchor = parseLocalDate(anchorDate)
    if (anchor.isAfter(now)) return emptyList()
    val cap = if (frequency == RecurringFrequency.monthly) 1200 else 200
    val out = ArrayList<LocalDate>()
    var cursor = anchor
    var i = 0
    while (!cursor.isAfter(now) && i < cap) {
      out.add(cursor)
      cursor = when (frequency) {
        RecurringFrequency.monthly -> {
          val next = cursor.plusMonths(1)
          clampDay(next.year, next.monthValue, anchor.dayOfMonth)
        }
        RecurringFrequency.yearly -> clampDay(cursor.year + 1, anchor.monthValue, anchor.dayOfMonth)
      }
      i++
    }
    return out
  }

  enum class OccurrenceSelection { ALL, SELECTED }

  fun recurringTransactionDates(
    anchorDate: String,
    frequency: RecurringFrequency,
    selection: OccurrenceSelection,
    now: LocalDate = LocalDate.now(zone),
  ): List<LocalDate> {
    val anchor = parseLocalDate(anchorDate)
    if (anchor.isAfter(now)) return emptyList()
    return when (selection) {
      OccurrenceSelection.SELECTED -> listOf(anchor)
      OccurrenceSelection.ALL -> occurrencesThrough(anchorDate, frequency, now)
    }
  }

  fun occurrenceTimestamp(date: LocalDate, time: LocalTime = LocalTime.NOON): Long =
    LocalDateTime.of(date, time).atZone(zone).toInstant().toEpochMilli()

  fun recurringDueLabel(due: LocalDate, now: LocalDate = LocalDate.now(zone)): String {
    val monthDay = due.format(DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()))
    val days = java.time.temporal.ChronoUnit.DAYS.between(now, due)
    val relative = when (days) {
      0L -> "today"
      1L -> "tomorrow"
      else -> "in $days days"
    }
    return "Due $monthDay · $relative"
  }

  fun startOfDayMs(date: LocalDate = LocalDate.now(zone)): Long =
    date.atStartOfDay(zone).toInstant().toEpochMilli()

  fun monthStart(date: LocalDate = LocalDate.now(zone), offsetMonths: Long = 0): LocalDate =
    date.withDayOfMonth(1).plusMonths(offsetMonths)

  private fun clampDay(year: Int, month: Int, day: Int): LocalDate {
    val max = daysInMonth(year, month)
    return LocalDate.of(year, month, day.coerceAtMost(max))
  }
}
