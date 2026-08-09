package app.dimo.android.email.analysis

import app.dimo.android.data.model.Currency
import app.dimo.android.domain.EmailSuggestionSelectors
import app.dimo.android.email.domain.EmailAnalysisConfidence
import app.dimo.android.email.domain.EmailAnalysisKind
import app.dimo.android.email.domain.EmailAnalysisRequest
import app.dimo.android.email.domain.EmailAnalysisResult
import app.dimo.android.email.domain.EmailAnalyzerType
import app.dimo.android.email.domain.EmailDeterministicEvidence
import app.dimo.android.email.domain.EmailStructuredOutputException
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Port of `ios-native/Dimo/Email/Analysis/EmailStructuredOutputValidator.swift`.
 *
 * This is the trust boundary for model output. Nothing the model says is taken at
 * face value: every merchant, amount, date, last-four and reference must also be
 * findable in the email text, and anything that is not is either replaced with
 * deterministic evidence or dropped, with the result downgraded to low confidence
 * so review surfaces it.
 */
data class EmailStructuredOutput(
  val schemaVersion: Int,
  val kind: EmailAnalysisKind,
  val merchant: String? = null,
  val amount: String? = null,
  val currency: Currency? = null,
  val occurredAt: String? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val paymentLastFour: String? = null,
  val reference: String? = null,
)

internal data class DeterministicValidationResult(
  val merchant: String? = null,
  val amount: BigDecimal? = null,
  val currency: Currency? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
)

/**
 * Extracts only literal evidence used to validate model output. This does not
 * classify an email and is never used as a standalone analysis fallback.
 */
internal object EmailDeterministicEvidenceExtractor {
  fun extract(request: EmailAnalysisRequest): DeterministicValidationResult {
    val source = request.subject + "\n" + request.normalizedBody
    val evidence = deterministicEvidence(source)
    val strongestAmount = evidence.amounts.lastOrNull()
    val merchant = request.senderName?.trim()
    val lastFour = evidence.paymentLastFour
    val paymentMethodId = lastFour?.let { digits ->
      request.paymentMethods.firstOrNull {
        it.lastFour.orEmpty().filter(Char::isDigit).takeLast(4) == digits
      }?.id
    }
    val merchantKey = normalizedKey(merchant.orEmpty())
    val categoryId = request.merchantHistory.firstOrNull {
      val historyKey = normalizedKey(it.merchant)
      merchantKey.isNotEmpty() &&
        (merchantKey.contains(historyKey) || historyKey.contains(merchantKey))
    }?.categoryId

    return DeterministicValidationResult(
      merchant = merchant,
      amount = strongestAmount?.value,
      currency = strongestAmount?.currency,
      occurredAt = evidencedDate(source) ?: request.receivedAt,
      categoryId = categoryId,
      paymentMethodId = paymentMethodId,
    )
  }

  fun deterministicEvidence(source: String): EmailDeterministicEvidence {
    val amounts = mutableListOf<EmailDeterministicEvidence.Amount>()
    for ((pattern, currency) in AMOUNT_PATTERNS) {
      for (match in pattern.findAll(source)) {
        val text = match.groupValues[1].replace(",", "")
        val value = runCatching { BigDecimal(text) }.getOrNull() ?: continue
        if (value.signum() <= 0) continue
        amounts.add(EmailDeterministicEvidence.Amount(value, currency, match.value))
      }
    }
    return EmailDeterministicEvidence(
      amounts = amounts,
      paymentLastFour = LAST_FOUR.find(source)?.groupValues?.get(1),
      reference = REFERENCE.find(source)?.groupValues?.get(1),
    )
  }

  private fun evidencedDate(source: String): Long? {
    for ((pattern, formatter) in DATE_FORMATS) {
      val match = pattern.find(source) ?: continue
      val date = runCatching { LocalDate.parse(match.value, formatter) }.getOrNull() ?: continue
      return date.atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    }
    return null
  }

  private fun normalizedKey(value: String): String =
    EmailSuggestionSelectors.fold(value).replace(NON_ALPHANUMERIC, "")

