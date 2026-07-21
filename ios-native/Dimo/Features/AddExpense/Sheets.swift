import SwiftUI

struct AddExpenseSheet: View {
  @Bindable var store: AppStore
  var onManagePaymentMethods: () -> Void
  @State private var merchantSuggestions: [MerchantSuggestion] = []
  @State private var selectedMerchantSuggestion: String?
  @FocusState private var merchantFieldFocused: Bool

  var body: some View {
    SheetContainer(title: "Add expense", onClose: { store.closeOverlay() }) {
      VStack(spacing: 12) {
        Text(Formatting.currencySymbol(store.currency) + (store.expenseDraft.amount.isEmpty ? "0" : store.expenseDraft.amount))
          .font(DimoFont.display(44, weight: .bold))
          .foregroundStyle(store.expenseDraft.amount.isEmpty ? Theme.faint : Theme.ink)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)

        TextField("Merchant", text: $store.expenseDraft.name)
          .focused($merchantFieldFocused)
          .font(DimoFont.body(16))
          .padding(12)
          .background(Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        if merchantFieldFocused && !merchantSuggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(merchantSuggestions, id: \.name) { suggestion in
                Chip(label: suggestion.name, selected: false) {
                  merchantFieldFocused = false
                  selectedMerchantSuggestion = suggestion.name
                  merchantSuggestions = []
                  store.expenseDraft.name = suggestion.name
                  store.expenseDraft.category = suggestion.category
                }
              }
            }
          }
        }

        CategoryDropdown(
          categories: store.categories,
          selected: store.expenseDraft.category,
          onSelect: { store.expenseDraft.category = $0 },
          onAdd: { store.openOverlay(.category) }
        )

        PaymentMethodField(
          methods: store.paymentMethods.filter { !$0.archived },
          selectedId: store.expenseDraft.paymentMethodId,
          onSelect: { store.expenseDraft.paymentMethodId = $0 },
          onManage: {
            store.closeOverlay()
            onManagePaymentMethods()
          }
        )

        DatePicker(
          "Date",
          selection: $store.expenseDraft.date,
          in: ...Date(),
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        )
        .tint(Theme.green)

        AmountKeypad { store.pressAmountKey($0) }

        Button {
          store.saveExpense()
        } label: {
          Text("Save")
            .font(DimoFont.body(16, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSave ? Theme.green : Theme.disabled)
            .foregroundStyle(Theme.onGreen)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!canSave)
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 12)
      .background(Theme.surface)
    }
    .presentationBackground(Theme.surface)
    .onAppear { updateMerchantSuggestions(for: store.expenseDraft.name) }
    .onChange(of: store.expenseDraft.name) { _, name in
      updateMerchantSuggestions(for: name)
    }
  }

  private var canSave: Bool {
    (Double(store.expenseDraft.amount) ?? 0) > 0
      && store.categories.contains { $0.name == store.expenseDraft.category }
  }

  private func updateMerchantSuggestions(for query: String) {
    if let selectedMerchantSuggestion,
       selectedMerchantSuggestion.caseInsensitiveCompare(query) == .orderedSame {
      merchantSuggestions = []
      return
    }
    selectedMerchantSuggestion = nil
    merchantSuggestions = TransactionSelectors.merchantSuggestions(
      store.transactions,
      query: query
    )
  }
}

enum ExpenseEditorMode: Equatable {
  case create
  case transaction(String)
  case recurring(String)
  case emailSuggestion(String)
}

private struct ExpenseEditorSnapshot: Equatable {
  var name: String
  var amount: String
  var currency: String
  var category: String
  var paymentMethodId: String?
  var date: Date
  var frequency: RecurringFrequency
}

struct ExpenseEditorSheet: View {
  @Bindable var store: AppStore
  var mode: ExpenseEditorMode
  var onManagePaymentMethods: () -> Void

  @State private var name = ""
  @State private var amount = ""
  @State private var entryCurrency = "INR"
  @State private var category = ""
  @State private var paymentMethodId: String?
  @State private var date = Date()
  @State private var isRecurring = false
  @State private var frequency: RecurringFrequency = .monthly
  @State private var paused = false
  @State private var original: ExpenseEditorSnapshot?
  @State private var historicalTransactionsPrompt = false
  @State private var confirmDelete = false
  @State private var merchantSuggestions: [MerchantSuggestion] = []
  @State private var selectedMerchantSuggestion: String?
  @State private var fieldRowWidth: CGFloat = 0
  @State private var sourceEmail: EmailUIEmailDetail?
  @State private var presentedSourceEmail: EmailUIEmailDetail?
  @State private var duplicateMatches: [EmailDuplicateTransactionMatch] = []
  @FocusState private var merchantFieldFocused: Bool

