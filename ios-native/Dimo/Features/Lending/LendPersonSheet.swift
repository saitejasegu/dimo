import SwiftUI

/// One person: their balance, "I gave / I got", their history, and sharing
/// controls. The header stays put while the history scrolls.
struct LendPersonSheet: View {
  @Bindable var store: AppStore
  var contactId: String
  @State private var confirmStop = false
  @State private var cancelTarget: OutgoingLendInvite?
  @State private var linking = false

  private var sharing: LendingSharingStore { store.lendingSharing }

  private var person: LendPerson? {
    let people = LendPeople.split(
      summaries: store.entities.lendSummaries,
      outgoingInvites: sharing.outgoingInvites
    )
    return (people.active + people.settled).first { $0.contactId == contactId }
  }

  private var entries: [Lend] {
    store.lends
      .filter { $0.contactId == contactId }
      .sorted { $0.occurredAt > $1.occurredAt }
  }

  var body: some View {
    Group {
      if let person {
        content(person)
      } else {
        // The person went away (last entry deleted, invite cancelled).
        Color.clear.onAppear { store.lendPersonId = nil }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.surface)
    .sheet(isPresented: Binding(
      get: { store.overlay == .lend },
      set: { if !$0 { store.closeOverlay() } }
    )) {
      AddLendSheet(store: store)
    }
  }

  private func content(_ person: LendPerson) -> some View {
    let pending = sharing.pendingInvite(contactId: contactId)
    let connected = sharing.activeConnection(contactId: contactId) != nil
    let stopped = !connected && sharing.stoppedConnection(contactId: contactId) != nil
    return VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(person.contactName)
          .font(DimoFont.display(20, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        moreMenu(person, connected: connected)
      }
      .padding(.top, 22)

      header(person, pending: pending != nil, connected: connected, stopped: stopped)

      HStack(spacing: 10) {
        flowButton("I gave", flow: .gave, person: person)
        flowButton("I got", flow: .got, person: person)
      }

      if entries.isEmpty {
        Text("No entries yet.")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, lend in
              if index > 0 { Divider().overlay(Theme.line) }
              entryRow(lend)
            }
          }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
      }

      footer(person, pending: pending, connected: connected, stopped: stopped)
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 16)
    .frame(maxHeight: .infinity, alignment: .top)
    .alert("Stop sharing with \(person.contactName)?", isPresented: $confirmStop) {
      Button("Stop sharing", role: .destructive) {
        Task {
          do {
            try await sharing.stopSharing(contactId: contactId)
            store.showToast("Stopped sharing with \(person.contactName)")
          } catch {
            store.showToast(error.localizedDescription)
          }
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You both keep the entries so far, but new changes won’t reach each other.")
    }
    .alert(
      "Cancel invite to \(person.contactName)?",
      isPresented: Binding(get: { cancelTarget != nil }, set: { if !$0 { cancelTarget = nil } })
    ) {
      Button("Cancel invite", role: .destructive) {
        guard let invite = cancelTarget else { return }
        Task {
          do {
            try await sharing.cancel(invite)
            store.showToast("Invite cancelled")
          } catch {
            store.showToast(error.localizedDescription)
          }
        }
      }
      Button("Keep", role: .cancel) {}
    } message: {
      Text("They won’t be able to accept it. Your entries with them stay on your side only.")
    }
    .sheet(isPresented: $linking) {
      LinkAccountSheet(store: store, person: person)
    }
  }

  private func moreMenu(_ person: LendPerson, connected: Bool) -> some View {
    Menu {
      if !entries.isEmpty {
        ShareLink(item: shareText(person)) {
          Label("Share summary", systemImage: "square.and.arrow.up")
        }
      }
      if connected {
        Button(role: .destructive) {
          confirmStop = true
        } label: {
          Label("Stop sharing", systemImage: "person.2.slash")
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Theme.muted)
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("More options for \(person.contactName)")
  }

  private func header(_ person: LendPerson, pending: Bool, connected: Bool, stopped: Bool) -> some View {
    let status = connected ? "Shared" : pending ? "Invite pending" : stopped ? "Sharing stopped" : nil
    let subtitle: String
    if person.isSettled {
      subtitle = status ?? "Nothing owed either way"
    } else {
      subtitle = [person.balance > 0 ? "Owes you" : "You owe", status].compactMap { $0 }.joined(separator: " · ")
    }
    return HStack(spacing: 14) {
      AvatarView(
        name: person.contactName,
        photoUrl: sharing.photoUrl(contactId: contactId),
        size: 52,
        radius: 15,
        fontSize: 19
      )
      VStack(alignment: .leading, spacing: 2) {
        Text(person.isSettled ? "All settled" : money(abs(person.balance), currencyCode: person.currency))
          .font(DimoFont.display(26, weight: .semibold))
          .foregroundStyle(
            person.isSettled ? Theme.muted : person.balance > 0 ? Theme.green : Theme.danger
          )
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(subtitle)
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }
      Spacer(minLength: 0)
    }
  }

  /// The direction that settles the balance is highlighted.
  private func flowButton(_ title: String, flow: LendFlow, person: LendPerson) -> some View {
    let settles: LendFlow? = person.isSettled ? nil : person.balance > 0 ? .got : .gave
    let primary = settles == flow
    return Button {
      store.openAddLend(contactName: person.contactName, contactId: contactId, flow: flow)
    } label: {
      Text(title)
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(primary ? Theme.onGreen : Theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(primary ? Theme.green : Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: primary ? 0 : 1)
        )
    }
    .buttonStyle(.plain)
  }

  private func entryRow(_ lend: Lend) -> some View {
    let got = LendFlow(kind: lend.kind) == .got
    let flowLabel = got ? "You got" : "You gave"
    let note = lend.comment.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = [note.isEmpty ? nil : flowLabel, LendPeople.shortDay(lend.occurredAt), attribution(lend)]
      .compactMap { $0 }
      .joined(separator: " · ")
    return Button {
      store.openEditLend(lend.id)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(note.isEmpty ? flowLabel : note)
            .font(DimoFont.body(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(detail)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text(money(lend.amount, currencyCode: lend.currency))
          .font(DimoFont.display(15, weight: .semibold))
          .foregroundStyle(got ? Theme.green : Theme.danger)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func footer(
    _ person: LendPerson,
    pending: OutgoingLendInvite?,
    connected: Bool,
    stopped: Bool
  ) -> some View {
    if connected {
      EmptyView()
    } else if let pending {
      Button("Cancel invite") { cancelTarget = pending }
        .font(DimoFont.body(13, weight: .medium))
        .foregroundStyle(Theme.muted)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    } else if stopped {
      promptCard(
        "Changes no longer reach \(person.contactName). Share again to bring both sides back in step.",
        action: "Share again"
      ) {
        Task {
          do {
            try await sharing.shareAgain(contactId: contactId)
            store.showToast("Invite sent to \(person.contactName)")
          } catch {
            store.showToast(error.localizedDescription)
          }
        }
      }
    } else if !contactId.hasPrefix(sharedLendContactPrefix) {
      promptCard(
        "Is \(person.contactName) on Dimo? Link them and you’ll both see this history.",
        action: "Link to Dimo account"
      ) { linking = true }
    }
  }

  private func promptCard(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
      Text(text)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
      Button(action: perform) {
        Text(action)
          .font(DimoFont.body(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .padding(.horizontal, 18)
          .frame(height: 40)
          .background(Theme.surface)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
      }
      .buttonStyle(.plain)
    }
    .padding(14)
    .frame(maxWidth: .infinity)
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  /// Who recorded or last changed a shared entry, when it was the other person.
  private func attribution(_ lend: Lend) -> String? {
    guard lend.isShared else { return nil }
    let firstName = lend.contactName.split(separator: " ").first.map(String.init) ?? lend.contactName
    if lend.createdBy == .contact { return "Added by \(firstName)" }
    if lend.lastEditedBy == .contact { return "Edited by \(firstName)" }
    return nil
  }

  private func money(_ amount: Double, currencyCode: String?) -> String {
    if let currencyCode, !currencyCode.isEmpty {
      return Formatting.money(amount, currencyCode: currencyCode)
    }
    return Formatting.money(amount, currency: store.currency)
  }

  /// Fixed-format and locale-independent, so it is built once rather than per share.
  private static let shareDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd-MMM-yyyy"
    return formatter
  }()

  /// Plain-text summary of the current unsettled cycle, for Messages etc.
  private func shareText(_ person: LendPerson) -> String {
    let lines = LendSelectors.unsettledTransactions(for: contactId, in: store.lends).map { lend -> String in
      let sign = lend.isIncoming ? "-" : "+"
      let date = Self.shareDateFormatter.string(
        from: Date(timeIntervalSince1970: TimeInterval(lend.occurredAt) / 1000)
      )
      return "• \(date) · \(sign)\(money(lend.amount, currencyCode: lend.currency))"
    }
    let balance = money(abs(person.balance), currencyCode: person.currency)
    let headline = person.isSettled
      ? "All settled"
      : person.balance > 0 ? "Outstanding: \(balance)" : "I owe you: \(balance)"
    return """
    Hi \(person.contactName), here’s our lending summary:

    \(headline)

    \(lines.joined(separator: "\n"))
    """
  }
}

/// Finds the Dimo account for someone already tracked and invites them for
/// this person, so accepting shares the existing history.
private struct LinkAccountSheet: View {
  var store: AppStore
  var person: LendPerson
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: (query: String, users: [LendUser])?
  @State private var sending = false

  private var sharing: LendingSharingStore { store.lendingSharing }
  private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var users: [LendUser]? {
    guard let results, results.query == trimmed else { return nil }
    return results.users
  }

  var body: some View {
    SheetContainer(title: "Link to Dimo account", onClose: { dismiss() }) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Find \(person.contactName) on Dimo. Once they accept, your entries with them are shared and either of you can add or edit them.")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
        TextField("Name or email", text: $query)
          .font(DimoFont.body(15))
          .foregroundStyle(Theme.ink)
          .textFieldStyle(.plain)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .padding(.horizontal, 14)
          .frame(height: 50)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        if let users, !users.isEmpty {
          VStack(spacing: 0) {
            ForEach(Array(users.enumerated()), id: \.element.userId) { index, user in
              if index > 0 { Divider().overlay(Theme.line) }
              Button { link(user) } label: {
                HStack(spacing: 10) {
                  AvatarView(name: user.name, photoUrl: user.photoUrl, size: 32, radius: 10, fontSize: 13)
                  VStack(alignment: .leading, spacing: 1) {
                    Text(user.name)
                      .font(DimoFont.body(15))
                      .foregroundStyle(Theme.ink)
                      .lineLimit(1)
                    if let email = user.email {
                      Text(email)
                        .font(DimoFont.body(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    }
                  }
                  Spacer(minLength: 0)
                  Text(user.relation == "none" ? "Link" : lendRelationLabel(user))
                    .font(DimoFont.body(12, weight: .medium))
                    .foregroundStyle(Theme.green)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(sending)
            }
          }
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        } else if users != nil {
          Text("No one on Dimo matches “\(trimmed)”.")
            .font(DimoFont.body(13))
            .foregroundStyle(Theme.muted)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .presentationBackground(Theme.surface)
    .onAppear { if query.isEmpty { query = person.contactName } }
    .task(id: trimmed) {
      guard trimmed.count >= 2 else { return }
      let current = trimmed
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, let found = try? await sharing.searchUsers(current) else { return }
      results = (current, found)
    }
  }

  private func link(_ user: LendUser) {
    if user.relation == "connected" {
      store.showToast("You already share with \(user.name)")
      return
    }
    if user.relation == "invitedYou" {
      store.showToast("\(user.name) already invited you. Accept their invite first.")
      return
    }
    sending = true
    Task {
      defer { sending = false }
      do {
        try await sharing.sendInvite(to: user, contactId: person.contactId, contactName: user.name)
        // They're known by their account name, even before accepting.
        store.renameLendContact(contactId: person.contactId, to: user.name)
        store.showToast("Invite sent to \(user.name)")
        dismiss()
      } catch {
        store.showToast(error.localizedDescription)
      }
    }
  }
}
