package app.dimo.android.domain

import app.dimo.android.data.model.RecurringFrequency
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.ChronoUnit
import java.util.Locale

enum class RecurringOccurrenceSelection { ALL, SELECTED }

/**
 * Port of `ios-native/Dimo/Domain/DateHelpers.swift`.
 *
 * All month arithmetic is calendar-based (never fixed-millisecond intervals) so
 * short months and leap years land on the same dates as the Swift and TypeScript
 * implementations.
 */
object DateHelpers {
  const val DAY_MS = 86_400_000L

  fun zone(): ZoneId = ZoneId.systemDefault()

  fun localDate(timestamp: Long, zone: ZoneId = zone()): LocalDate =
    Instant.ofEpochMilli(timestamp).atZone(zone).toLocalDate()

  fun localDateKey(date: LocalDate): String =
    String.format(Locale.ROOT, "%04d-%02d-%02d", date.year, date.monthValue, date.dayOfMonth)

  fun localDateKey(timestamp: Long, zone: ZoneId = zone()): String =
    localDateKey(localDate(timestamp, zone))

  fun parseLocalDate(value: String): LocalDate {
    val parts = value.split("-").mapNotNull { it.toIntOrNull() }
    if (parts.size != 3) return LocalDate.now(zone())
    return runCatching { LocalDate.of(parts[0], parts[1], parts[2]) }
      .getOrElse { LocalDate.now(zone()) }
  }

  /** Midnight-of-day epoch millis, the analogue of `calendar.startOfDay`. */
  fun startOfDayMillis(date: LocalDate, zone: ZoneId = zone()): Long =
    date.atStartOfDay(zone).toInstant().toEpochMilli()

  fun formatTransactionDay(
    timestamp: Long,
    now: LocalDate = LocalDate.now(zone()),
    zone: ZoneId = zone(),
    locale: Locale = Locale.getDefault(),
  ): String {
    val date = localDate(timestamp, zone)
    if (date == now) return "Today"
    if (date == now.minusDays(1)) return "Yesterday"
    val pattern = if (date.year == now.year) "EEEE, MMM d" else "EEEE, MMM d, yyyy"
    return date.format(DateTimeFormatter.ofPattern(pattern, locale))
  }

  fun formatTransactionTime(
    timestamp: Long,
    zone: ZoneId = zone(),
    locale: Locale = Locale.getDefault(),
  ): String {
    val time = Instant.ofEpochMilli(timestamp).atZone(zone).toLocalTime()
    return time.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))
  }

  fun daysInMonth(year: Int, monthIndex: Int): Int {
    // monthIndex is zero-based, matching the Swift signature.
    val normalizedYear = year + Math.floorDiv(monthIndex, 12)
    val normalizedMonth = Math.floorMod(monthIndex, 12) + 1
    return LocalDate.of(normalizedYear, normalizedMonth, 1).lengthOfMonth()
  }

  /** The next occurrence on or after today, clamping the anchor day into short months. */
  fun nextOccurrence(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: LocalDate = LocalDate.now(zone()),
  ): LocalDate {
    val anchor = parseLocalDate(anchorDate)
    if (!anchor.isBefore(now)) return anchor

    val anchorDay = anchor.dayOfMonth
    val anchorMonthIndex = anchor.monthValue - 1

    if (frequency == RecurringFrequency.MONTHLY) {
      fun candidate(year: Int, monthIndex: Int): LocalDate {
        val day = minOf(anchorDay, daysInMonth(year, monthIndex))
        return LocalDate.of(year, monthIndex + 1, day)
      }
      val year = now.year
      val monthIndex = now.monthValue - 1
      var result = candidate(year, monthIndex)
      if (result.isBefore(now)) {
        var nextMonth = monthIndex + 1
        var nextYear = year
        if (nextMonth > 11) {
          nextMonth = 0
          nextYear += 1
        }
        result = candidate(nextYear, nextMonth)
      }
      return result
    }

    fun candidate(year: Int): LocalDate {
      val day = minOf(anchorDay, daysInMonth(year, anchorMonthIndex))
      return LocalDate.of(year, anchorMonthIndex + 1, day)
    }
    var result = candidate(now.year)
    if (result.isBefore(now)) result = candidate(now.year + 1)
    return result
  }

  /** Every occurrence from the anchor up to and including today. */
  fun occurrencesThrough(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: LocalDate = LocalDate.now(zone()),
  ): List<LocalDate> {
    val anchor = parseLocalDate(anchorDate)
    if (anchor.isAfter(now)) return emptyList()

    val day = anchor.dayOfMonth
    val dates = mutableListOf<LocalDate>()

    if (frequency == RecurringFrequency.MONTHLY) {
      var year = anchor.year
      var monthIndex = anchor.monthValue - 1
      while (dates.size < 1200) {
        val clamped = minOf(day, daysInMonth(year, monthIndex))
        val date = LocalDate.of(year, monthIndex + 1, clamped)
        if (date.isAfter(now)) break
        dates.add(date)
        monthIndex += 1
        if (monthIndex > 11) {
          monthIndex = 0
          year += 1
        }
      }
      return dates
    }

    var year = anchor.year
    val monthIndex = anchor.monthValue - 1
    while (dates.size < 200) {
      val clamped = minOf(day, daysInMonth(year, monthIndex))
      val date = LocalDate.of(year, monthIndex + 1, clamped)
      if (date.isAfter(now)) break
      dates.add(date)
      year += 1
    }
    return dates
  }

  fun recurringTransactionDates(
    anchorDate: String,
    frequency: RecurringFrequency,
    selection: RecurringOccurrenceSelection,
    now: LocalDate = LocalDate.now(zone()),
  ): List<LocalDate> {
    val anchor = parseLocalDate(anchorDate)
    if (anchor.isAfter(now)) return emptyList()
    return if (selection == RecurringOccurrenceSelection.ALL) {
      occurrencesThrough(anchorDate, frequency, now)
    } else {
      listOf(anchor)
    }
  }

  /** Occurrences pin to local noon so day grouping is stable across time zones. */
  fun occurrenceTimestamp(date: LocalDate, zone: ZoneId = zone()): Long =
    date.atTime(LocalTime.NOON).atZone(zone).toInstant().toEpochMilli()

  /** Occurrence on [date] carrying the hour and minute of [time]. */
  fun occurrenceTimestamp(date: LocalDate, time: LocalTime, zone: ZoneId = zone()): Long =
    LocalDateTime.of(date, LocalTime.of(time.hour, time.minute))
      .atZone(zone)
      .toInstant()
      .toEpochMilli()

  fun recurringDueLabel(
    anchorDate: String,
    frequency: RecurringFrequency,
    now: LocalDate = LocalDate.now(zone()),
    locale: Locale = Locale.getDefault(),
  ): String {
    val due = nextOccurrence(anchorDate, frequency, now)
    val days = ChronoUnit.DAYS.between(now, due).toInt()
    val date = due.format(DateTimeFormatter.ofPattern("MMM d", locale))
    val relative = when (days) {
      0 -> "today"
      1 -> "tomorrow"
      else -> "in $days days"
    }
    return "Due $date · $relative"
  }
}
