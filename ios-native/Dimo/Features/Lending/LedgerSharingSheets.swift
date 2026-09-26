import SwiftUI
import UIKit

/// Invites another Dimo account to share a lending ledger, by link/code and
/// optionally by their verified email.
struct LedgerInviteSheet: View {
  var store: AppStore
  var initialContactId: String?
  var initialContactName: String

  @State private var contactName = ""
  @State private var contactId: String?
  @State private var email = ""
  @State private var invite: LendInviteCode?
  @State private var working = false
  @State private var errorMessage: String?
  @State private var sentByEmail = false

  private var sharing: LendingSharingStore { store.lendingSharing }

  /// Existing, not-yet-shared lending contacts whose history can come along.
  private var shareableContacts: [LendContactSuggestion] {
    LendSelectors.recentContacts(store.lends, limit: 20)
      .filter { !$0.contactId.hasPrefix(sharedLendContactPrefix) }
  }

  private var canCreate: Bool {
    !contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !working
  }

  var body: some View {
    SheetContainer(title: invite == nil ? "Share a ledger" : "Invite ready", onClose: close) {
      VStack(alignment: .leading, spacing: 16) {
        if let invite {
          inviteReady(invite)
        } else {
          form
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
    .onAppear {
      contactName = initialContactName
      contactId = initialContactId
      if let initialContactId, let pending = sharing.pendingInvite(contactId: initialContactId) {
        invite = LendInviteCode(code: pending.code, expiresAt: pending.expiresAt)
      }
    }
  }

  @ViewBuilder
  private var form: some View {
    Text("You and the other person see the same entries, and either of you can add, edit or delete them.")
      .font(DimoFont.body(13))
      .foregroundStyle(Theme.muted)

    VStack(alignment: .leading, spacing: 6) {
      label("Who are you sharing with?")
      if initialContactId != nil {
        lockedField(contactName)
      } else {
        TextField("Their name", text: $contactName)
          .textFieldStyle(.plain)
          .modifier(SharingFieldStyle())
          .onChange(of: contactName) { _, name in
            // Typing a new name detaches a previously tapped contact.
            if let contactId, shareableContacts.first(where: { $0.contactId == contactId })?.contactName != name {
              self.contactId = nil
            }
          }
        if !shareableContacts.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(shareableContacts) { suggestion in
                let selected = contactId == suggestion.contactId
                Button {
                  contactName = suggestion.contactName
                  contactId = suggestion.contactId
                } label: {
                  Text(suggestion.contactName)
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
            }
          }
        }
      }
      if contactId != nil {
        Text("Your past entries with \(contactName) will be shared too.")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }
    }

    if sharing.emailInvitesAvailable {
      VStack(alignment: .leading, spacing: 6) {
        label("Their Dimo email (optional)")
        TextField("name@example.com", text: $email)
          .textFieldStyle(.plain)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .modifier(SharingFieldStyle())
        Text("If they use Dimo with this email, the invite appears in their Lending tab. You can also share the link.")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }
    }

    primaryButton(working ? "Creating…" : "Create invite", enabled: canCreate) {
      Task { await create() }
    }
  }

  @ViewBuilder
  private func inviteReady(_ invite: LendInviteCode) -> some View {
    if sentByEmail {
      Text("If \(contactName) uses Dimo with that email, they’ll see your invite in their Lending tab.")
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
    }
    VStack(spacing: 6) {
      Text(Self.groupedCode(invite.code))
        .font(DimoFont.display(28, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
        .accessibilityLabel("Invite code \(invite.code.map(String.init).joined(separator: " "))")
      Text("Expires \(Self.expiryText(invite.expiresAt))")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line))

    ShareLink(item: LendInviteLinks.message(inviterName: store.profileName, code: invite.code)) {
      Text("Share invite")
        .font(DimoFont.body(16, weight: .semibold))
        .foregroundStyle(Theme.onGreen)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Theme.green)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)

    HStack(spacing: 10) {
      secondaryButton("Copy code") {
        UIPasteboard.general.string = invite.code
        store.showToast("Invite code copied")
      }
      secondaryButton("Cancel invite", destructive: true) {
        Task {
          do {
            try await sharing.cancel(code: invite.code)
            store.showToast("Invite cancelled")
            close()
          } catch {
            errorMessage = error.localizedDescription
          }
        }
      }
    }
  }

  private func create() async {
    working = true
    errorMessage = nil
    defer { working = false }
    do {
      let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
      invite = try await sharing.createInvite(
        contactId: contactId,
        contactName: contactName,
        email: trimmedEmail
      )
      sentByEmail = !trimmedEmail.isEmpty
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func close() { sharing.sheet = nil }

  static func groupedCode(_ code: String) -> String {
    code.count == 10 ? "\(code.prefix(5))-\(code.suffix(5))" : code
  }

  static func expiryText(_ expiresAt: Double) -> String {
    let date = Date(timeIntervalSince1970: expiresAt / 1000)
    return date.formatted(.relative(presentation: .named))
  }
}

/// Joins a ledger someone shared: preview the invite, optionally link an
/// existing contact, choose whose history to keep, then accept.
struct JoinLedgerSheet: View {
  var store: AppStore
  var initialCode: String

  @State private var code = ""
  @State private var preview: LendInvitePreview?
  @State private var previewedCode: String?
  @State private var linkedContactId: String?
  @State private var contactName = ""
  @State private var history: LendHistoryChoice = .both
  @State private var working = false
  @State private var errorMessage: String?

  private var sharing: LendingSharingStore { store.lendingSharing }

  /// Addressed to this account by email, so it can also be declined.
  private var isIncoming: Bool {
    sharing.incomingInvites.contains { $0.code == LendInviteLinks.normalize(code) }
  }

  private var linkableContacts: [LendContactSuggestion] {
    LendSelectors.recentContacts(store.lends, limit: 20)
      .filter { !$0.contactId.hasPrefix(sharedLendContactPrefix) }
  }

  var body: some View {
    SheetContainer(title: "Join a shared ledger", onClose: close) {
      VStack(alignment: .leading, spacing: 16) {
        if let preview, previewedCode == LendInviteLinks.normalize(code) {
          reviewForm(preview)
        } else {
          codeForm
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
    .onAppear {
      code = initialCode
      if !initialCode.isEmpty { Task { await lookUp() } }
    }
  }

  @ViewBuilder
  private var codeForm: some View {
    Text("Enter the code from the invite someone shared with you.")
      .font(DimoFont.body(13))
      .foregroundStyle(Theme.muted)
    TextField("ABCDE-12345", text: $code)
      .textFieldStyle(.plain)
      .textInputAutocapitalization(.characters)
      .autocorrectionDisabled()
      .font(DimoFont.display(20, weight: .semibold))
      .modifier(SharingFieldStyle())
    primaryButton(
      working ? "Checking…" : "Continue",
      enabled: LendInviteLinks.normalize(code).count >= 6 && !working
    ) {
      Task { await lookUp() }
    }
  }

  @ViewBuilder
  private func reviewForm(_ preview: LendInvitePreview) -> some View {
    if !preview.isAcceptable {
      Text(unavailableReason(preview))
        .font(DimoFont.body(14))
        .foregroundStyle(Theme.muted)
      secondaryButton("Try another code") { self.preview = nil; previewedCode = nil }
    } else {
      Text("\(preview.inviterName) wants to keep a shared lending ledger with you. You’ll both see the same entries, and either of you can edit them.")
        .font(DimoFont.body(14))
        .foregroundStyle(Theme.ink)

      if !linkableContacts.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          label("Already tracking \(preview.inviterName) here?")
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              chip("No", selected: linkedContactId == nil) {
                linkedContactId = nil
                contactName = preview.inviterName
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
          Text(historyExplanation(preview.inviterName))
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        label("Show them as")
        TextField(preview.inviterName, text: $contactName)
          .textFieldStyle(.plain)
          .modifier(SharingFieldStyle())
      }

      primaryButton(working ? "Joining…" : "Join ledger", enabled: !working) {
        Task { await accept() }
      }
      if isIncoming {
        secondaryButton("Decline", destructive: true) {
          Task {
            do {
              try await sharing.decline(code: LendInviteLinks.normalize(code))
              close()
            } catch {
              errorMessage = error.localizedDescription
            }
          }
        }
      }
    }
  }

  private func unavailableReason(_ preview: LendInvitePreview) -> String {
    if preview.isOwnInvite { return "This is your own invite. Share it with the other person instead." }
    switch preview.status {
    case "accepted": return "This invite has already been used."
    case "revoked": return "This invite was cancelled."
    default: return "This invite has expired. Ask \(preview.inviterName) for a new one."
    }
  }

  private func historyExplanation(_ inviterName: String) -> String {
    switch history {
    case .both: return "Both of your past entries are added to the shared ledger."
    case .inviter: return "Only \(inviterName)’s past entries are kept; yours with them are deleted so nothing is counted twice."
    case .accepter: return "Only your past entries are kept; \(inviterName)’s are deleted so nothing is counted twice."
    }
  }

  private func lookUp() async {
    working = true
    errorMessage = nil
    defer { working = false }
    do {
      let normalized = LendInviteLinks.normalize(code)
      guard let found = try await sharing.preview(code: normalized) else {
        errorMessage = "No invite matches that code."
        return
      }
      preview = found
      previewedCode = normalized
      if contactName.isEmpty { contactName = found.inviterName }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func accept() async {
    working = true
    errorMessage = nil
    defer { working = false }
    do {
      _ = try await sharing.accept(
        code: code,
        contactId: linkedContactId,
        contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
        history: linkedContactId == nil ? .both : history
      )
      store.showToast("Ledger shared with \(contactName)")
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

private func lockedField(_ value: String) -> some View {
  Text(value)
    .lineLimit(1)
    .modifier(SharingFieldStyle())
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
