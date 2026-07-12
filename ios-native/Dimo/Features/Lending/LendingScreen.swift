import SwiftUI

enum LendingSection: String, CaseIterable, Identifiable {
  case summary
  case transactions

  var id: String { rawValue }

  var title: String {
    switch self {
    case .summary: return "Summary"
    case .transactions: return "Transactions"
    }
  }
}

struct LendingScreen: View {
  @Bindable var store: AppStore
  @State private var section: LendingSection = .summary

  var body: some View {
    let summaries = LendSelectors.contactSummaries(store.lends)
    let total = LendSelectors.totalLent(store.lends)

    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Lending")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
        }
        .frame(minHeight: 56)

        hero(total: total, contacts: summaries.count)
          .padding(.top, 16)

        sectionSwitcher
          .padding(.top, 14)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        VStack(spacing: 8) {
          if store.lends.isEmpty {
            emptyState
          } else {
            switch section {
            case .summary:
              if summaries.isEmpty {
                settledEmptyState
              } else {
                ForEach(summaries) { summary in
                  summaryRow(summary)
                }
              }
            case .transactions:
              transactionList
            }
          }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 24)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
  }

  private func hero(total: Double, contacts: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Outstanding")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.sideMuted)
        .padding(.bottom, 8)
      Text(Formatting.money(total, currency: store.currency))
        .font(DimoFont.display(30, weight: .semibold))
        .foregroundStyle(Theme.sideText)
        .padding(.bottom, 6)
      Text(
        store.lends.isEmpty
          ? "No money lent yet"
          : "\(contacts) contact\(contacts == 1 ? "" : "s") · \(store.lends.count) entr\(store.lends.count == 1 ? "y" : "ies")"
      )
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.sideSub)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var sectionSwitcher: some View {
    HStack(spacing: 8) {
      ForEach(LendingSection.allCases) { candidate in
        let selected = section == candidate
        Button(candidate.title) {
          withAnimation(.easeOut(duration: 0.15)) { section = candidate }
        }
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(selected ? Theme.canvas : Theme.muted)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(selected ? Theme.ink : Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
        .buttonStyle(.plain)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("Nothing lent yet")
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("Tap + to record money you lend to a contact.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 44)
  }

  private var settledEmptyState: some View {
    VStack(spacing: 8) {
      Text("All settled")
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("Everyone has paid you back.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 44)
  }

  private func summaryRow(_ summary: LendContactSummary) -> some View {
    Button {
      store.openAddRepayment(contactName: summary.contactName, outstanding: summary.total)
    } label: {
      HStack(spacing: 12) {
        AvatarView(name: summary.contactName, size: 38, radius: 11, fontSize: 15)
        VStack(alignment: .leading, spacing: 2) {
          Text(summary.contactName)
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text("\(summary.count) entr\(summary.count == 1 ? "y" : "ies") · last \(DateHelpers.formatTransactionDay(summary.lastOccurredAt).lowercased())")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        Spacer()
        Text(Formatting.money(summary.total, currency: store.currency))
          .font(DimoFont.display(15, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
      .padding(12)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Record amount got back from \(summary.contactName)")
  }

  private var transactionList: some View {
    LazyVStack(alignment: .leading, spacing: 14) {
      ForEach(LendSelectors.groupByDay(store.lends), id: \.label) { group in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(group.label.uppercased())
              .font(DimoFont.body(12, weight: .medium))
              .kerning(0.96)
              .foregroundStyle(Theme.muted)
            Spacer()
            Text(Formatting.money(group.total, currency: store.currency))
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.faint)
          }
          ForEach(group.items) { lend in
            lendRow(lend)
          }
        }
      }
    }
  }

  private func lendRow(_ lend: Lend) -> some View {
    let isRepaid = lend.kind == .repaid
    let detail: String = {
      if isRepaid {
        let base = lend.comment.isEmpty ? "Got back" : lend.comment
        return "\(base) · \(lend.time)"
      }
      return lend.comment.isEmpty ? lend.time : "\(lend.comment) · \(lend.time)"
    }()

    return Button {
      store.openEditLend(lend.id)
    } label: {
      HStack(spacing: 12) {
        AvatarView(name: lend.contactName, size: 38, radius: 11, fontSize: 15)
        VStack(alignment: .leading, spacing: 2) {
          Text(lend.contactName)
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(detail)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        Spacer()
        Text(Formatting.money(lend.signedAmount, currency: store.currency))
          .font(DimoFont.display(15, weight: .semibold))
          .foregroundStyle(isRepaid ? Theme.green : Theme.ink)
      }
      .padding(12)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
