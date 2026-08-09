package app.dimo.android.email.gmail

import java.util.UUID
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlin.coroutines.coroutineContext

/**
 * Port of `ios-native/Dimo/Email/Gmail/GmailAPIClient.swift`.
 *
 * Only read paths exist. Message fetches go through Gmail's multipart batch
 * endpoint 20 at a time with pacing between batches, because per-message GETs
 * exhaust the per-user quota on any real inbox.
 */

@Serializable
data class GmailMessageReference(
  val id: String,
  val threadId: String? = null,
)

data class GmailMessageListPage(
  val messages: List<GmailMessageReference>,
  val nextPageToken: String?,
)

data class GmailHistoryPage(
  val addedMessageIds: List<String>,
  val latestHistoryId: String,
  val nextPageToken: String?,
)

@Serializable
data class GmailProfile(
  val emailAddress: String,
  val historyId: String,
)

@Serializable
data class GmailMessageHeader(
  val name: String,
  val value: String,
)

@Serializable
data class GmailMessageBody(
  val attachmentId: String? = null,
  val size: Int? = null,
  val data: String? = null,
)

@Serializable
data class GmailMessagePart(
  val partId: String? = null,
  val mimeType: String? = null,
  val filename: String? = null,
  val headers: List<GmailMessageHeader>? = null,
  val body: GmailMessageBody? = null,
  val parts: List<GmailMessagePart>? = null,
)

@Serializable
data class GmailMessageResource(
  val id: String,
  val threadId: String,
  val labelIds: List<String>? = null,
  val snippet: String? = null,
  val historyId: String? = null,
  val internalDate: String,
  val payload: GmailMessagePart? = null,
)

interface GmailAPIClient {
  suspend fun listMessages(
    subject: String,
    dimoUserId: String,
    since: Long,
    pageToken: String?,
  ): GmailMessageListPage

  suspend fun getMessages(
    subject: String,
    dimoUserId: String,
    ids: List<String>,
  ): List<GmailMessageResource>

  /**
   * Fetches a MIME part body Gmail returned as `attachmentId` instead of inline
   * `data` (common for larger text/html bodies even without a file).
   */
  suspend fun getAttachmentData(
    subject: String,
    dimoUserId: String,
    messageId: String,
    attachmentId: String,
  ): ByteArray

  suspend fun listHistory(
    subject: String,
    dimoUserId: String,
    startHistoryId: String,
    pageToken: String?,
  ): GmailHistoryPage

  suspend fun profile(subject: String, dimoUserId: String): GmailProfile
}

