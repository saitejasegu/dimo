import SwiftUI

struct AddExpenseSheet: View {
  @Bindable var store: AppStore

  var body: some View {
    SheetContainer(title: "Add expense", onClose: { store.closeOverlay() }) {
      VStack(spacing: 12) {
        Text(Formatting.currencySymbol(store.currency) + (store.expenseDraft.amount.isEmpty ? "0" : store.expenseDraft.amount))
          .font(DimoFont.display(44, weight: .bold))
          .foregroundStyle(store.expenseDraft.amount.isEmpty ? Theme.faint : Theme.ink)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 4)

        TextField("Merchant", text: $store.expenseDraft.name)
          .font(DimoFont.body(16))
          .padding(12)
          .background(Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        let suggestions = TransactionSelectors.merchantSuggestions(
          store.transactions,
          query: store.expenseDraft.name
        )
        if !suggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(suggestions, id: \.name) { suggestion in
                Chip(label: suggestion.name, selected: false) {
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
            store.setView(.settings)
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
  }

  private var canSave: Bool {
    (Double(store.expenseDraft.amount) ?? 0) > 0
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
          Text([selectedCategory?.emoji, selected].compactMap { $0 }.joined(separator: " "))
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(Theme.ink)
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
        .onAppear { searchFocused = true }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}

struct AddRecurringSheet: View {
  @Bindable var store: AppStore

  var body: some View {
    SheetContainer(
      title: store.recurringDraft.editingId == nil ? "Add recurring" : "Edit recurring",
      onClose: { store.closeOverlay() }
    ) {
      VStack(spacing: 16) {
        TextField("Name", text: $store.recurringDraft.name)
        TextField("Amount", text: $store.recurringDraft.amount)
          .keyboardType(.decimalPad)
        Picker("Category", selection: $store.recurringDraft.category) {
          ForEach(Array(store.limits.keys.sorted()), id: \.self) { Text($0).tag($0) }
        }
        Picker("Frequency", selection: $store.recurringDraft.frequency) {
          Text("Monthly").tag(RecurringFrequency.monthly)
          Text("Yearly").tag(RecurringFrequency.yearly)
        }
        TextField("Anchor date (YYYY-MM-DD)", text: $store.recurringDraft.anchorDate)
        if store.recurringDraft.editingId != nil {
          Toggle("Paused", isOn: $store.recurringDraft.paused)
        }
        Button("Save") { store.saveRecurring() }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
  }
}

struct NewCategorySheet: View {
  @Bindable var store: AppStore

  var body: some View {
    SheetContainer(
      title: store.categoryDraft.editingId == nil ? "New category" : "Edit category",
      onClose: { store.closeOverlay() }
    ) {
      VStack(spacing: 16) {
        TextField("Name", text: $store.categoryDraft.name)
        TextField("Emoji", text: $store.categoryDraft.emoji)
        TextField("Monthly budget", text: $store.categoryDraft.limitText)
          .keyboardType(.decimalPad)
        Picker("Tint", selection: $store.categoryDraft.tint) {
          Text("Green").tag(CategoryTint.green)
          Text("Neutral").tag(CategoryTint.neutral)
        }
        Button("Save") { store.saveCategory() }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
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
    .confirmationDialog("Delete this expense?", isPresented: $confirmDelete) {
      Button("Delete expense", role: .destructive) {
        store.deleteTransaction(transactionId)
      }
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
