import Foundation

struct EmailStructuredOutput: Sendable {
  var schemaVersion: Int
  var kind: EmailAnalysisKind
  var merchant: String?
  var amount: String?
  var currency: Currency?
  var occurredAt: String?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
}

private struct EmailDeterministicValidationResult {
  var merchant: String?
  var amount: Decimal?
  var currency: Currency?
  var occurredAt: Date?
  var categoryId: String?
  var paymentMethodId: String?
}

/// Extracts only literal evidence used to validate Gemma output. This does not
/// classify an email and is never used as a standalone analysis fallback.
private enum EmailDeterministicEvidenceExtractor {
  static func extract(_ request: EmailAnalysisRequest) -> EmailDeterministicValidationResult {
    let source = request.subject + "\n" + request.normalizedBody
    let evidence = deterministicEvidence(in: source)
    let strongestAmount = evidence.amounts.last
    let merchant = request.senderName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let lastFour = evidence.paymentLastFour
    let paymentMethodId = lastFour.flatMap { digits in
      request.paymentMethods.first {
        String(($0.lastFour ?? "").filter(\.isNumber).suffix(4)) == digits
      }?.id
    }
    let merchantKey = normalizedKey(merchant ?? "")
    let categoryId = request.merchantHistory.first {
      let historyKey = normalizedKey($0.merchant)
      return !merchantKey.isEmpty && (merchantKey.contains(historyKey) || historyKey.contains(merchantKey))
    }?.categoryId

    return EmailDeterministicValidationResult(
      merchant: merchant,
      amount: strongestAmount?.value,
      currency: strongestAmount?.currency,
      occurredAt: evidencedDate(in: source) ?? request.receivedAt,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId
    )
  }

  static func deterministicEvidence(in source: String) -> EmailDeterministicEvidence {
    var amounts: [EmailDeterministicEvidence.Amount] = []
    let patterns: [(String, Currency)] = [
      (#"(?:₹|\bINR\s*)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .INR),
      (#"(?:US\$|\bUSD\s*|\$)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .USD),
      (#"(?:€|\bEUR\s*)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#, .EUR),
    ]
    let fullRange = NSRange(source.startIndex..., in: source)
    for (pattern, currency) in patterns {
      guard let regex = try? NSRegularExpression(
        pattern: pattern,
        options: [.caseInsensitive]
      ) else { continue }
      for match in regex.matches(in: source, range: fullRange) {
        guard match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source) else { continue }
        let text = source[valueRange].replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(
          string: text,
          locale: Locale(identifier: "en_US_POSIX")
        ), value > 0 else { continue }
        let matchedSource = Range(match.range, in: source).map { String(source[$0]) } ?? String(text)
        amounts.append(.init(value: value, currency: currency, source: matchedSource))
      }
    }

    return EmailDeterministicEvidence(
      amounts: amounts,
      paymentLastFour: firstCapture(
        in: source,
        pattern: #"(?:ending|last\s*four|x{2,}|\*{2,})\D{0,8}([0-9]{4})\b"#
      ),
      reference: firstCapture(
        in: source,
        pattern: #"\b(?:ref(?:erence)?|txn|transaction|order)\s*(?:id|no|number)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9-]{5,63})\b"#
      )
    )
  }

  private static func firstCapture(in source: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: source) else { return nil }
    return String(source[range])
  }

  private static func evidencedDate(in source: String) -> Date? {
    let formats = [
      "d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd",
      "MMMM d, yyyy", "MMM d, yyyy",
    ]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = .current
      formatter.dateFormat = format
      if let range = source.range(
        of: datePattern(for: format),
        options: [.regularExpression, .caseInsensitive]
      ), let date = formatter.date(from: String(source[range])) {
        return date
      }
    }
    return nil
  }

  private static func datePattern(for format: String) -> String {
    switch format {
    case "d MMMM yyyy", "d MMM yyyy": return #"\b[0-3]?[0-9]\s+[A-Za-z]{3,9}\s+[0-9]{4}\b"#
    case "dd/MM/yyyy": return #"\b[0-3][0-9]/[0-1][0-9]/[0-9]{4}\b"#
    case "dd-MM-yyyy": return #"\b[0-3][0-9]-[0-1][0-9]-[0-9]{4}\b"#
    case "yyyy-MM-dd": return #"\b[0-9]{4}-[0-1][0-9]-[0-3][0-9]\b"#
    default: return #"\b[A-Za-z]{3,9}\s+[0-3]?[0-9],\s+[0-9]{4}\b"#
    }
  }

