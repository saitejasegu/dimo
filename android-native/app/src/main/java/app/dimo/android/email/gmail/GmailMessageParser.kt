package app.dimo.android.email.gmail

import android.util.Base64
import java.text.Normalizer

/**
 * Port of `ios-native/Dimo/Email/Gmail/GmailMessageParser.swift`.
 *
 * Turns a Gmail message resource into the normalized plain text the analyzer
 * sees. Merchant mail is adversarially messy — HTML masquerading as `text/plain`,
 * "view in browser" stubs, CSS dumped into the body — so body selection is
 * evidence-based rather than trusting the declared MIME type.
 */
data class ParsedGmailMessage(
  val gmailMessageId: String,
  val gmailThreadId: String,
  val rfcMessageId: String?,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBody: String,
)

object GmailMessageParser {
  /**
   * Attachment IDs for text body parts Gmail omitted from the message payload.
   * Large `text/plain` / `text/html` parts often come back with only `attachmentId`.
   */
  fun unresolvedBodyAttachmentIds(message: GmailMessageResource): List<String> {
    val ids = mutableListOf<String>()
    collectBodyParts(message.payload) { _, body ->
      val attachmentId = body.attachmentId?.trim()
      if (!attachmentId.isNullOrEmpty() && body.data.isNullOrEmpty()) ids.add(attachmentId)
    }
    return ids.distinct()
  }

  fun parse(
    message: GmailMessageResource,
    resolvedBodies: Map<String, ByteArray> = emptyMap(),
  ): ParsedGmailMessage {
    val headers = message.payload?.headers.orEmpty()
    val sender = parseSender(header(headers, "From").orEmpty())
    val subject = decodeHeaderValue(header(headers, "Subject").orEmpty())
    val rfcMessageId = header(headers, "Message-ID") ?: header(headers, "Message-Id")
    val milliseconds = message.internalDate.toLongOrNull()
      ?: throw GmailMessageParserException("The Gmail message date is invalid.")

    val body = selectedBody(message.payload, resolvedBodies) ?: message.snippet.orEmpty()
    return ParsedGmailMessage(
      gmailMessageId = message.id,
      gmailThreadId = message.threadId,
      rfcMessageId = rfcMessageId?.trim(),
      senderName = sender.first,
      senderAddress = sender.second,
      subject = subject,
      snippet = normalizePlainText(message.snippet.orEmpty()),
      internalDate = milliseconds,
      normalizedBody = extractReadableText(body),
    )
  }

  /** Converts HTML/markup into readable plain text for storage and analysis. */
  fun extractReadableText(raw: String): String {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return ""
    return if (looksLikeHtml(trimmed)) sanitizeHtml(trimmed) else normalizePlainText(trimmed)
  }

  fun sanitizeHtml(html: String): String {
    var value = html
    // Drop comments and non-content blocks, including unclosed style/script tails.
    value = NON_CONTENT_BLOCKS.replace(value, " ")
    value = LINE_BREAK_TAGS.replace(value, "\n")
    value = CELL_END_TAGS.replace(value, "\t")
    value = ANY_TAG.replace(value, " ")
    value = decodeHtmlEntities(value)
    value = stripCssLikeNoise(value)
    return normalizePlainText(value)
  }

  fun normalizePlainText(text: String): String {
    var value = Normalizer.normalize(text, Normalizer.Form.NFC)
      .replace(" ", " ")
      .replace("\r\n", "\n")
      .replace("\r", "\n")
    // Keep newline and tab; drop every other control character.
    value = value.filter { it == '\n' || it == '\t' || !it.isISOControl() }
    value = HORIZONTAL_SPACE.replace(value, " ")
    value = PADDED_NEWLINE.replace(value, "\n")
    value = EXCESS_NEWLINES.replace(value, "\n\n")
    return value.trim()
  }

  fun decodeBase64Url(encoded: String): ByteArray? = runCatching {
    Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
  }.getOrNull()

  // MARK: - Body selection

  private fun selectedBody(
    root: GmailMessagePart?,
    resolvedBodies: Map<String, ByteArray>,
  ): String? {
    val plainParts = mutableListOf<String>()
    val htmlParts = mutableListOf<String>()
    collectBodyParts(root) { mimeType, body ->
      val text = decodeBodyText(body, resolvedBodies) ?: return@collectBodyParts
      when (mimeType) {
        "text/plain" -> plainParts.add(text)
        "text/html" -> htmlParts.add(text)
      }
    }
    return preferredReadableBody(
      plainRaw = plainParts.joinToString("\n\n"),
      htmlRaw = htmlParts.joinToString("\n\n"),
    )
  }

