import SwiftUI

struct SplitPersonDraft: Identifiable, Equatable {
  var contactId: String
  var contactName: String
  /// What's typed for an `.exact` or `.percent` split.
  var value = ""
  /// Picked from Dimo search without a shared ledger yet; saving invites them.
  var invite: LendUser?

  var id: String { contactId }
}

struct SplitDraft: Equatable {
  var mode: SplitMode = .equal
  /// nil when the user paid.
  var paidBy: String?
  var people: [SplitPersonDraft] = []

  var isActive: Bool { !people.isEmpty }

  /// Shares in minor units of `currency`, or nil when the split doesn't add up.
  func shares(totalMinor: Int, currency: String) -> SplitShares? {
    SplitSelectors.shares(
      totalMinor: totalMinor,
      mode: mode,
      people: people.map { person in
        let typed = Double(person.value) ?? 0
        return SplitShareInput(
          contactId: person.contactId,
          value: mode == .exact ? Double(ExchangeRates.toMinorUnits(typed, currency)) : typed
        )
      }
    )
  }

  /// Someone else paying needs the user to have a share; the user paying needs
  /// someone else to owe part of it.
  func isSavable(_ shares: SplitShares?) -> Bool {
    guard let shares, isActive else { return false }
    return paidBy == nil ? shares.others.contains { $0.share > 0 } : shares.mine > 0
  }

  var title: String {
    "Split with " + people.map { firstName($0.contactName) }.joined(separator: ", ")
  }

  var detail: String {
    let payer = people.first { $0.contactId == paidBy }.map { "\(firstName($0.contactName)) paid" } ?? "You paid"
    return "\(payer) · \(mode.label.lowercased())"
  }

  private func firstName(_ name: String) -> String {
    name.split(separator: " ").first.map(String.init) ?? name
  }
}

/// The split step of the expense sheet: who shares the bill, who paid it and
/// how it divides. The expense itself records only the user's share; the rest
/// becomes lending entries.
struct SplitStep: View {
  @Bindable var store: AppStore
  @Binding var draft: SplitDraft
  var totalMinor: Int
  var currency: String
  var onDone: () -> Void

  @State private var query = ""
  @State private var recentContacts: [LendContactSuggestion] = []
  @State private var knownContacts: [LendContactSuggestion] = []