  private static func normalizedKey(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
  }
}

enum EmailStructuredOutputValidator {
  static func validate(
    response: String,
    request: EmailAnalysisRequest,
    analyzer: EmailAnalyzerType = .gemma,
    now: Date = .now
  ) throws -> EmailAnalysisResult {
    let object = try EmailJSONEnvelopeExtractor.extract(response)
    let data = Data(object.utf8)
    guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw EmailLanguageModelError.invalidOutput("The response is not a JSON object.")
    }
    let output = try decodeOutput(dictionary)
    guard output.schemaVersion == EmailAnalysisResult.schemaVersion else {
      throw EmailLanguageModelError.invalidOutput("Unsupported schema version.")
    }

    let categoryIds = Set(request.categories.map(\.id))
    let paymentMethodIds = Set(request.paymentMethods.map(\.id))
    let deterministic = EmailDeterministicEvidenceExtractor.extract(request)
    if output.kind == .irrelevant {
      return .irrelevant(analyzer: analyzer)
    }

    var amount = parseAmount(output.amount)
    var currency = output.currency
    var correctedOutput = output.amount != nil && amount == nil
    if (amount == nil) != (currency == nil) {
      amount = nil
      currency = nil
      correctedOutput = true
    }
    var confidence: EmailAnalysisConfidence = .high
    let source = request.subject + "\n" + request.normalizedBody
    let evidence = EmailDeterministicEvidenceExtractor.deterministicEvidence(in: source)

    if let modelAmount = amount, let modelCurrency = currency {
      // Currency is constrained by the OpenRouter schema to Dimo's supported
      // values, so only the amount must be evidenced by the email text.
      let isEvidenced = evidence.amounts.contains {
        decimalEqual($0.value, modelAmount)
      } || evidencedAmount(modelAmount, source: source)
      if !isEvidenced {
        if let deterministicAmount = deterministic.amount {
          amount = deterministicAmount
          currency = modelCurrency
        } else {
          // Keep a valid classification reviewable without trusting monetary
          // values that cannot be found in the email. The user can enter the
          // missing amount during review; malformed JSON still fails above.
          amount = nil
          currency = nil
        }
        confidence = .low
        correctedOutput = true
      }
    } else if output.kind != .irrelevant,
              let deterministicAmount = deterministic.amount,
              let deterministicCurrency = deterministic.currency {
      amount = deterministicAmount
      currency = deterministicCurrency
      confidence = .medium
    }

    let modelMerchant = evidencedText(
      output.merchant,
      source: source,
      maximumLength: 100
    )
    let merchant = modelMerchant ?? evidencedText(
      deterministic.merchant,
      source: source,
      maximumLength: 100
    )
    if output.merchant != nil, modelMerchant == nil { correctedOutput = true }

    let modelLastFour = validateLastFour(output.paymentLastFour, source: source)
    let lastFour = modelLastFour ?? validateLastFour(evidence.paymentLastFour, source: source)
    if output.paymentLastFour != nil, modelLastFour == nil { correctedOutput = true }

    let modelPaymentMethodId = validatePaymentMethod(
      output.paymentMethodId,
      lastFour: lastFour,
      request: request,
      source: source
    )
    let paymentMethodId = modelPaymentMethodId ?? validatePaymentMethod(
      deterministic.paymentMethodId,
      lastFour: lastFour,
      request: request,
      source: source
    )
    if output.paymentMethodId != nil, modelPaymentMethodId == nil { correctedOutput = true }

    let modelReference = evidencedText(
      output.reference,
      source: source,
      maximumLength: 64
    )
    let reference = modelReference ?? evidencedText(
      evidence.reference,
      source: source,
      maximumLength: 64
    )
    if output.reference != nil, modelReference == nil { correctedOutput = true }

    let modelOccurredAt = parseOccurredAt(
      output.occurredAt,
      request: request,
      source: source,
      kind: output.kind,
      now: now
    )
    let occurredAt = modelOccurredAt ?? safeDeterministicDate(
      deterministic.occurredAt,
      request: request,
      kind: output.kind,
      now: now
    )
    if output.occurredAt != nil, modelOccurredAt == nil { correctedOutput = true }

    let categoryId = output.categoryId.flatMap { categoryIds.contains($0) ? $0 : nil }
      ?? deterministic.categoryId.flatMap { categoryIds.contains($0) ? $0 : nil }
    if output.categoryId != nil, categoryId != output.categoryId { correctedOutput = true }
    if output.paymentMethodId != nil, !paymentMethodIds.contains(output.paymentMethodId!) {
      correctedOutput = true
    }
    if amount == nil || currency == nil { confidence = .low }
    if correctedOutput { confidence = .low }

