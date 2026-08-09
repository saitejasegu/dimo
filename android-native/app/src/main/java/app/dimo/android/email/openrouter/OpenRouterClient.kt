package app.dimo.android.email.openrouter

import android.util.Log
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.email.analysis.EmailPromptBuilder
import app.dimo.android.email.analysis.EmailStructuredOutputValidator
import app.dimo.android.email.domain.EmailAnalysisEnvelope
import app.dimo.android.email.domain.EmailAnalysisRequest
import app.dimo.android.email.domain.EmailAnalyzerType
import java.io.IOException
import java.net.SocketTimeoutException
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Port of `ios-native/Dimo/Email/OpenRouter/OpenRouterClient.swift`. */

@Serializable
data class OpenRouterKeyInfo(
  val label: String = "",
  val limit: Double? = null,
  @SerialName("limit_remaining") val limitRemaining: Double? = null,
  val usage: Double = 0.0,
  @SerialName("usage_daily") val usageDaily: Double = 0.0,
  @SerialName("is_free_tier") val isFreeTier: Boolean = false,
)

@Serializable
data class OpenRouterModel(
  val id: String,
  val name: String,
  @SerialName("context_length") val contextLength: Int = 0,
  val pricing: Pricing = Pricing(),
  @SerialName("supported_parameters") val supportedParameters: List<String> = emptyList(),
  val hasZDREndpoint: Boolean = false,
  val zdrSupportedParameters: List<String> = emptyList(),
) {
  @Serializable
  data class Pricing(val prompt: String? = null, val completion: String? = null)

  val isFree: Boolean
    get() = pricePerToken(pricing.prompt) == 0.0 && pricePerToken(pricing.completion) == 0.0

  val hasKnownPrice: Boolean
    get() = pricePerToken(pricing.prompt) != null && pricePerToken(pricing.completion) != null

  val inputPricePerMillion: Double? get() = pricePerToken(pricing.prompt)?.times(1_000_000)
  val outputPricePerMillion: Double? get() = pricePerToken(pricing.completion)?.times(1_000_000)

  fun supports(parameter: String): Boolean = supportedParameters.contains(parameter)

  private fun pricePerToken(value: String?): Double? = value?.toDoubleOrNull()
}

sealed class OpenRouterClientException(message: String) : Exception(message) {
  object InvalidKey :
    OpenRouterClientException("The OpenRouter key is invalid or has been revoked.")

  object Forbidden :
    OpenRouterClientException("The OpenRouter key or guardrail blocked this request.")

  object InsufficientCredits : OpenRouterClientException(
    "The OpenRouter key has insufficient credits or reached its spending limit.",
  )

  object ModelUnavailable : OpenRouterClientException(
    "The selected OpenRouter model is unavailable for the current privacy settings.",
  )

  object InvalidResponse : OpenRouterClientException("OpenRouter returned an invalid response.")
  object TimedOut : OpenRouterClientException("OpenRouter analysis timed out.")

  class RateLimited(val retryAfterSeconds: Double?) : OpenRouterClientException(
    "OpenRouter is rate limiting requests. Analysis will retry automatically.",
  )

  class TemporarilyUnavailable(val status: Int, val retryAfterSeconds: Double?) :
    OpenRouterClientException("The selected OpenRouter model is temporarily unavailable.")

  class InvalidRequest(val detail: String) : OpenRouterClientException(detail)

  class InvalidOutput(val detail: String) : OpenRouterClientException("Analysis failed.")

  class Transport(val detail: String) : OpenRouterClientException(
    "OpenRouter could not be reached. Analysis will retry automatically.",
  )

  val statusCode: Int?
    get() = when (this) {
      is InvalidKey -> 401
      is InsufficientCredits -> 402
      is Forbidden -> 403
      is RateLimited -> 429
      is TemporarilyUnavailable -> status
      else -> null
    }