  private fun preferredReadableBody(plainRaw: String, htmlRaw: String): String? {
    val plainText = plainRaw.takeIf { it.isNotEmpty() }?.let { extractReadableText(it).nilIfBlank() }
    val htmlText = htmlRaw.takeIf { it.isNotEmpty() }?.let { sanitizeHtml(it).nilIfBlank() }
    if (plainText == null) return htmlText
    if (htmlText == null) return plainText
    // Decide from the raw MIME parts: merchant "plain" is often HTML source or a
    // short "view in browser" stub.
    if (looksLikeHtml(plainRaw) || looksLikeMarkupHeavy(plainRaw) || isHtmlViewerStub(plainRaw)) {
      return htmlText
    }
    if (plainText.length < 48 && htmlText.length > maxOf(96, plainText.length * 3)) {
      return htmlText
    }
    return plainText
  }

  private fun looksLikeHtml(text: String): Boolean {
    val sample = text.take(8_000).lowercase()
    val markers = listOf(
      "<html", "<!doctype", "<body", "<div", "<table", "<span", "<br", "<p ", "<p>",
    )
    if (markers.any { sample.contains(it) }) return true
    return OPEN_TAG.findAll(sample).take(4).count() >= 4
  }

  private fun looksLikeMarkupHeavy(text: String): Boolean {
    val sample = text.take(4_000)
    if (sample.length < 40) return false
    val angles = sample.count { it == '<' || it == '>' }
    val braces = sample.count { it == '{' || it == '}' }
    return angles.toDouble() / sample.length > 0.04 || braces.toDouble() / sample.length > 0.05
  }

  private fun isHtmlViewerStub(text: String): Boolean {
    if (text.length >= 280) return false
    val lower = text.lowercase()
    return VIEWER_STUB_HINTS.any { lower.contains(it) }
  }

  private fun stripCssLikeNoise(text: String): String =
    text.split("\n").filter { line ->
      val trimmed = line.trim()
      when {
        trimmed.isEmpty() -> true
        trimmed == "{" || trimmed == "}" -> false
        trimmed.endsWith("{") -> false
        trimmed.contains("{") && trimmed.contains("}") -> false
        // Compact CSS declarations: font-size:14px;color:#333;
        trimmed.contains(":") && trimmed.contains(";") &&
          CSS_DECLARATION.containsMatchIn(trimmed) &&
          trimmed.split(WHITESPACE).size <= 4 -> false
        else -> true
      }
    }.joinToString("\n")

  private fun collectBodyParts(
    root: GmailMessagePart?,
    visit: (mimeType: String, body: GmailMessageBody) -> Unit,
  ) {
    if (root == null) return

    fun walk(part: GmailMessagePart) {
      // Skip real file attachments (non-empty filename). Large inline text/html
      // bodies often use attachmentId with an empty filename and must be kept.
      if (!part.filename.orEmpty().trim().isEmpty()) return
      val mimeType = part.mimeType.orEmpty().lowercase()
      part.body?.let { body ->
        when {
          mimeType.startsWith("text/plain") -> visit("text/plain", body)
          mimeType.startsWith("text/html") -> visit("text/html", body)
        }
      }
      part.parts.orEmpty().forEach(::walk)
    }

    walk(root)
  }

  private fun decodeBodyText(
    body: GmailMessageBody,
    resolvedBodies: Map<String, ByteArray>,
  ): String? {
    body.data?.takeIf { it.isNotEmpty() }?.let { encoded ->
      decodeBase64Url(encoded)?.let { data -> decodeText(data)?.let { return it } }
    }
    body.attachmentId?.trim()?.takeIf { it.isNotEmpty() }?.let { attachmentId ->
      resolvedBodies[attachmentId]?.let { data -> decodeText(data)?.let { return it } }
    }
    return null
  }

  private fun header(headers: List<GmailMessageHeader>, name: String): String? =
    headers.firstOrNull { it.name.equals(name, ignoreCase = true) }?.value

  /** UTF-8 with a Latin-1 fallback, matching the Swift decoder chain. */
  private fun decodeText(data: ByteArray): String? =
    runCatching { data.toString(Charsets.UTF_8) }.getOrNull()
      ?: runCatching { data.toString(Charsets.ISO_8859_1) }.getOrNull()

  private fun parseSender(rawValue: String): Pair<String?, String> {
    val decoded = decodeHeaderValue(rawValue).trim()
    val start = decoded.lastIndexOf('<')
    val end = if (start >= 0) decoded.indexOf('>', start) else -1
    if (start >= 0 && end > start) {
      val address = decoded.substring(start + 1, end).trim().lowercase()
      val rawName = decoded.substring(0, start).trim().trim('"')
      return (rawName.takeIf { it.isNotEmpty() }) to address
    }
    ADDRESS_PATTERN.find(decoded)?.let { return null to it.value.lowercase() }
    return null to decoded.lowercase()
  }