  var body: some View {
    SheetContainer(
      title: title,
      onClose: close,
      titleHorizontalOffset: mode.showsDeleteButton ? 18 : 0
    ) {
      VStack(alignment: .leading, spacing: 12) {
        if let emailDraft {
          emailSuggestionContext(emailDraft)
        }

        if let sourceEmail {
          sourceEmailRow(sourceEmail)
        }

        VStack(spacing: 4) {
          HStack(spacing: 0) {
            if mode.supportsCurrencyEntry {
              currencyMenu
            } else {
              Text(Formatting.currencySymbol(store.currency))
                .font(DimoFont.display(44, weight: .bold))
            }

            Text(amount.isEmpty ? "0" : amount)
              .font(DimoFont.display(44, weight: .bold))
          }
          .foregroundStyle(amount.isEmpty ? Theme.faint : Theme.ink)

          Group {
            if let conversionCalculation {
              Text(conversionCalculation)
                .foregroundStyle(conversionAvailable ? Theme.muted : Theme.danger)
            } else {
              Color.clear
            }
          }
          .font(DimoFont.body(12))
          .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)

        TextField("Merchant", text: $name)
          .focused($merchantFieldFocused)
          .font(DimoFont.body(16))
          .padding(12)
          .background(Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        if merchantFieldFocused && !merchantSuggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(merchantSuggestions, id: \.name) { suggestion in
                Chip(label: suggestion.name, selected: false) {
                  merchantFieldFocused = false
                  selectedMerchantSuggestion = suggestion.name
                  merchantSuggestions = []
                  name = suggestion.name
                  category = suggestion.category
                }
              }
            }
          }
        }

        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Category")
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
            CategoryDropdown(
              categories: store.categories,
              selected: category,
              onSelect: { category = $0 },
              onAdd: openCategoryCreator,
              flyoutWidth: fieldRowWidth > 0 ? fieldRowWidth : nil
            )
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)

          PaymentMethodField(
            methods: availablePaymentMethods,
            selectedId: paymentMethodId,
            onSelect: { paymentMethodId = $0 },
            onManage: {
              close()
              onManagePaymentMethods()
            },
            flyoutWidth: fieldRowWidth > 0 ? fieldRowWidth : nil,
            flyoutOffset: fieldRowWidth > 0 ? -(fieldRowWidth + 10) / 2 : 0
          )
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background {
          GeometryReader { proxy in
            Color.clear
              .onAppear { fieldRowWidth = proxy.size.width }
              .onChange(of: proxy.size.width) { _, width in fieldRowWidth = width }
          }
        }

        datePicker

        if !mode.isTransactionEdit {
          recurringControls
        }

        AmountKeypad { pressAmountKey($0) }

