import SwiftUI

struct StatsScreen: View {
  @Bindable var store: AppStore

  var body: some View {
    let scope = StatsSelectors.statsScope(range: store.statsRange, transactions: store.transactions)
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        topBar
        hero(scope)
          .padding(.top, 16)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          trendCard(scope)
          categoriesCard(scope)
          merchantsCard(scope)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .onChange(of: store.statsRange) { _, _ in
      store.selectedMonth = nil
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Text("Stats")
        .font(DimoFont.display(24, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Spacer()
      PillDropdown(
        options: StatsConstants.ranges,
        selected: store.statsRange,
        label: { StatsConstants.rangeLabel[$0] ?? $0.rawValue }
      ) { range in
        store.statsRange = range
      }
    }
    .frame(minHeight: 56)
  }

  private func hero(_ scope: StatsScope) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(scope.spentLabel)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.sideMuted)
        .padding(.bottom, 8)
      Text(Formatting.money(scope.scopeTotal, currency: store.currency))
        .font(DimoFont.display(30, weight: .semibold))
        .foregroundStyle(Theme.sideText)
        .padding(.bottom, 6)
      Text(scope.averageLabel)
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.sideSub)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder
  private func trendCard(_ scope: StatsScope) -> some View {
    let bars = StatsSelectors.trendBars(
      range: store.statsRange,
      transactions: scope.transactions,
      selectedKey: store.selectedMonth
    )
    if bars.visible {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          statsSectionTitle(bars.title)
          Spacer()
          Text(bars.caption)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
        MonthBarsView(bars: bars.bars) { key in
          store.selectedMonth = key
        }
      }
      .statsCard()
    }
  }

  private func categoriesCard(_ scope: StatsScope) -> some View {
    let cats = StatsSelectors.statCategories(
      scope: scope,
      limit: store.categoriesExpanded ? Int.max : 5
    )
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        statsSectionTitle("By category")
        Spacer()
        if cats.total > 5 {
          Button(store.categoriesExpanded ? "Show top 5" : "See all (\(cats.total))") {
            store.categoriesExpanded.toggle()
          }
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.green)
        }
      }
      VStack(alignment: .leading, spacing: 12) {
        ForEach(cats.categories) { cat in
          Button {
            store.filter = TransactionFilter(
              categories: [cat.category],
              startDate: StatsSelectors.rangeStart(store.statsRange),
              endDate: Date()
            )
            store.setView(.home)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              HStack(alignment: .firstTextBaseline) {
                Text(cat.category)
                  .font(DimoFont.body(13, weight: .medium))
                  .foregroundStyle(Theme.ink)
                Spacer()
                Text(cat.caption)
                  .font(DimoFont.body(12))
                  .foregroundStyle(Theme.muted)
              }
              StatBarTrack(value: cat.relative, fill: cat.primary ? Theme.green : Theme.barSoft)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .statsCard()
  }

  private func merchantsCard(_ scope: StatsScope) -> some View {
    let merchants = StatsSelectors.topMerchants(
      scope: scope,
      limit: store.merchantsExpanded ? Int.max : 5
    )
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        statsSectionTitle("Top merchants")
        Spacer()
        if merchants.total > 5 {
          Button(store.merchantsExpanded ? "Show top 5" : "Show all (\(merchants.total))") {
            store.merchantsExpanded.toggle()
          }
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.green)
        }
      }
      VStack(spacing: 6) {
        ForEach(merchants.merchants) { merchant in
          Button {
            store.filter = TransactionFilter(
              query: merchant.name,
              startDate: StatsSelectors.rangeStart(store.statsRange),
              endDate: Date()
            )
            store.setView(.home)
          } label: {
            HStack(spacing: 12) {
              CategoryTintView(green: merchant.green, emoji: merchant.emoji ?? "🙂", size: 34, radius: 10)
              VStack(alignment: .leading, spacing: 2) {
                Text(merchant.name)
                  .font(DimoFont.body(14, weight: .medium))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(1)
                Text(merchant.sub)
                  .font(DimoFont.body(11))
                  .foregroundStyle(Theme.muted)
                  .lineLimit(1)
              }
              Spacer()
              VStack(alignment: .trailing, spacing: 4) {
                Text(Formatting.money(merchant.amount, currency: store.currency))
                  .font(DimoFont.display(14, weight: .semibold))
                  .foregroundStyle(Theme.ink)
                StatBarTrack(value: merchant.relative, fill: Theme.green, height: 4)
                  .frame(width: 52)
              }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .statsCard()
  }

  private func statsSectionTitle(_ title: String) -> some View {
    Text(title.uppercased())
      .font(DimoFont.body(12, weight: .medium))
      .kerning(0.96)
      .foregroundStyle(Theme.muted)
  }
}

/// Horizontal bar chart matching the web MonthBars (mobile size).
private struct MonthBarsView: View {
  var bars: [MonthBar]
  var onSelect: (String) -> Void

  private var scrollable: Bool { bars.count > 7 }

  var body: some View {
    if scrollable {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          barRow
        }
        .onAppear {
          if let last = bars.last?.key {
            proxy.scrollTo(last, anchor: .trailing)
          }
        }
      }
    } else {
      barRow
    }
  }

  private var barRow: some View {
    HStack(alignment: .bottom, spacing: 2) {
      ForEach(bars) { bar in
        Button {
          onSelect(bar.key)
        } label: {
          VStack(spacing: 6) {
            Text(bar.display)
              .font(DimoFont.body(bar.wide ? 8 : 10, weight: bar.selected ? .semibold : .regular))
              .foregroundStyle(bar.selected ? Theme.green : Theme.muted)
              .lineLimit(1)
              .frame(height: 14)
            UnevenRoundedRectangle(
              topLeadingRadius: 6,
              bottomLeadingRadius: 3,
              bottomTrailingRadius: 3,
              topTrailingRadius: 6,
              style: .continuous
            )
            .fill(bar.selected ? Theme.green : Theme.bar)
            .frame(
              width: bar.wide ? 16 : 30,
              height: max(8, 62 * bar.heightRatio)
            )
            Text(bar.label)
              .font(DimoFont.body(bar.wide ? 9 : 11, weight: bar.selected ? .semibold : .regular))
              .foregroundStyle(bar.selected ? Theme.green : Theme.faint)
              .lineLimit(1)
          }
          .frame(maxWidth: scrollable ? nil : .infinity)
          .frame(width: scrollable ? 40 : nil, height: 104, alignment: .bottom)
        }
        .buttonStyle(.plain)
        .id(bar.key)
      }
    }
    .frame(maxWidth: .infinity)
  }
}

/// Thin rounded progress track matching the web ProgressBar (canvas-deep track).
private struct StatBarTrack: View {
  var value: Int
  var fill: Color
  var height: CGFloat = 6

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.canvasDeep)
        Capsule()
          .fill(fill)
          .frame(width: geo.size.width * Double(min(100, max(0, value))) / 100)
      }
    }
    .frame(height: height)
  }
}

