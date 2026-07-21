import Foundation

enum Formatting {
  private static let symbols: [Currency: String] = [
    .INR: "₹",
    .USD: "$",
    .EUR: "€",
  ]

  static func currencySymbol(_ currency: Currency = .INR) -> String {
    symbols[currency] ?? "₹"
  }

  static func money(_ amount: Double, currency: Currency = .INR) -> String {
    money(amount, symbol: currencySymbol(currency))
  }

  /// Format money for any currency code (default or a foreign entry currency).
  static func money(_ amount: Double, currencyCode: String) -> String {
    money(amount, symbol: CurrencyMeta.symbol(currencyCode))
  }

  static func decimal(_ value: Double, maximumFractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = maximumFractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
  }

  private static func money(_ amount: Double, symbol: String) -> String {
    let hasFraction = abs(amount.truncatingRemainder(dividingBy: 1)) > 0.0001
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = hasFraction ? 2 : 0
    formatter.maximumFractionDigits = 2
    let formatted = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
    return (amount < 0 ? "−" : "") + symbol + formatted
  }

  static func spent(_ amount: Double, currency: Currency = .INR) -> String {
    "−" + money(amount, currency: currency)
  }

  static func percent(_ value: Double, total: Double) -> Int {
    if total <= 0 { return 0 }
    return Int((value / total * 100).rounded())
  }

  static func compactMoney(_ amount: Double, currency: Currency = .INR) -> String {
    let symbol = currencySymbol(currency)
    if amount >= 1000 {
      let k = String(format: "%.1f", amount / 1000).replacingOccurrences(of: ".0", with: "")
      return "\(symbol)\(k)k"
    }
    let trimmed = String(format: "%.2f", amount)
      .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    return "\(symbol)\(trimmed)"
  }
}

enum Greeting {
  static func greetingFor(_ date: Date = Date(), calendar: Calendar = .current) -> String {
    let hour = calendar.component(.hour, from: date)
    if hour < 12 { return "Good morning" }
    if hour < 17 { return "Good afternoon" }
    return "Good evening"
  }
}
