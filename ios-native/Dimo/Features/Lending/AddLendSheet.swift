import Contacts
import SwiftUI

struct AddLendSheet: View {
  @Bindable var store: AppStore
  @State private var confirmDelete = false
  /// While the contact dropdown is open the rest of the form is hidden so the
  /// search field and list stay visible above the keyboard.
  @State private var contactSearchOpen = false

  private var isEditing: Bool { store.lendDraft.editingId != nil }
  private var isRepayment: Bool { store.lendDraft.kind == .repaid }
  /// Contact is locked when recording a repayment from summary, or when editing.
  private var contactLocked: Bool { isEditing || (isRepayment && !store.lendDraft.contactName.isEmpty) }

  private var sheetTitle: String {
    if isEditing {
      return isRepayment ? "Edit repayment" : "Edit lend"
    }
    return isRepayment ? "Got back" : "Add lend"
  }

  private var saveTitle: String {
    if isEditing {
      return isRepayment ? "Save repayment" : "Save lend"
    }
    return isRepayment ? "Save got back" : "Save lend"
  }

  var body: some View {
    SheetContainer(
      title: sheetTitle,
      onClose: { store.closeOverlay() },
      titleAlignment: isEditing ? .leading : .center
    ) {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          lendLabel(isRepayment ? "From" : "Lent to")
          if contactLocked {
            HStack(spacing: 10) {
              ContactAvatar(
                contact: LendContact(
                  id: store.lendDraft.contactId ?? store.lendDraft.contactName,
                  name: store.lendDraft.contactName,
                  thumbnail: ContactsLoader.shared.thumbnail(contactId: store.lendDraft.contactId)
                ),
                size: 28
              )
              Text(store.lendDraft.contactName)
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
            ContactDropdown(
              selectedName: $store.lendDraft.contactName,
              selectedContactId: $store.lendDraft.contactId,
              isSearching: $contactSearchOpen
            )
            if !contactSearchOpen && store.lendDraft.contactName.isEmpty {
              contactSuggestions
            }
          }
        }

        if !contactSearchOpen {
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

          lendField(isRepayment ? "Amount got back" : "Amount") {
            HStack(spacing: 8) {
              Text(Formatting.currencySymbol(store.currency))
                .foregroundStyle(Theme.muted)
              TextField("0", text: $store.lendDraft.amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
            }
          }

          lendField("Comments (optional)") {
            TextField(
              isRepayment ? "e.g. Partial repayment" : "e.g. Dinner split, emergency",
              text: $store.lendDraft.comment
            )
            .textFieldStyle(.plain)
          }

          Button {
            store.saveLend()
          } label: {
            Text(saveTitle)
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
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .animation(.snappy(duration: 0.2), value: contactSearchOpen)
    }
    .presentationBackground(Theme.surface)
    .onAppear { ContactsLoader.shared.loadIfAuthorized() }
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
        .padding(.top, 14)
        .padding(.trailing, 20)
      }
    }
    .alert(isRepayment ? "Delete this repayment?" : "Delete this lend?", isPresented: $confirmDelete) {
      Button("Delete", role: .destructive) {
        guard let id = store.lendDraft.editingId else { return }
        store.deleteLend(id)
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private var canSave: Bool {
    store.lendDraft.contactId != nil
      && !store.lendDraft.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (Double(store.lendDraft.amount) ?? 0) > 0
  }

  /// Recent contacts from lend history, offered as one-tap picks until a
  /// contact is chosen.
  @ViewBuilder
  private var contactSuggestions: some View {
    let suggestions = LendSelectors.recentContacts(store.lends)
    if !suggestions.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(suggestions) { suggestion in
            Button {
              store.lendDraft.contactName = suggestion.contactName
              store.lendDraft.contactId = suggestion.contactId
            } label: {
              HStack(spacing: 6) {
                ContactAvatar(
                  contact: LendContact(
                    id: suggestion.contactId,
                    name: suggestion.contactName,
                    thumbnail: ContactsLoader.shared.thumbnail(contactId: suggestion.contactId)
                  ),
                  size: 22
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

struct LendContact: Identifiable, Equatable {
  let id: String
  let name: String
  let thumbnail: Data?
}

/// Loads the address book with full Contacts access so contacts can be
/// listed inline, including their photos. Photos are only ever read from the
/// device address book at render time — they are never persisted or synced.
@Observable
final class ContactsLoader {
  enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case denied
  }

  static let shared = ContactsLoader()

  private(set) var state: LoadState = .idle
  private(set) var contacts: [LendContact] = []

  /// Thumbnail for a lend's contact, looked up strictly by identifier; nil
  /// when the contact was removed from the address book.
  func thumbnail(contactId: String?) -> Data? {
    contact(contactId: contactId)?.thumbnail
  }

  func contact(contactId: String?) -> LendContact? {
    guard let contactId else { return nil }
    return contacts.first { $0.id == contactId }
  }

  /// Fetches contacts only when access is already granted; never prompts.
  func loadIfAuthorized() {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    guard status != .denied, status != .restricted, status != .notDetermined else { return }
    guard state == .idle else { return }
    state = .loading
    fetch(from: CNContactStore())
  }

  func load() {
    guard state == .idle else { return }
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .denied, .restricted:
      state = .denied
    case .notDetermined:
      state = .loading
      let store = CNContactStore()
      store.requestAccess(for: .contacts) { granted, _ in
        DispatchQueue.main.async {
          if granted {
            self.fetch(from: store)
          } else {
            self.state = .denied
          }
        }
      }
    default:
      state = .loading
      fetch(from: CNContactStore())
    }
  }

  private func fetch(from store: CNContactStore) {
    DispatchQueue.global(qos: .userInitiated).async {
      let keys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
      ]
      let request = CNContactFetchRequest(keysToFetch: keys)
      request.sortOrder = .userDefault
      var result: [LendContact] = []
      try? store.enumerateContacts(with: request) { contact, _ in
        let name = CNContactFormatter.string(from: contact, style: .fullName)
          ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        guard !name.isEmpty else { return }
        result.append(
          LendContact(id: contact.identifier, name: name, thumbnail: contact.thumbnailImageData)
        )
      }
      DispatchQueue.main.async {
        self.contacts = result
        self.state = .loaded
      }
    }
  }
}

/// Searchable single-select dropdown: the field doubles as the search box,
/// and the list below filters as the user types.
private struct ContactDropdown: View {
  @Binding var selectedName: String
  @Binding var selectedContactId: String?
  @Binding var isSearching: Bool
  private let loader = ContactsLoader.shared
  @State private var text = ""
  @FocusState private var searching: Bool

  private var selectedContact: LendContact? {
    loader.contact(contactId: selectedContactId)
  }

  private var filtered: [LendContact] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return loader.contacts }
    return loader.contacts.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        if !searching, let contact = selectedContact {
          ContactAvatar(contact: contact, size: 28)
        } else {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
        TextField(
          selectedName.isEmpty ? "Search contacts" : selectedName,
          text: $text
        )
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.ink)
        .textFieldStyle(.plain)
        .autocorrectionDisabled()
        .focused($searching)
        Button {
          searching.toggle()
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.green)
            .rotationEffect(.degrees(searching ? 180 : 0))
            .frame(width: 32, height: 50)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(searching ? "Close contact list" : "Choose from contacts")
      }
      .padding(.leading, 14)
      .padding(.trailing, 6)
      .frame(height: 50)

      if searching {
        Divider().overlay(Theme.line)
        dropdownBody
      }
    }
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    .animation(.snappy(duration: 0.2), value: searching)
    .onAppear { text = selectedName }
    .onChange(of: selectedName) { _, name in
      // Selection can change from outside (suggestion chips); mirror it.
      if !searching { text = name }
    }
    .onChange(of: searching) { _, focused in
      isSearching = focused
      if focused {
        text = ""
        loader.load()
      } else {
        // Closed without picking: revert to the current selection.
        text = selectedName
      }
    }
  }

  @ViewBuilder
  private var dropdownBody: some View {
    switch loader.state {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity)
        .frame(height: 72)
    case .denied:
      VStack(spacing: 10) {
        Text("Contacts access is off. Allow access in Settings to pick a contact.")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
          .multilineTextAlignment(.center)
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        .font(DimoFont.body(14, weight: .semibold))
        .foregroundStyle(Theme.green)
      }
      .padding(14)
      .frame(maxWidth: .infinity)
    case .loaded:
      if filtered.isEmpty {
        Text(loader.contacts.isEmpty ? "No contacts found" : "No matches")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
          .frame(maxWidth: .infinity)
          .frame(height: 64)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(filtered) { contact in
              Button {
                selectedName = contact.name
                selectedContactId = contact.id
                searching = false
              } label: {
                HStack(spacing: 10) {
                  ContactAvatar(contact: contact, size: 32)
                  Text(contact.name)
                    .font(DimoFont.body(15))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                  Spacer(minLength: 0)
                  if contact.id == selectedContact?.id {
                    Image(systemName: "checkmark")
                      .font(.system(size: 13, weight: .semibold))
                      .foregroundStyle(Theme.green)
                  }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 240)
        .scrollDismissesKeyboard(.never)
      }
    }
  }
}

private struct ContactAvatar: View {
  let contact: LendContact
  let size: CGFloat

  private var initials: String {
    let parts = contact.name.split(separator: " ")
    let letters = [parts.first, parts.count > 1 ? parts.last : nil]
      .compactMap { $0?.first.map(String.init) }
    return letters.joined().uppercased()
  }

  var body: some View {
    Group {
      if let data = contact.thumbnail, let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Text(initials)
          .font(DimoFont.body(size * 0.38, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Theme.greenSoft)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
