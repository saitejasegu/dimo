import SwiftUI

struct EmailDetailSheet: View {
  var detail: EmailUIEmailDetail
  var onClose: () -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          headerCard
          bodyCard
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Email")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.green)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
  }

  private var headerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(detail.subject.isEmpty ? "No subject" : detail.subject)
        .font(DimoFont.display(20, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 6) {
        labeledRow(title: "From", value: detail.sender)
        if detail.senderAddress.caseInsensitiveCompare(detail.sender) != .orderedSame {
          labeledRow(title: "Address", value: detail.senderAddress)
        }
        labeledRow(title: "To", value: detail.accountEmail)
        labeledRow(title: "Received", value: EmailUIFormatting.dateTime(detail.receivedAt))
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          Text(detail.analysisState.title)
            .emailDetailBadge(
              foreground: statusForeground,
              background: statusBackground
            )

          if let analyzer = detail.analyzer {
            Label(
              analyzer.provenanceTitle(modelVersion: detail.modelVersion),
              systemImage: "sparkles"
            )
            .emailDetailBadge(
              foreground: Theme.green,
              background: Theme.greenSoft
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
          }

          if let classification = detail.classification {
            Text(classification.title)
              .emailDetailBadge(
                foreground: classification == .refund ? Theme.green : Theme.muted,
                background: classification == .refund ? Theme.greenSoft : Theme.canvasDeep
              )
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
  }

  private var bodyCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Message")
        .font(DimoFont.body(13, weight: .semibold))
        .foregroundStyle(Theme.ink)

      if detail.bodyText.isEmpty {
        Text("No message text is available for this email.")
          .font(DimoFont.body(14))
          .foregroundStyle(Theme.muted)
      } else {
        Text(detail.bodyText)
          .font(DimoFont.body(14))
          .foregroundStyle(Theme.body)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !detail.isBodyRetained {
        Label(
          "Only the Gmail snippet is shown. The retained email body was removed after review or retention cleanup.",
          systemImage: "lock.shield.fill"
        )
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 2)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
  }

  private func labeledRow(title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(title)
        .font(DimoFont.body(12, weight: .medium))
        .foregroundStyle(Theme.muted)
        .frame(width: 72, alignment: .leading)
      Text(value)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var statusForeground: Color {
    switch detail.analysisState {
    case .pending, .dismissed, .expired: return Theme.muted
    case .failed: return Theme.danger
    case .needsReview: return Theme.warn
    case .analyzed, .added, .refundApplied: return Theme.green
    }
  }

  private var statusBackground: Color {
    switch detail.analysisState {
    case .analyzed, .added, .refundApplied: return Theme.greenSoft
    case .pending, .failed, .needsReview, .dismissed, .expired: return Theme.canvasDeep
    }
  }
}

private extension View {
  func emailDetailBadge(foreground: Color, background: Color) -> some View {
    font(DimoFont.body(10, weight: .medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(background)
      .clipShape(Capsule())
      .fixedSize(horizontal: true, vertical: false)
  }
}
