import SwiftUI

struct StatsScreen: View {
  var store: AppStore
  @Bindable var entities: EntitiesStore
  @Bindable var nav: NavStore
  @State private var txSheet: StatsTxSelection?
  /// Global frame of the trend chart while it scrolls horizontally on its own; `.zero` otherwise.
  @State private var chartScrollFrame: CGRect = .zero
  /// Direction of the last period change: +1 toward newer periods, -1 toward older ones,
  /// 0 when the content changed for another reason and should just crossfade.
  @State private var pageStep = 0
  /// Damped follow of an in-progress swipe, so the page reacts before it commits.
  @State private var dragOffset: CGFloat = 0

  private var statsInputs: StatsInputs {
    StatsInputs(
      revision: entities.revision,
      range: nav.statsRange,
      periodOffset: nav.statsPeriodOffset,
      selectedMonth: nav.selectedMonth,
      categoriesExpanded: nav.categoriesExpanded,
      merchantsExpanded: nav.merchantsExpanded
    )
  }

  var body: some View {
    let scope = entities.statsScope
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        topBar
        periodNav(scope)
          .padding(.top, 4)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)

      // The period's figures live in one keyed subtree so stepping periods slides the
      // old numbers out and the new ones in rather than swapping them in place.
      ZStack(alignment: .top) {
        periodPage(scope)
          .id(scope.periodLabel)
          .transition(pageTransition)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .offset(x: dragOffset)
      // The projection lands asynchronously, so the page animates off the delivered
      // label rather than the offset the tap or swipe set.
      .animation(.snappy(duration: 0.28), value: scope.periodLabel)
    }
    .background(Theme.canvas.ignoresSafeArea())
    // Whole-screen horizontal swipe mirrors the period chevrons; vertical scrolls stay free.
    .simultaneousGesture(periodSwipeGesture)
    // Stats projections are the heaviest derived work in the app, so they are computed
    // only while this screen is on screen rather than on every hydrate.
    .onAppear { entities.setStatsVisible(true, inputs: statsInputs) }
    .onDisappear { entities.setStatsVisible(false, inputs: statsInputs) }
    .onChange(of: nav.statsRange) { _, _ in
      // A new range reinterprets the offset's length, so snap back to current.
      pageStep = 0
      store.statsPeriodOffset = 0
      store.selectedMonth = nil
    }
    .sheet(item: $txSheet) { selection in
      let matching = entities.statsScope.transactions.filter { tx in
        switch selection.kind {
        case .category: tx.category == selection.name
        case .merchant: tx.name == selection.name
        }
      }
      StatsTransactionListSheet(
        entities: entities,
        store: store,
        title: selection.name,
        transactions: matching
      )
    }
  }

  /// Everything that belongs to the shown period: the hero total and the three cards.
  private func periodPage(_ scope: StatsScope) -> some View {
    VStack(spacing: 0) {
      hero(scope)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          trendCard
          categoriesCard
          merchantsCard
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
      .onScrollPhaseChange { _, phase in
        store.setUIScrolling(phase != .idle)
      }
      // A period change replaces this scroll view mid-scroll, which would otherwise
      // strand the flag that pauses background email work.
      .onDisappear { store.setUIScrolling(false) }
    }
  }

  /// Older periods arrive from the leading edge, newer ones from the trailing edge, so
  /// the motion matches the chevron or swipe that asked for them. The first projection
  /// to land and range switches have no direction, so they crossfade instead.
  private var pageTransition: AnyTransition {
    guard pageStep != 0 else { return .opacity }
    let insertion: Edge = pageStep > 0 ? .trailing : .leading
    let removal: Edge = pageStep > 0 ? .leading : .trailing
    return .asymmetric(
      insertion: .move(edge: insertion).combined(with: .opacity),
      removal: .move(edge: removal).combined(with: .opacity)
    )
  }

  private func step(by delta: Int) {
    pageStep = delta
    store.statsPeriodOffset = nav.statsPeriodOffset + delta
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Text("Stats")
        .font(DimoFont.display(24, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Spacer()
      PillDropdown(
        options: StatsConstants.ranges,
        selected: nav.statsRange,
        label: { StatsConstants.rangeLabel[$0] ?? $0.rawValue }
      ) { range in
        store.statsRange = range
      }
    }
    .frame(minHeight: 56)
  }

  private func periodNav(_ scope: StatsScope) -> some View {
    let isCurrent = nav.statsPeriodOffset == 0
    let canGoBack = StatsSelectors.hasEarlierData(
      entities.transactions,
      range: nav.statsRange,
      offset: nav.statsPeriodOffset
    )
    // One bordered row rather than free-floating chevrons, matching the web nav.
    return HStack(spacing: 12) {
      periodStep(systemName: "chevron.left", enabled: canGoBack) {
        step(by: -1)
      }
      Spacer(minLength: 0)
      Button {
        // Offsets only run backwards, so returning to current always moves newer.
        pageStep = 1
        store.statsPeriodOffset = 0
      } label: {
        Text(scope.periodLabel)
          .font(DimoFont.body(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
      }
      .buttonStyle(.plain)
      .disabled(isCurrent)
      Spacer(minLength: 0)
      periodStep(systemName: "chevron.right", enabled: !isCurrent) {
        step(by: 1)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }

  private func periodStep(
    systemName: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(enabled ? Theme.ink : Theme.disabled)
        // Keeps a 32pt tap target without drawing a nested box.
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  /// Swipe right → older period (left chevron); swipe left → newer (right chevron).
  private var periodSwipeGesture: some Gesture {
    DragGesture(minimumDistance: 40, coordinateSpace: .global)
      .onChanged { value in
        guard isPeriodSwipe(value) else { return }
        // Damped, capped follow measured past the recognition threshold, so the page
        // picks the drag up smoothly instead of jumping when the gesture engages.
        let slack = max(0, abs(value.translation.width) - 40)
        dragOffset = (value.translation.width < 0 ? -1 : 1) * min(48, slack * 0.3)
      }
      .onEnded { value in
        withAnimation(.snappy(duration: 0.28)) { dragOffset = 0 }
        guard isPeriodSwipe(value) else { return }

        let horizontal = value.translation.width
        // Require a decisive flick so an incidental sideways drift does nothing.
        guard abs(horizontal) >= 80 else { return }

        if horizontal > 0 {
          let canGoBack = StatsSelectors.hasEarlierData(
            entities.transactions,
            range: nav.statsRange,
            offset: nav.statsPeriodOffset
          )
          guard canGoBack else { return }
          step(by: -1)
        } else {
          guard nav.statsPeriodOffset < 0 else { return }
          step(by: 1)
        }
      }
  }

  /// A drag counts as a period swipe when it is clearly horizontal and did not start on
  /// the trend chart, whose own scroll view owns horizontal drags.
  private func isPeriodSwipe(_ value: DragGesture.Value) -> Bool {
    guard !chartScrollFrame.contains(value.startLocation) else { return false }
    return abs(value.translation.width) > abs(value.translation.height) * 1.5
  }

  private func hero(_ scope: StatsScope) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(scope.spentLabel)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.sideMuted)
        .padding(.bottom, 8)
      Text(Formatting.money(scope.scopeTotal, currency: entities.currency))
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
  private var trendCard: some View {
    let bars = entities.statsTrendBars
    if bars.visible {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          statsSectionTitle(bars.title)
          Spacer()
          Text(bars.caption)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
        MonthBarsView(bars: bars.bars, scrollFrame: $chartScrollFrame) { key in
          store.selectedMonth = key
        }
      }
      .statsCard()
    }
  }

  private var categoriesCard: some View {
    let cats = entities.statsCategories
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        statsSectionTitle("By category")
        Spacer()
        if cats.total > 5 {
          Button(nav.categoriesExpanded ? "Show top 5" : "See all (\(cats.total))") {
            store.categoriesExpanded.toggle()
          }
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.green)
        }
      }
      VStack(alignment: .leading, spacing: 12) {
        ForEach(cats.categories) { cat in
          Button {
            txSheet = StatsTxSelection(kind: .category, name: cat.category)
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

  private var merchantsCard: some View {
    let merchants = entities.statsMerchants
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        statsSectionTitle("Top merchants")
        Spacer()
        if merchants.total > 5 {
          Button(nav.merchantsExpanded ? "Show top 5" : "Show all (\(merchants.total))") {
            store.merchantsExpanded.toggle()
          }
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.green)
        }
      }
      VStack(spacing: 6) {
        ForEach(merchants.merchants) { merchant in
          Button {
            txSheet = StatsTxSelection(kind: .merchant, name: merchant.name)
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
                Text(Formatting.money(merchant.amount, currency: entities.currency))
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

private struct StatsTxSelection: Identifiable {
  enum Kind: String { case category, merchant }
  var kind: Kind
  var name: String
  var id: String { "\(kind.rawValue):\(name)" }
}

/// Read-only list of the scoped transactions behind a stats row, styled like home rows.
private struct StatsTransactionListSheet: View {
  var entities: EntitiesStore
  var store: AppStore
  var title: String
  var transactions: [Transaction]

  var body: some View {
    let groups = TransactionSelectors.groupByDay(transactions)
    VStack(spacing: 16) {
      Text(title)
        .font(DimoFont.display(18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .center)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(groups, id: \.label) { group in
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline) {
                Text(group.label.uppercased())
                  .font(DimoFont.body(12, weight: .medium))
                  .kerning(0.96)
                  .foregroundStyle(Theme.muted)
                Spacer()
                Text(Formatting.spent(group.total, currency: entities.currency))
                  .font(DimoFont.body(12))
                  .foregroundStyle(Theme.faint)
              }
              ForEach(group.items) { tx in
                transactionRow(tx)
              }
            }
          }
        }
      }
      .frame(height: listHeight(groups))
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 22)
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
  }

  private func listHeight(_ groups: [DayGroup]) -> CGFloat {
    let rows = CGFloat(transactions.count) * 68
    let headers = CGFloat(groups.count) * 34
    return min(max(rows + headers, 120), 460)
  }

  private func transactionRow(_ tx: Transaction) -> some View {
    HStack(spacing: 12) {
      CategoryTintView(
        green: tx.green,
        emoji: store.categoryEmoji(explicit: tx.emoji, categoryId: tx.categoryId, category: tx.category)
      )
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
      Text(Formatting.spent(tx.amount, currency: entities.currency))
        .font(DimoFont.display(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }
}

/// Horizontal bar chart matching the web MonthBars (mobile size).
private struct MonthBarsView: View {
  var bars: [MonthBar]
  /// Reports the chart's frame while it owns horizontal drags, so the page-level period
  /// swipe can skip them; stays `.zero` when the bars fit and nothing scrolls.
  @Binding var scrollFrame: CGRect
  var onSelect: (String) -> Void

  private var scrollable: Bool { bars.count > 7 }

  var body: some View {
    if scrollable {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
          barRow
        }
        .onGeometryChange(for: CGRect.self) { geometry in
          geometry.frame(in: .global)
        } action: { frame in
          scrollFrame = frame
        }
        .onAppear {
          if let last = bars.last?.key {
            proxy.scrollTo(last, anchor: .trailing)
          }
        }
      }
    } else {
      barRow
        .onAppear { scrollFrame = .zero }
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
    let total = RecurringSelectors.monthlyRecurringTotal(store.recurring) { recurring in
      ExchangeRates.recurringAmountInDefault(
        recurring,
        defaultCurrency: store.currency.rawValue,
        rates: store.rates
      )
    }
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
        LazyVStack(spacing: 8) {
          ForEach(store.recurring) { rec in
            recurringRow(rec)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        // Clears the floating add button overlaying the list's bottom edge.
        .padding(.bottom, 110)
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
          Text(
            Formatting.money(
              rec.amount,
              currencyCode: rec.currency ?? store.currency.rawValue
            )
          )
            .font(DimoFont.display(15, weight: .semibold))
            .foregroundStyle(rec.paused ? Theme.faint : Theme.ink)
          if let estimate = rec.convertedEstimateLabel {
            Text(estimate)
              .font(DimoFont.body(11))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }
          StatusBadge(label: rec.paused ? "Paused" : "Active", tone: rec.paused ? .muted : .green)
        }
        .fixedSize(horizontal: true, vertical: false)
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
  var store: AppStore
  @Bindable var entities: EntitiesStore
  @State private var suggestedOpen = false
  @State private var totalOpen = false

  var body: some View {
    let totals = entities.monthBudgetTotals
    let budgets = entities.categoryBudgets
    let suggestions = entities.suggestedBudgetUpdates

    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Budgets")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
          Button {
            totalOpen = true
          } label: {
            Image(systemName: "target")
              .font(.system(size: 18))
              .foregroundStyle(Theme.green)
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Set monthly budget")
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
        LazyVStack(spacing: 12) {
          ForEach(budgets) { budget in
            budgetCard(budget)
          }
          if !archivedCategories.isEmpty {
            archivedSection(archivedCategories)
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        // Clears the floating add button overlaying the list's bottom edge.
        .padding(.bottom, 110)
      }
      .onScrollPhaseChange { _, phase in
        store.setUIScrolling(phase != .idle)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .sheet(isPresented: $suggestedOpen) {
      SuggestedBudgetsSheet(store: store, suggestions: suggestions)
    }
    .sheet(isPresented: $totalOpen) {
      GlobalBudgetSheet(store: store)
    }
  }

  private var archivedCategories: [CategoryEntity] {
    entities.categories.filter(\.archived)
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
        Text(Formatting.money(totals.totalSpent, currency: entities.currency))
          .font(DimoFont.display(30, weight: .semibold))
          .foregroundStyle(Theme.sideText)
        Text("of \(Formatting.money(totals.totalLimit, currency: entities.currency))")
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
      Text("\(Formatting.money(totals.left, currency: entities.currency)) left · \(daysToGo) days to go")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.sideSub)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func budgetCard(_ budget: CategoryBudget) -> some View {
    let cat = entities.categories.first(where: { $0.name == budget.category })
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
              ? "\(Formatting.money(budget.spent, currency: entities.currency)) of \(Formatting.money(budget.limit ?? 0, currency: entities.currency))"
              : "\(Formatting.money(budget.spent, currency: entities.currency)) · no budget"
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

  private func archivedSection(_ archivedCategories: [CategoryEntity]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Archived")
        .font(DimoFont.body(12, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.top, 8)
      VStack(spacing: 0) {
        ForEach(archivedCategories) { category in
          Button {
            store.openEditCategory(category.id)
          } label: {
            HStack {
              Text("\(category.emoji) \(category.name)")
                .font(DimoFont.body(14, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
              Spacer()
              Text("Archived")
                .font(DimoFont.body(10, weight: .medium))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.canvasDeep)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
          }
          .buttonStyle(.plain)
          if category.id != archivedCategories.last?.id {
            Divider().overlay(Theme.lineSoft)
          }
        }
      }
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
      Text("Archived categories stay attached to past transactions.")
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
    }
  }

  private var daysToGo: Int {
    let cal = Calendar.current
    let now = Date()
    let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
    return daysInMonth - cal.component(.day, from: now)
  }
}

private struct GlobalBudgetSheet: View {
  @Bindable var store: AppStore
  @State private var amount: String
  @State private var initialAmount: String
  @State private var drafts: [String: String]?
  @Environment(\.dismiss) private var dismiss

  init(store: AppStore) {
    self.store = store
    let currentMinor = store.categories.filter { !$0.archived }.reduce(0) { $0 + ($1.monthlyBudgetMinor ?? 0) }
    let initial = currentMinor > 0
      ? String(Int((Double(currentMinor) / 100).rounded()))
      : ""
    _amount = State(initialValue: initial)
    _initialAmount = State(initialValue: initial)
    _drafts = State(initialValue: nil)
  }

  private var activeCategories: [CategoryEntity] {
    store.categories.filter { !$0.archived }
  }

  private var parsedAmount: Int? {
    guard !amount.isEmpty,
          amount.allSatisfy(\.isNumber),
          let value = Int(amount),
          value > 0,
          value <= Int.max / 100 else { return nil }
    return value
  }

  private var allocation: GlobalBudgetAllocation {
    BudgetSelectors.globalBudgetAllocation(
      store.transactions,
      categories: activeCategories.map {
        GlobalBudgetCategoryInput(
          id: $0.id,
          name: $0.name,
          sortOrder: $0.sortOrder,
          monthlyBudgetMinor: $0.monthlyBudgetMinor
        )
      },
      totalBudget: parsedAmount ?? 0
    )
  }

  private var customizing: Bool { drafts != nil }

  private var proposing: Bool { !customizing && amount != initialAmount }

  private var displayedLimits: [GlobalBudgetLimitUpdate] {
    allocation.allocations.map { item in
      let limit: Int?
      if let drafts {
        limit = Self.parseLimit(drafts[item.id])
      } else if proposing {
        limit = item.allocatedLimit
      } else {
        limit = Self.wholeLimit(item.currentLimit)
      }
      return GlobalBudgetLimitUpdate(id: item.id, allocatedLimit: limit)
    }
  }

  private var changedCount: Int {
    zip(allocation.allocations, displayedLimits).filter { item, displayed in
      Self.currentDiffers(item.currentLimit, displayed.allocatedLimit)
    }.count
  }

  private var canApply: Bool {
    !activeCategories.isEmpty
      && parsedAmount != nil
      && changedCount > 0
      && (customizing || allocation.canApply)
  }

  private var validationMessage: String? {
    if activeCategories.isEmpty {
      return "Create a category before setting a total budget."
    }
    if proposing && allocation.issue == .noHistory {
      return "No spending was found in the last 6 completed months. Enter amounts on each category below, or wait until there is enough history for a split."
    }
    if !amount.isEmpty && parsedAmount == nil {
      return "Enter a whole monthly amount greater than zero."
    }
    if (proposing || customizing), parsedAmount != nil, changedCount == 0 {
      return "Your category budgets already match these amounts."
    }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Set monthly budget")
        .font(DimoFont.display(18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .center)

      Text("Set one monthly total to split from spending in \(lookbackLabel), or edit any category — the total follows the sum.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 7) {
        Text("Monthly total")
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.muted)
        HStack(spacing: 8) {
          Text(Formatting.currencySymbol(store.currency))
            .font(DimoFont.body(16))
            .foregroundStyle(Theme.muted)
          TextField("Amount", text: Binding(
            get: { amount },
            set: { handleTotalChange($0) }
          ))
            .font(DimoFont.body(15))
            .keyboardType(.numberPad)
            .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))

        if let validationMessage {
          Text(validationMessage)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(Array(allocation.allocations.enumerated()), id: \.element.id) { index, item in
            if index > 0 { Divider().overlay(Theme.line) }
            HStack(spacing: 12) {
              Text(store.categories.first(where: { $0.id == item.id })?.emoji ?? "🙂")
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Theme.canvasDeep)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

              VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                  .font(DimoFont.body(14, weight: .medium))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(1)
                Text(
                  item.sixMonthSpend > 0
                    ? "\(Formatting.money(item.monthlyAverage, currency: store.currency)) monthly average · \(item.share)%"
                    : "No spending history · no allocation"
                )
                  .font(DimoFont.body(11))
                  .foregroundStyle(Theme.faint)
                  .lineLimit(2)
              }
              Spacer(minLength: 8)
              VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                  Text(Formatting.currencySymbol(store.currency))
                    .font(DimoFont.body(13))
                    .foregroundStyle(Theme.muted)
                  TextField("0", text: Binding(
                    get: { categoryFieldValue(item) },
                    set: { handleCategoryChange(item.id, $0) }
                  ))
                    .font(DimoFont.body(14, weight: .semibold))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .frame(width: 72)
                    .accessibilityLabel("\(item.name) monthly budget")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line)
                )
                Text(item.sixMonthSpend > 0 && proposing ? "PROPOSED" : "BUDGET")
                  .font(DimoFont.body(9, weight: .semibold))
                  .kerning(0.4)
                  .foregroundStyle(item.sixMonthSpend > 0 && proposing ? Theme.green : Theme.muted)
              }
              .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
          }
          if allocation.allocations.isEmpty {
            Text("No categories yet.")
              .font(DimoFont.body(14))
              .foregroundStyle(Theme.muted)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 28)
          }
        }
      }
      // The list is full of amount fields, and its height is capped, so the
      // relayout when the keyboard opens reads as a scroll. Under the default
      // mode that scroll closes the keyboard the instant a field is tapped.
      .scrollDismissesKeyboard(.never)
      .frame(maxHeight: 360)
      .background(Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))

      Text("Changing the total proposes a new split. Editing a category updates the total to match. Apply replaces every category budget with the amounts shown here.")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvasDeep)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      HStack(spacing: 12) {
        Button("Cancel") { dismiss() }
          .font(DimoFont.body(15, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .frame(width: 90, height: 54)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))
          .buttonStyle(.plain)

        Button(applyTitle) {
          guard canApply else { return }
          store.applyGlobalBudget(displayedLimits)
          dismiss()
        }
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(canApply ? Theme.onGreen : Theme.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(canApply ? Theme.green : Theme.disabled)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .buttonStyle(.plain)
        .disabled(!canApply)
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 22)
    // This sheet sets its own detent, so it does not get the background
    // tap-to-dismiss that contentHeightSheet() installs for the other sheets.
    .dismissesKeyboardOnBackgroundTap()
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
  }

  private var applyTitle: String {
    if (proposing || customizing), parsedAmount != nil, changedCount == 0 {
      return "Already applied"
    }
    return customizing ? "Apply budgets" : "Apply split"
  }

  private var lookbackLabel: String {
    let calendar = Calendar.current
    let first = Date(timeIntervalSince1970: Double(allocation.window.start) / 1000)
    let end = Date(timeIntervalSince1970: Double(allocation.window.end) / 1000)
    let last = calendar.date(byAdding: .month, value: -1, to: end) ?? end
    let month = DateFormatter()
    month.dateFormat = "MMM"
    let monthYear = DateFormatter()
    monthYear.dateFormat = "MMM yyyy"
    if calendar.component(.year, from: first) == calendar.component(.year, from: last) {
      return "\(month.string(from: first))–\(monthYear.string(from: last))"
    }
    return "\(monthYear.string(from: first))–\(monthYear.string(from: last))"
  }

  private func categoryFieldValue(_ item: GlobalBudgetCategoryAllocation) -> String {
    if let drafts {
      return drafts[item.id] ?? ""
    }
    if proposing {
      return Self.fieldValue(item.allocatedLimit)
    }
    return Self.fieldValue(Self.wholeLimit(item.currentLimit))
  }

  private func handleTotalChange(_ next: String) {
    amount = String(next.filter(\.isNumber).prefix(15))
    drafts = nil
  }

  private func handleCategoryChange(_ id: String, _ next: String) {
    let value = String(next.filter(\.isNumber).prefix(15))
    var snapshot = drafts ?? Dictionary(uniqueKeysWithValues: allocation.allocations.map { item in
      (item.id, categoryFieldValue(item))
    })
    snapshot[id] = value
    drafts = snapshot
    let total = snapshot.values.reduce(0) { $0 + (Self.parseLimit($1) ?? 0) }
    amount = total > 0 ? String(total) : ""
  }

  private static func parseLimit(_ value: String?) -> Int? {
    guard let value,
          !value.isEmpty,
          value.allSatisfy(\.isNumber),
          let amount = Int(value),
          amount > 0,
          amount <= Int.max / 100 else { return nil }
    return amount
  }

  private static func wholeLimit(_ current: Double?) -> Int? {
    guard let current, current.isFinite, current > 0 else { return nil }
    let rounded = Int(current.rounded())
    return rounded > 0 ? rounded : nil
  }

  private static func fieldValue(_ limit: Int?) -> String {
    guard let limit, limit > 0 else { return "" }
    return String(limit)
  }

  private static func currentDiffers(_ current: Double?, _ allocated: Int?) -> Bool {
    switch (current, allocated) {
    case (nil, nil): return false
    case (nil, _), (_, nil): return true
    case let (current?, allocated?): return current != Double(allocated)
    }
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
