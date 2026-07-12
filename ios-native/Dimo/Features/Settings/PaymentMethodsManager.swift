import SwiftUI

struct PaymentMethodsManager: View {
  @Bindable var store: AppStore
  @State private var editingId: String?
  @State private var isNew = false
  @State private var draftName = ""
  @State private var draftType: PaymentMethodType = .UPI
  @State private var draftDetail = ""
  @State private var error = ""

  private var active: [PaymentMethodOption] {
    store.paymentMethods.filter { !$0.archived }
  }

  private var archived: [PaymentMethodOption] {
    store.paymentMethods.filter(\.archived)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Payment methods")
            .font(DimoFont.display(17, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Text("Choose how new expenses are paid.")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
        Spacer()
        if editingId == nil && !isNew {
          Button { startAdd() } label: {
            Text("Add")
              .font(DimoFont.body(14, weight: .semibold))
              .foregroundStyle(Theme.onGreen)
              .padding(.horizontal, 18)
              .padding(.vertical, 11)
              .background(Theme.green)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }

      if isNew || editingId != nil {
        editor
      }

      VStack(spacing: 0) {
        ForEach(active) { method in
          methodRow(method)
          if method.id != active.last?.id {
            Divider().overlay(Theme.lineSoft)
          }
        }
      }

      if !archived.isEmpty {
        Text("Archived")
          .font(DimoFont.body(11, weight: .medium))
          .foregroundStyle(Theme.muted)
          .padding(.top, 8)
        VStack(spacing: 0) {
          ForEach(archived) { method in
            methodRow(method)
            if method.id != archived.last?.id {
              Divider().overlay(Theme.lineSoft)
            }
          }
        }
      }

      Text("Archived methods stay attached to past transactions.")
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
    }
    .settingsCard()
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isNew ? "New payment method" : "Edit payment method")
        .font(DimoFont.display(16, weight: .semibold))
        .foregroundStyle(Theme.ink)

      VStack(alignment: .leading, spacing: 8) {
        Text("Display name")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
        editorField(placeholder: "e.g. HDFC Debit", text: $draftName)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Type")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
        FlowChips(
          items: PaymentMethodType.allCases.map(\.rawValue),
          selected: draftType.rawValue
        ) { label in
          draftType = PaymentMethodType(rawValue: label) ?? .UPI
          if draftType == .Cash { draftDetail = "" }
        }
      }

      if draftType != .Cash {
        VStack(alignment: .leading, spacing: 8) {
          Text("Identifier")
            .font(DimoFont.body(13))
            .foregroundStyle(Theme.muted)
          editorField(
            placeholder: draftType == .UPI ? "e.g. aarav@upi or ••42" : "e.g. ••42",
            text: $draftDetail
          )
        }
      }
      if !error.isEmpty {
        Text(error).font(DimoFont.body(12)).foregroundStyle(Theme.danger)
      }
      HStack(spacing: 10) {
        Button("Cancel") {
          isNew = false
          editingId = nil
          error = ""
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .foregroundStyle(Theme.ink)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        )
        Button("Save method") { save() }
          .frame(maxWidth: .infinity)
          .frame(height: 48)
          .background(Theme.green)
          .foregroundStyle(Theme.onGreen)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .font(DimoFont.body(14, weight: .semibold))
    }
    .padding(18)
    .background(Theme.canvas)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    )
  }

  private func editorField(placeholder: String, text: Binding<String>) -> some View {
    TextField(placeholder, text: text)
      .font(DimoFont.body(16))
      .foregroundStyle(Theme.ink)
      .textFieldStyle(.plain)
      .padding(.horizontal, 16)
      .frame(height: 52)
      .background(Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
  }

  private func methodRow(_ method: PaymentMethodOption) -> some View {
    HStack(spacing: 12) {
      Text(method.type == .Cash ? Formatting.currencySymbol(store.currency) : String(method.name.prefix(1)).uppercased())
        .font(DimoFont.display(14, weight: .semibold))
        .frame(width: 40, height: 40)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(method.name)
            .font(DimoFont.body(14, weight: .medium))
          if method.isDefault && !method.archived {
            Text("Default")
              .font(DimoFont.body(10, weight: .semibold))
              .foregroundStyle(Theme.greenDeep)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Theme.greenSoft)
              .clipShape(Capsule())
          }
          if method.archived {
            Text("Archived")
              .font(DimoFont.body(10, weight: .medium))
              .foregroundStyle(Theme.muted)
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(Theme.canvasDeep)
              .clipShape(Capsule())
          }
        }
        Text([method.type.rawValue, method.detail].filter { !$0.isEmpty }.joined(separator: " · "))
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        if method.archived {
          Button("Restore") { store.setPaymentMethodArchived(method.id, archived: false) }
            .foregroundStyle(Theme.green)
        } else {
          if !method.isDefault {
            Button("Set default") { store.setDefaultPaymentMethod(method.id) }
              .foregroundStyle(Theme.green)
          }
          Button("Edit") { startEdit(method) }
            .foregroundStyle(Theme.body)
          Button("Archive") { store.setPaymentMethodArchived(method.id, archived: true) }
            .foregroundStyle(Theme.danger)
        }
      }
      .font(DimoFont.body(12, weight: .medium))
    }
    .padding(.vertical, 12)
  }

  private func startAdd() {
    isNew = true
    editingId = nil
    draftName = ""
    draftType = .UPI
    draftDetail = ""
    error = ""
  }

  private func startEdit(_ method: PaymentMethodOption) {
    isNew = false
    editingId = method.id
    draftName = method.name
    draftType = method.type
    draftDetail = method.detail
    error = ""
  }

  private func save() {
    let message = store.savePaymentMethod(
      id: isNew ? nil : editingId,
      name: draftName,
      type: draftType,
      detail: draftDetail
    )
    if let message {
      error = message
      return
    }
    isNew = false
    editingId = nil
    error = ""
  }
}

struct FlowChips: View {
  var items: [String]
  var selected: String
  var onSelect: (String) -> Void

  var body: some View {
    FlexibleChipWrap(items: items, selected: selected, onSelect: onSelect)
  }
}

/// Simple wrapping chip row without a full layout engine.
private struct FlexibleChipWrap: View {
  var items: [String]
  var selected: String
  var onSelect: (String) -> Void

  var body: some View {
    ChipWrapLayout(spacing: 8) {
      ForEach(items, id: \.self) { item in
        Chip(label: item, selected: item == selected) {
          onSelect(item)
        }
      }
    }
  }
}

/// Packs as many chips as fit on each line so the layout tracks the available width.
private struct ChipWrapLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let width = proposal.width ?? .infinity
    var rowWidth: CGFloat = 0
    var totalHeight: CGFloat = 0
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if rowWidth > 0, rowWidth + spacing + size.width > width {
        totalHeight += rowHeight + spacing
        rowWidth = 0
        rowHeight = 0
      }
      rowWidth += (rowWidth == 0 ? 0 : spacing) + size.width
      rowHeight = max(rowHeight, size.height)
    }

    return CGSize(width: proposal.width ?? rowWidth, height: totalHeight + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
