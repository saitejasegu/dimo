import SwiftUI

struct EmailSuggestionCard: View {
  var suggestion: EmailUISuggestion
  var onOpen: () -> Void = {}
  var onReview: () -> Void
  var onDismiss: () -> Void
  var onRestore: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 12) {
            kindIcon

            VStack(alignment: .leading, spacing: 3) {
              Text(suggestion.merchant?.nilIfBlank ?? suggestion.subject)
                .font(DimoFont.body(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)

              Text(suggestion.subject)
                .font(DimoFont.body(12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let amount = suggestion.amount {
              Text(EmailUIFormatting.amount(amount, currency: suggestion.currency))
                .font(DimoFont.display(16, weight: .semibold))
                .foregroundStyle(suggestion.kind == .refund ? Theme.green : Theme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
              accountBadge
              analyzerBadge
              Text(suggestion.kind.title)
                .emailBadge(
                  foreground: suggestion.kind == .refund ? Theme.green : Theme.muted,
                  background: suggestion.kind == .refund ? Theme.greenSoft : Theme.canvasDeep
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
          }

          if let occurredAt = suggestion.occurredAt {
            Label(EmailUIFormatting.date(occurredAt), systemImage: "calendar")
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
          }

          if let category = suggestion.categoryName?.nilIfBlank
            ?? suggestion.paymentMethodLabel?.nilIfBlank {
            Text(suggestionMetadata(fallback: category))
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.body)
              .lineLimit(2)
          }

          if let warning = suggestion.currencyWarning?.nilIfBlank {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
              .font(DimoFont.body(12, weight: .medium))
              .foregroundStyle(Theme.warn)
              .fixedSize(horizontal: false, vertical: true)
          }

          if !suggestion.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(suggestion.snippet)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(2)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows the email contents")

      actionRow
    }
    .padding(16)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
    .accessibilityElement(children: .contain)
  }

  private var kindIcon: some View {
    Image(systemName: suggestion.kind == .refund ? "arrow.uturn.backward" : "cart.fill")
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(suggestion.kind == .refund ? Theme.green : Theme.ink)
      .frame(width: 38, height: 38)
      .background(suggestion.kind == .refund ? Theme.greenSoft : Theme.canvasDeep)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityHidden(true)
  }

  private var accountBadge: some View {
    Label(suggestion.accountEmail, systemImage: "envelope.fill")
      .emailBadge(foreground: Theme.body, background: Theme.canvasDeep)
      .lineLimit(1)
  }

  private var analyzerBadge: some View {
    Label(
      suggestion.analyzer.provenanceTitle(modelVersion: suggestion.modelVersion),
      systemImage: suggestion.analyzer == .gemma ? "sparkles" : "text.magnifyingglass"
    )
    .emailBadge(
      foreground: suggestion.analyzer == .gemma ? Theme.green : Theme.muted,
      background: suggestion.analyzer == .gemma ? Theme.greenSoft : Theme.canvasDeep
    )
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
  }

  @ViewBuilder
  private var actionRow: some View {
    if suggestion.status.isReviewed {
      HStack(spacing: 12) {
        HStack(spacing: 8) {
          Image(systemName: reviewedIcon)
          Text(suggestion.status.title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if suggestion.status == .dismissed, let onRestore {
          Button(action: onRestore) {
            Label("Restore", systemImage: "arrow.uturn.backward")
              .font(DimoFont.body(13, weight: .semibold))
              .foregroundStyle(Theme.green)
          }
          .buttonStyle(.plain)
        }
      }
      .font(DimoFont.body(13, weight: .medium))
      .foregroundStyle(Theme.muted)
    } else {
      HStack(spacing: 10) {
        Button(action: onDismiss) {
          Text("Dismiss")
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button(action: onReview) {
          Text(suggestion.kind == .refund ? "Review refund" : "Review")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.green)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var reviewedIcon: String {
    switch suggestion.status {
    case .added, .refundApplied: return "checkmark.circle.fill"
    case .dismissed: return "xmark.circle"
    case .expired: return "clock.badge.xmark"
    case .unactionable: return "info.circle"
    case .pendingPurchase, .pendingRefund: return "circle"
    }
  }

  private func suggestionMetadata(fallback: String) -> String {
    [
      suggestion.categoryName?.nilIfBlank,
      suggestion.paymentMethodLabel?.nilIfBlank,
      suggestion.paymentLastFour.map { "•••• \($0)" }
    ]
    .compactMap { $0 }
    .nilIfEmpty?
    .joined(separator: " · ") ?? fallback
  }
}

enum EmailUIFormatting {
  static func currencySymbol(_ currency: Currency) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency.rawValue
    return formatter.currencySymbol ?? currency.rawValue
  }

  static func amount(_ amount: Decimal, currency: Currency?) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = currency == nil ? .decimal : .currency
    formatter.currencyCode = currency?.rawValue
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSDecimalNumber(decimal: amount))
      ?? NSDecimalNumber(decimal: amount).stringValue
  }

  static func date(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .omitted)
  }

  static func dateTime(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}

private extension View {
  func emailBadge(foreground: Color, background: Color) -> some View {
    font(DimoFont.body(10, weight: .medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(background)
      .clipShape(Capsule())
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Array {
  var nilIfEmpty: Self? { isEmpty ? nil : self }
}
