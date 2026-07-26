import SwiftUI

struct SourceEmailsSheet: View {
  var emails: [EmailUIEmailDetail]
  var navigationTitle: String?
  var onClose: () -> Void
  var onShowSeparately: (() -> Void)?

  @State private var expandedIDs: Set<String>

  init(
    emails: [EmailUIEmailDetail],
    navigationTitle: String? = nil,
    onClose: @escaping () -> Void,
    onShowSeparately: (() -> Void)? = nil
  ) {
    self.emails = emails
    self.navigationTitle = navigationTitle
    self.onClose = onClose
    self.onShowSeparately = onShowSeparately
    _expandedIDs = State(
      initialValue: emails.count == 1 ? Set(emails.map(\.id)) : []
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 10) {
          ForEach(emails) { detail in
            SourceEmailAccordion(
              detail: detail,
              isExpanded: binding(for: detail.id)
            )
          }

          if let onShowSeparately {
            Button(action: onShowSeparately) {
              Text("Show separately")
                .font(DimoFont.body(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.line)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .accessibilityHint("Ungroups these emails into separate suggestions")
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle(
        navigationTitle
          ?? (emails.count == 1 ? "Linked email" : "Linked emails")
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done", action: onClose)
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.green)
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
  }

  private func binding(for id: String) -> Binding<Bool> {
    Binding(
      get: { expandedIDs.contains(id) },
      set: { expanded in
        if expanded {
          expandedIDs.insert(id)
        } else {
          expandedIDs.remove(id)
        }
      }
    )
  }
}

private struct SourceEmailAccordion: View {
  var detail: EmailUIEmailDetail
  @Binding var isExpanded: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        isExpanded.toggle()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "envelope.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.green)
            .frame(width: 34, height: 34)
            .background(Theme.greenSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

          VStack(alignment: .leading, spacing: 2) {
            Text(detail.subject.isEmpty ? "No subject" : detail.subject)
              .font(DimoFont.body(14, weight: .semibold))
              .foregroundStyle(Theme.ink)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
            Text(detail.sender.isEmpty ? detail.senderAddress : detail.sender)
              .font(DimoFont.body(12))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Image(systemName: "chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.faint)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(detail.subject.isEmpty ? "Email" : detail.subject)
      .accessibilityHint(isExpanded ? "Collapse email details" : "Expand email details")
      .accessibilityAddTraits(.isButton)

      if isExpanded {
        VStack(alignment: .leading, spacing: 0) {
          Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.horizontal, 14)

          EmailDetailContent(detail: detail, usesCardChrome: false, showsSubject: false)
            .padding(14)
        }
      }
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
    .animation(.snappy(duration: 0.22), value: isExpanded)
  }
}
