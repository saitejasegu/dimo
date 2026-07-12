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

        if !merchantSuggestions.isEmpty {
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

private struct CategoryDropdown: View {
  var categories: [CategoryEntity]
  var selected: String
  var onSelect: (String) -> Void
  var onAdd: () -> Void

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

      if isOpen {
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
    }
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

        if !merchantSuggestions.isEmpty {
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
            Text(Formatting.currencySymbol(store.currency))
              .foregroundStyle(Theme.muted)
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

        Button(primaryButtonTitle) {
          handlePrimaryAction()
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

        AmountKeypad { pressAmountKey($0) }

        Button {
          guard let value = Double(amount) else { return }
          store.saveTransactionEdits(
            id: transactionId,
            name: name,
            amount: value,
            categoryName: category,
            paymentMethodId: paymentMethodId
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