        Button { handlePrimaryAction() } label: {
          Text(primaryButtonTitle)
            .font(DimoFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSave ? Theme.green : Theme.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 12)
      .background(Theme.surface)
    }
    .presentationBackground(Theme.surface)
    .overlay(alignment: .topTrailing) {
      if mode.showsDeleteButton {
        Button { confirmDelete = true } label: {
          Image(systemName: "trash")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .frame(width: 42, height: 42)
            .background(Theme.dangerSoft)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.dangerLine))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 20)
      }
    }
    .onAppear {
      loadRecord()
      updateMerchantSuggestions(for: name)
    }
    .onChange(of: name) { _, value in updateMerchantSuggestions(for: value) }
    .alert("Add previous transactions?", isPresented: $historicalTransactionsPrompt) {
      Button("Add all occurrences") { saveNew(selection: .all) }
      Button("Add only this expense") { saveNew(selection: .selected) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This schedule has \(historicalTransactionCount) occurrence\(historicalTransactionCount == 1 ? "" : "s") through today.")
    }
    .alert(deleteTitle, isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) { deleteRecord() }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(item: $presentedSourceEmail) { detail in
      EmailDetailSheet(detail: detail) { presentedSourceEmail = nil }
    }
    .alert(
      "Already added?",
      isPresented: Binding(
        get: { !duplicateMatches.isEmpty },
        set: { if !$0 { duplicateMatches = [] } }
      )
    ) {
      ForEach(duplicateMatches) { match in
        Button("Link to \(match.name)") { linkToExistingTransaction(match) }
      }
      Button("Add as a new expense") { acceptEmailDraft() }
      Button("Cancel", role: .cancel) { duplicateMatches = [] }
    } message: {
      Text(duplicateDialogMessage)
    }
  }

  private var title: String {
    switch mode {
    case .create: return "Add expense"
    case .transaction: return "Edit expense"
    case .recurring: return "Edit recurring expense"
    case .emailSuggestion: return "Review email suggestion"
    }
  }

  private var deleteTitle: String {
    switch mode {
    case .transaction: return "Delete this expense?"
    case .recurring: return "Delete this recurring expense?"
    case .create, .emailSuggestion: return "Delete?"
    }
  }

  private var emailDraft: EmailUIPurchaseReviewDraft? {
    guard case .emailSuggestion(let id) = mode,
          store.emailFeatureStore.purchaseReview?.suggestionID == id else { return nil }
    return store.emailFeatureStore.purchaseReview
  }

  private func emailSuggestionContext(_ draft: EmailUIPurchaseReviewDraft) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Label(draft.accountEmail, systemImage: "envelope.fill")
        Spacer(minLength: 8)
        Label(
          draft.analyzer.title,
          systemImage: draft.analyzer == .gemma ? "sparkles" : "text.magnifyingglass"
        )
      }
      .font(DimoFont.body(11, weight: .medium))
      .foregroundStyle(Theme.muted)

      if let warning = draft.currencyWarning, !warning.isEmpty {
        Label(warning, systemImage: "exclamationmark.triangle.fill")
          .font(DimoFont.body(11, weight: .medium))
          .foregroundStyle(Theme.warn)
      }
      if !draft.possibleDuplicateDescriptions.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          Label("Possible duplicate", systemImage: "doc.on.doc.fill")
            .font(DimoFont.body(11, weight: .semibold))
            .foregroundStyle(Theme.warn)
          ForEach(Array(draft.possibleDuplicateDescriptions.prefix(3).enumerated()), id: \.offset) { _, row in
            Text("• \(row)")
              .font(DimoFont.body(10))
              .foregroundStyle(Theme.muted)
          }
        }
      }
    }
    .padding(12)
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
  }

  private func sourceEmailRow(_ detail: EmailUIEmailDetail) -> some View {
    Button { presentedSourceEmail = detail } label: {
      HStack(spacing: 10) {
        Image(systemName: "envelope.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(width: 30, height: 30)
          .background(Theme.greenSoft)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        VStack(alignment: .leading, spacing: 1) {
          Text("Added from email")
            .font(DimoFont.body(11, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Text(detail.subject.isEmpty ? detail.sender : detail.subject)
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.faint)
      }
      .padding(10)
      .background(Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("View the source email for this expense")
  }

  private var availablePaymentMethods: [PaymentMethodOption] {
    store.paymentMethods.filter { !$0.archived || $0.id == paymentMethodId }
  }

  @ViewBuilder
  private var datePicker: some View {
    let components: DatePickerComponents = mode.isRecurringEdit ? [.date] : [.date, .hourAndMinute]
    if isRecurring {
      DatePicker(mode.isRecurringEdit ? "Next due date" : "Start date", selection: $date, displayedComponents: components)
        .labelsHidden()
        .datePickerStyle(.compact)
        .dateFieldStyle()
    } else {
      DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: components)
        .labelsHidden()
        .datePickerStyle(.compact)
        .dateFieldStyle()
    }
  }

  private var recurringControls: some View {
    HStack(spacing: 12) {
      Button {
        guard mode.canToggleRecurring else { return }
        isRecurring.toggle()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: isRecurring ? "checkmark.square.fill" : "square")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(isRecurring ? Theme.green : Theme.muted)
          Text("Recurring")
            .font(DimoFont.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
        }
      }
      .buttonStyle(.plain)
      .disabled(!mode.canToggleRecurring)
      .opacity(mode.canToggleRecurring ? 1 : 0.72)
      .accessibilityLabel("Recurring")
      .accessibilityValue(isRecurring ? "Checked" : "Unchecked")

      Spacer(minLength: 8)

      if isRecurring {
        Menu {
          Picker("Recurring frequency", selection: $frequency) {
            Text("Monthly").tag(RecurringFrequency.monthly)
            Text("Yearly").tag(RecurringFrequency.yearly)
          }
        } label: {
          HStack(spacing: 7) {
            Text(frequency == .monthly ? "Monthly" : "Yearly")
              .font(DimoFont.body(14, weight: .semibold))
              .foregroundStyle(Theme.ink)
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(Theme.muted)
          }
          .padding(.horizontal, 12)
          .frame(height: 36)
          .background(Theme.surface)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recurring frequency")
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 50)
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
  }

  private var currentSnapshot: ExpenseEditorSnapshot {
    ExpenseEditorSnapshot(
      name: name,
      amount: amount,
      currency: entryCurrency,
      category: category,
      paymentMethodId: paymentMethodId,
      date: date,
      frequency: frequency
    )
  }

  private var hasChanges: Bool { original.map { $0 != currentSnapshot } ?? false }

  private var primaryButtonTitle: String {
    switch mode {
    case .create: return isRecurring ? "Save recurring expense" : "Save expense"
    case .transaction: return "Save expense"
    case .recurring: return hasChanges ? "Save recurring" : (paused ? "Resume" : "Pause")
    case .emailSuggestion: return isRecurring ? "Save recurring expense" : "Save expense"
    }
  }

  private var canSave: Bool {
    guard (Double(amount) ?? 0) > 0,
          store.categories.contains(where: { $0.name == category }) else { return false }
    if isRecurring {
      return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return date <= Date()
  }

  private var hasPastStartDate: Bool {
    Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
  }

  private var historicalTransactionCount: Int {
    DateHelpers.recurringTransactionDates(
      anchorDate: DateHelpers.localDateKey(date),
      frequency: frequency,
      selection: .all
    ).count
  }

  private func handlePrimaryAction() {
    guard let value = Double(amount) else { return }
    switch mode {
    case .create:
      if isRecurring && hasPastStartDate {
        historicalTransactionsPrompt = true
      } else {
        saveNew(selection: .selected)
      }
    case .transaction(let id):
      store.saveTransactionEdits(
        id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category : name,
        amount: value, categoryName: category, paymentMethodId: paymentMethodId, date: date,
        entryCurrency: entryCurrency
      )
    case .recurring(let id):
      if hasChanges {
        store.recurringDraft = RecurringDraft(
          editingId: id,
          name: name,
          amount: amount,
          currency: entryCurrency,
          category: category,
          paymentMethodId: paymentMethodId,
          frequency: frequency,
          anchorDate: DateHelpers.localDateKey(date),
          paused: paused
        )
        store.saveRecurring()
      } else {
        store.toggleRecurring(id)
        store.closeOverlay()
      }
    case .emailSuggestion:
      guard var draft = emailDraft else { return }
      draft.merchant = name
      draft.amount = amount
      draft.occurredAt = date
      draft.categoryID = store.categories.first(where: { $0.name == category })?.id
      draft.paymentMethodID = paymentMethodId
      draft.isRecurring = isRecurring
      draft.recurringFrequency = frequency
      store.emailFeatureStore.purchaseReview = draft

      let matches = existingTransactionMatches(amount: value)
      if matches.isEmpty {
        acceptEmailDraft()
      } else {
        duplicateMatches = matches
      }
    }
  }

  /// Same amount on the same day as an expense the user already has means the
  /// email probably describes a purchase they entered by hand. Linking is only
  /// offered for a plain expense: a recurring schedule has to be created here,
  /// and linking to an existing transaction would silently drop it.
  private func existingTransactionMatches(amount value: Double) -> [EmailDuplicateTransactionMatch] {
    guard !isRecurring else { return [] }
    return EmailSuggestionSelectors.duplicateTransactionMatches(
      amountMinor: Int((value * 100).rounded()),
      dayKey: DateHelpers.localDateKey(date),
      merchant: name,
      transactions: store.transactions
    )
  }

  private func acceptEmailDraft() {
    duplicateMatches = []
    guard let draft = emailDraft else { return }
    store.emailFeatureStore.acceptPurchase(draft)
  }

  private func linkToExistingTransaction(_ match: EmailDuplicateTransactionMatch) {
    guard case .emailSuggestion(let id) = mode else { return }
    duplicateMatches = []
    store.emailFeatureStore.linkPurchaseToTransaction(
      suggestionID: id,
      transactionID: match.transactionId
    )
  }

  private var duplicateDialogMessage: String {
    let day = date.formatted(date: .abbreviated, time: .omitted)
    let amountText = CurrencyMeta.symbol(entryCurrency) + amount
    guard duplicateMatches.count == 1, let match = duplicateMatches.first else {
      return "\(duplicateMatches.count) expenses are already recorded for \(amountText) on \(day). Link this email to one of them, or add it as a separate expense."
    }
    return "\(match.name) · \(match.categoryName) is already recorded for \(amountText) on \(day). Link this email to it, or add it as a separate expense."
  }

  private func saveNew(selection: RecurringOccurrenceSelection) {
    guard let value = Double(amount) else { return }
    store.saveExpense(
      name: name,
      amount: value,
      categoryName: category,
      paymentMethodId: paymentMethodId,
      date: date,
      recurringFrequency: isRecurring ? frequency : nil,
      occurrenceSelection: selection,
      entryCurrency: entryCurrency
    )
  }

  private func close() {
    switch mode {
    case .transaction: store.closeDetail()
    case .create, .recurring: store.closeOverlay()
    case .emailSuggestion: store.emailFeatureStore.purchaseReview = nil
    }
  }

  private func openCategoryCreator() {
    if case .emailSuggestion = mode {
      store.emailFeatureStore.purchaseReview = nil
      Task { @MainActor in
        await Task.yield()
        store.openOverlay(.category)
      }
    } else {
      store.openOverlay(.category)
    }
  }

  private func deleteRecord() {
    switch mode {
    case .transaction(let id): store.deleteTransaction(id)
    case .recurring(let id): store.deleteRecurring(id)
    case .create, .emailSuggestion: break
    }
  }

  private func loadRecord() {
    switch mode {
    case .create:
      entryCurrency = store.currency.rawValue
      name = store.expenseDraft.name
      amount = store.expenseDraft.amount
      category = store.expenseDraft.category
      paymentMethodId = store.expenseDraft.paymentMethodId
      date = store.expenseDraft.date
      isRecurring = false
    case .transaction(let id):
      guard let item = store.transactions.first(where: { $0.id == id }) else { return }
      entryCurrency = item.sourceCurrency ?? item.currency ?? store.currency.rawValue
      name = item.name
      amount = formatAmount(item.sourceAmount ?? item.amount)
      category = item.category
      paymentMethodId = item.paymentMethodId
      if let occurredAt = item.occurredAt {
        date = Date(timeIntervalSince1970: TimeInterval(occurredAt) / 1000)
      }
      isRecurring = false
      sourceEmail = store.sourceEmail(forTransactionId: id)
    case .recurring(let id):
      guard let item = store.recurring.first(where: { $0.id == id }) else { return }
      entryCurrency = item.currency ?? store.currency.rawValue
      name = item.name
      amount = formatAmount(item.amount)
      category = item.category
      paymentMethodId = item.paymentMethodId
      frequency = item.frequency ?? .monthly
      date = DateHelpers.parseLocalDate(item.anchorDate ?? DateHelpers.localDateKey(Date()))
      paused = item.paused
      isRecurring = true
    case .emailSuggestion:
      guard let draft = emailDraft else { return }
      entryCurrency = store.currency.rawValue
      name = draft.merchant
      amount = draft.amount
      category = draft.categoryID.flatMap { id in
        store.categories.first(where: { $0.id == id })?.name
      } ?? ""
      paymentMethodId = draft.paymentMethodID
      date = min(draft.occurredAt, Date())
      frequency = draft.recurringFrequency
      isRecurring = draft.isRecurring
    }
    original = currentSnapshot
  }

  private func formatAmount(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
  }

  private func updateMerchantSuggestions(for query: String) {
    if let selectedMerchantSuggestion,
       selectedMerchantSuggestion.caseInsensitiveCompare(query) == .orderedSame {
      merchantSuggestions = []
      return
    }
    selectedMerchantSuggestion = nil
    merchantSuggestions = TransactionSelectors.merchantSuggestions(store.transactions, query: query)
  }

  private func pressAmountKey(_ key: String) {
    if key == "⌫" { if !amount.isEmpty { amount.removeLast() }; return }
    if key == "." { if !amount.contains(".") { amount += amount.isEmpty ? "0." : "." }; return }
    let fractionalCount = amount.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0
    if amount.contains("."), fractionalCount >= 2 { return }
    if amount.filter(\.isNumber).count >= 7 { return }
    amount = amount == "0" ? key : amount + key
  }

  private var currencyMenu: some View {
    Menu {
      ForEach(CurrencyMeta.enterable, id: \.self) { code in
        Button {
          entryCurrency = code
        } label: {
          HStack {
            Text("\(CurrencyMeta.symbol(code)) \(CurrencyMeta.label(code))")
            if code == entryCurrency { Image(systemName: "checkmark") }
          }
        }
      }
    } label: {
      HStack(spacing: 3) {
        Text(CurrencyMeta.symbol(entryCurrency))
          .font(DimoFont.display(44, weight: .bold))
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Theme.muted)
      }
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Expense currency")
    .accessibilityValue(CurrencyMeta.label(entryCurrency))
  }

  private var conversionAvailable: Bool {
    guard entryCurrency != store.currency.rawValue, (Double(amount) ?? 0) > 0 else { return true }
    return ExchangeRates.rateBetween(entryCurrency, store.currency.rawValue, store.rates) != nil
  }

  private var conversionCalculation: String? {
    let defaultCurrency = store.currency.rawValue
    guard entryCurrency != defaultCurrency, let amountValue = Double(amount), amountValue > 0 else {
      return nil
    }
    guard let rate = ExchangeRates.rateBetween(entryCurrency, defaultCurrency, store.rates),
          let convertedMinor = ExchangeRates.convertMinor(
            ExchangeRates.toMinorUnits(amountValue, entryCurrency),
            from: entryCurrency,
            to: defaultCurrency,
            rates: store.rates
          ) else {
      return "Rates unavailable"
    }
    let source = Formatting.decimal(amountValue, maximumFractionDigits: 2)
    let ratio = Formatting.decimal(rate, maximumFractionDigits: 4)
    let converted = Formatting.money(
      ExchangeRates.toMajorUnits(convertedMinor, defaultCurrency),
      currencyCode: defaultCurrency
    )
    return "\(CurrencyMeta.symbol(entryCurrency))\(source) × \(ratio) = \(converted)"
  }

}

private extension ExpenseEditorMode {
  var isTransactionEdit: Bool {
    if case .transaction = self { return true }
    return false
  }

  var isRecurringEdit: Bool {
    if case .recurring = self { return true }
    return false
  }

  var canToggleRecurring: Bool {
    switch self {
    case .create, .emailSuggestion: return true
    case .transaction, .recurring: return false
    }
  }

  var showsDeleteButton: Bool {
    switch self {
    case .transaction, .recurring: return true
    case .create, .emailSuggestion: return false
    }
  }

  var supportsCurrencyEntry: Bool {
    if case .emailSuggestion = self { return false }
    return true
  }
}

private extension View {
  func dateFieldStyle() -> some View {
    self
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .frame(height: 50)
      .background(Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
      .tint(Theme.green)
  }
}

private struct CategoryDropdown: View {
  var categories: [CategoryEntity]
  var selected: String
  var onSelect: (String) -> Void
  var onAdd: () -> Void
  var flyoutWidth: CGFloat? = nil

  @State private var isOpen = false
  @State private var query = ""
  @FocusState private var searchFocused: Bool

  private var selectedCategory: CategoryEntity? {
    categories.first { $0.name == selected }
  }

  private var filteredCategories: [CategoryEntity] {
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !search.isEmpty else { return categories.sorted { $0.sortOrder < $1.sortOrder } }
    return categories
      .filter { $0.name.localizedCaseInsensitiveContains(search) }
      .sorted { $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    VStack(spacing: 8) {
      Button {
        query = ""
        withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
        if !isOpen { searchFocused = false }
      } label: {
        HStack(spacing: 8) {
          Text(categoryLabel)
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(selected.isEmpty ? Theme.muted : Theme.ink)
            .lineLimit(1)
          Spacer()
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isOpen ? Theme.green : Theme.line, lineWidth: 1)
        )
      }
      .buttonStyle(.plain)

      if isOpen && flyoutWidth == nil {
        categoryFlyout
      }
    }
    .overlay(alignment: .topLeading) {
      if isOpen, let flyoutWidth {
        categoryFlyout
          .frame(width: flyoutWidth)
          .offset(y: 58)
      }
    }
    .padding(.bottom, isOpen && flyoutWidth != nil ? categoryFlyoutHeight + 8 : 0)
  }

  private var categoryFlyoutHeight: CGFloat {
    let resultsHeight = min(210, CGFloat(max(filteredCategories.count, 1)) * 42)
    return 123 + resultsHeight
  }

  private var categoryFlyout: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(Theme.faint)
        TextField("Search categories", text: $query)
          .font(DimoFont.body(16))
          .foregroundStyle(Theme.ink)
          .textFieldStyle(.plain)
          .focused($searchFocused)
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )

      ScrollView {
            LazyVStack(spacing: 2) {
              if filteredCategories.isEmpty {
                Text("No categories found")
                  .font(DimoFont.body(13))
                  .foregroundStyle(Theme.faint)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 14)
              } else {
                ForEach(filteredCategories) { category in
                  let isSelected = category.name == selected
                  Button {
                    onSelect(category.name)
                    searchFocused = false
                    withAnimation(.easeOut(duration: 0.18)) { isOpen = false }
                  } label: {
                    HStack {
                      Text("\(category.emoji) \(category.name)")
                        .font(DimoFont.body(14, weight: isSelected ? .semibold : .regular))
                      Spacer()
                      if isSelected {
                        Image(systemName: "checkmark")
                          .font(.system(size: 14, weight: .bold))
                      }
                    }
                    .foregroundStyle(isSelected ? Theme.greenDeep : Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(isSelected ? Theme.greenSoft : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                  }
                  .buttonStyle(.plain)
                }
              }
            }
      }
      // A max height alone collapses to zero inside a fitted presentation.
      // Give the results their intrinsic row height, capped at five rows.
      .frame(height: min(210, CGFloat(max(filteredCategories.count, 1)) * 42))

      Divider().overlay(Theme.lineSoft)

      Button {
        searchFocused = false
        onAdd()
      } label: {
        Text("+ Add category")
          .font(DimoFont.body(14, weight: .medium))
          .foregroundStyle(Theme.green)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 12)
          .frame(height: 38)
      }
      .buttonStyle(.plain)
    }
    .padding(8)
    .background(Theme.popup)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }

  private var categoryLabel: String {
    guard !selected.isEmpty else { return "Select category" }
    guard let selectedCategory else { return selected }
    return "\(selectedCategory.emoji) \(selectedCategory.name)"
  }
}

struct AddRecurringSheet: View {
  @Bindable var store: AppStore
  @State private var originalDraft: RecurringDraft?
  @State private var historicalTransactionsPrompt = false
  @State private var confirmDeleteRecurring = false
  @State private var merchantSuggestions: [MerchantSuggestion] = []
  @State private var selectedMerchantSuggestion: String?
  @FocusState private var nameFieldFocused: Bool

  var body: some View {
    SheetContainer(
      title: store.recurringDraft.editingId == nil ? "Add recurring" : "Edit recurring",
      onClose: { store.closeOverlay() },
      titleAlignment: store.recurringDraft.editingId == nil ? .center : .leading
    ) {
      VStack(alignment: .leading, spacing: 16) {
        recurringField("Name") {
          TextField("e.g. iCloud, House help, SIP", text: $store.recurringDraft.name)
            .focused($nameFieldFocused)
            .textFieldStyle(.plain)
        }

        if nameFieldFocused && !merchantSuggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(merchantSuggestions, id: \.name) { suggestion in
                Chip(label: suggestion.name, selected: false) {
                  nameFieldFocused = false
                  selectedMerchantSuggestion = suggestion.name
                  merchantSuggestions = []
                  store.recurringDraft.name = suggestion.name
                  store.recurringDraft.category = suggestion.category
                }
              }
            }
          }
        }

        recurringField("Amount") {
          HStack(spacing: 8) {
            Menu {
              ForEach(CurrencyMeta.enterable, id: \.self) { code in
                Button {
                  store.recurringDraft.currency = code
                } label: {
                  HStack {
                    Text("\(CurrencyMeta.symbol(code)) \(CurrencyMeta.label(code))")
                    if code == recurringCurrency { Image(systemName: "checkmark") }
                  }
                }
              }
            } label: {
              HStack(spacing: 3) {
                Text(CurrencyMeta.symbol(recurringCurrency))
                Image(systemName: "chevron.down")
                  .font(.system(size: 9, weight: .bold))
              }
              .foregroundStyle(Theme.muted)
              .frame(minWidth: 44, minHeight: 44)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recurring currency")
            .accessibilityValue(CurrencyMeta.label(recurringCurrency))
            TextField("0", text: $store.recurringDraft.amount)
              .keyboardType(.decimalPad)
              .textFieldStyle(.plain)
          }
        }

        RecurringDateField(anchorDate: $store.recurringDraft.anchorDate)

        VStack(alignment: .leading, spacing: 6) {
          recurringLabel("Category")
          CategoryDropdown(
            categories: store.categories,
            selected: store.recurringDraft.category,
            onSelect: { store.recurringDraft.category = $0 },
            onAdd: { store.openOverlay(.category) }
          )
        }

        PaymentMethodField(
          methods: store.paymentMethods.filter { !$0.archived },
          selectedId: store.recurringDraft.paymentMethodId,
          onSelect: { store.recurringDraft.paymentMethodId = $0 },
          onManage: nil
        )

        VStack(alignment: .leading, spacing: 8) {
          recurringLabel("Repeats")
          HStack(spacing: 8) {
            frequencyButton("Monthly", value: .monthly)
            frequencyButton("Yearly", value: .yearly)
          }
        }

        Button { handlePrimaryAction() } label: {
          Text(primaryButtonTitle)
            .font(DimoFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSave ? Theme.green : Theme.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .presentationBackground(Theme.surface)
    .overlay(alignment: .topTrailing) {
      if store.recurringDraft.editingId != nil {
        Button { confirmDeleteRecurring = true } label: {
          Image(systemName: "trash")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .frame(width: 42, height: 42)
            .background(Theme.dangerSoft)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.dangerLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 20)
      }
    }
    .onAppear {
      if store.recurringDraft.currency == nil {
        store.recurringDraft.currency = store.currency.rawValue
      }
      originalDraft = store.recurringDraft
      updateMerchantSuggestions(for: store.recurringDraft.name)
    }
    .onChange(of: store.recurringDraft.name) { _, name in
      updateMerchantSuggestions(for: name)
    }
    .alert(
      "Add previous transactions?",
      isPresented: $historicalTransactionsPrompt
    ) {
      Button("Add all \(historicalTransactionCount) transaction\(historicalTransactionCount == 1 ? "" : "s")") {
        store.saveRecurring(includeHistoricalTransactions: true)
      }
      Button("Discard previous transactions") {
        store.saveRecurring(includeHistoricalTransactions: false)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The selected start date creates \(historicalTransactionCount) transaction\(historicalTransactionCount == 1 ? "" : "s") through today.")
    }
    .alert("Delete this recurring transaction?", isPresented: $confirmDeleteRecurring) {
      Button("Delete", role: .destructive) {
        guard let id = store.recurringDraft.editingId else { return }
        store.deleteRecurring(id)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var hasChanges: Bool {
    guard let originalDraft else { return false }
    return store.recurringDraft != originalDraft
  }

  private var primaryButtonTitle: String {
    guard store.recurringDraft.editingId != nil else { return "Add recurring" }
    if hasChanges { return "Save recurring" }
    return store.recurringDraft.paused ? "Resume" : "Pause"
  }

  private var hasPastStartDate: Bool {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: DateHelpers.parseLocalDate(store.recurringDraft.anchorDate))
    return start < calendar.startOfDay(for: Date())
  }

  private var historicalTransactionCount: Int {
    DateHelpers.occurrencesThrough(
      anchorDate: store.recurringDraft.anchorDate,
      frequency: store.recurringDraft.frequency
    ).count
  }

  private func handlePrimaryAction() {
    if let editingId = store.recurringDraft.editingId {
      if hasChanges {
        store.saveRecurring()
      } else {
        store.toggleRecurring(editingId)
        store.closeOverlay()
      }
    } else if hasPastStartDate {
      historicalTransactionsPrompt = true
    } else {
      store.saveRecurring()
    }
  }

  private var canSave: Bool {
    !store.recurringDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (Double(store.recurringDraft.amount) ?? 0) > 0
      && !store.recurringDraft.anchorDate.isEmpty
  }

  private var recurringCurrency: String {
    store.recurringDraft.currency ?? store.currency.rawValue
  }

  private func updateMerchantSuggestions(for query: String) {
    if let selectedMerchantSuggestion,
       selectedMerchantSuggestion.caseInsensitiveCompare(query) == .orderedSame {
      merchantSuggestions = []
      return
    }
    selectedMerchantSuggestion = nil
    merchantSuggestions = TransactionSelectors.merchantSuggestions(
      store.transactions,
      query: query
    )
  }

  private func recurringLabel(_ title: String) -> some View {
    Text(title)
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.muted)
  }

  private func recurringField<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      recurringLabel(title)
      content()
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
  }

  private func frequencyButton(_ title: String, value: RecurringFrequency) -> some View {
    let selected = store.recurringDraft.frequency == value
    return Button(title) { store.recurringDraft.frequency = value }
      .font(DimoFont.body(15, weight: .semibold))
      .foregroundStyle(selected ? Theme.canvas : Theme.muted)
      .frame(maxWidth: .infinity)
      .frame(height: 46)
      .background(selected ? Theme.ink : Theme.canvas)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
      .buttonStyle(.plain)
  }
}

private struct RecurringDateField: View {
  @Binding var anchorDate: String

  private var date: Binding<Date> {
    Binding(
      get: { DateHelpers.parseLocalDate(anchorDate) },
      set: { anchorDate = DateHelpers.localDateKey($0) }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Start date")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)

      DatePicker("Start date", selection: date, displayedComponents: .date)
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        .tint(Theme.green)
    }
  }
}

struct NewCategorySheet: View {
  @Bindable var store: AppStore
  @State private var confirmDeleteCategory = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(store.categoryDraft.editingId == nil ? "New category" : "Edit category")
        .font(DimoFont.display(18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(
          maxWidth: .infinity,
          alignment: store.categoryDraft.editingId == nil ? .center : .leading
        )

      VStack(alignment: .leading, spacing: 8) {
        categoryLabel("Name")
        HStack(spacing: 10) {
          TextField("🙂", text: $store.categoryDraft.emoji)
            .font(.system(size: 22))
            .multilineTextAlignment(.center)
            .textFieldStyle(.plain)
            .frame(width: 50, height: 50)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))

          TextField("e.g. Pets, Travel, Health", text: $store.categoryDraft.name)
            .font(DimoFont.body(15))
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        categoryLabel("Monthly budget (optional)")
        if let lookback = categoryLookback, lookback.total > 0 {
          Text("\(Formatting.money(lookback.total, currency: store.currency)) spent over the last 6 months")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.faint)
        }
        HStack(spacing: 8) {
          Text(Formatting.currencySymbol(store.currency))
            .font(DimoFont.body(16))
            .foregroundStyle(Theme.muted)
          TextField("Amount", text: $store.categoryDraft.limitText)
            .font(DimoFont.body(15))
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))

        BudgetChipWrapLayout(spacing: 8) {
          if let suggestedBudget {
            Button {
              store.categoryDraft.limitText = String(Int(suggestedBudget))
            } label: {
              HStack(spacing: 7) {
                Text(Formatting.money(suggestedBudget, currency: store.currency))
                Text("SUGGESTED")
                  .font(DimoFont.body(9, weight: .semibold))
                  .padding(.horizontal, 7)
                  .padding(.vertical, 4)
                  .background(Theme.canvas.opacity(0.2))
                  .clipShape(Capsule())
              }
              .font(DimoFont.body(12, weight: .semibold))
              .foregroundStyle(Theme.canvas)
              .padding(.horizontal, 14)
              .frame(height: 38)
              .background(Theme.ink)
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }

          ForEach([1000, 2500, 5000, 10000], id: \.self) { amount in
            Button(Formatting.money(Double(amount), currency: store.currency)) {
              store.categoryDraft.limitText = String(amount)
            }
            .font(DimoFont.body(12, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Theme.canvas)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line))
            .buttonStyle(.plain)
          }
        }
      }

      Button(store.categoryDraft.editingId == nil ? "Create category" : "Save category") {
        store.saveCategory()
      }
      .font(DimoFont.body(16, weight: .semibold))
      .foregroundStyle(Theme.onGreen)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(canSave ? Theme.green : Theme.disabled)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .buttonStyle(.plain)
      .disabled(!canSave)
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 22)
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
    .overlay(alignment: .topTrailing) {
      if store.categoryDraft.editingId != nil {
        Button { confirmDeleteCategory = true } label: {
          Image(systemName: "trash")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .frame(width: 42, height: 42)
            .background(Theme.dangerSoft)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.dangerLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.trailing, 22)
      }
    }
    .alert("Delete this category?", isPresented: $confirmDeleteCategory) {
      Button("Delete", role: .destructive) {
        guard let id = store.categoryDraft.editingId else { return }
        store.deleteCategoryAndTransactions(id)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(categoryDeletionMessage)
    }
  }

  private var canSave: Bool {
    !store.categoryDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var categoryLookback: CategoryLookbackSpend? {
    guard let categoryId = store.categoryDraft.editingId else { return nil }
    return BudgetSelectors.categoryLookbackSpend(
      store.transactions,
      categoryId: categoryId,
      monthCount: 6
    )
  }

  private var suggestedBudget: Double? {
    guard let categoryLookback, categoryLookback.total > 0 else { return nil }
    return categoryLookback.monthlyAverage.rounded()
  }

  private var categoryDeletionMessage: String {
    let count = categoryTransactionCount
    return "This will also permanently delete \(count) transaction\(count == 1 ? "" : "s") in this category. This action cannot be undone."
  }

  private var categoryTransactionCount: Int {
    guard let categoryId = store.categoryDraft.editingId else { return 0 }
    return store.transactions.filter { $0.categoryId == categoryId }.count
  }

  private func categoryLabel(_ title: String) -> some View {
    Text(title)
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.muted)
  }
}

private struct BudgetChipWrapLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let width = proposal.width ?? .infinity
    var rowWidth: CGFloat = 0
    var totalHeight: CGFloat = 0
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if rowWidth > 0, rowWidth + spacing + size.width > width {
        totalHeight += rowHeight + spacing
        rowWidth = 0
        rowHeight = 0
      }
      rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
      rowHeight = max(rowHeight, size.height)
    }

    return CGSize(width: proposal.width ?? rowWidth, height: totalHeight + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

struct TxDetailSheet: View {
  @Bindable var store: AppStore
  var transactionId: String
  @State private var name = ""
  @State private var amount = ""
  @State private var category = ""
  @State private var paymentMethodId: String?
  @State private var date = Date()
  @State private var confirmDelete = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Edit expense")
            .font(DimoFont.display(22, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
          Button {
            confirmDelete = true
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(Theme.danger)
              .frame(width: 42, height: 42)
              .background(Theme.dangerSoft)
              .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                  .stroke(Theme.dangerLine, lineWidth: 1)
              )
          }
          .buttonStyle(.plain)
        }

        Text(Formatting.currencySymbol(store.currency) + (amount.isEmpty ? "0" : amount))
          .font(DimoFont.display(44, weight: .bold))
          .foregroundStyle(amount.isEmpty ? Theme.faint : Theme.ink)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)

        TextField("Merchant", text: $name)
          .font(DimoFont.body(16))
          .foregroundStyle(Theme.ink)
          .textFieldStyle(.plain)
          .padding(.horizontal, 14)
          .frame(height: 52)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Theme.line, lineWidth: 1)
          )

        CategoryDropdown(
          categories: store.categories,
          selected: category,
          onSelect: { category = $0 },
          onAdd: { store.openOverlay(.category) }
        )

        PaymentMethodField(
          methods: store.paymentMethods.filter { !$0.archived },
          selectedId: paymentMethodId,
          onSelect: { paymentMethodId = $0 },
          onManage: {
            store.closeDetail()
            store.setView(.settings)
          }
        )

        DatePicker(
          "Date",
          selection: $date,
          in: ...Date(),
          displayedComponents: [.date, .hourAndMinute]
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        )
        .tint(Theme.green)

        AmountKeypad { pressAmountKey($0) }

        Button {
          guard let value = Double(amount) else { return }
          store.saveTransactionEdits(
            id: transactionId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category : name,
            amount: value,
            categoryName: category,
            paymentMethodId: paymentMethodId,
            date: date
          )
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
    }
    .padding(.horizontal, 20)
    .padding(.top, 20)
    .padding(.bottom, 12)
    .background(Theme.surface)
    .onAppear {
      guard let tx = store.transactions.first(where: { $0.id == transactionId }) else { return }
      name = tx.name
      amount = formattedAmount(tx.amount)
      category = tx.category
      paymentMethodId = tx.paymentMethodId
      if let occurredAt = tx.occurredAt {
        date = Date(timeIntervalSince1970: TimeInterval(occurredAt) / 1000)
      }
    }
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
    .alert("Delete this expense?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        store.deleteTransaction(transactionId)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var canSave: Bool {
    (Double(amount) ?? 0) > 0
  }

  private func formattedAmount(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
  }

  private func pressAmountKey(_ key: String) {
    if key == "⌫" {
      if !amount.isEmpty { amount.removeLast() }
      return
    }
    if key == "." {
      if !amount.contains(".") { amount += amount.isEmpty ? "0." : "." }
      return
    }
    let fractionalCount = amount.split(separator: ".", omittingEmptySubsequences: false).last?.count ?? 0
    if amount.contains("."), fractionalCount >= 2 { return }
    if amount.filter(\.isNumber).count >= 7 { return }
    amount = amount == "0" ? key : amount + key
  }
}
