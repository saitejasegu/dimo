package app.dimo.android.email.openrouter

import app.dimo.android.auth.WorkOSSession
import app.dimo.android.data.model.OpenRouterPrivacyMode
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

/**
 * Port of `ios-native/Dimo/Email/OpenRouter/OpenRouterConvexTransport.swift`.
 *
 * Authenticated Convex proxy for the shared free-model OpenRouter key. The key
 * itself never reaches the device in Free mode; only the prompt and the model id
 * cross this boundary.
 */
data class OpenRouterConvexAnalyzeResult(
  val content: String,
  val modelId: String,
  val requestId: String? = null,
)

interface OpenRouterConvexTransporting {
  suspend fun listFreeModels(): List<OpenRouterModel>

  suspend fun analyzeEmail(
    modelId: String,
    privacyMode: OpenRouterPrivacyMode,
    prompt: String,
    outputTokenLimit: Int,
  ): OpenRouterConvexAnalyzeResult
}

sealed class OpenRouterConvexTransportException(message: String) : Exception(message) {
  object NotReady : OpenRouterConvexTransportException(
    "Free OpenRouter analysis needs an online Dimo sync session.",
  )

  class Remote(val detail: String) : OpenRouterConvexTransportException(detail)

  /**
   * Maps a Convex action failure onto the client error the retry policy already
   * understands, so Free and BYOK modes back off identically.
   */
  fun asClientException(): OpenRouterClientException = when (this) {
    is NotReady -> OpenRouterClientException.Transport("convex-not-ready")
    is Remote -> {
      val lowered = detail.lowercase()
      when {
        lowered.contains("rate limit") ->
          OpenRouterClientException.RateLimited(parseRetrySeconds(detail))

        lowered.contains("insufficient") || lowered.contains("credits") ->
          OpenRouterClientException.InsufficientCredits

        lowered.contains("unavailable") || lowered.contains("no zero-data-retention") ->
          OpenRouterClientException.ModelUnavailable

        lowered.contains("timed out") || lowered.contains("timeout") ->
          OpenRouterClientException.TimedOut

        lowered.contains("could not be reached") || lowered.contains("network") ->
          OpenRouterClientException.Transport(detail)

        else -> OpenRouterClientException.InvalidRequest(detail)
      }
    }
  }

  private companion object {
    val RETRY_SECONDS = Regex("Retry in (\\d+) seconds")

    fun parseRetrySeconds(message: String): Double? =
      RETRY_SECONDS.find(message)?.groupValues?.get(1)?.toDoubleOrNull()
  }
}

class OpenRouterConvexTransport(
  private val client: ConvexClientWithAuth<WorkOSSession>,
) : OpenRouterConvexTransporting {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun listFreeModels(): List<OpenRouterModel> = try {
    val rows: JsonArray = withTimeout(TIMEOUT_MS) {
      client.action<JsonArray>("openRouter:listFreeModels", emptyMap())
    }
    rows.mapNotNull { element ->
      runCatching {
        json.decodeFromJsonElement(OpenRouterFreeModelWire.serializer(), element)
      }.getOrNull()?.asModel()
    }
  } catch (error: Exception) {
    throw OpenRouterConvexTransportException.Remote(error.message ?: "OpenRouter is unavailable.")
  }

  override suspend fun analyzeEmail(
    modelId: String,
    privacyMode: OpenRouterPrivacyMode,
    prompt: String,
    outputTokenLimit: Int,
  ): OpenRouterConvexAnalyzeResult = try {
    val result: JsonObject = withTimeout(TIMEOUT_MS) {
      client.action<JsonObject>(
        "openRouter:analyzeEmail",
        mapOf(
          "modelId" to modelId,
          "privacyMode" to privacyMode.wire,
          "prompt" to prompt,
          // Convex `v.number()` requires a floating encoding.
          "outputTokenLimit" to outputTokenLimit.toDouble(),
        ),
      )
    }
    val wire = runCatching {
      json.decodeFromJsonElement(OpenRouterConvexAnalyzeWire.serializer(), result)
    }.getOrNull() ?: throw OpenRouterClientException.InvalidResponse
    OpenRouterConvexAnalyzeResult(wire.content, wire.modelId, wire.requestId)
  } catch (error: OpenRouterClientException) {
    throw error
  } catch (error: Exception) {
    throw OpenRouterConvexTransportException.Remote(error.message ?: "OpenRouter is unavailable.")
  }

  private companion object {
    const val TIMEOUT_MS = 120_000L
  }
}

@Serializable
private data class OpenRouterConvexAnalyzeWire(
  val content: String,
  val modelId: String,
  val requestId: String? = null,
)

@Serializable
private data class OpenRouterFreeModelWire(
  val id: String,
  val name: String,
  val contextLength: Int = 0,
  val pricing: OpenRouterModel.Pricing = OpenRouterModel.Pricing(),
  val supportedParameters: List<String> = emptyList(),
  val hasZDREndpoint: Boolean = false,
  val zdrSupportedParameters: List<String> = emptyList(),
) {
  fun asModel() = OpenRouterModel(
    id = id,
    name = name,
    contextLength = contextLength,
    pricing = pricing,
    supportedParameters = supportedParameters,
    hasZDREndpoint = hasZDREndpoint,
    zdrSupportedParameters = zdrSupportedParameters,
  )
}
