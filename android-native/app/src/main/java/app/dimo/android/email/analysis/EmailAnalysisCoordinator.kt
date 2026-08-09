package app.dimo.android.email.analysis

import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.email.domain.EmailAnalysisEnvelope
import app.dimo.android.email.domain.EmailAnalysisProviding
import app.dimo.android.email.domain.EmailAnalysisRequest
import app.dimo.android.email.domain.EmailAnalyzerType
import app.dimo.android.email.openrouter.OpenRouterClient
import app.dimo.android.email.openrouter.OpenRouterClientException
import app.dimo.android.email.openrouter.OpenRouterConvexTransportException
import app.dimo.android.email.openrouter.OpenRouterConvexTransporting
import app.dimo.android.email.openrouter.OpenRouterModel
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Port of `ios-native/Dimo/Email/Analysis/EmailAnalysisCoordinator.swift`. */

/** BYOK analyzer: the key stays on device and talks to OpenRouter directly. */
class OpenRouterEmailAnalyzer(
  private val client: OpenRouterClient,
  private val model: OpenRouterModel,
  private val privacyMode: OpenRouterPrivacyMode,
  private val apiKey: String,
) : EmailAnalysisProviding {
  override suspend fun analyze(request: EmailAnalysisRequest): EmailAnalysisEnvelope = try {
    client.analyze(request, model, privacyMode, apiKey)
  } catch (error: OpenRouterClientException.InvalidOutput) {
    // A truncated object is worth one retry with a bigger budget; any other
    // validation failure is a real rejection.
    if (error.detail.contains("incomplete", ignoreCase = true)) {
      client.analyze(
        request,
        model,
        privacyMode,
        apiKey,
        OpenRouterClient.INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT,
      )
    } else {
      throw error
    }
  }
}

/** Free-mode analyzer: prompt + validation stay on-device; completions go through Convex. */
class ConvexFreeOpenRouterEmailAnalyzer(
  private val transport: OpenRouterConvexTransporting,
  private val model: OpenRouterModel,
  private val privacyMode: OpenRouterPrivacyMode,
) : EmailAnalysisProviding {
  override suspend fun analyze(request: EmailAnalysisRequest): EmailAnalysisEnvelope {
    val prompt = EmailPromptBuilder.build(request)
    return try {
      complete(request, prompt, OpenRouterClient.STANDARD_OUTPUT_TOKEN_LIMIT)
    } catch (error: OpenRouterClientException.InvalidOutput) {
      if (error.detail.contains("incomplete", ignoreCase = true)) {
        complete(request, prompt, OpenRouterClient.INCOMPLETE_OUTPUT_RETRY_TOKEN_LIMIT)
      } else {
        throw error
      }
    }
  }

  private suspend fun complete(
    request: EmailAnalysisRequest,
    prompt: String,
    outputTokenLimit: Int,
  ): EmailAnalysisEnvelope {
    val remote = try {
      transport.analyzeEmail(model.id, privacyMode, prompt, outputTokenLimit)
    } catch (error: OpenRouterConvexTransportException) {
      throw error.asClientException()
    }

    return try {
      val result = EmailStructuredOutputValidator.validate(
        response = remote.content,
        request = request,
        analyzer = EmailAnalyzerType.OPEN_ROUTER,
      )
      EmailAnalysisEnvelope(
        result = result,
        analyzer = EmailAnalyzerType.OPEN_ROUTER,
        modelId = remote.modelId,
        requestId = remote.requestId,
      )
    } catch (error: Exception) {
      throw OpenRouterClientException.InvalidOutput(error.toString())
    }
  }
}

/** Holds the analyzer currently configured for each provider. */
class EmailAnalysisCoordinator {
  private val providers = ConcurrentHashMap<EmailAnalysisProvider, EmailAnalysisProviding>()

  fun set(analyzer: EmailAnalysisProviding?, provider: EmailAnalysisProvider) {
    if (analyzer == null) providers.remove(provider) else providers[provider] = analyzer
  }

  suspend fun analyze(
    request: EmailAnalysisRequest,
    provider: EmailAnalysisProvider,
  ): EmailAnalysisEnvelope {
    val analyzer = providers[provider]
      ?: throw EmailAnalysisCoordinatorException("OpenRouter is not configured.")
    return analyzer.analyze(request)
  }

  fun removeAll() = providers.clear()
}

class EmailAnalysisCoordinatorException(message: String) : Exception(message)

/**
 * Reserves process-wide start times across every OpenRouter analysis path.
 *
 * Reserving *before* sleeping is the point: two callers that both check "has 3s
 * elapsed?" would otherwise wake up together and fire simultaneously.
 */
object EmailAnalysisStartThrottle {
  /** Three seconds keeps requests sequential while allowing up to 20 starts per minute. */
  const val MINIMUM_START_INTERVAL_MS = 3_000L

  private val mutex = Mutex()
  private var nextStart: Long = 0

  suspend fun waitForNextStart(minimumIntervalMs: Long = MINIMUM_START_INTERVAL_MS) {
    val waitFor = mutex.withLock {
      val now = System.currentTimeMillis()
      val scheduledStart = if (nextStart > now) nextStart else now
      nextStart = scheduledStart + minimumIntervalMs
      scheduledStart - now
    }
    if (waitFor > 0) kotlinx.coroutines.delay(waitFor)
  }

  /** Test hook: forgets the reserved slot so cases do not wait on each other. */
  suspend fun reset() = mutex.withLock { nextStart = 0 }
}
