import SwiftUI

struct RefundReviewSheet: View {
  @Binding var review: EmailUIRefundReview
  var activeCurrency: Currency
  var onCancel: () -> Void
  var onMarkReviewed: (EmailUIRefundReview) -> Void
  var onConfirm: (EmailUIRefundReview) -> Void

  @State private var confirmRemoval = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          refundSummary

          if !review.isFullRefund {
            partialRefundNotice
          } else if review.currency != activeCurrency {
            currencyMismatchNotice
          } else if review.candidates.isEmpty {
            noMatchesNotice
          } else {
            candidateSection
          }

          privacyFootnote
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Review refund")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", action: onCancel)
            .foregroundStyle(Theme.muted)
        }
      }
      .safeAreaInset(edge: .bottom) {
        if canRemoveTransaction {
          Button {
            confirmRemoval = true
          } label: {
            Text("Remove refunded transaction")
              .font(DimoFont.body(16, weight: .semibold))
              .foregroundStyle(Theme.onGreen)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(Theme.danger)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 8)
          .background(.ultraThinMaterial)
        } else {
          Button {
            onMarkReviewed(review)
          } label: {
            Text("Mark as reviewed")
              .font(DimoFont.body(16, weight: .semibold))
              .foregroundStyle(Theme.ink)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(Theme.surface)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 20)
          .padding(.top, 10)
          .padding(.bottom, 8)
          .background(.ultraThinMaterial)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
    .alert(
      "Remove this Dimo transaction?",
      isPresented: $confirmRemoval
    ) {
      Button("Remove transaction", role: .destructive) {
        onConfirm(review)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(removalConfirmationMessage)
    }
  }

  private var refundSummary: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "arrow.uturn.backward")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(width: 42, height: 42)
          .background(Theme.greenSoft)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          Text(review.merchant)
            .font(DimoFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
          Text(review.accountEmail)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
          Label(
            review.analyzer.title,
            systemImage: review.analyzer == .gemma ? "sparkles" : "text.magnifyingglass"
          )
          .font(DimoFont.body(10, weight: .medium))
          .foregroundStyle(review.analyzer == .gemma ? Theme.green : Theme.muted)
        }

        Spacer(minLength: 8)

        if let amount = review.amount {
          Text(EmailUIFormatting.amount(amount, currency: review.currency))
            .font(DimoFont.display(18, weight: .semibold))
            .foregroundStyle(Theme.green)
            .lineLimit(1)
        }
      }

      if let occurredAt = review.occurredAt {
        Label(EmailUIFormatting.dateTime(occurredAt), systemImage: "calendar")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }
    }
    .refundReviewCard()
  }

  private var partialRefundNotice: some View {
    reviewNotice(
      title: "Partial refund",
      detail: "Dimo cannot represent partial refunds in the current transaction model. This suggestion is informational and will not change an expense.",
      systemImage: "info.circle.fill",
      color: Theme.warn
    )
  }

  private var currencyMismatchNotice: some View {
    reviewNotice(
      title: "Currency does not match",
      detail: "This refund uses \(review.currency?.rawValue ?? "an unknown currency"), while Dimo is set to \(activeCurrency.rawValue). Dimo does not convert currencies, so no transaction can be removed.",
      systemImage: "coloncurrencysign.circle.fill",
      color: Theme.warn
    )
  }

  private var noMatchesNotice: some View {
    reviewNotice(
      title: "No exact match",
      detail: "A full refund can remove an expense only after you select a same-currency transaction with the exact amount. No eligible transaction was found.",
      systemImage: "magnifyingglass",
      color: Theme.muted
    )
  }

  private var candidateSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("MATCHING TRANSACTIONS")
          .font(DimoFont.body(12, weight: .medium))
          .kerning(0.8)
          .foregroundStyle(Theme.muted)
        Text("Select the expense that this full refund reverses. A match is never applied automatically.")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.body)
          .fixedSize(horizontal: false, vertical: true)
      }

      ForEach(Array(review.candidates.prefix(3))) { candidate in
        candidateRow(candidate)
      }
    }
  }

  private func candidateRow(_ candidate: EmailUIRefundCandidate) -> some View {
    let selected = review.selectedTransactionID == candidate.id
    return Button {
      review.selectedTransactionID = candidate.id
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(selected ? Theme.green : Theme.faint)

        VStack(alignment: .leading, spacing: 4) {
          Text(candidate.merchant)
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
          Text(candidateMetadata(candidate))
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
            .lineLimit(2)
          if let reason = candidate.matchReason, !reason.isEmpty {
            Text(reason)
              .font(DimoFont.body(10, weight: .medium))
              .foregroundStyle(Theme.green)
          }
        }

        Spacer(minLength: 8)

        Text(EmailUIFormatting.amount(candidate.amount, currency: candidate.currency))
          .font(DimoFont.display(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
      }
      .padding(14)
      .background(selected ? Theme.greenSoft.opacity(0.55) : Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(selected ? Theme.green : Theme.line, lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(candidate.merchant), \(EmailUIFormatting.amount(candidate.amount, currency: candidate.currency)), \(EmailUIFormatting.date(candidate.occurredAt))")
    .accessibilityValue(selected ? "Selected" : "Not selected")
  }

  private var privacyFootnote: some View {
    Label(
      "Confirming deletes the selected transaction through Dimo's normal sync. The linked email suggestion stays in sync with its email text for restore. Gmail credentials never leave this iPhone.",
      systemImage: "lock.shield.fill"
    )
    .font(DimoFont.body(11))
    .foregroundStyle(Theme.muted)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var canRemoveTransaction: Bool {
    review.isFullRefund
      && review.currency == activeCurrency
      && review.selectedTransactionID != nil
      && review.candidates.contains { $0.id == review.selectedTransactionID }
  }

  private var removalConfirmationMessage: String {
    guard let selected = review.candidates.first(where: { $0.id == review.selectedTransactionID }) else {
      return "This action removes the selected transaction from Dimo and cannot be undone."
    }
    return "Remove \(selected.merchant) for \(EmailUIFormatting.amount(selected.amount, currency: selected.currency))? This deletion will use Dimo's normal sync pipeline."
  }

  private func candidateMetadata(_ candidate: EmailUIRefundCandidate) -> String {
    [
      EmailUIFormatting.date(candidate.occurredAt),
      candidate.categoryName,
      candidate.paymentMethodLabel
    ]
    .compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }
    .joined(separator: " · ")
  }

  private func reviewNotice(
    title: String,
    detail: String,
    systemImage: String,
    color: Color
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color)
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(DimoFont.body(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text(detail)
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.body)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .refundReviewCard()
  }
}

private extension View {
  func refundReviewCard() -> some View {
    padding(15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
  }
}
