import SwiftUI

struct EmailMessageStatusCard: View {
  var email: EmailUIMessage
  var onOpen: () -> Void = {}
  var onRestore: (() -> Void)? = nil
  var onRetryWithAlternate: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(statusForeground)
              .frame(width: 38, height: 38)
              .background(statusBackground)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
              Text(email.sender)
                .font(DimoFont.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
              Text(email.subject.isEmpty ? "No subject" : email.subject)
                .font(DimoFont.body(12))
                .foregroundStyle(Theme.body)
                .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(email.analysisState.title)
              .emailStatusBadge(foreground: statusForeground, background: statusBackground)
              .multilineTextAlignment(.trailing)
          }

          if !email.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(email.snippet)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(2)
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
              Label(email.accountEmail, systemImage: "envelope.fill")
                .emailStatusBadge(foreground: Theme.body, background: Theme.canvasDeep)

              if let analyzer = email.analyzer {
                Label(
                  analyzer.provenanceTitle(modelVersion: email.modelVersion),
                  systemImage: "sparkles"
                )
                .emailStatusBadge(
                  foreground: Theme.green,
                  background: Theme.greenSoft
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
              } else {
                Label("Not analyzed", systemImage: "hourglass")
                  .emailStatusBadge(foreground: Theme.muted, background: Theme.canvasDeep)
              }

              if let classification = email.classification {
                Text(classification.title)
                  .emailStatusBadge(
                    foreground: classification == .refund ? Theme.green : Theme.muted,
                    background: classification == .refund ? Theme.greenSoft : Theme.canvasDeep
                  )
              }
            }
          }

          HStack(spacing: 6) {
            Label(EmailUIFormatting.dateTime(email.receivedAt), systemImage: "clock")
            if let analyzedAt = email.analyzedAt {
              Text("·")
              Text("Analyzed \(EmailUIFormatting.dateTime(analyzedAt))")
            }
          }
          .font(DimoFont.body(10))
          .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint("Shows the email contents")

      if email.analysisState == .dismissed, let onRestore {
        Divider().overlay(Theme.lineSoft)
        Button(action: onRestore) {
          Label("Restore to review", systemImage: "arrow.uturn.backward")
            .font(DimoFont.body(13, weight: .semibold))
            .foregroundStyle(Theme.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
      }

      if email.analysisState == .failed, let onRetryWithAlternate {
        Divider().overlay(Theme.lineSoft)
        Button(action: onRetryWithAlternate) {
          Label(alternateTitle, systemImage: "arrow.triangle.2.circlepath")
            .font(DimoFont.body(13, weight: .semibold))
            .foregroundStyle(Theme.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    .accessibilityElement(children: .contain)
  }

  private var alternateTitle: String {
    email.analyzer == .openRouter ? "Try with Local Gemma" : "Try with OpenRouter"
  }

  private var statusIcon: String {
    switch email.analysisState {
    case .pending: return "hourglass"
    case .failed: return "exclamationmark.triangle.fill"
    case .needsReview: return "exclamationmark.bubble.fill"
    case .analyzed: return "checkmark.circle"
    case .added, .refundApplied: return "checkmark.circle.fill"
    case .dismissed: return "xmark.circle"
    case .expired: return "clock.badge.xmark"
    }
  }

  private var statusForeground: Color {
    switch email.analysisState {
    case .pending, .dismissed, .expired: return Theme.muted
    case .failed: return Theme.danger
    case .needsReview: return Theme.warn
    case .analyzed, .added, .refundApplied: return Theme.green
    }
  }

  private var statusBackground: Color {
    switch email.analysisState {
    case .analyzed, .added, .refundApplied: return Theme.greenSoft
    case .pending, .failed, .needsReview, .dismissed, .expired: return Theme.canvasDeep
    }
  }
}

private extension View {
  func emailStatusBadge(foreground: Color, background: Color) -> some View {
    font(DimoFont.body(10, weight: .medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(background)
      .clipShape(Capsule())
      .fixedSize(horizontal: true, vertical: false)
  }
}