  /** Decodes the common single-part RFC 2047 forms used by merchant senders. */
  private fun decodeHeaderValue(value: String): String {
    var result = value
    for (match in RFC2047.findAll(value).toList().asReversed()) {
      val encoding = match.groupValues[2].lowercase()
      val payload = match.groupValues[3]
      val data = if (encoding == "b") {
        runCatching { Base64.decode(payload, Base64.DEFAULT) }.getOrNull()
      } else {
        decodeQuotedPrintable(payload.replace('_', ' '))
      }
      val decoded = data?.let { decodeText(it) } ?: continue
      result = result.replaceRange(match.range, decoded)
    }
    return result
  }

  private fun decodeQuotedPrintable(value: String): ByteArray {
    val input = value.toByteArray(Charsets.UTF_8)
    val bytes = ArrayList<Byte>(input.size)
    var index = 0
    while (index < input.size) {
      val high = if (index + 2 < input.size) hex(input[index + 1]) else null
      val low = if (index + 2 < input.size) hex(input[index + 2]) else null
      if (input[index] == '='.code.toByte() && high != null && low != null) {
        bytes.add((high * 16 + low).toByte())
        index += 3
      } else {
        bytes.add(input[index])
        index += 1
      }
    }
    return bytes.toByteArray()
  }

  private fun hex(value: Byte): Int? = when (val code = value.toInt() and 0xFF) {
    in 48..57 -> code - 48
    in 65..70 -> code - 55
    in 97..102 -> code - 87
    else -> null
  }

  private fun decodeHtmlEntities(value: String): String {
    var result = value
    for ((entity, replacement) in NAMED_ENTITIES) {
      result = result.replace(entity, replacement, ignoreCase = true)
    }
    for (match in NUMERIC_ENTITY.findAll(result).toList().asReversed()) {
      val raw = match.groupValues[1]
      val number = if (raw.startsWith("x", ignoreCase = true)) {
        raw.drop(1).toIntOrNull(16)
      } else {
        raw.toIntOrNull()
      } ?: continue
      if (number !in 0..0x10FFFF) continue
      result = result.replaceRange(match.range, String(Character.toChars(number)))
    }
    return result
  }

  private fun String.nilIfBlank(): String? = takeIf { it.isNotBlank() }

  private val NON_CONTENT_BLOCKS = Regex(
    "<!--.*?-->|<(script|style|head|svg|template|noscript)\\b[^>]*>.*?(</\\1\\s*>|$)",
    setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL),
  )
  private val LINE_BREAK_TAGS = Regex(
    "<\\s*br\\s*/?\\s*>|</\\s*(p|div|li|tr|h[1-6]|section|article|table|blockquote|pre)\\s*>",
    RegexOption.IGNORE_CASE,
  )
  private val CELL_END_TAGS = Regex("</\\s*td\\s*>|</\\s*th\\s*>", RegexOption.IGNORE_CASE)
  private val ANY_TAG = Regex("<[^>]+>", RegexOption.DOT_MATCHES_ALL)
  private val OPEN_TAG = Regex("<[a-z][\\w:-]*\\b")
  private val HORIZONTAL_SPACE = Regex("[\\t ]+")
  private val PADDED_NEWLINE = Regex(" *\\n *")
  private val EXCESS_NEWLINES = Regex("\\n{3,}")
  private val CSS_DECLARATION = Regex("[\\w\\-]+\\s*:\\s*[^;{]+;")
  private val WHITESPACE = Regex("\\s+")
  private val ADDRESS_PATTERN =
    Regex("[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}", RegexOption.IGNORE_CASE)
  private val RFC2047 = Regex("=\\?([^?]+)\\?([bBqQ])\\?([^?]+)\\?=")
  private val NUMERIC_ENTITY = Regex("&#(x[0-9a-fA-F]+|[0-9]+);")

  private val NAMED_ENTITIES = listOf(
    "&amp;" to "&", "&lt;" to "<", "&gt;" to ">", "&quot;" to "\"",
    "&#39;" to "'", "&apos;" to "'", "&nbsp;" to " ", "&ndash;" to "–", "&mdash;" to "—",
  )

  private val VIEWER_STUB_HINTS = listOf(
    "view this email in your browser",
    "view in browser",
    "enable html",
    "html is required",
    "doesn't support html",
    "does not support html",
    "multipart/alternative",
  )
}

class GmailMessageParserException(message: String) : Exception(message)
