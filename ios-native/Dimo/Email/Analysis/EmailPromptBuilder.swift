import Foundation

enum EmailPromptBuilder {
  enum Provider {
    case gemma
    case openRouter

    var includesMerchantHistory: Bool { self == .openRouter }
  }

  static let defaultRuntimeContextTokens = 4_096
  // Leaves room for one bounded JSON-only repair turn if the small model uses
  // its first response for prose instead of producing the requested object.
  static let reservedOutputTokens = 640
  static let maximumGeneratedTokens = 256
  static let jsonRepairPrompt = """
    Return the required JSON object now. Output only the JSON object. Do not explain or reason. The first character must be { and the last character must be }.
    """
  private static let outputRequest = "Return only the JSON object now."

  static func build(
    _ request: EmailAnalysisRequest,
    provider: Provider,
    contextTokens: Int = defaultRuntimeContextTokens
  ) -> String {
    let categoryGuidance = provider.includesMerchantHistory
      ? "For purchase/debit/refund, always set categoryId when Merchant/category history matches or an Allowed category name clearly fits; otherwise null."
      : "For purchase/debit/refund, set categoryId when an Allowed category name clearly fits; otherwise null."
    let instructions = """
    You are a JSON extraction function. Extract one completed financial event from one email. Return one raw JSON object immediately. Do not think aloud. Do not use Markdown fences, prose, or comments. The first output character must be { and the last must be }.

    The only kind values are "purchase", "debit", "refund", and "irrelevant". Default to "irrelevant". Use purchase/debit/refund only when the email clearly confirms a completed payment, bank debit, or completed refund with an evidenced amount. Treat newsletters, OTPs, promotions, price lists, pending authorizations, failed or declined payments, shipping updates, statements, cancellations, balance/limit alerts, and ambiguous prices as irrelevant. A credit or completed refund is refund. Never convert currency.

    Return null for every missing fact and for every extracted field when kind is "irrelevant". Never invent values. paymentMethodId must be null or one of the supplied IDs. categoryId must be null, one of the Allowed categories ids, or the exact Allowed category name. \(categoryGuidance) Every merchant, amount, currency, occurrence time, last four, and reference must be directly evidenced by the email or its supplied received time. Use a quoted decimal string without separators for amount.

    Return these exact keys in this order. This example shows the required shape only — do not copy kind=purchase unless the email is a completed payment:
    {"schemaVersion":1,"kind":"irrelevant","merchant":null,"amount":null,"currency":null,"occurredAt":null,"categoryId":null,"paymentMethodId":null,"paymentLastFour":null,"reference":null}
    """

    let receivedAt = ISO8601DateFormatter().string(from: request.receivedAt)
    let resolvedContextTokens = max(2_048, contextTokens)
    let inputBudget = resolvedContextTokens - reservedOutputTokens
    // Leave useful space for the leading receipt/payment sections even on
    // accounts with unusually large category or payment-method lists.
    let targetFixedTokens = inputBudget - 256
    var historyLimit = provider.includesMerchantHistory
      ? min(request.merchantHistory.count, 40)
      : 0
    var categoryLimit = request.categories.count
    var methodLimit = request.paymentMethods.count
    var context = ""
    repeat {
      // Always keep category/payment labels. Small local models cannot pick opaque
      // IDs reliably and need the display names for category tagging.
      let categories = compactJSON(request.categories.prefix(categoryLimit).map {
        ["id": $0.id, "name": bounded($0.name, count: 80)]
      })
      let methods = compactJSON(request.paymentMethods.prefix(methodLimit).map {
        [
          "id": $0.id,
          "label": bounded($0.label, count: 80),
          "lastFour": $0.lastFour ?? "",
          "archived": $0.archived ? "true" : "false",
        ]
      })
      let historyContext: String
      if provider.includesMerchantHistory {
        let history = compactJSON(request.merchantHistory.prefix(historyLimit).map { hint in
          [
            "merchant": bounded(hint.merchant, count: 80),
            "categoryId": hint.categoryId,
            "categoryName": request.categories.first { $0.id == hint.categoryId }.map {
              bounded($0.name, count: 80)
            } ?? "",
          ]
        })
        historyContext = "\nMerchant/category history: \(history)"
      } else {
        historyContext = ""
      }
      context = """
      Sender name: \(jsonString(request.senderName.map { bounded($0, count: 160) }))
      Sender address: \(jsonString(bounded(request.senderAddress, count: 254)))
      Subject: \(jsonString(bounded(request.subject, count: 320)))
      Gmail received time: \(jsonString(receivedAt))
      Active Dimo currency: \(request.activeCurrency.rawValue)
      Allowed categories: \(categories)
      Allowed payment methods: \(methods)\(historyContext)
      Email body:
      """
      if estimatedTokens(instructions + context) <= targetFixedTokens { break }
      if historyLimit > 0 {
        historyLimit = max(0, historyLimit - 5)
      } else if methodLimit > 0 || categoryLimit > 0 {
        // Pathological option counts cannot all fit a finite model context.
        // Retain a deterministic prefix of labeled options and prefer the
        // larger list for the next reduction.
        if methodLimit >= categoryLimit, methodLimit > 0 {
          methodLimit = max(0, methodLimit - max(1, methodLimit / 8))
        } else {
          categoryLimit = max(0, categoryLimit - max(1, categoryLimit / 8))
        }
      } else {
        break
      }
    } while true

    let fixed = instructions + "\n\n" + context
    return fixed + "\n" + request.normalizedBody + "\n\n" + outputRequest
  }

  static func estimatedTokens(_ text: String) -> Int {
    // Conservative for English receipt text and safer than the common four-chars estimate.
    max(1, Int(ceil(Double(text.utf8.count) / 3.0)))
  }

  private static func jsonString(_ value: String?) -> String {
    guard let value else { return "null" }
    let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\""
  }

  private static func bounded(_ value: String, count: Int) -> String {
    guard value.count > count else { return value }
    return String(value.prefix(count))
  }

  private static func compactJSON(_ value: [[String: String]]) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
      return "[]"
    }
    return String(data: data, encoding: .utf8) ?? "[]"
  }
}
