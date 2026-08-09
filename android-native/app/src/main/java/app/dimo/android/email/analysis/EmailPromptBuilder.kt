package app.dimo.android.email.analysis

import app.dimo.android.email.domain.EmailAnalysisRequest
import java.time.Instant
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Port of `ios-native/Dimo/Email/Analysis/EmailPromptBuilder.swift`.
 *
 * The instruction block is copied verbatim from iOS: both clients write into the
 * same Convex-backed suggestion contract, so a divergent prompt would produce
 * differently-shaped suggestions for the same inbox.
 */
object EmailPromptBuilder {
  const val DEFAULT_RUNTIME_CONTEXT_TOKENS = 4_096
  const val RESERVED_OUTPUT_TOKENS = 640
  const val MAXIMUM_GENERATED_TOKENS = 256

  val JSON_REPAIR_PROMPT =
    "Return the required JSON object now. Output only the JSON object. Do not explain or " +
      "reason. The first character must be { and the last character must be }."

  private const val OUTPUT_REQUEST = "Return only the JSON object now."

  private val INSTRUCTIONS = """
    You are a JSON extraction function. Extract one completed financial event from one email. Return one raw JSON object immediately. Do not think aloud. Do not use Markdown fences, prose, or comments. The first output character must be { and the last must be }.

    The only kind values are "purchase", "debit", "refund", and "irrelevant". Default to "irrelevant". Use purchase/debit/refund only when the email clearly confirms a completed payment, bank debit, or completed refund with an evidenced amount. Treat newsletters, OTPs, promotions, price lists, pending authorizations, failed or declined payments, shipping updates, statements, cancellations, balance/limit alerts, and ambiguous prices as irrelevant. A credit or completed refund is refund. Never convert currency.

    Return null for every missing fact and for every extracted field when kind is "irrelevant". Never invent values. paymentMethodId must be null or one of the supplied IDs. categoryId must be null, one of the Allowed categories ids, or the exact Allowed category name. For purchase/debit/refund, always set categoryId when Merchant/category history matches or an Allowed category name clearly fits; otherwise null. Every merchant, amount, currency, occurrence time, last four, and reference must be directly evidenced by the email or its supplied received time. Use a quoted decimal string without separators for amount.

    Return these exact keys in this order. This example shows the required shape only — do not copy kind=purchase unless the email is a completed payment:
    {"schemaVersion":1,"kind":"irrelevant","merchant":null,"amount":null,"currency":null,"occurredAt":null,"categoryId":null,"paymentMethodId":null,"paymentLastFour":null,"reference":null}
  """.trimIndent()

  fun build(
    request: EmailAnalysisRequest,
    contextTokens: Int = DEFAULT_RUNTIME_CONTEXT_TOKENS,
  ): String {
    val receivedAt = DateTimeFormatter.ISO_INSTANT
      .format(Instant.ofEpochMilli(request.receivedAt).let { it.minusNanos(it.nano.toLong()) })
    val resolvedContextTokens = max(2_048, contextTokens)
    val targetFixedTokens = resolvedContextTokens - RESERVED_OUTPUT_TOKENS - 256

    // Shed the least valuable context first — merchant history, then whichever of
    // methods/categories is longer — until the fixed prefix fits the window.
    var historyLimit = min(request.merchantHistory.size, 40)
    var categoryLimit = request.categories.size
    var methodLimit = request.paymentMethods.size
    var context: String
    while (true) {
      val categories = compactJson(
        request.categories.take(categoryLimit).map {
          mapOf("id" to it.id, "name" to bounded(it.name, 80))
        },
      )
      val methods = compactJson(
        request.paymentMethods.take(methodLimit).map {
          mapOf(
            "id" to it.id,
            "label" to bounded(it.label, 80),
            "lastFour" to it.lastFour.orEmpty(),
            "archived" to if (it.archived) "true" else "false",
          )
        },
      )
      val history = compactJson(
        request.merchantHistory.take(historyLimit).map { hint ->
          mapOf(
            "merchant" to bounded(hint.merchant, 80),
            "categoryId" to hint.categoryId,
            "categoryName" to (
              request.categories.firstOrNull { it.id == hint.categoryId }
                ?.let { bounded(it.name, 80) } ?: ""
              ),
          )
        },
      )
      context = buildString {
        append("Sender name: ").append(jsonString(request.senderName?.let { bounded(it, 160) }))
        append("\nSender address: ").append(jsonString(bounded(request.senderAddress, 254)))
        append("\nSubject: ").append(jsonString(bounded(request.subject, 320)))
        append("\nGmail received time: ").append(jsonString(receivedAt))
        append("\nActive Dimo currency: ").append(request.activeCurrency.wire)
        append("\nAllowed categories: ").append(categories)
        append("\nAllowed payment methods: ").append(methods)
        append("\nMerchant/category history: ").append(history)
        append("\nEmail body:")
      }
      if (estimatedTokens(INSTRUCTIONS + context) <= targetFixedTokens) break
      if (historyLimit > 0) {
        historyLimit = max(0, historyLimit - 5)
      } else if (methodLimit > 0 || categoryLimit > 0) {
        if (methodLimit >= categoryLimit && methodLimit > 0) {
          methodLimit = max(0, methodLimit - max(1, methodLimit / 8))
        } else {
          categoryLimit = max(0, categoryLimit - max(1, categoryLimit / 8))
        }
      } else {
        break
      }
    }

    return INSTRUCTIONS + "\n\n" + context + "\n" + request.normalizedBody + "\n\n" + OUTPUT_REQUEST
  }

  /** Deliberately crude: ~3 bytes per token, matching the iOS budgeting heuristic. */
  fun estimatedTokens(text: String): Int =
    max(1, ceil(text.toByteArray(Charsets.UTF_8).size / 3.0).toInt())

  private fun jsonString(value: String?): String =
    if (value == null) "null" else JsonPrimitive(value).toString()

  private fun bounded(value: String, count: Int): String =
    if (value.length > count) value.take(count) else value

  private fun compactJson(value: List<Map<String, String>>): String = runCatching {
    JsonArray(
      value.map { entry ->
        // Sorted keys so the same context always produces the same prompt text.
        JsonObject(entry.toSortedMap().mapValues { (_, v) -> JsonPrimitive(v) })
      },
    ).toString()
  }.getOrDefault("[]")

  private val json = Json
}
