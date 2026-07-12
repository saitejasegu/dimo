import Foundation

enum TransactionCSV {
  static let headers = ["Date", "Note", "Amount", "Category", "Type"]
  static let template =
    "Date,Note,Amount,Category,Type\n2026-07-11 11:38:08 +0000,Example purchase,354.00,Snacks,Expense\n"

  struct Row: Equatable, Sendable {
    var occurredAt: Int
    var merchant: String
    var amountMinor: Int
    var category: String
  }

  struct Source: Equatable, Sendable {
    var name: String
    var category: String
    var amount: Double
    var amountMinor: Int?
    var occurredAt: Int?
  }

  static func defaultPaymentMethodIdForImport(_ paymentMethods: [PaymentMethodOption]) -> String? {
    paymentMethods.first(where: \.isDefault)?.id
  }

  private static let emojiRules: [(NSRegularExpression, String)] = {
    let patterns: [(String, String)] = [
      (#"breakfast|lunch|dinner|dining|meal|restaurant|food"#, "🍽️"),
      (#"snack|coffee|cafe|tea|bakery"#, "☕"),
      (#"grocer|vegetable|fruit|milk|yogurt"#, "🛒"),
      (#"rent|house|home"#, "🏠"),
      (#"subscription|membership"#, "🔁"),
      (#"utilit|electric|water|gas|internet|phone|bill"#, "💡"),
      (#"movie|cinema|entertainment"#, "🎬"),
      (#"shopping|clothes|fashion"#, "🛍️"),
      (#"transport|transit|taxi|cab|fuel|petrol|travel"#, "🚕"),
      (#"health|medical|doctor|pharmacy"#, "💊"),
      (#"education|school|course|book"#, "📚"),
      (#"gift|donation"#, "🎁"),
      (#"laundry|cleaning"#, "🧺"),
      (#"fitness|gym|sport"#, "🏋️"),
    ]
    return patterns.compactMap { pattern, emoji in
      guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
      return (regex, emoji)
    }
  }()

  static func categoryEmojiForName(_ category: String) -> String {
    let normalized = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let range = NSRange(normalized.startIndex..., in: normalized)
    for (regex, emoji) in emojiRules {
      if regex.firstMatch(in: normalized, options: [], range: range) != nil {
        return emoji
      }
    }
    return "💸"
  }

  static func formatDate(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let c = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
    return String(
      format: "%04d-%02d-%02d %02d:%02d:%02d +0000",
      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
    )
  }

  static func formatAmount(_ amountMinor: Int) -> String {
    String(format: "%.2f", Double(amountMinor) / 100)
  }

  static func format(_ transactions: [Source]) -> String {
    let rows = transactions
      .sorted { ($0.occurredAt ?? 0) < ($1.occurredAt ?? 0) }
      .map { tx -> String in
        let amountMinor = tx.amountMinor ?? Int((tx.amount * 100).rounded())
        return [
          formatDate(tx.occurredAt ?? 0),
          escape(tx.name),
          formatAmount(amountMinor),
          escape(tx.category),
          "Expense",
        ].joined(separator: ",")
      }
    let body = rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n"
    return headers.joined(separator: ",") + "\n" + body
  }

  static func parse(_ input: String) throws -> [Row] {
    var text = input
    if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
    text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let records = try parseRecords(text)
    guard !records.isEmpty else { throw CSVError.empty }
    let header = records[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard header.count == headers.count, zip(header, headers).allSatisfy({ $0.0 == $0.1 }) else {
      throw CSVError.badHeaders
    }
    var rows: [Row] = []
    for index in 1..<records.count {
      let record = records[index]
      if record.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
      let rowNumber = index + 1
      guard record.count == headers.count else { throw CSVError.columnCount(rowNumber) }
      let date = record[0]
      let note = record[1].trimmingCharacters(in: .whitespacesAndNewlines)
      let amountValue = record[2].trimmingCharacters(in: .whitespacesAndNewlines)
      let category = record[3].trimmingCharacters(in: .whitespacesAndNewlines)
      let type = record[4].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard let occurredAt = parseDate(date) else { throw CSVError.invalidDate(rowNumber) }
      guard !note.isEmpty else { throw CSVError.emptyNote(rowNumber) }
      guard let amount = Double(amountValue), amount > 0 else { throw CSVError.invalidAmount(rowNumber) }
      guard !category.isEmpty else { throw CSVError.emptyCategory(rowNumber) }
      guard type == "expense" else { throw CSVError.notExpense(rowNumber) }
      rows.append(Row(
        occurredAt: occurredAt,
        merchant: note,
        amountMinor: Int((amount * 100).rounded()),
        category: category
      ))
    }
    guard !rows.isEmpty else { throw CSVError.noTransactions }
    return rows
  }

  private static func escape(_ value: String) -> String {
    if value.range(of: #"[",\n\r]"#, options: .regularExpression) != nil {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }

  private static func parseDate(_ value: String) -> Int? {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.dateFormat = "yyyy-MM-dd"
    dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
    dateOnly.isLenient = false
    if trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
       let date = dateOnly.date(from: trimmed),
       dateOnly.string(from: date) == trimmed {
      return Int(date.timeIntervalSince1970 * 1000)
    }
    if let regex = try? NSRegularExpression(pattern: #" ([+-]\d{2})(\d{2})$"#),
       let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
       let r1 = Range(match.range(at: 1), in: trimmed),
       let r2 = Range(match.range(at: 2), in: trimmed) {
      let replacement = " \(trimmed[r1]):\(trimmed[r2])"
      trimmed = regex.stringByReplacingMatches(
        in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: replacement
      )
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: trimmed.replacingOccurrences(of: " ", with: "T")) {
      return Int(date.timeIntervalSince1970 * 1000)
    }
    let fallback = DateFormatter()
    fallback.locale = Locale(identifier: "en_US_POSIX")
    fallback.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    fallback.timeZone = TimeZone(secondsFromGMT: 0)
    if let date = fallback.date(from: trimmed) {
      return Int(date.timeIntervalSince1970 * 1000)
    }
    return nil
  }

  private static func parseRecords(_ input: String) throws -> [[String]] {
    var records: [[String]] = []
    var record: [String] = []
    var field = ""
    var quoted = false
    let chars = Array(input)
    var index = 0
    while index < chars.count {
      let char = chars[index]
      if quoted {
        if char == "\"" {
          if index + 1 < chars.count, chars[index + 1] == "\"" {
            field.append("\"")
            index += 1
          } else {
            quoted = false
          }
        } else {
          field.append(char)
        }
      } else if char == "\"" {
        quoted = true
      } else if char == "," {
        record.append(field)
        field = ""
      } else if char == "\n" {
        record.append(field)
        records.append(record)
        record = []
        field = ""
      } else if char != "\r" {
        field.append(char)
      }
      index += 1
    }
    if quoted { throw CSVError.unclosedQuote }
    record.append(field)
    if record.contains(where: { !$0.isEmpty }) { records.append(record) }
    return records
  }

  enum CSVError: LocalizedError {
    case empty, badHeaders, noTransactions, unclosedQuote
    case columnCount(Int), invalidDate(Int), emptyNote(Int), invalidAmount(Int), emptyCategory(Int), notExpense(Int)

    var errorDescription: String? {
      switch self {
      case .empty: return "CSV is empty"
      case .badHeaders: return "Expected headers: \(headers.joined(separator: ", "))"
      case .noTransactions: return "CSV has no transactions"
      case .unclosedQuote: return "CSV contains an unclosed quoted field"
      case .columnCount(let n): return "Row \(n) must have exactly 5 columns"
      case .invalidDate(let n): return "Row \(n) has an invalid date"
      case .emptyNote(let n): return "Row \(n) has an empty note"
      case .invalidAmount(let n): return "Row \(n) has an invalid amount"
      case .emptyCategory(let n): return "Row \(n) has an empty category"
      case .notExpense(let n): return "Row \(n) type must be Expense"
      }
    }
  }
}
