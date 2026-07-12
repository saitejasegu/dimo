import ContactsUI
import SwiftUI

struct AddLendSheet: View {
  @Bindable var store: AppStore
  @State private var contactPickerOpen = false
  @State private var confirmDelete = false

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
            HStack(spacing: 8) {
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
            Button {
              contactPickerOpen = true
            } label: {
              HStack(spacing: 8) {
                Text(store.lendDraft.contactName.isEmpty ? "Choose contact" : store.lendDraft.contactName)
                  .font(DimoFont.body(15))
                  .foregroundStyle(store.lendDraft.contactName.isEmpty ? Theme.muted : Theme.ink)
                  .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "person.crop.circle.badge.plus")
                  .font(.system(size: 20, weight: .medium))
                  .foregroundStyle(Theme.green)
              }
              .padding(.horizontal, 14)
              .frame(height: 50)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Theme.canvas)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose from contacts")
          }
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
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .presentationBackground(Theme.surface)
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
    .sheet(isPresented: $contactPickerOpen) {
      ContactPicker { name in
        store.lendDraft.contactName = name
      }
      .ignoresSafeArea()
    }
  }

  private var canSave: Bool {
    !store.lendDraft.contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (Double(store.lendDraft.amount) ?? 0) > 0
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

/// System contact picker; runs out of process, so it needs no Contacts permission
/// or usage-description key.
private struct ContactPicker: UIViewControllerRepresentable {
  var onSelect: (String) -> Void

  func makeUIViewController(context: Context) -> CNContactPickerViewController {
    let picker = CNContactPickerViewController()
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(onSelect: onSelect)
  }

  final class Coordinator: NSObject, CNContactPickerDelegate {
    let onSelect: (String) -> Void

    init(onSelect: @escaping (String) -> Void) {
      self.onSelect = onSelect
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
      let name = CNContactFormatter.string(from: contact, style: .fullName)
        ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
      if !name.isEmpty {
        onSelect(name)
      }
    }
  }
}
