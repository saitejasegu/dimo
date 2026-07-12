import SwiftUI

struct HomeScreen: View {
  @Bindable var store: AppStore
  @Environment(AppEnvironment.self) private var environment
  @State private var filtersOpen = false
  @State private var visibleLimit = TransactionSelectors.homePageSize
  @State private var selecting = false
  @State private var selectedIds: Set<String> = []
  @State private var confirmDelete = false

  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        VStack(spacing: 0) {
          header
          hero
            .padding(.top, 16)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            upcomingSection
            transactionsSection
          }
          .padding(.horizontal, 22)
          .padding(.top, 16)
          .padding(.bottom, selecting ? 120 : 24)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .background(Theme.canvas.ignoresSafeArea())

      if selecting {
        selectionBar
      }
    }
    .sheet(isPresented: $filtersOpen) {
      FilterSheet(store: store)
    }
    .confirmationDialog(
      "Delete \(selectedIds.count) transaction\(selectedIds.count == 1 ? "" : "s")?",
      isPresented: $confirmDelete
    ) {
      Button("Delete", role: .destructive) {
        store.deleteTransactions(Array(selectedIds))
        selectedIds = []
        selecting = false
      }
    }
    .onChange(of: store.filter) { _, _ in
      visibleLimit = TransactionSelectors.homePageSize
    }
    .onAppear { environment.applyTheme(store.theme) }
    .onChange(of: store.theme) { _, theme in
      environment.applyTheme(theme)
    }
  }

  private var totals: BudgetTotals {
    BudgetSelectors.budgetTotals(store.transactions, limits: store.limits)
  }

  private var filtered: [Transaction] {
    TransactionSelectors.filterTransactions(store.transactions, filter: store.filter)
  }

  private var page: (items: [Transaction], hasMore: Bool) {
    TransactionSelectors.paginateTransactionsByDay(filtered, limit: visibleLimit)
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(Greeting.greetingFor())
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
        Text(store.profileName.isEmpty ? "there" : store.profileName)
          .font(DimoFont.display(22, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
      }
      Spacer()
      Button { store.openAccount() } label: {
        AvatarView(name: store.profileName, photoUrl: store.profilePhotoUrl)
      }
      .buttonStyle(.plain)
    }
    .frame(minHeight: 56)
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Spent in \(currentMonthName)")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.sideMuted)
        .padding(.bottom, 8)
      Text(Formatting.money(totals.totalSpent, currency: store.currency))
        .font(DimoFont.display(34, weight: .semibold))
        .foregroundStyle(Theme.sideText)
        .padding(.bottom, 8)
      HStack(alignment: .bottom, spacing: 16) {
        Text("\(monthTransactionCount) transactions")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.sideSub)
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("Budget left")
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.sideMuted)
          Text(Formatting.money(totals.left, currency: store.currency))
            .font(DimoFont.display(18, weight: .semibold))
            .foregroundStyle(totals.left < 0 ? Theme.danger : Theme.greenBright)
        }
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder
  private var upcomingSection: some View {
    let upcoming = RecurringSelectors.upcomingBills(store.recurring, limit: 3)
    if !upcoming.isEmpty {
      let upcomingTotal = upcoming.reduce(0) { $0 + $1.amount }
      HStack(alignment: .firstTextBaseline) {
        Text("Upcoming")
          .font(DimoFont.display(16, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Spacer()
        Button {
          store.setView(.recurring)
        } label: {
          Text(Formatting.money(upcomingTotal, currency: store.currency))
            .font(DimoFont.body(13, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
      }
      .padding(.bottom, 10)

      VStack(spacing: 8) {
        ForEach(upcoming) { rec in
          Button {
            store.setView(.recurring)
          } label: {
            HStack(spacing: 12) {
              CategoryTintView(green: rec.green, emoji: store.categoryEmoji(explicit: rec.emoji, categoryId: rec.categoryId, category: rec.category))
              VStack(alignment: .leading, spacing: 2) {
                Text(rec.name)
                  .font(DimoFont.body(14, weight: .medium))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(1)
                Text(rec.due)
                  .font(DimoFont.body(12, weight: rec.urgent == true ? .medium : .regular))
                  .foregroundStyle(rec.urgent == true ? Theme.warn : Theme.muted)
                  .lineLimit(1)
              }
              Spacer()
              Text(Formatting.money(rec.amount, currency: store.currency))
                .font(DimoFont.display(15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            }
            .cardRow()
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.bottom, 22)
    }
  }

  private var transactionsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Transactions")
          .font(DimoFont.display(16, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Spacer()
        if selecting {
          Button("Cancel") {
            selecting = false
            selectedIds = []
          }
          .font(DimoFont.body(13, weight: .medium))
          .foregroundStyle(Theme.body)
        }
        Button { filtersOpen = true } label: {
          Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(filtersActive ? Theme.green : Theme.muted)
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
      }
      .padding(.bottom, 14)

      let groups = TransactionSelectors.groupByDay(page.items)
      if groups.isEmpty {
        Text("No transactions match.")
          .font(DimoFont.body(14))
          .foregroundStyle(Theme.faint)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 48)
      }
      ForEach(groups, id: \.label) { group in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(group.label.uppercased())
              .font(DimoFont.body(12, weight: .medium))
              .kerning(0.96)
              .foregroundStyle(Theme.muted)
            Spacer()
            Text(Formatting.spent(group.total, currency: store.currency))
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.faint)
          }
          ForEach(group.items) { tx in
            transactionRow(tx)
          }
        }
        .padding(.bottom, 18)
      }

      if page.hasMore {
        Button {
          visibleLimit += TransactionSelectors.homePageSize
        } label: {
          Text("Load more")
            .font(DimoFont.body(13, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
      }
    }
  }

  private func transactionRow(_ tx: Transaction) -> some View {
    let selected = selectedIds.contains(tx.id)
    return Button {
      if selecting {
        if selected { selectedIds.remove(tx.id) } else { selectedIds.insert(tx.id) }
      } else {
        store.openDetail(tx.id)
      }
    } label: {
      HStack(spacing: 12) {
        if selecting {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Theme.green : Theme.surface)
            .frame(width: 20, height: 20)
            .overlay(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(selected ? Theme.green : Theme.line, lineWidth: 2)
            )
            .overlay {
              if selected {
                Image(systemName: "checkmark")
                  .font(.system(size: 10, weight: .bold))
                  .foregroundStyle(Theme.onGreen)
              }
            }
        } else {
          CategoryTintView(green: tx.green, emoji: store.categoryEmoji(explicit: tx.emoji, categoryId: tx.categoryId, category: tx.category))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(tx.name)
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text("\(tx.category) · \(tx.time)")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        Spacer()
        Text(Formatting.spent(tx.amount, currency: store.currency))
          .font(DimoFont.display(15, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
      .cardRow(
        borderColor: selecting && selected ? Theme.green : Theme.line,
        background: selecting && selected ? Theme.greenSoft.opacity(0.4) : Theme.surface
      )
    }
    .buttonStyle(.plain)
    .onLongPressGesture {
      guard !selecting else { return }
      selecting = true
      selectedIds = [tx.id]
    }
  }

  private var selectionBar: some View {
    HStack {
      Text("\(selectedIds.count) selected")
        .font(DimoFont.body(14, weight: .medium))
      Spacer()
      Button("Delete") { confirmDelete = true }
        .font(DimoFont.body(14, weight: .semibold))
        .foregroundStyle(Theme.danger)
        .disabled(selectedIds.isEmpty)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) { Divider().overlay(Theme.line) }
    .padding(.bottom, 8)
  }

  private var filtersActive: Bool {
    !store.filter.categories.isEmpty
      || store.filter.paymentMethod != "All"
      || !store.filter.query.isEmpty
  }

  private var currentMonthName: String {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMM")
    return formatter.string(from: Date())
  }

  private var monthTransactionCount: Int {
    let cal = Calendar.current
    let now = Date()
    return store.transactions.filter {
      guard let at = $0.occurredAt else { return false }
      let d = Date(timeIntervalSince1970: TimeInterval(at) / 1000)
      return cal.isDate(d, equalTo: now, toGranularity: .month)
    }.count
  }
}

/// The rounded-square emoji swatch used in list rows, matching the web CategoryTint.
struct CategoryTintView: View {
  var green: Bool?
  var emoji: String
  var size: CGFloat = 38
  var radius: CGFloat = 11

  var body: some View {
    Text(emoji)
      .font(.system(size: 17))
      .frame(width: size, height: size)
      .background(green == true ? Theme.greenSoft : Theme.canvasDeep)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

/// Bordered white card treatment shared by home list rows, matching the web card rows.
private struct CardRowModifier: ViewModifier {
  var borderColor: Color
  var background: Color

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .background(background)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      )
  }
}

private extension View {
  func cardRow(borderColor: Color = Theme.line, background: Color = Theme.surface) -> some View {
    modifier(CardRowModifier(borderColor: borderColor, background: background))
  }
}

private struct FilterSheet: View {
  @Bindable var store: AppStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
        Text("Filter transactions")
          .font(DimoFont.display(18, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .frame(maxWidth: .infinity, alignment: .center)

        VStack(alignment: .leading, spacing: 8) {
          filterLabel("Search")
          HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 17, weight: .medium))
              .foregroundStyle(Theme.faint)
            TextField("Search merchant or category", text: $store.filter.query)
              .font(DimoFont.body(16))
              .foregroundStyle(Theme.ink)
              .textFieldStyle(.plain)
          }
          .padding(.horizontal, 14)
          .frame(height: 50)
          .background(Theme.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Theme.line, lineWidth: 1)
          )
        }

        VStack(alignment: .leading, spacing: 8) {
          filterLabel("Categories")
          FilterCategoryDropdown(
            categories: store.categories,
            selected: $store.filter.categories
          )
        }
        .zIndex(2)

        VStack(alignment: .leading, spacing: 8) {
          filterLabel("Payment methods")
          FilterPaymentDropdown(
            methods: store.paymentMethods.filter { !$0.archived },
            selection: $store.filter.paymentMethod
          )
        }
        .zIndex(1)

        HStack(spacing: 12) {
          ActionButton(title: "Clear", variant: .secondary) {
            store.filter = TransactionFilter()
            dismiss()
          }
          ActionButton(title: "Done", variant: .accent) {
            dismiss()
          }
        }
    }
    .padding(.horizontal, 22)
    .padding(.top, 24)
    .padding(.bottom, 22)
    .background(Theme.surface)
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
  }

  private func filterLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(DimoFont.body(12, weight: .semibold))
      .foregroundStyle(Theme.muted)
      .tracking(0.8)
  }
}

private struct FilterCategoryDropdown: View {
  var categories: [CategoryEntity]
  @Binding var selected: [String]
  @State private var isOpen = false
  @State private var query = ""

  private var label: String {
    if selected.isEmpty { return "All categories" }
    if selected.count == 1, let name = selected.first {
      let emoji = categories.first { $0.name == name }?.emoji
      return [emoji, name].compactMap { $0 }.joined(separator: " ")
    }
    return "\(selected.count) categories"
  }

  private var filtered: [CategoryEntity] {
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return categories.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    ZStack(alignment: .top) {
      dropdownTrigger(label: label, isOpen: isOpen) {
        query = ""
        withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
      }

      if isOpen {
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField("Search categories", text: $query)
              .font(DimoFont.body(15))
              .textFieldStyle(.plain)
          }
          .padding(.horizontal, 12)
          .frame(height: 42)
          .background(Theme.surface)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line))

          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(filtered) { category in
                let checked = selected.contains(category.name)
                Button {
                  if checked {
                    selected.removeAll { $0 == category.name }
                  } else {
                    selected.append(category.name)
                  }
                } label: {
                  HStack {
                    Text("\(category.emoji) \(category.name)")
                      .font(DimoFont.body(14, weight: checked ? .semibold : .regular))
                    Spacer()
                    if checked { Image(systemName: "checkmark").fontWeight(.bold) }
                  }
                  .foregroundStyle(checked ? Theme.greenDeep : Theme.ink)
                  .padding(.horizontal, 12)
                  .frame(height: 40)
                  .background(checked ? Theme.greenSoft : .clear)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
          .frame(height: min(160, CGFloat(max(filtered.count, 1)) * 40))
        }
        .filterPopup()
        .offset(y: 58)
      }
    }
    .frame(height: 50)
  }
}

private struct FilterPaymentDropdown: View {
  var methods: [PaymentMethodOption]
  @Binding var selection: String
  @State private var isOpen = false

  private var selectedMethod: PaymentMethodOption? {
    methods.first { $0.label == selection }
  }

  var body: some View {
    ZStack(alignment: .top) {
      dropdownTrigger(
        label: selectedMethod?.label ?? "All payment methods",
        isOpen: isOpen
      ) {
        withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
      }

      if isOpen {
        VStack(spacing: 4) {
          paymentRow(name: "All payment methods", detail: "", checked: selection == "All") {
            selection = "All"
            isOpen = false
          }
          ForEach(methods) { method in
            paymentRow(
              name: method.name,
              detail: [method.type.rawValue, method.detail].filter { !$0.isEmpty }.joined(separator: " · "),
              checked: selection == method.label
            ) {
              selection = method.label
              isOpen = false
            }
          }
        }
        .filterPopup()
        .offset(y: 58)
      }
    }
    .frame(height: 50)
  }

  private func paymentRow(
    name: String,
    detail: String,
    checked: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(name).font(DimoFont.body(14, weight: checked ? .semibold : .regular))
          if !detail.isEmpty {
            Text(detail).font(DimoFont.body(12)).foregroundStyle(Theme.muted)
          }
        }
        Spacer()
        if checked { Image(systemName: "checkmark").fontWeight(.bold) }
      }
      .foregroundStyle(checked ? Theme.greenDeep : Theme.ink)
      .padding(.horizontal, 12)
      .frame(height: detail.isEmpty ? 42 : 54)
      .background(checked ? Theme.greenSoft : .clear)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}

private func dropdownTrigger(
  label: String,
  isOpen: Bool,
  action: @escaping () -> Void
) -> some View {
  Button(action: action) {
    HStack {
      Text(label)
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
      Spacer()
      Image(systemName: "chevron.down")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .rotationEffect(.degrees(isOpen ? 180 : 0))
    }
    .padding(.horizontal, 14)
    .frame(height: 50)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(isOpen ? Theme.green : Theme.line, lineWidth: 1)
    )
  }
  .buttonStyle(.plain)
}

private extension View {
  func filterPopup() -> some View {
    self
      .padding(8)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
      .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
      .transition(.opacity.combined(with: .move(edge: .top)))
  }
}