private struct StatsCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
  }
}

private extension View {
  func statsCard() -> some View {
    modifier(StatsCardModifier())
  }
}

struct RecurringScreen: View {
  @Bindable var store: AppStore

  var body: some View {
    let total = RecurringSelectors.monthlyRecurringTotal(store.recurring)
    let active = RecurringSelectors.activeRecurring(store.recurring)
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Recurring")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
        }
        .frame(minHeight: 56)

        VStack(alignment: .leading, spacing: 0) {
          Text("Monthly recurring total")
            .font(DimoFont.body(13))
            .foregroundStyle(Theme.sideMuted)
            .padding(.bottom, 8)
          Text(Formatting.money(total, currency: store.currency))
            .font(DimoFont.display(30, weight: .semibold))
            .foregroundStyle(Theme.sideText)
            .padding(.bottom, 6)
          Text(
            active.isEmpty
              ? "No active recurring expenses"
              : "\(active.count) active · \(active[0].due.lowercased())"
          )
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.sideSub)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inverse)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 16)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        VStack(spacing: 8) {
          ForEach(store.recurring) { rec in
            recurringRow(rec)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
  }

  private func recurringRow(_ rec: Recurring) -> some View {
    Button {
      store.openEditRecurring(rec.id)
    } label: {
      HStack(spacing: 12) {
        CategoryTintView(
          green: rec.green,
          emoji: store.categoryEmoji(explicit: rec.emoji, categoryId: rec.categoryId, category: rec.category)
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(rec.name)
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(RecurringSelectors.recurringSubtitle(rec))
            .font(DimoFont.body(12, weight: !rec.paused && rec.urgent == true ? .medium : .regular))
            .foregroundStyle(subtitleColor(rec))
            .lineLimit(1)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 4) {
          Text(Formatting.money(rec.amount, currency: store.currency))
            .font(DimoFont.display(15, weight: .semibold))
            .foregroundStyle(rec.paused ? Theme.faint : Theme.ink)
          StatusBadge(label: rec.paused ? "Paused" : "Active", tone: rec.paused ? .muted : .green)
        }
      }
      .padding(12)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
      .opacity(rec.paused ? 0.65 : 1)
    }
    .buttonStyle(.plain)
  }

  private func subtitleColor(_ rec: Recurring) -> Color {
    if rec.paused { return Theme.faint }
    if rec.urgent == true { return Theme.warn }
    return Theme.muted
  }
}

struct BudgetsScreen: View {
  @Bindable var store: AppStore
  @State private var suggestedOpen = false

