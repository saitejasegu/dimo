package app.dimo.android.domain

import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.SeedData
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.roundToLong

/**
 * Port of `ios-native/Dimo/Domain/TransactionCSV.swift`.
 *
 * The header row, date format, amount format, and emoji fallback must stay
 * byte-compatible with the web and iOS clients — a CSV exported anywhere has to
 * import everywhere.
 */
object TransactionCSV {
  val headers = listOf("Date", "Note", "Amount", "Category", "Type")

  val template =
    "Date,Note,Amount,Category,Type\n" +
      "2026-07-11 11:38:08 +0000,Example purchase,354.00,Snacks,Expense\n"

  data class Row(
    val occurredAt: Long,
    val merchant: String,
    val amountMinor: Long,
    val category: String,
  )

  data class Source(
    val name: String,
    val category: String,
    val amount: Double,
    val amountMinor: Long? = null,
    val occurredAt: Long? = null,
  )

  /** Account default payment method for CSV imports — never null. */
  fun defaultPaymentMethodIdForImport(paymentMethods: List<PaymentMethodOption>): String =
    paymentMethods.firstOrNull { it.isDefault }?.id
      ?: paymentMethods.firstOrNull { !it.archived }?.id
      ?: SeedData.CASH_PAYMENT_METHOD.id

  private val emojiRules: List<Pair<Regex, String>> = listOf(
    Regex("breakfast|lunch|dinner|dining|meal|restaurant|food", RegexOption.IGNORE_CASE) to "🍽️",
    Regex("snack|coffee|cafe|tea|bakery", RegexOption.IGNORE_CASE) to "☕",
    Regex("grocer|vegetable|fruit|milk|yogurt", RegexOption.IGNORE_CASE) to "🛒",
    Regex("rent|house|home", RegexOption.IGNORE_CASE) to "🏠",
    Regex("subscription|membership", RegexOption.IGNORE_CASE) to "🔁",
    Regex("utilit|electric|water|gas|internet|phone|bill", RegexOption.IGNORE_CASE) to "💡",
    Regex("movie|cinema|entertainment", RegexOption.IGNORE_CASE) to "🎬",
    Regex("shopping|clothes|fashion", RegexOption.IGNORE_CASE) to "🛍️",
    Regex("transport|transit|taxi|cab|fuel|petrol|travel", RegexOption.IGNORE_CASE) to "🚕",
    Regex("health|medical|doctor|pharmacy", RegexOption.IGNORE_CASE) to "💊",
    Regex("education|school|course|book", RegexOption.IGNORE_CASE) to "📚",
    Regex("gift|donation", RegexOption.IGNORE_CASE) to "🎁",
    Regex("laundry|cleaning", RegexOption.IGNORE_CASE) to "🧺",
    Regex("fitness|gym|sport", RegexOption.IGNORE_CASE) to "🏋️",
  )

  fun categoryEmojiForName(category: String): String {
    val normalized = category.trim().lowercase()
    for ((regex, emoji) in emojiRules) {
      if (regex.containsMatchIn(normalized)) return emoji
    }
    return "💸"
  }

  /** UTC wall-clock stamp, e.g. `2026-07-11 11:38:08 +0000`. */
  fun formatDate(timestamp: Long): String {
    val utc = Instant.ofEpochMilli(timestamp).atZone(ZoneOffset.UTC)
    return String.format(
      Locale.ROOT,
      "%04d-%02d-%02d %02d:%02d:%02d +0000",
      utc.year,
      utc.monthValue,
      utc.dayOfMonth,
      utc.hour,
      utc.minute,
      utc.second,
    )
  }

  fun formatAmount(amountMinor: Long): String =
    String.format(Locale.ROOT, "%.2f", amountMinor.toDouble() / 100)

  fun format(transactions: List<Source>): String {
    val rows = transactions
      .sortedBy { it.occurredAt ?: 0L }
      .map { tx ->
        val amountMinor = tx.amountMinor ?: (tx.amount * 100).roundToLong()
        listOf(
          formatDate(tx.occurredAt ?: 0L),
          escape(tx.name),
          formatAmount(amountMinor),
          escape(tx.category),
          "Expense",
        ).joinToString(",")
      }
    val body = if (rows.isEmpty()) "" else rows.joinToString("\n") + "\n"
    return headers.joinToString(",") + "\n" + body
  }

