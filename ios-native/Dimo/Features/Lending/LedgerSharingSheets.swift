import SwiftUI

/// Accepts or declines an invite, optionally linking a contact already tracked
/// here so its history joins the shared ledger.
struct AcceptInviteSheet: View {
  var store: AppStore
  var invite: IncomingLendInvite

  @State private var linkedContactId: String?
  @State private var contactName = ""
  @State private var history: LendHistoryChoice = .both
  @State private var working = false
  @State private var errorMessage: String?

  private var sharing: LendingSharingStore { store.lendingSharing }

  private var linkableContacts: [LendContactSuggestion] {
    LendSelectors.recentContacts(store.lends, limit: 20)
      .filter { !$0.contactId.hasPrefix(sharedLendContactPrefix) }
  }

  var body: some View {
    SheetContainer(title: "Shared ledger invite", onClose: close) {
      VStack(alignment: .leading, spacing: 16) {
        Text(intro)
          .font(DimoFont.body(14))
          .foregroundStyle(Theme.ink)

        if !linkableContacts.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            label("Already tracking \(invite.inviterName) here?")
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                chip("No", selected: linkedContactId == nil) {
                  linkedContactId = nil
                  contactName = invite.inviterName
                }
                ForEach(linkableContacts) { contact in
                  chip(contact.contactName, selected: linkedContactId == contact.contactId) {
                    linkedContactId = contact.contactId
                    contactName = contact.contactName
                  }
                }
              }
            }
          }
        }

        if linkedContactId != nil {
          VStack(alignment: .leading, spacing: 6) {
            label("If you both recorded the same loans")
            Picker("History", selection: $history) {
              Text("Keep both").tag(LendHistoryChoice.both)
              Text("Keep theirs").tag(LendHistoryChoice.inviter)
              Text("Keep mine").tag(LendHistoryChoice.accepter)
            }
            .pickerStyle(.segmented)
            Text(historyExplanation)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
          }
        }

        HStack(spacing: 10) {
          secondaryButton("Decline") {
            Task { await run(done: "Invite declined") { try await sharing.decline(invite) } }
          }
          primaryButton(working ? "Accepting…" : "Accept", enabled: !working) {
            Task {
              await run(done: "Ledger shared with \(contactName)") {
                try await sharing.accept(
                  invite,
                  contactId: linkedContactId,
                  contactName: contactName,
                  history: linkedContactId == nil ? .both : history
                )
              }
            }
          }
        }

        if let errorMessage {
          Text(errorMessage)
            .font(DimoFont.body(13))
            .foregroundStyle(Theme.danger)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .presentationBackground(Theme.surface)
    .onAppear { contactName = invite.inviterName }
  }

  private var intro: String {
    let from = invite.inviterEmail.map { "\(invite.inviterName) (\($0))" } ?? invite.inviterName
    return "\(from) wants to keep a shared lending ledger with you. You’ll both see the same entries, and either of you can edit them."
  }

  private var historyExplanation: String {
    switch history {
    case .both: return "Both of your past entries are added to the shared ledger."
    case .inviter: return "Only \(invite.inviterName)’s past entries are kept; yours with them are deleted so nothing is counted twice."
    case .accepter: return "Only your past entries are kept; \(invite.inviterName)’s are deleted so nothing is counted twice."
    }
  }

  private func run(done: String, _ action: () async throws -> Void) async {
    working = true
    errorMessage = nil
    defer { working = false }
    do {
      try await action()
      store.showToast(done)
      close()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func close() { sharing.sheet = nil }
}

private struct SharingFieldStyle: ViewModifier {
  func body(content: Content) -> some View {
    content
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

private func label(_ title: String) -> some View {
  Text(title)
    .font(DimoFont.body(12))
    .foregroundStyle(Theme.muted)
}

private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Text(title)
      .font(DimoFont.body(13, weight: .medium))
      .foregroundStyle(selected ? Theme.canvas : Theme.ink)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(selected ? Theme.ink : Theme.canvas)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
  }
  .buttonStyle(.plain)
}

private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Text(title)
      .font(DimoFont.body(16, weight: .semibold))
      .foregroundStyle(Theme.onGreen)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(enabled ? Theme.green : Theme.disabled)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
  .buttonStyle(.plain)
  .disabled(!enabled)
}

private func secondaryButton(
  _ title: String,
  destructive: Bool = false,
  action: @escaping () -> Void
) -> some View {
  Button(action: action) {
    Text(title)
      .font(DimoFont.body(15, weight: .semibold))
      .foregroundStyle(destructive ? Theme.danger : Theme.ink)
      .frame(maxWidth: .infinity)
      .frame(height: 48)
      .background(destructive ? Theme.dangerSoft : Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(destructive ? Theme.dangerLine : Theme.line, lineWidth: 1)
      )
  }
  .buttonStyle(.plain)
}