    return EmailAnalysisResult(
      kind: output.kind,
      merchant: merchant,
      amount: amount,
      currency: currency,
      occurredAt: occurredAt,
      categoryId: categoryId,
      paymentMethodId: paymentMethodId,
      paymentLastFour: lastFour,
      reference: reference,
      analyzer: analyzer,
      confidence: confidence
    )
  }

  private static func decodeOutput(_ dictionary: [String: Any]) throws -> EmailStructuredOutput {
    guard let schemaVersion = integerValue(dictionary["schemaVersion"]),
          let rawKind = stringValue(dictionary["kind"]),
          let kind = EmailAnalysisKind(rawValue: rawKind.lowercased()) else {
      throw EmailLanguageModelError.invalidOutput("The schema version or kind is invalid.")
    }
    let amount: String?
    if let text = stringValue(dictionary["amount"]) {
      amount = nullNormalized(text)
    } else if let number = dictionary["amount"] as? NSNumber,
              !isBoolean(number) {
      amount = number.stringValue
    } else {
      amount = nil
    }
    let currency = stringValue(dictionary["currency"])
      .flatMap { nullNormalized($0) }
      .flatMap { Currency(rawValue: $0.uppercased()) }
    return EmailStructuredOutput(
      schemaVersion: schemaVersion,
      kind: kind,
      merchant: stringValue(dictionary["merchant"]).flatMap(nullNormalized),
      amount: amount,
      currency: currency,
      occurredAt: stringValue(dictionary["occurredAt"]).flatMap(nullNormalized),
      categoryId: stringValue(dictionary["categoryId"]).flatMap(nullNormalized),
      paymentMethodId: stringValue(dictionary["paymentMethodId"]).flatMap(nullNormalized),
      paymentLastFour: stringValue(dictionary["paymentLastFour"]).flatMap(nullNormalized),
      reference: stringValue(dictionary["reference"]).flatMap(nullNormalized)
    )
  }

  private static func integerValue(_ value: Any?) -> Int? {
    if let value = value as? NSNumber {
      guard !isBoolean(value) else { return nil }
      let integer = value.intValue
      return value.doubleValue == Double(integer) ? integer : nil
    }
    if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespaces)) }
    return nil
  }

  private static func isBoolean(_ value: NSNumber) -> Bool {
    CFGetTypeID(value) == CFBooleanGetTypeID()
  }

  private static func stringValue(_ value: Any?) -> String? {
    guard let value, !(value is NSNull), let string = value as? String else { return nil }
    return string.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func nullNormalized(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
  }

  private static func parseAmount(_ raw: String?) -> Decimal? {
    guard let raw else { return nil }
    guard raw.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
          let amount = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")),
          amount > 0 else {
      return nil
    }
    return amount
  }

  private static func parseOccurredAt(
    _ raw: String?,
    request: EmailAnalysisRequest,
    source: String,
    kind: EmailAnalysisKind,
    now: Date
  ) -> Date? {
    guard let raw else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var parsed = formatter.date(from: raw)
    if parsed == nil {
      formatter.formatOptions = [.withInternetDateTime]
      parsed = formatter.date(from: raw)
    }
    if parsed == nil {
      let dateOnlyFormatter = DateFormatter()
      dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
      dateOnlyFormatter.calendar = Calendar(identifier: .gregorian)
      dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
      dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
      parsed = dateOnlyFormatter.date(from: raw)
    }
    guard let parsed else {
      return nil
    }
    if kind == .purchase || kind == .debit, parsed > now.addingTimeInterval(300) {
      return nil
    }
    let calendar = Calendar(identifier: .gregorian)
    let metadataEvidence = abs(parsed.timeIntervalSince(request.receivedAt)) <= 1
    let textualEvidence = dateEvidenceStrings(parsed, calendar: calendar).contains {
      source.range(of: $0, options: .caseInsensitive) != nil
    }
    return metadataEvidence || textualEvidence ? parsed : nil
  }

  private static func safeDeterministicDate(
    _ date: Date?,
    request: EmailAnalysisRequest,
    kind: EmailAnalysisKind,
    now: Date
  ) -> Date? {
    guard let date else { return nil }
    if kind == .purchase || kind == .debit, date > now.addingTimeInterval(300) {
      return request.receivedAt <= now.addingTimeInterval(300) ? request.receivedAt : nil
    }
    return date
  }

  private static func dateEvidenceStrings(_ date: Date, calendar: Calendar) -> [String] {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return []
    }
    let monthName = calendar.monthSymbols[month - 1]
    let shortMonth = calendar.shortMonthSymbols[month - 1]
    return [
      String(format: "%04d-%02d-%02d", year, month, day),
      String(format: "%02d/%02d/%04d", day, month, year),
      String(format: "%02d-%02d-%04d", day, month, year),
      "\(day) \(monthName) \(year)", "\(day) \(shortMonth) \(year)",
      "\(monthName) \(day), \(year)", "\(shortMonth) \(day), \(year)",
    ]
  }

  private static func validateLastFour(_ value: String?, source: String) -> String? {
    guard let value else { return nil }
    return value.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil
      && source.contains(value) ? value : nil
  }

  private static func evidencedAmount(_ amount: Decimal, source: String) -> Bool {
    let ungroupedSource = source.replacingOccurrences(of: ",", with: "")
    let canonical = NSDecimalNumber(decimal: amount).stringValue
    let escaped = NSRegularExpression.escapedPattern(for: canonical)
    let pattern: String
    if let decimalSeparator = canonical.firstIndex(of: ".") {
      let fractionLength = canonical.distance(
        from: canonical.index(after: decimalSeparator),
        to: canonical.endIndex
      )
      let optionalTrailingZero = fractionLength == 1 ? "0?" : ""
      pattern = #"(?<![0-9.])"# + escaped + optionalTrailingZero
        + #"(?![0-9]|\.[0-9])"#
    } else {
      pattern = #"(?<![0-9.])"# + escaped + #"(?:\.0{1,2})?(?![0-9]|\.[0-9])"#
    }
    return ungroupedSource.range(of: pattern, options: .regularExpression) != nil
  }

  private static func validatePaymentMethod(
    _ id: String?,
    lastFour: String?,
    request: EmailAnalysisRequest,
    source: String
  ) -> String? {
    guard let id else { return nil }
    guard let method = request.paymentMethods.first(where: { $0.id == id }) else { return nil }
    if let expected = method.lastFour {
      let expectedDigits = String(expected.filter(\.isNumber).suffix(4))
      return expectedDigits.count == 4 && source.contains(expectedDigits)
        && (lastFour == nil || lastFour == expectedDigits) ? id : nil
    }

    let genericTokens: Set<String> = [
      "account", "archived", "bank", "card", "cash", "credit", "debit",
      "method", "payment", "upi", "wallet",
    ]
    let sourceKey = evidenceKey(source)
    let distinctiveTokens = method.label
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { $0.count >= 3 && !genericTokens.contains($0) }
    return distinctiveTokens.contains(where: { sourceKey.contains(evidenceKey($0)) }) ? id : nil
  }

  private static func evidencedText(
    _ value: String?,
    source: String,
    maximumLength: Int
  ) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= maximumLength else { return nil }
    let needle = evidenceKey(trimmed)
    let haystack = evidenceKey(source)
    return needle.count >= 2 && haystack.contains(needle) ? trimmed : nil
  }

  private static func evidenceKey(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
  }

  private static func decimalEqual(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
    NSDecimalNumber(decimal: lhs).compare(NSDecimalNumber(decimal: rhs)) == .orderedSame
  }
}

enum EmailJSONEnvelopeExtractor {
  static func extract(_ response: String) throws -> String {
    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let startIndex = trimmed.firstIndex(of: "{") else {
      throw EmailLanguageModelError.invalidOutput("Expected a JSON object.")
    }
    let candidate = trimmed[startIndex...]
    var depth = 0
    var insideString = false
    var escaped = false
    var endIndex: String.Index?
    for index in candidate.indices {
      let character = candidate[index]
      if insideString {
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          insideString = false
        }
        continue
      }
      if character == "\"" {
        insideString = true
      } else if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth < 0 {
          throw EmailLanguageModelError.invalidOutput("The JSON object is unbalanced.")
        }
        if depth == 0 {
          endIndex = candidate.index(after: index)
          break
        }
      }
    }
    guard !insideString, depth == 0, let endIndex else {
      throw EmailLanguageModelError.invalidOutput("The JSON object is incomplete.")
    }
    return String(candidate[..<endIndex])
  }

  static func containsCompleteObject(_ response: String) -> Bool {
    (try? extract(response)) != nil
  }
}