  // Indian receipts commonly use "Rs." / "Rs" / "INR" / ₹ before the amount.
  private val AMOUNT_PATTERNS = listOf(
    Regex(
      "(?:₹|\\bINR\\s*|\\bRs\\.?\\s*)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
      RegexOption.IGNORE_CASE,
    ) to Currency.INR,
    Regex(
      "(?:US\\$|\\bUSD\\s*|\\$)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
      RegexOption.IGNORE_CASE,
    ) to Currency.USD,
    Regex(
      "(?:€|\\bEUR\\s*)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)",
      RegexOption.IGNORE_CASE,
    ) to Currency.EUR,
  )

  private val LAST_FOUR = Regex(
    "(?:ending|last\\s*four|x{2,}|\\*{2,})\\D{0,8}([0-9]{4})\\b",
    RegexOption.IGNORE_CASE,
  )

  private val REFERENCE = Regex(
    "\\b(?:ref(?:erence)?|txn|transaction|order)\\s*(?:id|no|number)?\\s*[:#-]?\\s*" +
      "([A-Z0-9][A-Z0-9-]{5,63})\\b",
    RegexOption.IGNORE_CASE,
  )

  private val DATE_FORMATS = listOf(
    Regex("\\b[0-3]?[0-9]\\s+[A-Za-z]{4,9}\\s+[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.US),
    Regex("\\b[0-3]?[0-9]\\s+[A-Za-z]{3}\\s+[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("d MMM yyyy", Locale.US),
    Regex("\\b[0-3][0-9]/[0-1][0-9]/[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale.US),
    Regex("\\b[0-3][0-9]-[0-1][0-9]-[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("dd-MM-yyyy", Locale.US),
    Regex("\\b[0-9]{4}-[0-1][0-9]-[0-3][0-9]\\b") to
      DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US),
    Regex("\\b[A-Za-z]{4,9}\\s+[0-3]?[0-9],\\s+[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("MMMM d, yyyy", Locale.US),
    Regex("\\b[A-Za-z]{3}\\s+[0-3]?[0-9],\\s+[0-9]{4}\\b") to
      DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US),
  )

  private val NON_ALPHANUMERIC = Regex("[^a-z0-9]")
}

object EmailStructuredOutputValidator {
  private val json = Json { ignoreUnknownKeys = true; isLenient = true }

  /** A spend may run at most this far ahead of the clock before it is a parse error. */
  private const val FUTURE_TOLERANCE_MS = 300_000L

  fun validate(
    response: String,
    request: EmailAnalysisRequest,
    analyzer: EmailAnalyzerType = EmailAnalyzerType.OPEN_ROUTER,
    now: Long = System.currentTimeMillis(),
  ): EmailAnalysisResult {
    val objectText = EmailJSONEnvelopeExtractor.extract(response)
    val element = runCatching { json.parseToJsonElement(objectText) }.getOrNull()
    val dictionary = element as? JsonObject
      ?: throw EmailStructuredOutputException("The response is not a JSON object.")
    val output = decodeOutput(dictionary)
    if (output.schemaVersion != EmailAnalysisResult.SCHEMA_VERSION) {
      throw EmailStructuredOutputException("Unsupported schema version.")
    }

    val deterministic = EmailDeterministicEvidenceExtractor.extract(request)
    if (output.kind == EmailAnalysisKind.IRRELEVANT) {
      return EmailAnalysisResult.irrelevant(analyzer)
    }

    var amount = parseAmount(output.amount)
    var currency = output.currency
    var correctedOutput = output.amount != null && amount == null
    // An amount without a currency (or the reverse) is unusable; drop both.
    if ((amount == null) != (currency == null)) {
      amount = null
      currency = null
      correctedOutput = true
    }
    var confidence = EmailAnalysisConfidence.HIGH
    val source = request.subject + "\n" + request.normalizedBody
    val evidence = EmailDeterministicEvidenceExtractor.deterministicEvidence(source)

    val modelAmount = amount
    val modelCurrency = currency
    if (modelAmount != null && modelCurrency != null) {
      // Currency is constrained by the OpenRouter schema to Dimo's supported
      // values, so only the amount must be evidenced by the email text.
      val isEvidenced = evidence.amounts.any { it.value.compareTo(modelAmount) == 0 } ||
        evidencedAmount(modelAmount, source)
      if (!isEvidenced) {
        val deterministicAmount = deterministic.amount
        if (deterministicAmount != null) {
          amount = deterministicAmount
          currency = modelCurrency
        } else {
          // Keep a valid classification reviewable without trusting monetary
          // values that cannot be found in the email. The user can enter the
          // missing amount during review; malformed JSON still fails above.
          amount = null
          currency = null
        }
        confidence = EmailAnalysisConfidence.LOW
        correctedOutput = true
      }
    } else if (deterministic.amount != null && deterministic.currency != null) {
      amount = deterministic.amount
      currency = deterministic.currency
      confidence = EmailAnalysisConfidence.MEDIUM
    }

    // Merchant evidence may live only in the From display name (common for
    // BookMyShow / Amazon / bank alerts) rather than the body text.
    val merchantEvidenceSource = listOfNotNull(
      request.senderName,
      request.senderAddress,
      request.subject,
      request.normalizedBody,
    ).map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
    val modelMerchant = evidencedText(output.merchant, merchantEvidenceSource, 100)
    val merchant = modelMerchant ?: evidencedText(deterministic.merchant, merchantEvidenceSource, 100)
    if (output.merchant != null && modelMerchant == null) correctedOutput = true

    val modelLastFour = validateLastFour(output.paymentLastFour, source)
    val lastFour = modelLastFour ?: validateLastFour(evidence.paymentLastFour, source)
    if (output.paymentLastFour != null && modelLastFour == null) correctedOutput = true

    val modelPaymentMethodId = validatePaymentMethod(output.paymentMethodId, lastFour, request, source)
    val paymentMethodId = modelPaymentMethodId
      ?: validatePaymentMethod(deterministic.paymentMethodId, lastFour, request, source)
    if (output.paymentMethodId != null && modelPaymentMethodId == null) correctedOutput = true

    val modelReference = evidencedText(output.reference, source, 64)
    val reference = modelReference ?: evidencedText(evidence.reference, source, 64)
    if (output.reference != null && modelReference == null) correctedOutput = true

    val modelOccurredAt = parseOccurredAt(output.occurredAt, request, source, output.kind, now)
    val occurredAt = modelOccurredAt
      ?: safeDeterministicDate(deterministic.occurredAt, request, output.kind, now)
    if (output.occurredAt != null && modelOccurredAt == null) correctedOutput = true

    val categoryId = resolveCategoryId(output.categoryId, merchant, request, deterministic.categoryId)
    if (output.categoryId != null && categoryId != output.categoryId) correctedOutput = true
    val paymentMethodIds = request.paymentMethods.map { it.id }.toSet()
    if (output.paymentMethodId != null && output.paymentMethodId !in paymentMethodIds) {
      correctedOutput = true
    }
    if (amount == null || currency == null) confidence = EmailAnalysisConfidence.LOW
    if (correctedOutput) confidence = EmailAnalysisConfidence.LOW

    return EmailAnalysisResult(
      kind = output.kind,
      merchant = merchant,
      amount = amount,
      currency = currency,
      occurredAt = occurredAt,
      categoryId = categoryId,
      paymentMethodId = paymentMethodId,
      paymentLastFour = lastFour,
      reference = reference,
      analyzer = analyzer,
      confidence = confidence,
    )
  }

  // MARK: - Decoding

  private fun decodeOutput(dictionary: JsonObject): EmailStructuredOutput {
    val schemaVersion = integerValue(dictionary["schemaVersion"])
    val kind = EmailAnalysisKind.fromWire(stringValue(dictionary["kind"])?.lowercase())
    if (schemaVersion == null || kind == null) {
      throw EmailStructuredOutputException("The schema version or kind is invalid.")
    }
    // Models sometimes emit the amount as a bare number instead of a string.
    val amount = stringValue(dictionary["amount"])?.let(::nullNormalized)
      ?: numberText(dictionary["amount"])
    val currency = stringValue(dictionary["currency"])
      ?.let(::nullNormalized)
      ?.let { raw -> Currency.entries.firstOrNull { it.wire == raw.uppercase() } }
    return EmailStructuredOutput(
      schemaVersion = schemaVersion,
      kind = kind,
      merchant = stringValue(dictionary["merchant"])?.let(::nullNormalized),
      amount = amount,
      currency = currency,
      occurredAt = stringValue(dictionary["occurredAt"])?.let(::nullNormalized),
      categoryId = stringValue(dictionary["categoryId"])?.let(::nullNormalized),
      paymentMethodId = stringValue(dictionary["paymentMethodId"])?.let(::nullNormalized),
      paymentLastFour = stringValue(dictionary["paymentLastFour"])?.let(::nullNormalized),
      reference = stringValue(dictionary["reference"])?.let(::nullNormalized),
    )
  }

  private fun integerValue(element: kotlinx.serialization.json.JsonElement?): Int? {
    val primitive = element as? JsonPrimitive ?: return null
    if (primitive.booleanOrNull != null && !primitive.isString) return null
    return primitive.content.trim().toIntOrNull()
  }

  private fun stringValue(element: kotlinx.serialization.json.JsonElement?): String? {
    val primitive = element as? JsonPrimitive ?: return null
    if (!primitive.isString) return null
    return primitive.content.trim()
  }

  private fun numberText(element: kotlinx.serialization.json.JsonElement?): String? {
    val primitive = element as? JsonPrimitive ?: return null
    if (primitive.isString) return null
    if (primitive.booleanOrNull != null) return null
    return primitive.content.takeIf { it.toBigDecimalOrNull() != null }
  }

  private fun nullNormalized(value: String): String? {
    val trimmed = value.trim()
    return if (trimmed.isEmpty() || trimmed.lowercase() == "null") null else trimmed
  }

  // MARK: - Field validation

  private fun parseAmount(raw: String?): BigDecimal? {
    if (raw == null || !AMOUNT_TEXT.matches(raw)) return null
    val amount = runCatching { BigDecimal(raw) }.getOrNull() ?: return null
    return amount.takeIf { it.signum() > 0 }
  }

  private fun parseOccurredAt(
    raw: String?,
    request: EmailAnalysisRequest,
    source: String,
    kind: EmailAnalysisKind,
    now: Long,
  ): Long? {
    if (raw == null) return null
    val parsed = parseTimestamp(raw) ?: return null
    if (isSpend(kind) && parsed > now + FUTURE_TOLERANCE_MS) return null
    // Accept the date only when the email actually attests to it, either through
    // its own received time or a date string in the text.
    val metadataEvidence = kotlin.math.abs(parsed - request.receivedAt) <= 1_000
    val textualEvidence = dateEvidenceStrings(parsed).any { source.contains(it, ignoreCase = true) }
    return if (metadataEvidence || textualEvidence) parsed else null
  }

  private fun parseTimestamp(raw: String): Long? {
    runCatching { Instant.parse(raw).toEpochMilli() }.getOrNull()?.let { return it }
    runCatching {
      java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli()
    }.getOrNull()?.let { return it }
    return try {
      LocalDate.parse(raw, DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.US))
        .atStartOfDay(ZoneOffset.UTC)
        .toInstant()
        .toEpochMilli()
    } catch (_: DateTimeParseException) {
      null
    }
  }

  private fun safeDeterministicDate(
    date: Long?,
    request: EmailAnalysisRequest,
    kind: EmailAnalysisKind,
    now: Long,
  ): Long? {
    if (date == null) return null
    if (isSpend(kind) && date > now + FUTURE_TOLERANCE_MS) {
      return request.receivedAt.takeIf { it <= now + FUTURE_TOLERANCE_MS }
    }
    return date
  }

  private fun isSpend(kind: EmailAnalysisKind): Boolean =
    kind == EmailAnalysisKind.PURCHASE || kind == EmailAnalysisKind.DEBIT

  private fun dateEvidenceStrings(timestamp: Long): List<String> {
    val date = Instant.ofEpochMilli(timestamp).atZone(ZoneId.systemDefault()).toLocalDate()
    val monthName = date.month.getDisplayName(java.time.format.TextStyle.FULL, Locale.US)
    val shortMonth = date.month.getDisplayName(java.time.format.TextStyle.SHORT, Locale.US)
    val day = date.dayOfMonth
    val month = date.monthValue
    val year = date.year
    return listOf(
      String.format(Locale.US, "%04d-%02d-%02d", year, month, day),
      String.format(Locale.US, "%02d/%02d/%04d", day, month, year),
      String.format(Locale.US, "%02d-%02d-%04d", day, month, year),
      "$day $monthName $year", "$day $shortMonth $year",
      "$monthName $day, $year", "$shortMonth $day, $year",
    )
  }

  private fun validateLastFour(value: String?, source: String): String? {
    if (value == null) return null
    return if (FOUR_DIGITS.matches(value) && source.contains(value)) value else null
  }

  /**
   * True when the amount appears in the email as its own number. The look-behind
   * covers digits only — not `.` — so "Rs.512.48" / "$12.00" still count, while
   * the trailing guard prevents matching inside a longer number.
   */
  private fun evidencedAmount(amount: BigDecimal, source: String): Boolean {
    val ungroupedSource = source.replace(",", "")
    val canonical = amount.toPlainString()
    val escaped = Regex.escape(canonical)
    val separatorIndex = canonical.indexOf('.')
    val pattern = if (separatorIndex >= 0) {
      val fractionLength = canonical.length - separatorIndex - 1
      val optionalTrailingZero = if (fractionLength == 1) "0?" else ""
      "(?<![0-9])$escaped$optionalTrailingZero(?![0-9]|\\.[0-9])"
    } else {
      "(?<![0-9])$escaped(?:\\.0{1,2})?(?![0-9]|\\.[0-9])"
    }
    return Regex(pattern).containsMatchIn(ungroupedSource)
  }

  /**
   * Resolves a category for models that return a name, an invalid id, or null.
   * Prefers an exact allowed id, then a category-name match, then merchant/category
   * history, then category names evidenced in the email text.
   */
  private fun resolveCategoryId(
    modelValue: String?,
    merchant: String?,
    request: EmailAnalysisRequest,
    deterministicCategoryId: String?,
  ): String? {
    val categoryIds = request.categories.map { it.id }.toSet()
    if (modelValue != null && modelValue in categoryIds) return modelValue
    if (modelValue != null) {
      categoryIdMatchingName(modelValue, request.categories)?.let { return it }
    }

    val historyMerchants = listOfNotNull(merchant, request.senderName)
      .map { it.trim() }
      .filter { it.isNotEmpty() }
    for (candidate in historyMerchants) {
      val merchantKey = evidenceKey(candidate)
      if (merchantKey.isEmpty()) continue
      val match = request.merchantHistory.firstOrNull {
        val historyKey = evidenceKey(it.merchant)
        historyKey.isNotEmpty() &&
          (merchantKey.contains(historyKey) || historyKey.contains(merchantKey)) &&
          it.categoryId in categoryIds
      }
      if (match != null) return match.categoryId
    }

    if (deterministicCategoryId != null && deterministicCategoryId in categoryIds) {
      return deterministicCategoryId
    }

    // Small models often leave categoryId null. Recover when an Allowed category
    // name clearly appears in the merchant/subject/body.
    return inferCategoryIdFromEmailText(merchant, request)
  }

  private fun categoryIdMatchingName(
    raw: String,
    categories: List<app.dimo.android.email.domain.EmailCategoryOption>,
  ): String? {
    val needle = evidenceKey(raw)
    if (needle.isEmpty()) return null
    categories.firstOrNull { evidenceKey(it.name) == needle }?.let { return it.id }
    // Prefer the longest fuzzy name match so "Food" does not beat "Fast Food".
    return categories
      .filter {
        val nameKey = evidenceKey(it.name)
        nameKey.length >= 3 && (nameKey.contains(needle) || needle.contains(nameKey))
      }
      .maxByOrNull { evidenceKey(it.name).length }
      ?.id
  }

  private fun inferCategoryIdFromEmailText(
    merchant: String?,
    request: EmailAnalysisRequest,
  ): String? {
    val haystack = evidenceKey(
      listOfNotNull(merchant, request.senderName, request.subject, request.normalizedBody)
        .joinToString("\n"),
    )
    if (haystack.isEmpty()) return null
    return request.categories
      // Require a meaningful name so short tokens like "TV" do not over-match.
      .filter { evidenceKey(it.name).length >= 4 && haystack.contains(evidenceKey(it.name)) }
      .maxByOrNull { evidenceKey(it.name).length }
      ?.id
  }

  private fun validatePaymentMethod(
    id: String?,
    lastFour: String?,
    request: EmailAnalysisRequest,
    source: String,
  ): String? {
    if (id == null) return null
    val method = request.paymentMethods.firstOrNull { it.id == id } ?: return null
    val expected = method.lastFour
    if (expected != null) {
      val expectedDigits = expected.filter(Char::isDigit).takeLast(4)
      val matches = expectedDigits.length == 4 &&
        source.contains(expectedDigits) &&
        (lastFour == null || lastFour == expectedDigits)
      return if (matches) id else null
    }
    // With no stored last-four, the method's own name has to appear in the email.
    val sourceKey = evidenceKey(source)
    val distinctiveTokens = EmailSuggestionSelectors.fold(method.label)
      .split(NON_ALPHANUMERIC_RUN)
      .filter { it.length >= 3 && it !in GENERIC_METHOD_TOKENS }
    return if (distinctiveTokens.any { sourceKey.contains(evidenceKey(it)) }) id else null
  }

  private fun evidencedText(value: String?, source: String, maximumLength: Int): String? {
    if (value == null) return null
    val trimmed = value.trim()
    if (trimmed.isEmpty() || trimmed.length > maximumLength) return null
    val needle = evidenceKey(trimmed)
    return if (needle.length >= 2 && evidenceKey(source).contains(needle)) trimmed else null
  }

  private fun evidenceKey(value: String): String =
    EmailSuggestionSelectors.fold(value).replace(NON_ALPHANUMERIC, "")

  private val AMOUNT_TEXT = Regex("^[0-9]+(?:\\.[0-9]{1,2})?$")
  private val FOUR_DIGITS = Regex("^[0-9]{4}$")
  private val NON_ALPHANUMERIC = Regex("[^a-z0-9]")
  private val NON_ALPHANUMERIC_RUN = Regex("[^\\p{Alnum}]+")

  private val GENERIC_METHOD_TOKENS = setOf(
    "account", "archived", "bank", "card", "cash", "credit", "debit",
    "method", "payment", "upi", "wallet",
  )
}

/** Pulls the first balanced JSON object out of a chatty model response. */
object EmailJSONEnvelopeExtractor {
  fun extract(response: String): String {
    val trimmed = response.trim()
    val startIndex = trimmed.indexOf('{')
    if (startIndex < 0) throw EmailStructuredOutputException("Expected a JSON object.")
    val candidate = trimmed.substring(startIndex)
    var depth = 0
    var insideString = false
    var escaped = false
    var endIndex = -1
    for (index in candidate.indices) {
      val character = candidate[index]
      if (insideString) {
        when {
          escaped -> escaped = false
          character == '\\' -> escaped = true
          character == '"' -> insideString = false
        }
        continue
      }
      when (character) {
        '"' -> insideString = true
        '{' -> depth += 1
        '}' -> {
          depth -= 1
          if (depth < 0) throw EmailStructuredOutputException("The JSON object is unbalanced.")
          if (depth == 0) {
            endIndex = index + 1
          }
        }
      }
      if (endIndex >= 0) break
    }
    if (insideString || depth != 0 || endIndex < 0) {
      throw EmailStructuredOutputException("The JSON object is incomplete.")
    }
    return candidate.substring(0, endIndex)
  }

  fun containsCompleteObject(response: String): Boolean =
    runCatching { extract(response) }.isSuccess
}
