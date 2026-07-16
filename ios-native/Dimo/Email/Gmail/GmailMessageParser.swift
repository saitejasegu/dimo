import Foundation

struct ParsedGmailMessage: Hashable, Sendable {
  var gmailMessageId: String
  var gmailThreadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Date
  var normalizedBody: String
}

enum GmailMessageParser {
  /// Attachment IDs for text body parts that Gmail omitted from the message payload.
  /// Large `text/plain` / `text/html` parts often come back with only `attachmentId`.
  static func unresolvedBodyAttachmentIds(from message: GmailMessageResource) -> [String] {
    var ids: [String] = []
    collectBodyParts(from: message.payload) { _, body in
      if let attachmentId = body.attachmentId?.trimmingCharacters(in: .whitespacesAndNewlines),
         !attachmentId.isEmpty,
         (body.data ?? "").isEmpty {
        ids.append(attachmentId)
      }
    }
    return ids.uniquedPreservingOrder()
  }

  static func parse(
    _ message: GmailMessageResource,
    resolvedBodies: [String: Data] = [:]
  ) throws -> ParsedGmailMessage {
    let headers = message.payload?.headers ?? []
    let sender = parseSender(header(headers, named: "From") ?? "")
    let subject = decodeHeaderValue(header(headers, named: "Subject") ?? "")
    let rfcMessageId = header(headers, named: "Message-ID")
      ?? header(headers, named: "Message-Id")
    guard let milliseconds = Int64(message.internalDate) else {
      throw GmailMessageParserError.invalidInternalDate
    }

    let body = selectedBody(from: message.payload, resolvedBodies: resolvedBodies)
      ?? message.snippet
      ?? ""
    return ParsedGmailMessage(
      gmailMessageId: message.id,
      gmailThreadId: message.threadId,
      rfcMessageId: rfcMessageId?.trimmingCharacters(in: .whitespacesAndNewlines),
      senderName: sender.name,
      senderAddress: sender.address,
      subject: subject,
      snippet: normalizePlainText(message.snippet ?? ""),
      internalDate: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000),
      normalizedBody: extractReadableText(body)
    )
  }

  /// Converts HTML/markup into readable plain text for storage and analysis.
  static func extractReadableText(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if looksLikeHTML(trimmed) {
      return sanitizeHTML(trimmed)
    }
    return normalizePlainText(trimmed)
  }

  static func sanitizeHTML(_ html: String) -> String {
    var value = html
    // Drop comments and non-content blocks, including unclosed style/script tails.
    value = value.replacingOccurrences(
      of: #"(?is)<!--.*?-->|<(script|style|head|svg|template|noscript)\b[^>]*>.*?(</\1\s*>|$)"#,
      with: " ",
      options: .regularExpression
    )
    value = value.replacingOccurrences(
      of: #"(?i)<\s*br\s*/?\s*>|</\s*(p|div|li|tr|h[1-6]|section|article|table|blockquote|pre)\s*>"#,
      with: "\n",
      options: .regularExpression
    )
    value = value.replacingOccurrences(
      of: #"(?i)</\s*td\s*>|</\s*th\s*>"#,
      with: "\t",
      options: .regularExpression
    )
    value = value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    value = decodeHTMLEntities(value)
    value = stripCSSLikeNoise(value)
    return normalizePlainText(value)
  }

  static func normalizePlainText(_ text: String) -> String {
    var value = text.precomposedStringWithCanonicalMapping
      .replacingOccurrences(of: "\u{00A0}", with: " ")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    value = String(value.unicodeScalars.filter { scalar in
      !CharacterSet.controlCharacters.contains(scalar)
        || scalar.value == 10 || scalar.value == 9
    })
    value = value.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
    value = value.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
    value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func decodeBase64URLData(_ encoded: String) -> Data? {
    var base64 = encoded.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    base64 += String(repeating: "=", count: padding)
    return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
  }

  private static func selectedBody(
    from root: GmailMessagePart?,
    resolvedBodies: [String: Data]
  ) -> String? {
    var plainParts: [String] = []
    var htmlParts: [String] = []

    collectBodyParts(from: root) { mimeType, body in
      guard let text = decodeBodyText(body, resolvedBodies: resolvedBodies) else { return }
      if mimeType == "text/plain" {
        plainParts.append(text)
      } else if mimeType == "text/html" {
        htmlParts.append(text)
      }
    }

    let plainRaw = plainParts.joined(separator: "\n\n")
    let htmlRaw = htmlParts.joined(separator: "\n\n")
    return preferredReadableBody(plainRaw: plainRaw, htmlRaw: htmlRaw)
  }

  private static func preferredReadableBody(plainRaw: String, htmlRaw: String) -> String? {
    let plainText = plainRaw.isEmpty ? nil : extractReadableText(plainRaw).nilIfEmpty
    let htmlText = htmlRaw.isEmpty ? nil : sanitizeHTML(htmlRaw).nilIfEmpty
    switch (plainText, htmlText) {
    case (nil, nil):
      return nil
    case (let plain?, nil):
      return plain
    case (nil, let html?):
      return html
    case (let plain?, let html?):
      // Decide from the raw MIME parts: merchant "plain" is often HTML source
      // or a short "view in browser" stub.
      if looksLikeHTML(plainRaw) || looksLikeMarkupHeavy(plainRaw) || isHTMLViewerStub(plainRaw) {
        return html
      }
      if plain.count < 48, html.count > max(96, plain.count * 3) {
        return html
      }
      return plain
    }
  }

  private static func looksLikeHTML(_ text: String) -> Bool {
    let sample = String(text.prefix(8_000)).lowercased()
    if sample.contains("<html")
      || sample.contains("<!doctype")
      || sample.contains("<body")
      || sample.contains("<div")
      || sample.contains("<table")
      || sample.contains("<span")
      || sample.contains("<br")
      || sample.contains("<p ")
      || sample.contains("<p>") {
      return true
    }
    guard let regex = try? NSRegularExpression(pattern: #"<[a-z][\w:-]*\b"#) else {
      return false
    }
    let range = NSRange(sample.startIndex..., in: sample)
    return regex.numberOfMatches(in: sample, range: range) >= 4
  }

  private static func looksLikeMarkupHeavy(_ text: String) -> Bool {
    let sample = String(text.prefix(4_000))
    let angleCount = sample.filter { $0 == "<" || $0 == ">" }.count
    let braceCount = sample.filter { $0 == "{" || $0 == "}" }.count
    guard sample.count >= 40 else { return false }
    return Double(angleCount) / Double(sample.count) > 0.04
      || Double(braceCount) / Double(sample.count) > 0.05
  }

  private static func isHTMLViewerStub(_ text: String) -> Bool {
    let lower = text.lowercased()
    let hints = [
      "view this email in your browser",
      "view in browser",
      "enable html",
      "html is required",
      "doesn't support html",
      "does not support html",
      "multipart/alternative",
    ]
    return text.count < 280 && hints.contains { lower.contains($0) }
  }

  private static func stripCSSLikeNoise(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .filter { line in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed == "{" || trimmed == "}" { return false }
        if trimmed.hasSuffix("{") { return false }
        if trimmed.contains("{"), trimmed.contains("}") { return false }
        // Compact CSS declarations: font-size:14px;color:#333;
        if trimmed.contains(":"),
           trimmed.contains(";"),
           trimmed.range(of: #"[\w\-]+\s*:\s*[^;{]+;"#, options: .regularExpression) != nil,
           trimmed.split(whereSeparator: \.isWhitespace).count <= 4 {
          return false
        }
        return true
      }
      .joined(separator: "\n")
  }

  private static func collectBodyParts(
    from root: GmailMessagePart?,
    visit: (_ mimeType: String, _ body: GmailMessageBody) -> Void
  ) {
    guard let root else { return }

    func walk(_ part: GmailMessagePart) {
      // Skip real file attachments (non-empty filename). Large inline text/html
      // bodies often use attachmentId with an empty filename and must be kept.
      let filename = (part.filename ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if !filename.isEmpty {
        return
      }

      let mimeType = (part.mimeType ?? "").lowercased()
      if let body = part.body {
        if mimeType.hasPrefix("text/plain") {
          visit("text/plain", body)
        } else if mimeType.hasPrefix("text/html") {
          visit("text/html", body)
        }
      }
      for child in part.parts ?? [] { walk(child) }
    }

    walk(root)
  }

  private static func decodeBodyText(
    _ body: GmailMessageBody,
    resolvedBodies: [String: Data]
  ) -> String? {
    if let encoded = body.data, !encoded.isEmpty,
       let data = decodeBase64URLData(encoded),
       let text = decodeText(data) {
      return text
    }
    if let attachmentId = body.attachmentId?.trimmingCharacters(in: .whitespacesAndNewlines),
       !attachmentId.isEmpty,
       let data = resolvedBodies[attachmentId],
       let text = decodeText(data) {
      return text
    }
    return nil
  }

  private static func header(_ headers: [GmailMessageHeader], named name: String) -> String? {
    headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  private static func decodeText(_ data: Data) -> String? {
    String(data: data, encoding: .utf8)
      ?? String(data: data, encoding: .isoLatin1)
  }

  private static func parseSender(_ rawValue: String) -> (name: String?, address: String) {
    let decoded = decodeHeaderValue(rawValue).trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = decoded.lastIndex(of: "<"),
       let end = decoded[start...].firstIndex(of: ">") {
      let address = decoded[decoded.index(after: start)..<end]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      let rawName = decoded[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
      return (rawName.isEmpty ? nil : rawName, address)
    }
    let addressPattern = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#
    if let range = decoded.range(of: addressPattern, options: [.regularExpression, .caseInsensitive]) {
      return (nil, String(decoded[range]).lowercased())
    }
    return (nil, decoded.lowercased())
  }

  /// Decodes the common single-part RFC 2047 forms used by merchant senders.
  private static func decodeHeaderValue(_ value: String) -> String {
    let pattern = #"=\?([^?]+)\?([bBqQ])\?([^?]+)\?="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
    let range = NSRange(value.startIndex..., in: value)
    var result = value
    for match in regex.matches(in: value, range: range).reversed() {
      guard let whole = Range(match.range(at: 0), in: value),
            let encodingRange = Range(match.range(at: 2), in: value),
            let payloadRange = Range(match.range(at: 3), in: value) else { continue }
      let encoding = value[encodingRange].lowercased()
      let payload = String(value[payloadRange])
      let data: Data?
      if encoding == "b" {
        data = Data(base64Encoded: payload)
      } else {
        let q = payload.replacingOccurrences(of: "_", with: " ")
        data = decodeQuotedPrintable(q)
      }
      guard let data, let decoded = decodeText(data) else { continue }
      result.replaceSubrange(whole, with: decoded)
    }
    return result
  }

  private static func decodeQuotedPrintable(_ value: String) -> Data? {
    var bytes: [UInt8] = []
    let input = Array(value.utf8)
    var index = 0
    while index < input.count {
      if input[index] == 61, index + 2 < input.count,
         let high = hex(input[index + 1]), let low = hex(input[index + 2]) {
        bytes.append(high * 16 + low)
        index += 3
      } else {
        bytes.append(input[index])
        index += 1
      }
    }
    return Data(bytes)
  }

  private static func hex(_ value: UInt8) -> UInt8? {
    switch value {
    case 48...57: return value - 48
    case 65...70: return value - 55
    case 97...102: return value - 87
    default: return nil
    }
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    let named: [String: String] = [
      "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
      "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—",
    ]
    var result = value
    for (entity, replacement) in named {
      result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }
    guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#) else {
      return result
    }
    for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
      guard let whole = Range(match.range(at: 0), in: result),
            let numberRange = Range(match.range(at: 1), in: result) else { continue }
      let raw = String(result[numberRange])
      let number = raw.lowercased().hasPrefix("x")
        ? UInt32(raw.dropFirst(), radix: 16)
        : UInt32(raw, radix: 10)
      if let number, let scalar = UnicodeScalar(number) {
        result.replaceSubrange(whole, with: String(scalar))
      }
    }
    return result
  }
}

enum GmailMessageParserError: LocalizedError {
  case invalidInternalDate

  var errorDescription: String? { "The Gmail message date is invalid." }
}

private extension Array where Element: Hashable {
  func uniquedPreservingOrder() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}

private extension String {
  var nilIfEmpty: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }
}