  /** Server-supplied backoff, when the failure carried one. */
  val retryAfterHint: Double?
    get() = when (this) {
      is RateLimited -> retryAfterSeconds
      is TemporarilyUnavailable -> retryAfterSeconds
      else -> null
    }

  /** Transient failures are retried on a backoff; everything else parks the queue. */
  val isTransient: Boolean
    get() = this is RateLimited || this is TemporarilyUnavailable ||
      this is Transport || this is TimedOut
}

class OpenRouterClient(
  private val http: OkHttpClient = defaultClient(),
) {
  private val json = Json { ignoreUnknownKeys = true; isLenient = true }

  suspend fun validateKey(apiKey: String): OpenRouterKeyInfo {
    val body = perform("key", "GET", apiKey, null).second
    val root = parseObject(body)
    val data = root["data"]?.jsonObject ?: throw OpenRouterClientException.InvalidResponse
    return runCatching { json.decodeFromJsonElement(OpenRouterKeyInfo.serializer(), data) }
      .getOrNull() ?: throw OpenRouterClientException.InvalidResponse
  }

  suspend fun models(apiKey: String): List<OpenRouterModel> {
    val catalogBody = perform("models/user", "GET", apiKey, null).second
    val zdrBody = perform("endpoints/zdr", "GET", apiKey, null).second
    val catalog = decodeArray(catalogBody, OpenRouterModel.serializer())
    val zdrEndpoints = decodeArray(zdrBody, ZDREndpoint.serializer()).groupBy { it.modelId }

    return catalog.mapNotNull { model ->
      // Only models that can be pinned to the JSON schema are usable at all.
      if (!model.supports("structured_outputs") || !model.supports("response_format")) {
        return@mapNotNull null
      }
      val compatible = zdrEndpoints[model.id].orEmpty().filter { endpoint ->
        val parameters = endpoint.supportedParameters.orEmpty().toSet()
        "structured_outputs" in parameters && "response_format" in parameters
      }
      val common = compatible.drop(1).fold(
        compatible.firstOrNull()?.supportedParameters.orEmpty().toSet(),
      ) { current, endpoint -> current.intersect(endpoint.supportedParameters.orEmpty().toSet()) }
      model.copy(
        hasZDREndpoint = compatible.isNotEmpty(),
        zdrSupportedParameters = if (compatible.isEmpty()) emptyList() else common.sorted(),
      )
    }.sortedWith(
      compareByDescending<OpenRouterModel> { it.isFree }.thenBy { it.name.lowercase() },
    )
  }

  suspend fun analyze(
    analysisRequest: EmailAnalysisRequest,
    model: OpenRouterModel,
    privacyMode: OpenRouterPrivacyMode,
    apiKey: String,
    outputTokenLimit: Int = STANDARD_OUTPUT_TOKEN_LIMIT,
  ): EmailAnalysisEnvelope {
    val prompt = EmailPromptBuilder.build(analysisRequest)
    val routeParameters = (
      if (privacyMode == OpenRouterPrivacyMode.ZDR_ONLY) {
        model.zdrSupportedParameters
      } else {
        model.supportedParameters
      }
      ).toSet()
    val usesReasoning = "reasoning" in routeParameters
    val resolvedOutputLimit =
      resolvedOutputTokenLimit(outputTokenLimit, model.id, usesReasoning)

    val payload = buildJsonObject {
      put("model", model.id)
      putJsonArray("messages") {
        add(
          buildJsonObject {
            put("role", "user")
            put("content", prompt)
          },
        )
      }
      put("stream", false)
      putJsonObject("provider") {
        put("require_parameters", true)
        if (privacyMode == OpenRouterPrivacyMode.ZDR_ONLY) put("zdr", true)
      }
      put("response_format", RESPONSE_FORMAT)
      when {
        "max_tokens" in routeParameters -> put("max_tokens", resolvedOutputLimit)
        "max_completion_tokens" in routeParameters ->
          put("max_completion_tokens", resolvedOutputLimit)
      }
      // Gemini 3.x thinking models are optimized for the default temperature (1.0).
      // Forcing 0 often yields Google 400 "Provider returned error" via OpenRouter.
      if ("temperature" in routeParameters && !isGoogleGeminiModel(model.id)) {
        put("temperature", 0)
      }
      if (usesReasoning) {
        putJsonObject("reasoning") {
          put("effort", "low")
          put("exclude", true)
        }
      }
    }

    val (headers, body) = perform("chat/completions", "POST", apiKey, payload.toString())
    val decoded = runCatching {
      json.decodeFromString(ChatCompletionResponse.serializer(), body)
    }.getOrNull() ?: run {
      Log.e(TAG, "OpenRouter response decoding failed; model=${model.id}")
      throw OpenRouterClientException.InvalidResponse
    }
    val content = decoded.choices.firstOrNull()?.message?.textContent()
    if (content.isNullOrBlank()) {
      Log.e(
        TAG,
        "OpenRouter success response has no text content; requested=${model.id}; " +
          "resolved=${decoded.model ?: "none"}; choices=${decoded.choices.size}",
      )
      throw OpenRouterClientException.InvalidResponse
    }

    return try {
      val result = EmailStructuredOutputValidator.validate(
        response = content,
        request = analysisRequest,
        analyzer = EmailAnalyzerType.OPEN_ROUTER,
      )
      EmailAnalysisEnvelope(
        result = result,
        analyzer = EmailAnalyzerType.OPEN_ROUTER,
        modelId = decoded.model ?: model.id,
        requestId = decoded.id ?: headers,
      )
    } catch (error: Exception) {
      val detail = error.toString()
      Log.e(
        TAG,
        "OpenRouter structured-output validation failed; requested=${model.id}; " +
          "resolved=${decoded.model ?: "none"}; chars=${content.length}; error=$detail",
      )
      throw OpenRouterClientException.InvalidOutput(detail)
    }
  }

  // MARK: - Private

  /** Returns the request id header and the response body. */
  private suspend fun perform(
    path: String,
    method: String,
    apiKey: String,
    body: String?,
  ): Pair<String?, String> = withContext(Dispatchers.IO) {
    val request = Request.Builder()
      .url("$BASE_URL/$path")
      .header("Authorization", "Bearer $apiKey")
      .header("Accept", "application/json")
      .header("X-OpenRouter-Title", "Dimo")
      .apply {
        if (method == "POST") {
          post((body ?: "").toRequestBody(JSON_MEDIA_TYPE))
        } else {
          get()
        }
      }
      .build()

    val response = try {
      http.newCall(request).execute()
    } catch (_: SocketTimeoutException) {
      throw OpenRouterClientException.TimedOut
    } catch (error: IOException) {
      throw OpenRouterClientException.Transport(error.javaClass.simpleName)
    }

    response.use {
      val payload = it.body.string()
      val requestId = it.header("x-request-id") ?: it.header("x-openrouter-request-id")
      if (it.code !in 200..299) {
        Log.e(
          TAG,
          "OpenRouter HTTP failure; path=$path; status=${it.code}; " +
            "requestId=${requestId ?: "none"}; bytes=${payload.length}",
        )
        throw errorFor(it.code, it.header("Retry-After"), payload)
      }
      requestId to payload
    }
  }

  private fun errorFor(status: Int, retryAfterHeader: String?, body: String): Exception {
    val retryAfter = parseRetryAfter(retryAfterHeader)
    val apiMessage = apiErrorDiagnostic(body)
    return when (status) {
      400 -> {
        val normalized = apiMessage.lowercase()
        when {
          normalized.contains("context") -> OpenRouterClientException.InvalidRequest(
            "The selected model context is too small for this email.",
          )

          normalized.contains("no endpoint") ||
            normalized.contains("model not found") ||
            normalized.contains("model is unavailable") -> OpenRouterClientException.ModelUnavailable

          else -> OpenRouterClientException.InvalidRequest(apiMessage)
        }
      }

      401 -> OpenRouterClientException.InvalidKey
      402 -> OpenRouterClientException.InsufficientCredits
      403 -> OpenRouterClientException.Forbidden
      404 -> OpenRouterClientException.ModelUnavailable
      408 -> OpenRouterClientException.TemporarilyUnavailable(408, retryAfter)
      429 -> OpenRouterClientException.RateLimited(retryAfter)
      502, 503 -> OpenRouterClientException.TemporarilyUnavailable(status, retryAfter)
      else -> OpenRouterClientException.InvalidRequest(
        apiMessage.ifEmpty { "OpenRouter rejected this analysis request (HTTP $status)." },
      )
    }
  }

  private fun parseObject(body: String): JsonObject =
    runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
      ?: throw OpenRouterClientException.InvalidResponse

  private fun <T> decodeArray(
    body: String,
    serializer: kotlinx.serialization.KSerializer<T>,
  ): List<T> {
    val data = parseObject(body)["data"] as? JsonArray
      ?: throw OpenRouterClientException.InvalidResponse
    return data.mapNotNull { element ->
      runCatching { json.decodeFromJsonElement(serializer, element) }.getOrNull()
    }
  }

  companion object {
    private const val TAG = "EmailOpenRouter"
    private const val BASE_URL = "https://openrouter.ai/api/v1"
    private val JSON_MEDIA_TYPE = "application/json".toMediaType()

    /**
     * Seeded when a user on the shared free tier has no model picked. Must stay a
     * `:free` model — free-mode selection filters on [OpenRouterModel.isFree].
     */
    const val DEFAULT_FREE_MODEL_ID = "openai/gpt-oss-20b:free"

    /** Seeded when a user saves their own API key and has no model picked. */
    const val DEFAULT_BYOK_MODEL_ID = "openai/gpt-5.6-luna"

    const val STANDARD_OUTPUT_TOKEN_LIMIT = 512
    const val INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT = 2_048

    fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
      .callTimeout(java.time.Duration.ofSeconds(120))
      .readTimeout(java.time.Duration.ofSeconds(90))
      .build()

    /**
     * Gemini 3 thinking shares the completion budget, so 512 is too small; other
     * reasoning models need headroom for the hidden trace plus the JSON object.
     */
    fun resolvedOutputTokenLimit(requested: Int, modelId: String, usesReasoning: Boolean): Int =
      when {
        !usesReasoning -> requested
        isGoogleGeminiModel(modelId) -> maxOf(requested, 4_096)
        else -> maxOf(requested, INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT)
      }

    fun isGoogleGeminiModel(modelId: String): Boolean =
      modelId.lowercase().startsWith("google/gemini")

    /**
     * OpenRouter often wraps upstream failures as "Provider returned error" with the
     * real Google/OpenAI message in `error.metadata.raw`.
     */
    fun apiErrorDiagnostic(body: String): String {
      val fallback = "OpenRouter rejected the selected model or request."
      val root = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
        ?: return body.trim().ifEmpty { fallback }
      val error = root["error"] as? JsonObject
        ?: return body.trim().ifEmpty { fallback }
      val topMessage = (error["message"] as? JsonPrimitive)?.content?.trim()?.ifEmpty { null }
        ?: fallback
      val metadata = error["metadata"] as? JsonObject
      val provider = (metadata?.get("provider_name") as? JsonPrimitive)?.content?.trim()
        ?.ifEmpty { null }
      val rawMessage = extractProviderRawMessage(metadata?.get("raw"))?.trim()?.ifEmpty { null }

      val parts = mutableListOf<String>()
      if (provider != null) parts.add("[$provider]")
      if (rawMessage != null && !rawMessage.equals(topMessage, ignoreCase = true)) {
        parts.add(rawMessage)
      } else {
        parts.add(topMessage)
      }
      return parts.joinToString(" ")
    }

    private fun extractProviderRawMessage(
      raw: kotlinx.serialization.json.JsonElement?,
    ): String? = when (raw) {
      is JsonPrimitive -> if (raw.isString) {
        val nested = runCatching { Json.parseToJsonElement(raw.content) }.getOrNull()
        (nested?.let(::extractProviderRawMessage)) ?: raw.content
      } else {
        null
      }

      is JsonObject -> {
        val error = raw["error"]
        when {
          error is JsonObject -> (error["message"] as? JsonPrimitive)?.content
          error is JsonPrimitive && error.isString -> error.content
          else -> (raw["message"] as? JsonPrimitive)?.content
        }
      }

      else -> null
    }

    fun parseRetryAfter(value: String?, now: Long = System.currentTimeMillis()): Double? {
      if (value == null) return null
      value.toDoubleOrNull()?.let { if (it > 0) return it }
      val date = runCatching {
        ZonedDateTime.parse(
          value,
          DateTimeFormatter.ofPattern("EEE, dd MMM yyyy HH:mm:ss zzz", Locale.US),
        )
      }.getOrNull() ?: return null
      return maxOf(0.0, (date.toInstant().toEpochMilli() - now) / 1000.0)
    }

    // RESPONSE_FORMAT references this value while the companion object is being
    // initialized, so it must be declared first. Kotlin initializes companion
    // properties in source order; declaring it below RESPONSE_FORMAT makes the
    // first OpenRouterClient construction fail with ExceptionInInitializerError.
    private val NULLABLE_STRING: JsonObject = buildJsonObject {
      putJsonArray("type") {
        add(JsonPrimitive("string"))
        add(JsonPrimitive("null"))
      }
    }

    /**
     * Keep Gemini-compatible: Google only allows `enum` on string types, so never
     * put `enum` on integers or mixed null enums here.
     */
    val RESPONSE_FORMAT: JsonObject = buildJsonObject {
      put("type", "json_schema")
      putJsonObject("json_schema") {
        put("name", "email_analysis")
        put("strict", true)
        putJsonObject("schema") {
          put("type", "object")
          put("additionalProperties", false)
          putJsonArray("required") {
            listOf(
              "schemaVersion", "kind", "merchant", "amount", "currency", "occurredAt",
              "categoryId", "paymentMethodId", "paymentLastFour", "reference",
            ).forEach { add(JsonPrimitive(it)) }
          }
          putJsonObject("properties") {
            // Client still rejects anything other than schemaVersion == 1.
            putJsonObject("schemaVersion") { put("type", "integer") }
            putJsonObject("kind") {
              put("type", "string")
              putJsonArray("enum") {
                listOf("purchase", "debit", "refund", "irrelevant")
                  .forEach { add(JsonPrimitive(it)) }
              }
            }
            // Currency membership is validated in EmailStructuredOutputValidator.
            listOf(
              "merchant", "amount", "currency", "occurredAt", "categoryId",
              "paymentMethodId", "paymentLastFour", "reference",
            ).forEach { key -> put(key, NULLABLE_STRING) }
          }
        }
      }
    }

  }
}

@Serializable
private data class ZDREndpoint(
  @SerialName("model_id") val modelId: String,
  @SerialName("supported_parameters") val supportedParameters: List<String>? = null,
)

@Serializable
private data class ChatCompletionResponse(
  val id: String? = null,
  val model: String? = null,
  val choices: List<Choice> = emptyList(),
) {
  @Serializable
  data class Choice(val message: Message)

  @Serializable
  data class Message(
    val content: kotlinx.serialization.json.JsonElement? = null,
  ) {
    /** Content is either a plain string or an array of typed parts. */
    fun textContent(): String? = when (val value = content) {
      null -> null
      is JsonPrimitive -> if (value.isString) value.content else null
      is JsonArray -> value.mapNotNull { part ->
        (part as? JsonObject)?.get("text")?.jsonPrimitive?.content
      }.joinToString("")

      else -> null
    }
  }
}