class GmailRESTClient(
  private val tokenProvider: GmailAccessTokenProviding,
  private val http: OkHttpClient = GmailHttp.client,
) : GmailAPIClient {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun listMessages(
    subject: String,
    dimoUserId: String,
    since: Long,
    pageToken: String?,
  ): GmailMessageListPage {
    val url = endpoint("users/me/messages") {
      addQueryParameter("q", "after:${since / 1000} -in:spam -in:trash")
      addQueryParameter("includeSpamTrash", "false")
      addQueryParameter("maxResults", "100")
      if (pageToken != null) addQueryParameter("pageToken", pageToken)
    }
    val body = authorizedGet(url, subject, dimoUserId)
    val response = decode<GmailMessageListResponse>(body)
    return GmailMessageListPage(response.messages.orEmpty(), response.nextPageToken)
  }

  override suspend fun getMessages(
    subject: String,
    dimoUserId: String,
    ids: List<String>,
  ): List<GmailMessageResource> {
    val messages = mutableListOf<GmailMessageResource>()
    val batches = ids.distinct().chunked(MESSAGE_BATCH_SIZE)
    batches.forEachIndexed { index, batch ->
      coroutineContext.ensureActive()
      var rateLimitAttempt = 0
      while (true) {
        try {
          messages += getMessageBatch(subject, dimoUserId, batch)
          break
        } catch (error: GmailAPIException.RateLimited) {
          if (rateLimitAttempt >= MAX_RATE_LIMIT_RETRIES) throw error
          waitForRateLimit(error.retryAfterSeconds, rateLimitAttempt)
          rateLimitAttempt += 1
        }
      }
      if (index < batches.size - 1) delay(BATCH_PACING_MS)
    }
    return messages
  }

  override suspend fun listHistory(
    subject: String,
    dimoUserId: String,
    startHistoryId: String,
    pageToken: String?,
  ): GmailHistoryPage {
    val url = endpoint("users/me/history") {
      addQueryParameter("startHistoryId", startHistoryId)
      addQueryParameter("historyTypes", "messageAdded")
      addQueryParameter("maxResults", "100")
      if (pageToken != null) addQueryParameter("pageToken", pageToken)
    }
    val body = try {
      authorizedGet(url, subject, dimoUserId)
    } catch (error: GmailAPIException.HttpStatus) {
      // Gmail drops history older than about a week; the caller must re-scan.
      if (error.status == 404) throw GmailAPIException.HistoryCursorExpired else throw error
    }
    val response = decode<GmailHistoryListResponse>(body)
    val ids = response.history.orEmpty()
      .flatMap { it.messagesAdded.orEmpty() }
      .map { it.message.id }
      .distinct()
    return GmailHistoryPage(ids, response.historyId, response.nextPageToken)
  }

  override suspend fun profile(subject: String, dimoUserId: String): GmailProfile =
    decode(authorizedGet(endpoint("users/me/profile") {}, subject, dimoUserId))

  override suspend fun getAttachmentData(
    subject: String,
    dimoUserId: String,
    messageId: String,
    attachmentId: String,
  ): ByteArray {
    val url = API_BASE.toHttpUrl().newBuilder()
      .addPathSegments("users/me/messages")
      .addPathSegment(messageId)
      .addPathSegment("attachments")
      .addPathSegment(attachmentId)
      .build()
      .toString()
    val response = decode<GmailAttachmentResponse>(authorizedGet(url, subject, dimoUserId))
    return response.data?.let { GmailMessageParser.decodeBase64Url(it) }
      ?: throw GmailAPIException.InvalidResponse
  }

  // MARK: - Private

  private suspend fun getMessageBatch(
    subject: String,
    dimoUserId: String,
    ids: List<String>,
    retriedAfterAuthentication: Boolean = false,
  ): List<GmailMessageResource> {
    if (ids.isEmpty()) return emptyList()
    val boundary = "dimo_email_" + UUID.randomUUID().toString().replace("-", "")
    // Built byte-for-byte: a stray newline before a MIME boundary makes Gmail
    // reject the whole batch.
    val body = buildString {
      for (id in ids) {
        append("--").append(boundary).append("\r\n")
        append("Content-Type: application/http\r\n")
        append("\r\n")
        append("GET /gmail/v1/users/me/messages/").append(id).append("?format=full HTTP/1.1\r\n")
        append("\r\n")
      }
      append("--").append(boundary).append("--\r\n")
    }

    val token = tokenProvider.accessToken(subject, dimoUserId, retriedAfterAuthentication)
    val mediaType = "multipart/mixed; boundary=$boundary".toMediaType()
    val request = Request.Builder()
      .url(BATCH_URL)
      .post(body.toByteArray(Charsets.UTF_8).toRequestBody(mediaType))
      .header("Authorization", "Bearer ${token.value}")
      .build()

    val (status, contentType, payload) = withContext(Dispatchers.IO) {
      http.newCall(request).execute().use { response ->
        Triple(
          response.code,
          response.header("Content-Type"),
          response.body.string(),
        )
      }
    }
    if (status == 401 && !retriedAfterAuthentication) {
      tokenProvider.invalidate(subject)
      return getMessageBatch(subject, dimoUserId, ids, retriedAfterAuthentication = true)
    }
    validate(status, payload, retryAfterHeader = null)
    if (contentType == null) throw GmailAPIException.InvalidBatchResponse
    return try {
      GmailBatchResponseParser.decodeMessages(payload, contentType, json)
    } catch (error: GmailAPIException.HttpStatus) {
      if (error.status == 401 && !retriedAfterAuthentication) {
        tokenProvider.invalidate(subject)
        getMessageBatch(subject, dimoUserId, ids, retriedAfterAuthentication = true)
      } else {
        throw error
      }
    }
  }

  private suspend fun authorizedGet(
    url: String,
    subject: String,
    dimoUserId: String,
    retriedAfterAuthentication: Boolean = false,
    rateLimitAttempt: Int = 0,
  ): String {
    val token = tokenProvider.accessToken(subject, dimoUserId, retriedAfterAuthentication)
    val request = Request.Builder()
      .url(url)
      .header("Authorization", "Bearer ${token.value}")
      .build()
    val (status, retryAfter, body) = withContext(Dispatchers.IO) {
      http.newCall(request).execute().use { response ->
        Triple(
          response.code,
          response.header("Retry-After")?.toDoubleOrNull(),
          response.body.string(),
        )
      }
    }
    if (status == 401 && !retriedAfterAuthentication) {
      tokenProvider.invalidate(subject)
      return authorizedGet(url, subject, dimoUserId, true, rateLimitAttempt)
    }
    try {
      validate(status, body, retryAfter)
    } catch (error: GmailAPIException.RateLimited) {
      if (rateLimitAttempt >= MAX_RATE_LIMIT_RETRIES) throw error
      waitForRateLimit(error.retryAfterSeconds, rateLimitAttempt)
      return authorizedGet(
        url,
        subject,
        dimoUserId,
        retriedAfterAuthentication,
        rateLimitAttempt + 1,
      )
    }
    return body
  }

  private suspend fun waitForRateLimit(retryAfterSeconds: Double?, attempt: Int) {
    val exponential = min(32.0, 2.0.pow(attempt))
    val requested = retryAfterSeconds?.coerceIn(1.0, 60.0)
    // Jitter only when the server did not name a delay, so a fleet of clients
    // does not retry in lockstep.
    val jitter = if (retryAfterSeconds == null) Random.nextDouble(0.0, 0.75) else 0.0
    delay(((requested ?: exponential) + jitter).times(1000).toLong())
  }

  private fun endpoint(path: String, build: okhttp3.HttpUrl.Builder.() -> Unit): String =
    API_BASE.toHttpUrl().newBuilder().addPathSegments(path).apply(build).build().toString()

  private fun validate(status: Int, body: String, retryAfterHeader: Double?) {
    if (status in 200..299) return
    if (status == 429) throw GmailAPIException.RateLimited(retryAfterHeader)
    val envelope = runCatching { json.decodeFromString<GmailErrorEnvelope>(body) }.getOrNull()
    val reasons = envelope?.error?.errors.orEmpty().mapNotNull { it.reason }
    // Gmail reports quota exhaustion as 403 with a reason, not as 429.
    if (status == 403 && reasons.any(::isRateLimitReason)) {
      throw GmailAPIException.RateLimited(retryAfterHeader)
    }
    throw GmailAPIException.HttpStatus(status, envelope?.error?.message)
  }

  private fun isRateLimitReason(reason: String): Boolean = when (reason.lowercase()) {
    "ratelimitexceeded", "userratelimitexceeded", "quotaexceeded" -> true
    else -> false
  }

  private inline fun <reified T> decode(body: String): T =
    runCatching { json.decodeFromString<T>(body) }.getOrNull()
      ?: throw GmailAPIException.InvalidResponse

  private companion object {
    const val API_BASE = "https://gmail.googleapis.com/gmail/v1"
    const val BATCH_URL = "https://gmail.googleapis.com/batch/gmail/v1"
    const val MESSAGE_BATCH_SIZE = 20
    const val BATCH_PACING_MS = 1_500L
    const val MAX_RATE_LIMIT_RETRIES = 6
  }
}

