import SwiftUI
import UIKit

/// Someone on the Lending screen: anyone recorded, or invited before any entries.
struct LendPerson: Identifiable, Equatable {
  var contactId: String
  var contactName: String
  /// Positive when they owe you.
  var balance: Double
  var currency: String?
  var lastOccurredAt: Int
  var entryCount: Int

  var id: String { contactId }
  var isSettled: Bool { abs(balance) <= 0.0001 }
}

enum LendPeople {
  /// Everyone recorded plus people invited before any entries, split into
  /// those with a balance (largest first) and those settled (most recent first).
  static func split(
    summaries: [LendContactSummary],
    outgoingInvites: [OutgoingLendInvite]
  ) -> (active: [LendPerson], settled: [LendPerson]) {
    var people = summaries.map {
      LendPerson(
        contactId: $0.contactId,
        contactName: $0.contactName,
        balance: $0.total,
        currency: $0.currency,
        lastOccurredAt: $0.lastOccurredAt,
        entryCount: $0.count
      )
    }
    for invite in outgoingInvites {
      guard let contactId = invite.contactId, !people.contains(where: { $0.contactId == contactId })
      else { continue }
      people.append(
        LendPerson(
          contactId: contactId,
          contactName: invite.contactName,
          balance: 0,
          currency: nil,
          lastOccurredAt: Int(invite.createdAt),
          entryCount: 0
        )
      )
    }
    let active = people.filter { !$0.isSettled }.sorted { abs($0.balance) > abs($1.balance) }
    let settled = people.filter(\.isSettled).sorted { $0.lastOccurredAt > $1.lastOccurredAt }
    return (active, settled)
  }

  private static let monthDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMM d")
    return formatter
  }()

  private static let monthDayYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMM d yyyy")
    return formatter
  }()

  /// "Today", "Yesterday", "Aug 22", or "Aug 22, 2025" for other years.
  static func shortDay(_ timestamp: Int, now: Date = Date()) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return (sameYear ? monthDay : monthDayYear).string(from: date)
  }
}

struct LendingScreen: View {
  var store: AppStore
  @Bindable var entities: EntitiesStore

  private var sharing: LendingSharingStore { store.lendingSharing }

  var body: some View {
    let people = LendPeople.split(
      summaries: entities.lendSummaries,
      outgoingInvites: sharing.outgoingInvites
    )

    VStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("Lending")
            .font(DimoFont.display(24, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Spacer()
        }
        .frame(minHeight: 56)

        hero(totals: entities.lendTotals)
          .padding(.top, 16)
      }
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 14)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          ForEach(sharing.incomingInvites) { invite in
            IncomingInviteCard(store: store, invite: invite)
          }
          if !people.active.isEmpty {
            peopleCard(people.active)
          }
          if !people.settled.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("SETTLED")
                .font(DimoFont.body(12, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
              peopleCard(people.settled)
            }
          }
          if people.active.isEmpty && people.settled.isEmpty {
            emptyState
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
      Task { await sharing.refresh() }
    }
    .refreshable {
      await sharing.refresh()
      store.syncNow()
    }
  }

  private func hero(totals: LendTotals) -> some View {
    HStack(alignment: .top, spacing: 16) {
      heroFigure(title: "Owed to me", amount: totals.owedToMe)
      heroFigure(title: "I owe", amount: totals.iOwe)
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

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("Nothing recorded yet")
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("Add an entry when you give or get money. Pick someone on Dimo and you’ll both see it.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 44)
  }

  private func peopleCard(_ people: [LendPerson]) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
        if index > 0 {
          Divider().overlay(Theme.line)
        }
        personRow(person)
      }
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
  }

  private func status(for person: LendPerson) -> (text: String, shared: Bool) {
    if sharing.pendingInvite(contactId: person.contactId) != nil { return ("Invite pending", false) }
    let when = person.entryCount > 0 ? LendPeople.shortDay(person.lastOccurredAt) : nil
    if sharing.activeConnection(contactId: person.contactId) != nil {
      return (["Shared", when].compactMap { $0 }.joined(separator: " · "), true)
    }
    if sharing.stoppedConnection(contactId: person.contactId) != nil {
      return (["Sharing stopped", when].compactMap { $0 }.joined(separator: " · "), false)
    }
    let count = "\(person.entryCount) entr\(person.entryCount == 1 ? "y" : "ies")"
    return ([count, when].compactMap { $0 }.joined(separator: " · "), false)
  }

  private func personRow(_ person: LendPerson) -> some View {
    let status = status(for: person)
    return Button {
      store.lendPersonId = person.contactId
    } label: {
      HStack(spacing: 12) {
        AvatarView(
          name: person.contactName,
          photoUrl: sharing.photoUrl(contactId: person.contactId),
          size: 40,
          radius: 12,
          fontSize: 15
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(person.contactName)
            .font(DimoFont.body(15, weight: .medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(status.text)
            .font(DimoFont.body(12))
            .foregroundStyle(status.shared ? Theme.green : Theme.muted)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        if !person.isSettled {
          VStack(alignment: .trailing, spacing: 2) {
            Text(money(abs(person.balance), currencyCode: person.currency))
              .font(DimoFont.display(15, weight: .semibold))
              .foregroundStyle(person.balance > 0 ? Theme.green : Theme.danger)
            Text(person.balance > 0 ? "owes you" : "you owe")
              .font(DimoFont.body(11))
              .foregroundStyle(Theme.faint)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func money(_ amount: Double, currencyCode: String?) -> String {
    if let currencyCode, !currencyCode.isEmpty {
      return Formatting.money(amount, currencyCode: currencyCode)
    }
    return Formatting.money(amount, currency: entities.currency)
  }
}

/// Someone inviting you to track lending together. Accept is one tap; only
/// when you already track someone by that name are you asked about merging.
private struct IncomingInviteCard: View {
  var store: AppStore
  var invite: IncomingLendInvite
  @State private var askMerge = false

  private var sharing: LendingSharingStore { store.lendingSharing }

  /// A private person you already track under the inviter's name.
  private var sameName: LendContactSuggestion? {
    let name = invite.inviterName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return LendSelectors.recentContacts(store.lends, limit: .max).first {
      !$0.contactId.hasPrefix(sharedLendContactPrefix)
        && $0.contactName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        AvatarView(
          name: invite.inviterName,
          photoUrl: invite.inviterPhotoUrl,
          size: 40,
          radius: 12,
          fontSize: 15
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(invite.inviterName)
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(invite.reconnect ? "Wants to share with you again" : "Invited you to track lending together")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
          if let email = invite.inviterEmail {
            Text(email)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.faint)
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
            .frame(height: 42)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
        Button {
          if sameName != nil && !invite.reconnect {
            askMerge = true
          } else {
            accept(mergeWith: nil)
          }
        } label: {
          Text("Accept")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Theme.green)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    .alert("Merge with your “\(sameName?.contactName ?? "")”?", isPresented: $askMerge) {
      Button("Merge") { accept(mergeWith: sameName?.contactId) }
      Button("Keep separate") { accept(mergeWith: nil) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your entries with them are shared too, so you both see one history.")
    }
  }

  private func accept(mergeWith contactId: String?) {
    Task {
      do {
        try await sharing.accept(invite, mergeWith: contactId)
        store.showToast("You’re now tracking lending with \(invite.inviterName)")
      } catch {
        store.showToast(error.localizedDescription)
      }
    }
  }
}
