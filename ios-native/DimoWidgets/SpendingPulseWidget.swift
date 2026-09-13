import AppIntents
import SwiftUI
import WidgetKit

struct SetPulsePeriod: AppIntent {
  static var title: LocalizedStringResource = "Change spending period"
  static var isDiscoverable: Bool = false
  @Parameter(title: "Show day") var showDay: Bool
  init() {}
  init(_ period: PulsePeriod) { showDay = period == .day }
  func perform() async throws -> some IntentResult {
    PulseStorage.period = showDay ? .day : .week
    WidgetCenter.shared.reloadTimelines(ofKind: PulseStorage.kind)
    return .result()
  }
}

struct PulseEntry: TimelineEntry {
  var date: Date
  var snapshot: PulseSnapshot?
  var period: PulsePeriod
}

struct PulseProvider: TimelineProvider {
  func placeholder(in context: Context) -> PulseEntry { sample }
  func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
    completion(context.isPreview ? sample : .init(date: Date(), snapshot: PulseStorage.read(), period: PulseStorage.period))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
    let now = Date()
    let snapshot = PulseStorage.read()
    // Calendar-hour entries also cross local midnight without the app running.
    let nextHour = Calendar.current.dateInterval(of: .hour, for: now)!.end
    let dates = [now] + (0..<24).compactMap { Calendar.current.date(byAdding: .hour, value: $0, to: nextHour) }
    completion(Timeline(entries: dates.map { PulseEntry(date: $0, snapshot: snapshot, period: PulseStorage.period) }, policy: .atEnd))
  }
  private var sample: PulseEntry {
    let now = Date()
    let expenses = (0..<7).map { offset in
      PulseSnapshot.Expense(date: Calendar.current.date(byAdding: .day, value: -offset, to: now)!,
                            amountMinor: [84000, 52000, 70000, 98000, 36000, 45000, 51000][offset],
                            categoryID: "food", categoryName: "Food")
    }
    return .init(date: now, snapshot: .init(updatedAt: now, currency: "INR", minorUnitDigits: 2, expenses: expenses), period: .week)
  }
}

struct SpendingPulseView: View {
  var entry: PulseEntry
  private let addURL = URL(string: "dimo://widget/add-expense")!
  private let statsURL = URL(string: "dimo://widget/stats")!

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        HStack(spacing: 2) {
          periodButton(.day, title: "Day")
          periodButton(.week, title: "Week")
        }
        .padding(3)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
        Spacer()
        Text("dimo").font(DimoFont.display(19, weight: .bold)).foregroundStyle(Theme.green)
      }
      if let snapshot = entry.snapshot {
        content(snapshot)
      } else {
        Text("Your spending, at a glance")
          .font(DimoFont.display(19)).foregroundStyle(Theme.ink)
        Text("Open Dimo and sign in to get started.")
          .font(DimoFont.body(12)).foregroundStyle(Theme.body)
        Spacer(minLength: 0)
      }
    }
    .containerBackground(Theme.surface, for: .widget)
    .widgetURL(statsURL)
  }

  private func periodButton(_ period: PulsePeriod, title: String) -> some View {
    Button(intent: SetPulsePeriod(period)) {
      Text(title).font(DimoFont.body(12, weight: .medium))
        .foregroundStyle(entry.period == period ? Theme.green : Theme.body)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(entry.period == period ? Theme.greenSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Show \(title.lowercased()) spending")
    .accessibilityAddTraits(entry.period == period ? .isSelected : [])
  }

  @ViewBuilder private func content(_ snapshot: PulseSnapshot) -> some View {
    let summary = PulseSelectors.summarize(snapshot, period: entry.period, now: entry.date)
    HStack(alignment: .bottom, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(Double(summary.totalMinor) / pow(10, Double(snapshot.minorUnitDigits)), format: .currency(code: snapshot.currency))
          .font(DimoFont.display(30, weight: .bold)).minimumScaleFactor(0.6).lineLimit(1)
          .foregroundStyle(Theme.ink).privacySensitive()
        Text(snapshot.missingRates ? "Some exchange rates unavailable" : summary.comparison)
          .font(DimoFont.body(11)).foregroundStyle(Theme.body).lineLimit(2)
      }
      Spacer(minLength: 0)
      chart(summary)
    }
    Spacer(minLength: 0)
    HStack(alignment: .bottom, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(summary.topCategory.map { "Top category · \($0)" } ?? "No expenses yet")
          .lineLimit(1).privacySensitive()
        Text(entry.period == .day ? "Today · 3-hour totals" : "This week · Mon–Sun")
          .foregroundStyle(Theme.muted)
      }.font(DimoFont.body(10)).foregroundStyle(Theme.body)
      Spacer(minLength: 0)
      Link(destination: addURL) {
        Label("Add expense", systemImage: "plus")
          .font(DimoFont.body(11, weight: .medium))
          .padding(.horizontal, 8).padding(.vertical, 7)
          .background(Theme.greenSoft, in: RoundedRectangle(cornerRadius: 9))
          .foregroundStyle(Theme.green)
      }.fixedSize()
    }
  }

  private func chart(_ summary: PulseSummary) -> some View {
    let maximum = max(summary.bars.max() ?? 0, 1)
    let active = entry.period == .day ? Calendar.current.component(.hour, from: entry.date) / 3
      : (Calendar.current.component(.weekday, from: entry.date) + 5) % 7
    return HStack(alignment: .bottom, spacing: 4) {
      ForEach(summary.bars.indices, id: \.self) { index in
        RoundedRectangle(cornerRadius: 3)
          .fill(index == active ? Theme.green : Theme.bar)
          .frame(height: summary.bars[index] == 0 ? 2 : max(3, 58 * Double(summary.bars[index]) / Double(maximum)))
      }
    }
    .frame(width: 94, height: 58, alignment: .bottom)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(entry.period == .day ? "Spending in eight three-hour intervals today" : "Daily spending from Monday to Sunday")
    .privacySensitive()
  }
}

@main
struct SpendingPulseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: PulseStorage.kind, provider: PulseProvider()) { entry in
      SpendingPulseView(entry: entry)
    }
    .configurationDisplayName("Spending pulse")
    .description("Switch between today and this week, and quickly add an expense. Uses your latest local Dimo data.")
    .supportedFamilies([.systemMedium])
  }
}