  var body: some View {
    let totals = BudgetSelectors.budgetTotals(store.transactions, limits: store.limits)
    let budgets = BudgetSelectors.categoryBudgets(store.transactions, limits: store.limits)
    let suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
      store.transactions,
      categories: store.categories.map { ($0.id, $0.name, $0.monthlyBudgetMinor) }
    )

    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Budgets")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
          Button {
            suggestedOpen = true
          } label: {
            Image(systemName: "sparkles")
              .font(.system(size: 18))
              .foregroundStyle(suggestions.isEmpty ? Theme.faint : Theme.green)
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
          .disabled(suggestions.isEmpty)
        }
        .frame(minHeight: 56)

        hero(totals)
          .padding(.top, 16)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        VStack(spacing: 12) {
          ForEach(budgets) { budget in
            budgetCard(budget)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .sheet(isPresented: $suggestedOpen) {
      SuggestedBudgetsSheet(store: store, suggestions: suggestions)
    }
  }

  private func hero(_ totals: BudgetTotals) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Monthly budget")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.sideMuted)
        Spacer()
        Text("\(totals.pct)% used")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.sideSub)
      }
      .padding(.bottom, 8)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(Formatting.money(totals.totalSpent, currency: store.currency))
          .font(DimoFont.display(30, weight: .semibold))
          .foregroundStyle(Theme.sideText)
        Text("of \(Formatting.money(totals.totalLimit, currency: store.currency))")
          .font(DimoFont.body(16, weight: .medium))
          .foregroundStyle(Theme.sideSub)
      }
      .padding(.bottom, 12)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.sideText.opacity(0.15))
          Capsule()
            .fill(totals.over ? Theme.warn : Theme.green)
            .frame(width: geo.size.width * Double(min(100, max(0, totals.pct))) / 100)
        }
      }
      .frame(height: 8)
      .padding(.bottom, 8)
      Text("\(Formatting.money(totals.left, currency: store.currency)) left · \(daysToGo) days to go")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.sideSub)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func budgetCard(_ budget: CategoryBudget) -> some View {
    let cat = store.categories.first(where: { $0.name == budget.category })
    return Button {
      if let id = cat?.id { store.openEditCategory(id) }
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("\(cat?.emoji.appending(" ") ?? "")\(budget.category)")
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Spacer()
          Text(
            budget.hasLimit
              ? "\(Formatting.money(budget.spent, currency: store.currency)) of \(Formatting.money(budget.limit ?? 0, currency: store.currency))"
              : "\(Formatting.money(budget.spent, currency: store.currency)) · no budget"
          )
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
        }
        StatBarTrack(
          value: budget.hasLimit ? budget.pct : 0,
          fill: budget.over ? Theme.warn : Theme.green,
          height: 8
        )
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var daysToGo: Int {
    let cal = Calendar.current
    let now = Date()
    let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
    return daysInMonth - cal.component(.day, from: now)
  }
}

private struct SuggestedBudgetsSheet: View {
  @Bindable var store: AppStore
  var suggestions: [SuggestedCategoryBudgetUpdate]
  @State private var selected: Set<String> = []
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Suggested budgets")
        .font(DimoFont.display(18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .center)

      Text("Based on the last 6 months of spend. Choose which categories to update.")
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)

      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(suggestions) { item in
            let isSelected = selected.contains(item.id)
            Button {
              if isSelected { selected.remove(item.id) }
              else { selected.insert(item.id) }
            } label: {
              HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                  .fill(isSelected ? Theme.green : Theme.canvasDeep)
                  .frame(width: 28, height: 28)
                  .overlay {
                    if isSelected {
                      Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onGreen)
                    }
                  }

                VStack(alignment: .leading, spacing: 4) {
                  let emoji = store.categories.first(where: { $0.id == item.id })?.emoji
                  Text([emoji, item.name].compactMap { $0 }.joined(separator: " "))
                    .font(DimoFont.body(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                  Text(item.currentLimit.map {
                    "Now \(Formatting.money($0, currency: store.currency))"
                  } ?? "No current budget")
                    .font(DimoFont.body(12))
                    .foregroundStyle(Theme.faint)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                  Text(Formatting.money(item.suggestedLimit, currency: store.currency))
                    .font(DimoFont.display(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                  Text("SUGGESTED")
                    .font(DimoFont.body(10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.green)
                }
              }
              .padding(.horizontal, 16)
              .frame(height: 82)
              .background(isSelected ? Theme.greenSoft.opacity(0.45) : Theme.canvas)
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(Theme.line, lineWidth: 1)
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(height: min(CGFloat(max(suggestions.count, 1)) * 92, 368))

      HStack(spacing: 12) {
        Button("Cancel") { dismiss() }
          .font(DimoFont.body(15, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .frame(width: 90, height: 54)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
          .buttonStyle(.plain)

        Button("Update \(selected.count) budget\(selected.count == 1 ? "" : "s")") {
          store.applySuggestedBudgets(selected)
          dismiss()
        }
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.onGreen)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(selected.isEmpty ? Theme.disabled : Theme.green)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 22)
    .onAppear { selected = Set(suggestions.map(\.id)) }
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
  }
}
