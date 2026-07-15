package app.dimo.android.domain

import app.dimo.android.data.model.CASH_PAYMENT_METHOD_ID
import app.dimo.android.store.UiPaymentMethod
import app.dimo.android.store.UiTransaction
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToInt

data class CsvRow(
  val name: String,
  val amountMinor: Int,
  val occurredAt: Long,
  val categoryName: String,
)

object TransactionCSV {
  val headers = listOf("Date", "Note", "Amount", "Category", "Type")
  val template =
    "Date,Note,Amount,Category,Type\n2026-07-11 11:38:08 +0000,Example purchase,354.00,Snacks,Expense\n"

  private val utcFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss xx")
    .withZone(ZoneOffset.UTC)

  fun formatDate(epochMs: Long): String = utcFormatter.format(Instant.ofEpochMilli(epochMs))

  fun formatAmount(amountMinor: Int): String = "%.2f".format(Locale.US, amountMinor / 100.0)

  fun format(sources: List<UiTransaction>): String {
    val sorted = sources.sortedBy { it.occurredAt }
    val sb = StringBuilder()
    sb.append(headers.joinToString(",")).append('\n')
    for (tx in sorted) {
      val amountMinor = (tx.amount * 100).roundToInt()
      sb.append(escape(formatDate(tx.occurredAt))).append(',')
      sb.append(escape(tx.name)).append(',')
      sb.append(escape(formatAmount(amountMinor))).append(',')
      sb.append(escape(tx.category)).append(',')
      sb.append(escape("Expense")).append('\n')
    }
    return sb.toString()
  }

  fun parse(csv: String): List<CsvRow> {
    val text = csv.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n')
    val lines = text.split('\n').filter { it.isNotBlank() }
    if (lines.isEmpty()) return emptyList()
    val header = parseLine(lines.first())
    require(header == headers) { "Invalid CSV header" }
    val rows = mutableListOf<CsvRow>()
    for (line in lines.drop(1)) {
      val cols = parseLine(line)
      if (cols.size < 5) continue
      val amount = cols[2].toDoubleOrNull() ?: continue
      if (amount <= 0) continue
      if (cols[4].trim().lowercase() != "expense") continue
      val occurredAt = parseDate(cols[0]) ?: continue
      rows += CsvRow(
        name = cols[1].ifBlank { "Expense" },
        amountMinor = (amount * 100).roundToInt(),
        occurredAt = occurredAt,
        categoryName = cols[3].ifBlank { "General" },
      )
    }
    return rows
  }

  fun categoryEmojiForName(name: String): String {
    val n = name.lowercase()
    val rules = listOf(
      Regex("food|restaurant|dining") to "🍽️",
      Regex("snack|coffee|cafe") to "☕",
      Regex("grocery|grocer") to "🛒",
      Regex("rent|housing") to "🏠",
      Regex("sub|subscription|netflix") to "🔁",
      Regex("util|electric|water|internet") to "💡",
      Regex("movie|entertainment") to "🎬",
      Regex("shop|amazon|store") to "🛍️",
      Regex("transit|uber|taxi|metro") to "🚕",
      Regex("health|pharma|medical") to "💊",
      Regex("edu|school|course") to "📚",
      Regex("gift") to "🎁",
      Regex("laundry") to "🧺",
      Regex("fitness|gym") to "🏋️",
    )
    return rules.firstOrNull { it.first.containsMatchIn(n) }?.second ?: "💸"
  }

  fun defaultPaymentMethodIdForImport(methods: List<UiPaymentMethod>): String =
    methods.firstOrNull { it.isDefault }?.id ?: methods.firstOrNull()?.id ?: CASH_PAYMENT_METHOD_ID

  private fun escape(value: String): String {
    return if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      "\"${value.replace("\"", "\"\"")}\""
    } else value
  }

  private fun parseLine(line: String): List<String> {
    val out = mutableListOf<String>()
    val sb = StringBuilder()
    var i = 0
    var inQuotes = false
    while (i < line.length) {
      val c = line[i]
      when {
        c == '"' -> {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            sb.append('"'); i++
          } else inQuotes = !inQuotes
        }
        c == ',' && !inQuotes -> {
          out += sb.toString(); sb.clear()
        }
        else -> sb.append(c)
      }
      i++
    }
    out += sb.toString()
    return out
  }

  private fun parseDate(raw: String): Long? {
    val value = raw.trim()
    return try {
      when {
        value.matches(Regex("""^\d{4}-\d{2}-\d{2}$""")) ->
          LocalDate.parse(value).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
        'T' in value -> Instant.parse(value).toEpochMilli()
        else -> {
          val normalized = value.replace(Regex("""([+-]\d{2})(\d{2})$"""), "$1:$2")
          val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss XXX")
          java.time.OffsetDateTime.parse(normalized, fmt).toInstant().toEpochMilli()
        }
      }
    } catch (_: Exception) {
      try {
        val fmt = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss xx")
        java.time.ZonedDateTime.parse(value, fmt.withZone(ZoneOffset.UTC)).toInstant().toEpochMilli()
      } catch (_: Exception) {
        null
      }
    }
  }
}