  fun parse(input: String): List<Row> {
    var text = input
    if (text.startsWith("﻿")) text = text.substring(1)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    val records = parseRecords(text)
    if (records.isEmpty()) throw CSVException.Empty
    val header = records[0].map { it.trim() }
    if (header.size != headers.size || header.zip(headers).any { it.first != it.second }) {
      throw CSVException.BadHeaders
    }
    val rows = mutableListOf<Row>()
    for (index in 1 until records.size) {
      val record = records[index]
      if (record.all { it.isBlank() }) continue
      val rowNumber = index + 1
      if (record.size != headers.size) throw CSVException.ColumnCount(rowNumber)
      val date = record[0]
      val note = record[1].trim()
      val amountValue = record[2].trim()
      val category = record[3].trim()
      val type = record[4].trim().lowercase()
      val occurredAt = parseDate(date) ?: throw CSVException.InvalidDate(rowNumber)
      if (note.isEmpty()) throw CSVException.EmptyNote(rowNumber)
      val amount = amountValue.toDoubleOrNull()
      if (amount == null || amount <= 0) throw CSVException.InvalidAmount(rowNumber)
      if (category.isEmpty()) throw CSVException.EmptyCategory(rowNumber)
      if (type != "expense") throw CSVException.NotExpense(rowNumber)
      rows.add(
        Row(
          occurredAt = occurredAt,
          merchant = note,
          amountMinor = (amount * 100).roundToLong(),
          category = category,
        ),
      )
    }
    if (rows.isEmpty()) throw CSVException.NoTransactions
    return rows
  }

  private fun escape(value: String): String {
    if (Regex("[\",\n\r]").containsMatchIn(value)) {
      return "\"" + value.replace("\"", "\"\"") + "\""
    }
    return value
  }

  private fun parseDate(value: String): Long? {
    var trimmed = value.trim()

    // Bare `yyyy-MM-dd` is interpreted as UTC midnight.
    if (Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(trimmed)) {
      return runCatching {
        java.time.LocalDate.parse(trimmed).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
      }.getOrNull()
    }

    // Normalize a trailing ` +0000` offset into ` +00:00` so ISO parsing accepts it.
    val offsetRegex = Regex(" ([+-]\\d{2})(\\d{2})$")
    val offsetMatch = offsetRegex.find(trimmed)
    if (offsetMatch != null) {
      trimmed = trimmed.replaceRange(
        offsetMatch.range,
        " ${offsetMatch.groupValues[1]}:${offsetMatch.groupValues[2]}",
      )
    }

    val isoCandidate = trimmed.replace(" ", "T")
    val iso = runCatching {
      DateTimeFormatter.ISO_OFFSET_DATE_TIME.parse(isoCandidate, Instant::from).toEpochMilli()
    }.getOrNull()
    if (iso != null) return iso

    return runCatching {
      DateTimeFormatter
        .ofPattern("yyyy-MM-dd HH:mm:ss XX", Locale.ROOT)
        .parse(value.trim(), Instant::from)
        .toEpochMilli()
    }.getOrNull()
  }

  private fun parseRecords(input: String): List<List<String>> {
    val records = mutableListOf<List<String>>()
    var record = mutableListOf<String>()
    val field = StringBuilder()
    var quoted = false
    var index = 0
    while (index < input.length) {
      val char = input[index]
      if (quoted) {
        if (char == '"') {
          if (index + 1 < input.length && input[index + 1] == '"') {
            field.append('"')
            index += 1
          } else {
            quoted = false
          }
        } else {
          field.append(char)
        }
      } else if (char == '"') {
        quoted = true
      } else if (char == ',') {
        record.add(field.toString())
        field.setLength(0)
      } else if (char == '\n') {
        record.add(field.toString())
        records.add(record)
        record = mutableListOf()
        field.setLength(0)
      } else if (char != '\r') {
        field.append(char)
      }
      index += 1
    }
    if (quoted) throw CSVException.UnclosedQuote
    record.add(field.toString())
    if (record.any { it.isNotEmpty() }) records.add(record)
    return records
  }

  /** Messages mirror `TransactionCSV.CSVError` in the Swift port. */
  sealed class CSVException(message: String) : Exception(message) {
    data object Empty : CSVException("CSV is empty")

    data object BadHeaders : CSVException("Expected headers: Date, Note, Amount, Category, Type")

    data object NoTransactions : CSVException("CSV has no transactions")

    data object UnclosedQuote : CSVException("CSV contains an unclosed quoted field")

    data class ColumnCount(val row: Int) : CSVException("Row $row must have exactly 5 columns")
    data class InvalidDate(val row: Int) : CSVException("Row $row has an invalid date")
    data class EmptyNote(val row: Int) : CSVException("Row $row has an empty note")
    data class InvalidAmount(val row: Int) : CSVException("Row $row has an invalid amount")
    data class EmptyCategory(val row: Int) : CSVException("Row $row has an empty category")
    data class NotExpense(val row: Int) : CSVException("Row $row type must be Expense")
  }
}
