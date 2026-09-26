import SwiftUI
import UIKit

/// Add or edit a lending entry as "I gave" / "I got". Whether it's a new loan
/// or a repayment follows from the balance with that person, so users never
/// pick between lent, borrowed, got back and paid back.
struct AddLendSheet: View {
  @Bindable var store: AppStore
  @State private var confirmDelete = false
  /// Everyone in lend history plus shared and invited people, for matching.
  @State private var knownContacts: [LendContactSuggestion] = []
  @State private var recentContacts: [LendContactSuggestion] = []

  private var sharing: LendingSharingStore { store.lendingSharing }
  private var draft: LendDraft { store.lendDraft }
  private var isEditing: Bool { draft.editingId != nil }
  private var contactLocked: Bool { isEditing || draft.contactLocked }

  var body: some View {
    SheetContainer(
      title: isEditing ? "Edit entry" : "Add entry",
      onClose: { store.closeOverlay() },
      titleAlignment: isEditing ? .leading : .center
    ) {
      VStack(alignment: .leading, spacing: 16) {
        LendFlowSwitcher(flow: $store.lendDraft.flow)

        VStack(alignment: .leading, spacing: 6) {
          lendLabel(draft.flow == .gave ? "To" : "From")
          if contactLocked {
            HStack(spacing: 10) {
              AvatarView(
                name: draft.contactName,
                photoUrl: draft.contactId.flatMap { sharing.photoUrl(contactId: $0) },
                size: 28,
                radius: 9,
                fontSize: 12
              )
              Text(draft.contactName)
                .font(DimoFont.body(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
          } else {
            LendContactField(
              name: draft.contactName,
              searching: draft.contactId == nil && draft.invite == nil,
              knownContacts: knownContacts,
              sharing: sharing,
              onEdit: editContactName,
              onPickContact: { contact in
                store.lendDraft.contactName = contact.contactName
                store.lendDraft.contactId = contact.contactId
                store.lendDraft.invite = nil
              },
              onPickDimoUser: pickDimoUser
            )
            if draft.contactName.isEmpty {
              contactSuggestions
            }
          }
          contactNote
        }

        VStack(alignment: .leading, spacing: 6) {
          lendLabel("Date")
          DatePicker(
            "Date",
            selection: $store.lendDraft.date,
            in: ...Date(),
            displayedComponents: .date
          )
          .labelsHidden()
          .datePickerStyle(.compact)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 14)
          .frame(height: 50)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
          .tint(Theme.green)
        }

        VStack(alignment: .leading, spacing: 6) {
          lendField("Amount") {
            HStack(spacing: 8) {
              Text(currencySymbol)
                .foregroundStyle(Theme.muted)
              TextField("0", text: $store.lendDraft.amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
            }
          }
          if let balanceText {
            Text(balanceText)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.faint)
          }
        }

        lendField("Note (optional)") {
          TextField("e.g. Dinner, cab fare", text: $store.lendDraft.comment)
            .textFieldStyle(.plain)
        }

        Button {
          store.saveLend()
        } label: {
          Text("Save")
            .font(DimoFont.body(16, weight: .semibold))
            .foregroundStyle(Theme.onGreen)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(canSave ? Theme.green : Theme.disabled)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .presentationBackground(Theme.surface)
    .onAppear { refreshContacts() }
    .onChange(of: store.entities.revision) { _, _ in refreshContacts() }
    .overlay(alignment: .topTrailing) {
      if isEditing {
        Button { confirmDelete = true } label: {
          Image(systemName: "trash")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .frame(width: 42, height: 42)
            .background(Theme.dangerSoft)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.dangerLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete entry")
        .padding(.top, 14)
        .padding(.trailing, 20)
      }
    }
    .alert("Delete this entry?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        guard let id = draft.editingId else { return }
        store.deleteLend(id)
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        isSharedContact
          ? "This also removes it for \(draft.contactName)."
          : "This can’t be undone."
      )
    }
  }

  @ViewBuilder
  private var contactNote: some View {
    if isSharedContact {
      Label("Shared with \(draft.contactName) — they see this entry too", systemImage: "person.2.fill")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.green)
    } else if let invite = pendingDraftInvite {
      Label(
        "Saving invites \(invite.user.email ?? invite.user.name). This entry stays private until they accept.",
        systemImage: "paperplane"
      )
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.muted)
    } else if let contactId = draft.contactId, let sent = sharing.pendingInvite(contactId: contactId) {
      Label(
        "Invited \(sent.inviteeEmail ?? sent.contactName). This entry is shared once they accept.",
        systemImage: "clock"
      )
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.muted)
    }
  }

  /// An edited entry keeps the currency it was recorded in.
  private var currencySymbol: String {
    if let id = draft.editingId, let code = store.lends.first(where: { $0.id == id })?.currency {
      return CurrencyMeta.symbol(code)
    }
    return Formatting.currencySymbol(store.currency)
  }

  /// "Priya owes you ₹100" / "You owe Priya ₹50", before this entry.
  private var balanceText: String? {
    guard let contactId = draft.contactId else { return nil }
    let balance = LendSelectors.netBalance(for: contactId, in: store.lends, excludingLendId: draft.editingId)
    guard abs(balance) > 0.0001 else { return nil }
    let name = draft.contactName.trimmingCharacters(in: .whitespacesAndNewlines)
    let amount = "\(currencySymbol)\(Self.amountText(abs(balance)))"
    return balance > 0
      ? "\(name.isEmpty ? "They" : name) owes you \(amount)"
      : "You owe \(name.isEmpty ? "them" : name) \(amount)"
  }

  private static func amountText(_ amount: Double) -> String {
    amount.rounded() == amount ? String(Int(amount)) : String(format: "%.2f", amount)
  }

  /// The invite saving will send, when the contact was picked as a Dimo account.
  private var pendingDraftInvite: LendDraftInvite? {
    guard let invite = draft.invite, invite.contactId == draft.contactId else { return nil }
    return invite
  }

  private var isSharedContact: Bool {
    draft.contactId.map { sharing.activeConnection(contactId: $0) != nil } ?? false
  }

  private var canSave: Bool {
    let amount = Double(draft.amount) ?? 0
    return !draft.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0
  }

  /// A typed name that matches someone already tracked continues their balance.
  private func editContactName(_ name: String) {
    let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    store.lendDraft.contactName = name
    store.lendDraft.invite = nil
    store.lendDraft.contactId = key.isEmpty
      ? nil
      : knownContacts.first {
        $0.contactName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
      }?.contactId
  }

  private func pickDimoUser(_ user: LendUser) {
    if user.relation == "invitedYou" {
      store.showToast("\(user.name) already invited you. Accept their invite in Lending first.")
      return
    }
    store.lendDraft.contactName = user.name
    if let contactId = user.contactId {
      // Already shared, or already invited for this contact.
      store.lendDraft.contactId = contactId
      store.lendDraft.invite = nil
    } else {
      let contactId = "contact_\(UUID().uuidString.lowercased())"
      store.lendDraft.contactId = contactId
      store.lendDraft.invite = LendDraftInvite(user: user, contactId: contactId)
    }
  }

  private func refreshContacts() {
    // Shared people and invites are offered even before any entries.
    var recent = LendSelectors.recentContacts(store.lends)
    var extra: [LendContactSuggestion] = []
    for connection in sharing.connections where connection.isActive {
      extra.append(LendContactSuggestion(contactName: connection.contactName, contactId: connection.contactId))
    }
    for invite in sharing.outgoingInvites {
      if let contactId = invite.contactId {
        extra.append(LendContactSuggestion(contactName: invite.contactName, contactId: contactId))
      }
    }
    for item in extra where !recent.contains(where: { $0.contactId == item.contactId }) {
      recent.append(item)
    }
    recentContacts = recent
    var known = LendSelectors.recentContacts(store.lends, limit: .max)
    for item in extra where !known.contains(where: { $0.contactId == item.contactId }) {
      known.append(item)
    }
    knownContacts = known
  }

  /// Recent people, offered as one-tap picks until someone is chosen.
  @ViewBuilder
  private var contactSuggestions: some View {
    if !recentContacts.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(recentContacts) { suggestion in
            Button {
              store.lendDraft.contactName = suggestion.contactName
              store.lendDraft.contactId = suggestion.contactId
              store.lendDraft.invite = nil
            } label: {
              HStack(spacing: 6) {
                AvatarView(
                  name: suggestion.contactName,
                  photoUrl: sharing.photoUrl(contactId: suggestion.contactId),
                  size: 22,
                  radius: 11,
                  fontSize: 10
                )
                Text(suggestion.contactName)
                  .font(DimoFont.body(13, weight: .medium))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(1)
              }
              .padding(.leading, 5)
              .padding(.trailing, 12)
              .padding(.vertical, 5)
              .background(Theme.canvas)
              .clipShape(Capsule())
              .overlay(Capsule().stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(suggestion.contactName)")
          }
        }
        .padding(.vertical, 1)
      }
      .padding(.top, 4)
    }
  }

  private func lendLabel(_ title: String) -> some View {
    Text(title)
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.muted)
  }

