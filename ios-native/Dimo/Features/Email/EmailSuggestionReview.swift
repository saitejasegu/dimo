import SwiftUI

struct EmailSuggestionReview: View {
  @Binding var draft: EmailUIPurchaseReviewDraft
  var activeCurrency: Currency
  var categories: [CategoryEntity]
  var paymentMethods: [PaymentMethodOption]
  var onCancel: () -> Void
  var onSave: (EmailUIPurchaseReviewDraft) -> Void

  @FocusState private var focusedField: Field?

  private enum Field {
    case merchant
    case amount
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          sourceSummary
          currencyWarnings
          editableFields
          duplicateWarning
          recurrenceControls

          Text("Nothing is added until you tap Save expense. The retained email body is then removed from Dimo's local database.")
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Review expense")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
            .foregroundStyle(Theme.muted)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save expense") { onSave(draft) }
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(canSave ? Theme.green : Theme.faint)
            .disabled(!canSave)
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          onSave(draft)
        } label: {
          Text("Save expense")
            .font(DimoFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSave ? Theme.green : Theme.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
  }

  private var sourceSummary: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "envelope.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.green)
        .frame(width: 40, height: 40)
        .background(Theme.greenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text("Suggested from Gmail")
          .font(DimoFont.body(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text(draft.accountEmail)
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
          .lineLimit(1)
        Label(
          draft.analyzer.title,
          systemImage: draft.analyzer == .gemma ? "sparkles" : "text.magnifyingglass"
        )
        .font(DimoFont.body(10, weight: .medium))
        .foregroundStyle(draft.analyzer == .gemma ? Theme.green : Theme.muted)
      }

      Spacer()
    }
    .emailReviewCard()
  }

  @ViewBuilder
  private var currencyWarnings: some View {
    if let warning = draft.currencyWarning, !warning.isEmpty {
      reviewWarning(warning, systemImage: "exclamationmark.triangle.fill", color: Theme.warn)
    } else if let currency = draft.currency, currency != activeCurrency {
      reviewWarning(
        "This email appears to use \(currency.rawValue), but Dimo is set to \(activeCurrency.rawValue). Dimo does not convert currencies.",
        systemImage: "coloncurrencysign.circle",
        color: Theme.warn
      )
    }
  }

  private var editableFields: some View {
    VStack(alignment: .leading, spacing: 14) {
      reviewField("Merchant") {
        TextField("Merchant", text: $draft.merchant)
          .textInputAutocapitalization(.words)
          .focused($focusedField, equals: .merchant)
      }

      reviewField("Amount") {
        HStack(spacing: 8) {
          Text(EmailUIFormatting.currencySymbol(activeCurrency))
            .foregroundStyle(Theme.muted)
          TextField("0.00", text: $draft.amount)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .amount)
        }
      }

      reviewField("Category") {
        Picker("Category", selection: categorySelection) {
          Text("Choose a category").tag("")
          ForEach(categories) { category in
            Text("\(category.emoji) \(category.name)").tag(category.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      reviewField("Paid with") {
        Picker("Paid with", selection: paymentSelection) {
          Text("No payment method").tag("")
          ForEach(availablePaymentMethods) { method in
            Text(method.label).tag(method.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      reviewField("Date") {
        DatePicker(
          "Date",
          selection: $draft.occurredAt,
          in: ...Date(),
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .tint(Theme.green)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private var duplicateWarning: some View {
    if !draft.possibleDuplicateDescriptions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Label("Possible duplicate", systemImage: "doc.on.doc.fill")
          .font(DimoFont.body(13, weight: .semibold))
          .foregroundStyle(Theme.warn)
        Text("Check these existing Dimo transactions before saving:")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.body)
        ForEach(Array(draft.possibleDuplicateDescriptions.prefix(3).enumerated()), id: \.offset) { _, item in
          Text("• \(item)")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.body)
        }
      }
      .padding(14)
      .background(Theme.dangerSoft.opacity(0.6))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.dangerLine))
    }
  }

  private var recurrenceControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: $draft.isRecurring) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Recurring")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Text("Never inferred automatically from email")
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
        }
      }
      .tint(Theme.green)

      if draft.isRecurring {
        Picker("Frequency", selection: $draft.recurringFrequency) {
          Text("Monthly").tag(RecurringFrequency.monthly)
          Text("Yearly").tag(RecurringFrequency.yearly)
        }
        .pickerStyle(.segmented)
      }
    }
    .emailReviewCard()
  }

  private var categorySelection: Binding<String> {
    Binding(
      get: { draft.categoryID ?? "" },
      set: { draft.categoryID = $0.isEmpty ? nil : $0 }
    )
  }

  private var paymentSelection: Binding<String> {
    Binding(
      get: { draft.paymentMethodID ?? "" },
      set: { draft.paymentMethodID = $0.isEmpty ? nil : $0 }
    )
  }

  private var availablePaymentMethods: [PaymentMethodOption] {
    paymentMethods.filter { !$0.archived || $0.id == draft.paymentMethodID }
  }

  private var canSave: Bool {
    guard !draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let amount = Decimal(string: draft.amount, locale: Locale(identifier: "en_US_POSIX")),
          amount > 0,
          let categoryID = draft.categoryID,
          categories.contains(where: { $0.id == categoryID }) else {
      return false
    }
    return true
  }

  private func reviewField<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
      content()
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
  }

  private func reviewWarning(_ text: String, systemImage: String, color: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(DimoFont.body(12, weight: .medium))
      .foregroundStyle(color)
      .fixedSize(horizontal: false, vertical: true)
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.dangerSoft.opacity(0.55))
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.dangerLine))
  }
}

private extension View {
  func emailReviewCard() -> some View {
    padding(15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
  }
}
