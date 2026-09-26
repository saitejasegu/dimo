import SwiftUI
import UIKit

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
  var store: AppStore
  @Bindable var entities: EntitiesStore
  @State private var section: LendingSection = .summary
  @State private var messageToShare: String?
  @State private var visibleLimit = LendSelectors.historyPageSize
  @State private var stopSharingTarget: LendContactSummary?
  private let contactPhotos = ContactsLoader.shared

  private var sharing: LendingSharingStore { store.lendingSharing }

  var body: some View {
    let summaries = entities.lendSummaries
    let totals = entities.lendTotals

    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Lending")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
        }
        .frame(minHeight: 56)

        hero(totals: totals, contacts: summaries.count)
          .padding(.top, 16)

        sectionSwitcher
          .padding(.top, 14)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(sharing.incomingInvites) { invite in
            incomingInviteBanner(invite)
          }
          if section == .summary {
            ForEach(invitedOnly) { invite in
              invitedRow(invite)
            }
          }
          if entities.lends.isEmpty {
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
        // Clears the floating add button overlaying the list's bottom edge.
        .padding(.bottom, 110)
      }
      .onScrollPhaseChange { _, phase in
        store.setUIScrolling(phase != .idle)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .onAppear {
      contactPhotos.loadIfAuthorized()
      Task { await sharing.refresh() }
    }
    .refreshable {
      await sharing.refresh()
      store.syncNow()
    }
    .alert(
      "Stop sharing with \(stopSharingTarget?.contactName ?? "")?",
      isPresented: Binding(
        get: { stopSharingTarget != nil },
        set: { if !$0 { stopSharingTarget = nil } }
      )
    ) {
      Button("Stop sharing", role: .destructive) {
        guard let target = stopSharingTarget else { return }
        Task {
          do {
            try await sharing.stopSharing(contactId: target.contactId)
            store.showToast("Stopped sharing with \(target.contactName)")
          } catch {
            store.showToast(error.localizedDescription)
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You both keep the entries so far, but new changes won’t reach each other.")
    }
    .onChange(of: section) { _, _ in
      visibleLimit = LendSelectors.historyPageSize
    }
    .sheet(
      isPresented: Binding(
        get: { messageToShare != nil },
        set: { if !$0 { messageToShare = nil } }
      )
    ) {
      if let messageToShare {
        LendingShareSheet(message: messageToShare)
          .presentationDetents([.medium, .large])
      }
    }
  }

  private func hero(totals: LendTotals, contacts: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        heroFigure(title: "Owed to me", amount: totals.owedToMe)
        heroFigure(title: "I owe", amount: totals.iOwe)
      }
      .padding(.bottom, 8)
      Text(
        entities.lends.isEmpty
          ? "Nothing recorded yet"
          : "\(contacts) contact\(contacts == 1 ? "" : "s") · \(entities.lends.count) entr\(entities.lends.count == 1 ? "y" : "ies")"
      )
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.sideSub)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.inverse)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func heroFigure(title: String, amount: Double) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.sideMuted)
      Text(Formatting.money(amount, currency: entities.currency))
        .font(DimoFont.display(26, weight: .semibold))
        .foregroundStyle(Theme.sideText)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sectionSwitcher: some View {
    HStack(spacing: 8) {
      ForEach(LendingSection.allCases) { candidate in
        let selected = section == candidate
        Button {
          withAnimation(.easeOut(duration: 0.15)) { section = candidate }
        } label: {
          Text(candidate.title)
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(selected ? Theme.canvas : Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? Theme.ink : Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("Nothing recorded yet")
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("Tap + to record money you lend or borrow.")
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
      Text("Nothing outstanding either way.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 44)
  }

  /// Sent invites whose contact has no outstanding balance to show a row for.
  private var invitedOnly: [OutgoingLendInvite] {
    sharing.outgoingInvites.filter { invite in
      !entities.lendSummaries.contains { $0.contactId == invite.contactId }
    }
  }

  private func incomingInviteBanner(_ invite: IncomingLendInvite) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: "person.2.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(width: 38, height: 38)
          .background(Theme.greenSoft)
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text("\(invite.inviterName) wants to share a ledger")
            .font(DimoFont.body(14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          if let email = invite.inviterEmail {
            Text(email)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 8) {
        Button {
          Task {
            do {
              try await sharing.decline(invite)
              store.showToast("Invite declined")
            } catch {
              store.showToast(error.localizedDescription)
            }
          }
        } label: {
          Text("Decline")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Theme.canvas)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        Button {
          sharing.sheet = .accept(invite)
        } label: {
          Text("Accept")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Theme.green)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Theme.green.opacity(0.5), lineWidth: 1)
    )
  }

  private func cancel(_ invite: OutgoingLendInvite) {
    Task {
      do {
        try await sharing.cancel(invite)
        store.showToast("Invite cancelled")
      } catch {
        store.showToast(error.localizedDescription)
      }
    }
  }

  private func invitedRow(_ invite: OutgoingLendInvite) -> some View {
    HStack(spacing: 12) {
      AvatarView(
        name: invite.contactName,
        photoImage: contactPhotos.thumbnailImage(contactId: invite.contactId),
        size: 38,
        radius: 11,
        fontSize: 15
      )
      VStack(alignment: .leading, spacing: 2) {
        Text(invite.contactName)
          .font(DimoFont.body(14, weight: .medium))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text("Invited · \(invite.inviteeEmail ?? "waiting for them to accept")")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      Button("Cancel") { cancel(invite) }
      .font(DimoFont.body(13, weight: .medium))
      .foregroundStyle(Theme.muted)
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }

  private func money(_ amount: Double, currencyCode: String?) -> String {
    if let currencyCode, !currencyCode.isEmpty {
      return Formatting.money(amount, currencyCode: currencyCode)
    }
    return Formatting.money(amount, currency: entities.currency)
  }

  private func summarySubtitle(_ summary: LendContactSummary) -> String {
    let owedToMe = summary.direction == .owedToMe
    var parts = [owedToMe ? "Owes you" : "You owe"]
    if summary.isShared {
      parts.append("Shared")
    } else if sharing.pendingInvite(contactId: summary.contactId) != nil {
      parts.append("Invited")
    }
    parts.append("\(summary.count) entr\(summary.count == 1 ? "y" : "ies")")
    parts.append("last \(DateHelpers.formatTransactionDay(summary.lastOccurredAt).lowercased())")
    return parts.joined(separator: " · ")
  }

  private func summaryRow(_ summary: LendContactSummary) -> some View {
    let owedToMe = summary.direction == .owedToMe
    return HStack(spacing: 0) {
      Button {
        store.openAddSettlement(
          contactName: summary.contactName,
          contactId: summary.contactId,
          direction: summary.direction
        )
      } label: {
        HStack(spacing: 12) {
          AvatarView(
            name: summary.contactName,
            photoImage: contactPhotos.thumbnailImage(contactId: summary.contactId),
            size: 38,
            radius: 11,
            fontSize: 15
          )
          VStack(alignment: .leading, spacing: 2) {
            Text(summary.contactName)
              .font(DimoFont.body(14, weight: .medium))
              .foregroundStyle(Theme.ink)
              .lineLimit(1)
            Text(summarySubtitle(summary))
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }
          Spacer()
          Text(money(summary.magnitude, currencyCode: summary.currency))
            .font(DimoFont.display(15, weight: .semibold))
            .foregroundStyle(owedToMe ? Theme.ink : Theme.danger)
        }
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        owedToMe
          ? "Record amount got back from \(summary.contactName)"
          : "Record amount paid back to \(summary.contactName)"
      )

      Button {
        messageToShare = shareText(for: summary)
      } label: {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(width: 48, height: 48)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Share lending summary with \(summary.contactName)")
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
    .contextMenu {
      if summary.isShared {
        if sharing.activeConnection(contactId: summary.contactId) != nil {
          Button(role: .destructive) {
            stopSharingTarget = summary
          } label: {
            Label("Stop sharing", systemImage: "person.2.slash")
          }
        }
      } else if let invite = sharing.pendingInvite(contactId: summary.contactId) {
        Button(role: .destructive) {
          cancel(invite)
        } label: {
          Label("Cancel invite", systemImage: "xmark.circle")
        }
      }
    }
  }

  /// Fixed-format and locale-independent, so it is built once rather than per share.
  private static let shareDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MMM-yyyy"
    return formatter
  }()

  private func shareText(for summary: LendContactSummary) -> String {
    let dateFormatter = Self.shareDateFormatter

    let transactionLines: [String] = LendSelectors
      .unsettledTransactions(for: summary.contactId, in: entities.lends)
      .map { lend -> String in
        let sign = lend.isIncoming ? "-" : "+"
        let amount = money(lend.amount, currencyCode: lend.currency)
        let occurredAt = Date(timeIntervalSince1970: TimeInterval(lend.occurredAt) / 1000)
        let date = dateFormatter.string(from: occurredAt)
        return "• \(date) · \(sign)\(amount)"
      }
    let transactions = transactionLines.joined(separator: "\n")
    let balance = money(summary.magnitude, currencyCode: summary.currency)
    let headline = summary.direction == .owedToMe
      ? "Outstanding: \(balance)"
      : "I owe you: \(balance)"

    return """
    Hi \(summary.contactName), here’s our lending summary:

    \(headline)

    \(transactions)
    """
  }

  private var transactionList: some View {
    let list = entities.lendHistoryList(limit: visibleLimit)
    return Group {
      ForEach(list.groups, id: \.label) { group in
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Text(group.label.uppercased())
              .font(DimoFont.body(12, weight: .medium))
              .kerning(0.96)
              .foregroundStyle(Theme.muted)
            Spacer()
            Text(Formatting.money(group.total, currency: entities.currency))
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.faint)
          }
          ForEach(group.items) { lend in
            lendRow(lend)
          }
        }
        .padding(.bottom, 6)
      }
      if list.hasMore {
        ProgressView()
          .tint(Theme.green)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .onAppear {
            let next = min(
              visibleLimit + LendSelectors.historyPageSize,
              entities.lends.count
            )
            guard next > visibleLimit else { return }
            DispatchQueue.main.async { visibleLimit = next }
          }
      }
    }
  }

  /// Stands in for an empty comment so a row still says what it was. Plain
  /// lends need none — the contact name already reads as "lent to".
  private func fallbackDetail(for kind: LendKind) -> String? {
    switch kind {
    case .lent: return nil
    case .repaid: return "Got back"
    case .borrowed: return "Borrowed"
    case .returned: return "Paid back"
    }
  }

  /// Who recorded or last changed a shared entry, when it was the other person.
  private func attribution(for lend: Lend) -> String? {
    guard lend.isShared else { return nil }
    let firstName = lend.contactName.split(separator: " ").first.map(String.init) ?? lend.contactName
    if lend.createdBy == .contact { return "Added by \(firstName)" }
    if lend.lastEditedBy == .contact { return "Edited by \(firstName)" }
    return nil
  }

  private func lendRow(_ lend: Lend) -> some View {
    let base = lend.comment.isEmpty ? fallbackDetail(for: lend.kind) : lend.comment
    let parts = [base, attribution(for: lend), lend.time].compactMap { $0 }
    let detail = parts.joined(separator: " · ")

    return Button {
      store.openEditLend(lend.id)
    } label: {
      HStack(spacing: 12) {
        AvatarView(
          name: lend.contactName,
          photoImage: contactPhotos.thumbnailImage(contactId: lend.contactId),
          size: 38,
          radius: 11,
          fontSize: 15
        )
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
        Text(money(lend.signedAmount, currencyCode: lend.currency))
          .font(DimoFont.display(15, weight: .semibold))
          .foregroundStyle(lend.isIncoming ? Theme.green : Theme.ink)
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

private struct LendingShareSheet: UIViewControllerRepresentable {
  var message: String

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [message], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