  private var sharing: LendingSharingStore { store.lendingSharing }
  private var typed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var picked: Set<String> { Set(draft.people.map(\.contactId)) }
  private var shares: SplitShares? {
    totalMinor > 0 ? draft.shares(totalMinor: totalMinor, currency: currency) : nil
  }
  private var payer: SplitPersonDraft? { draft.people.first { $0.contactId == draft.paidBy } }
  private var savable: Bool { draft.isSavable(shares) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 6) {
        Button(action: onDone) {
          Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to expense")
        Text(totalMinor > 0 ? "Split \(format(totalMinor))" : "Split expense")
          .font(DimoFont.display(18, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
      .padding(.leading, -8)

      VStack(alignment: .leading, spacing: 8) {
        LendContactField(
          name: query,
          placeholder: "Add a name or Dimo email",
          searching: true,
          knownContacts: knownContacts,
          sharing: sharing,
          onEdit: { query = $0 },
          onPickContact: { addPerson(contactId: $0.contactId, contactName: $0.contactName) },
          onPickDimoUser: pickDimoUser,
          excludedContactIds: picked,
          onSubmit: addTyped
        )
        if !typed.isEmpty {
          Button("Add “\(typed)”", action: addTyped)
            .font(DimoFont.body(13, weight: .medium))
            .foregroundStyle(Theme.green)
            .buttonStyle(.plain)
        } else if !unpicked.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(unpicked) { suggestion in
                Chip(label: suggestion.contactName, selected: false) {
                  addPerson(contactId: suggestion.contactId, contactName: suggestion.contactName)
                }
              }
            }
          }
        }
      }

      if draft.isActive {
        HStack(spacing: 10) {
          splitMenu(title: payer.map { "\($0.contactName) paid" } ?? "You paid") {
            Button("You paid") { draft.paidBy = nil }
            ForEach(draft.people) { person in
              Button("\(person.contactName) paid") { draft.paidBy = person.contactId }
            }
          }
          splitMenu(title: draft.mode.label) {
            ForEach(SplitMode.allCases, id: \.self) { mode in
              Button(mode.label) { draft.mode = mode }
            }
          }
        }

        VStack(spacing: 0) {
          shareRow(name: "You") {
            HStack(spacing: 4) {
              Text(format(shares?.mine))
                .foregroundStyle(Theme.muted)
              // Lines up with the remove buttons on everyone else's rows.
              Color.clear.frame(width: 32, height: 32)
            }
          }
          ForEach($draft.people) { $person in
            Divider().overlay(Theme.line)
            shareRow(name: person.contactName) {
              HStack(spacing: 4) {
                if draft.mode == .equal {
                  Text(format(shares?.share(for: person.contactId)))
                    .foregroundStyle(Theme.muted)
                } else {
                  HStack(spacing: 3) {
                    TextField("0", text: $person.value)
                      .keyboardType(.decimalPad)
                      .multilineTextAlignment(.trailing)
                      .accessibilityLabel(
                        "\(person.contactName)'s \(draft.mode == .percent ? "percentage" : "amount")"
                      )
                    if draft.mode == .percent {
                      Text("%").foregroundStyle(Theme.muted)
                    }
                  }
                  .padding(.horizontal, 10)
                  .frame(width: 96, height: 34)
                  .background(Theme.canvas)
                  .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                  .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line))
                }
                Button { removePerson(person.contactId) } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(person.contactName)")
              }
            }
          }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))

        Text(note)
          .font(DimoFont.body(12))
          .foregroundStyle(problem == nil ? Theme.muted : Theme.danger)
      }

      Button(action: onDone) {
        Text(draft.isActive ? "Done" : "Cancel")
          .font(DimoFont.body(16, weight: .semibold))
          .foregroundStyle(draft.isActive ? Theme.onGreen : Theme.ink)
          .frame(maxWidth: .infinity)
          .frame(height: 54)
          .background(
            draft.isActive ? (canFinish ? Theme.green : Theme.disabled) : Theme.canvas
          )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(Theme.line, lineWidth: draft.isActive ? 0 : 1)
          )
      }
      .buttonStyle(.plain)
      .disabled(!canFinish)
    }
    .onAppear(perform: refreshContacts)
    .onChange(of: store.entities.revision) { _, _ in refreshContacts() }
  }

  private var canFinish: Bool { !draft.isActive || savable || totalMinor == 0 }

  private var unpicked: [LendContactSuggestion] {
    recentContacts.filter { !picked.contains($0.contactId) }
  }

  private var problem: String? {
    guard draft.isActive, totalMinor > 0, !savable else { return nil }
    guard let shares else {
      return draft.mode == .percent
        ? "Shares add up to more than 100%."
        : "Shares add up to more than \(format(totalMinor))."
    }
    return payer != nil && shares.mine == 0
      ? "Your share is zero — nothing to record."
      : "Nobody else has a share yet."
  }

  private var note: String {
    if let problem { return problem }
    if let payer, let shares {
      return "You owe \(payer.contactName) \(format(shares.mine)). Only your share counts as spending."
    }
    return "Only your share counts as spending. The rest goes to Lending."
  }

  private func format(_ minor: Int?) -> String {
    guard let minor else { return "—" }
    return Formatting.money(ExchangeRates.toMajorUnits(minor, currency), currencyCode: currency)
  }

  private func splitMenu<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    Menu(content: content) {
      HStack(spacing: 6) {
        Text(title)
          .font(DimoFont.body(14, weight: .medium))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Spacer(minLength: 4)
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Theme.muted)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 40)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
    .buttonStyle(.plain)
  }

  private func shareRow<Trailing: View>(
    name: String,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 8) {
      Text(name)
        .font(DimoFont.body(15, weight: .medium))
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
      Spacer(minLength: 8)
      trailing()
        .font(DimoFont.body(15))
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
    .frame(minHeight: 48)
  }

  private func addPerson(contactId: String, contactName: String, invite: LendUser? = nil) {
    query = ""
    guard !picked.contains(contactId) else { return }
    draft.people.append(SplitPersonDraft(contactId: contactId, contactName: contactName, invite: invite))
  }

  /// A typed name that matches someone already tracked continues their
  /// balance; any other name starts a new person.
  private func addTyped() {
    guard !typed.isEmpty else { return }
    let key = typed.lowercased()
    if let known = knownContacts.first(where: {
      $0.contactName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
    }) {
      addPerson(contactId: known.contactId, contactName: known.contactName)
    } else {
      addPerson(contactId: "contact_\(UUID().uuidString.lowercased())", contactName: typed)
    }
  }

  private func pickDimoUser(_ user: LendUser) {
    if user.relation == "invitedYou" {
      store.showToast("\(user.name) already invited you. Accept their invite in Lending first.")
      return
    }
    if let contactId = user.contactId {
      // Already shared, or already invited for this contact.
      addPerson(contactId: contactId, contactName: user.name)
    } else {
      addPerson(contactId: "contact_\(UUID().uuidString.lowercased())", contactName: user.name, invite: user)
    }
  }

  private func removePerson(_ contactId: String) {
    if draft.paidBy == contactId { draft.paidBy = nil }
    draft.people.removeAll { $0.contactId == contactId }
  }

  private func refreshContacts() {
    let people = lendPeople(lends: store.lends, sharing: sharing)
    recentContacts = people.recent
    knownContacts = people.known
  }
}