@Serializable
private data class GmailAttachmentResponse(
  val size: Int? = null,
  val data: String? = null,
)

@Serializable
private data class GmailMessageListResponse(
  val messages: List<GmailMessageReference>? = null,
  val nextPageToken: String? = null,
)

@Serializable
private data class GmailHistoryListResponse(
  val history: List<History>? = null,
  val nextPageToken: String? = null,
  val historyId: String,
) {
  @Serializable
  data class History(val messagesAdded: List<Added>? = null)

  @Serializable
  data class Added(val message: GmailMessageReference)
}

@Serializable
private data class GmailErrorEnvelope(val error: Body) {
  @Serializable
  data class Body(
    val message: String? = null,
    val errors: List<Detail>? = null,
  )

  @Serializable
  data class Detail(val reason: String? = null)
}

/** Splits Gmail's `multipart/mixed` batch response into the individual JSON bodies. */
internal object GmailBatchResponseParser {
  fun decodeMessages(
    response: String,
    contentType: String,
    json: Json,
  ): List<GmailMessageResource> {
    val boundary = boundary(contentType) ?: throw GmailAPIException.InvalidBatchResponse
    val messages = mutableListOf<GmailMessageResource>()
    for (rawPart in response.split("--$boundary")) {
      val part = rawPart.trim()
      if (part.isEmpty() || part == "--") continue
      val statusMatch = STATUS_LINE.find(part) ?: throw GmailAPIException.InvalidBatchResponse
      val status = statusMatch.groupValues[1].toIntOrNull()
        ?: throw GmailAPIException.InvalidBatchResponse
      // Deleted between list and get; not an error for this sync.
      if (status == 404) continue
      if (status == 429) throw GmailAPIException.RateLimited(null)
      if (status == 403) {
        val normalized = part.lowercase()
        if (normalized.contains("ratelimitexceeded") ||
          normalized.contains("userratelimitexceeded") ||
          normalized.contains("quotaexceeded")
        ) {
          throw GmailAPIException.RateLimited(null)
        }
      }
      if (status !in 200..299) throw GmailAPIException.HttpStatus(status, null)

      val afterStatus = part.substring(statusMatch.range.last + 1)
      val headerEnd = afterStatus.indexOf("\r\n\r\n").takeIf { it >= 0 }?.let { it + 4 }
        ?: afterStatus.indexOf("\n\n").takeIf { it >= 0 }?.let { it + 2 }
        ?: throw GmailAPIException.InvalidBatchResponse
      val body = afterStatus.substring(headerEnd).trim()
      messages += runCatching { json.decodeFromString<GmailMessageResource>(body) }.getOrNull()
        ?: throw GmailAPIException.InvalidBatchResponse
    }
    return messages
  }

  private fun boundary(contentType: String): String? {
    for (component in contentType.split(";").drop(1)) {
      val pieces = component.split("=", limit = 2)
      if (pieces.size != 2) continue
      if (pieces[0].trim().lowercase() != "boundary") continue
      return pieces[1].trim().trim('"', ' ', '\t')
    }
    return null
  }

  private val STATUS_LINE = Regex("HTTP/(?:1\\.1|2)\\s+(\\d{3})")
}

sealed class GmailAPIException(message: String) : Exception(message) {
  object InvalidRequest : GmailAPIException("The Gmail API request was invalid.")
  object InvalidResponse : GmailAPIException("Gmail returned an invalid response.")
  object InvalidBatchResponse : GmailAPIException("Gmail returned an invalid batch response.")
  object HistoryCursorExpired :
    GmailAPIException("Gmail history expired; a new email scan is required.")

  class RateLimited(val retryAfterSeconds: Double?) :
    GmailAPIException("Gmail temporarily limited requests.")

  class HttpStatus(val status: Int, val detail: String?) : GmailAPIException(
    if (detail != null) "Gmail returned HTTP $status: $detail" else "Gmail returned HTTP $status.",
  )
}