  private func lendField<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      lendLabel(title)
      content()
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
}

/// "I gave" / "I got" capsule pair.
struct LendFlowSwitcher: View {
  @Binding var flow: LendFlow

  var body: some View {
    HStack(spacing: 8) {
      ForEach(LendFlow.allCases, id: \.self) { candidate in
        let selected = flow == candidate
        Button {
          flow = candidate
        } label: {
          Text(candidate == .gave ? "I gave" : "I got")
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(selected ? Theme.canvas : Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selected ? Theme.ink : Theme.canvas)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// Short label for a Dimo user's relationship to you.
func lendRelationLabel(_ user: LendUser) -> String {
  switch user.relation {
  case "connected": return "Shared"
  case "invited": return "Invited"
  case "invitedYou": return "Invited you"
  default: return "On Dimo"
  }
}

/// Typed name that searches your people as you type and, from two letters,
/// Dimo accounts by name or email. Picking a Dimo account makes saving invite
/// them.
private struct LendContactField: View {
  var name: String
  /// False once someone is picked, which hides the results.
  var searching: Bool
  var knownContacts: [LendContactSuggestion]
  var sharing: LendingSharingStore
  var onEdit: (String) -> Void
  var onPickContact: (LendContactSuggestion) -> Void
  var onPickDimoUser: (LendUser) -> Void

  @State private var results: (query: String, users: [LendUser])?

  private var query: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var searchQuery: String? {
    searching && sharing.isOnline && query.count >= 2 ? query : nil
  }
  private var dimoUsers: [LendUser]? {
    guard let results, results.query == searchQuery else { return nil }
    return results.users
  }
  private var matchingContacts: [LendContactSuggestion] {
    guard searching, !query.isEmpty else { return [] }
    // A Dimo result already stands for the contact it's shared or invited as.
    let linked = Set((dimoUsers ?? []).compactMap(\.contactId))
    return Array(
      knownContacts
        .filter { $0.contactName.localizedCaseInsensitiveContains(query) && !linked.contains($0.contactId) }
        .prefix(5)
    )
  }
  private var showsResults: Bool {
    searching && !query.isEmpty && (!matchingContacts.isEmpty || dimoUsers != nil)
  }

  var body: some View {
    VStack(spacing: 0) {
      TextField(
        "Their name or Dimo email",
        text: Binding(get: { name }, set: { onEdit($0) })
      )
      .font(DimoFont.body(15))
      .foregroundStyle(Theme.ink)
      .textFieldStyle(.plain)
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled()
      .padding(.horizontal, 14)
      .frame(height: 50)

      if showsResults {
        Divider().overlay(Theme.line)
        ForEach(matchingContacts) { contact in
          resultRow(
            name: contact.contactName,
            detail: nil,
            photoUrl: sharing.photoUrl(contactId: contact.contactId),
            badge: sharing.activeConnection(contactId: contact.contactId) != nil ? "Shared" : "Your contact",
            badgeTint: Theme.muted
          ) { onPickContact(contact) }
        }
        ForEach(dimoUsers ?? [], id: \.userId) { user in
          resultRow(
            name: user.name,
            detail: user.email,
            photoUrl: user.photoUrl,
            badge: lendRelationLabel(user),
            badgeTint: Theme.green
          ) { onPickDimoUser(user) }
        }
        if let dimoUsers, dimoUsers.isEmpty, matchingContacts.isEmpty {
          Text("No one named “\(query)” yet. Saving adds them as a new person.")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
      }
    }
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    .animation(.snappy(duration: 0.2), value: showsResults)
    .task(id: searchQuery) {
      guard let query = searchQuery else { return }
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled, let users = try? await sharing.searchUsers(query) else { return }
      results = (query, users)
    }
  }

  private func resultRow(
    name: String,
    detail: String?,
    photoUrl: String?,
    badge: String,
    badgeTint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        AvatarView(name: name, photoUrl: photoUrl, size: 32, radius: 10, fontSize: 13)
        VStack(alignment: .leading, spacing: 1) {
          Text(name)
            .font(DimoFont.body(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          if let detail {
            Text(detail)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
        Text(badge)
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(badgeTint)
      }
      .padding(.horizontal, 14)
      .frame(height: 54)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
