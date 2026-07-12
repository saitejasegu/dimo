import SwiftUI
import UIKit

struct FabButton: View {
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(Theme.onGreen)
        .frame(width: 58, height: 58)
        .background(Theme.green)
        .clipShape(Circle())
        .shadow(color: Theme.green.opacity(0.35), radius: 12, y: 6)
    }
    .buttonStyle(.plain)
  }
}

/// Rounded-square monogram avatar matching the web Avatar; shows the profile
/// photo when available and falls back to the initial.
struct AvatarView: View {
  var name: String
  var photoUrl: String?
  var size: CGFloat = 40
  var radius: CGFloat = 13
  var fontSize: CGFloat = 16

  var body: some View {
    ZStack {
      Theme.greenSoft
      initialView
      if let photoUrl, let url = URL(string: photoUrl) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          }
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }

  private var initialView: some View {
    Text(String(name.prefix(1)).uppercased())
      .font(DimoFont.display(fontSize, weight: .semibold))
      .foregroundStyle(Theme.green)
  }
}

/// Rounded-full bordered dropdown pill backed by a native menu, matching the web dropdowns.
struct PillDropdown<Option: Hashable>: View {
  var options: [Option]
  var selected: Option
  var label: (Option) -> String
  var onSelect: (Option) -> Void

  var body: some View {
    Menu {
      ForEach(options, id: \.self) { option in
        Button {
          onSelect(option)
        } label: {
          if option == selected {
            Label(label(option), systemImage: "checkmark")
          } else {
            Text(label(option))
          }
        }
      }
    } label: {
      HStack(spacing: 10) {
        Text(label(selected))
          .font(DimoFont.body(12, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Theme.muted)
      }
      .padding(.horizontal, 14)
      .frame(height: 36)
      .frame(minWidth: 112)
      .background(Theme.surface)
      .clipShape(Capsule())
      .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }
}

/// Full-width bordered payment dropdown matching the web PaymentMethodSelect ("Paid with").
struct PaymentMethodField: View {
  var methods: [PaymentMethodOption]
  var selectedId: String?
  var onSelect: (String?) -> Void
  var onManage: (() -> Void)?
  @State private var isOpen = false

  private var selected: PaymentMethodOption? {
    methods.first { $0.id == selectedId } ?? methods.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Paid with")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)

      Button {
        withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
      } label: {
        HStack(spacing: 12) {
          Text(selected?.label ?? "—")
            .font(DimoFont.body(15))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(isOpen ? Theme.green : Theme.line, lineWidth: 1)
        )
      }
      .buttonStyle(.plain)

      if isOpen {
        VStack(spacing: 6) {
          ForEach(methods) { method in
            let isSelected = method.id == selected?.id
            Button {
              onSelect(method.id)
              withAnimation(.easeOut(duration: 0.18)) { isOpen = false }
            } label: {
              HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(method.name)
                    .font(DimoFont.body(14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.greenDeep : Theme.ink)
                  Text([method.type.rawValue, method.detail]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(DimoFont.body(12))
                    .foregroundStyle(Theme.muted)
                }
                Spacer()
                if isSelected {
                  Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.green)
                }
              }
              .padding(.horizontal, 14)
              .frame(height: 58)
              .background(isSelected ? Theme.greenSoft : .clear)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
          }

          if let onManage {
            Divider().overlay(Theme.lineSoft)
            Button {
              isOpen = false
              onManage()
            } label: {
              Text("Manage payment methods…")
                .font(DimoFont.body(14, weight: .medium))
                .foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(8)
        .background(Theme.popup)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}

/// Small status pill matching the web Badge (Active / Paused, etc.).
struct StatusBadge: View {
  enum Tone { case green, muted }
  var label: String
  var tone: Tone = .muted

  var body: some View {
    Text(label)
      .font(DimoFont.body(11, weight: .medium))
      .foregroundStyle(tone == .green ? Theme.green : Theme.muted)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(tone == .green ? Theme.greenSoft : Theme.canvasDeep)
      .clipShape(Capsule())
  }
}

/// Full-width action button matching the web Button variants.
struct ActionButton: View {
  enum Variant { case accent, secondary, danger }
  var title: String
  var variant: Variant = .secondary
  var enabled: Bool = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(border, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }

  private var foreground: Color {
    guard enabled else { return Theme.muted }
    switch variant {
    case .accent: return Theme.onGreen
    case .secondary: return Theme.ink
    case .danger: return Theme.danger
    }
  }

  private var background: Color {
    guard enabled else { return Theme.canvasDeep }
    switch variant {
    case .accent: return Theme.green
    case .secondary: return Theme.canvas
    case .danger: return Theme.dangerSoft
    }
  }

  private var border: Color {
    guard enabled else { return Theme.line }
    switch variant {
    case .accent: return .clear
    case .secondary: return Theme.line
    case .danger: return Theme.dangerLine
    }
  }
}

struct Chip: View {
  var label: String
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(DimoFont.body(13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(selected ? Theme.ink : Theme.surface)
        .foregroundStyle(selected ? Theme.canvas : Theme.ink)
        .overlay(
          Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1)
        )
        .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

struct ToastView: View {
  var message: String

  var body: some View {
    Text(message)
      .font(DimoFont.body(14, weight: .medium))
      .foregroundStyle(Theme.canvas)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Theme.ink.opacity(0.92))
      .clipShape(Capsule())
      .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
  }
}

private struct ContentHeightSheetModifier: ViewModifier {
  @State private var contentHeight: CGFloat = 300

  func body(content: Content) -> some View {
    content
      // Ask the content for its intrinsic vertical size instead of accepting the
      // sheet's current detent as its proposed height.
      .fixedSize(horizontal: false, vertical: true)
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.size.height
      } action: { newHeight in
        guard newHeight > 0, abs(newHeight - contentHeight) > 0.5 else { return }
        contentHeight = newHeight
      }
      .background(BackgroundKeyboardDismissInstaller())
      .presentationDetents([.height(contentHeight)])
  }
}

/// Installs a non-blocking tap recognizer for the active sheet. Taps within a
/// text input retain focus; every other tap dismisses the keyboard while still
/// allowing the tapped control to perform its normal action.
private struct BackgroundKeyboardDismissInstaller: UIViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    installWhenAttached(view, coordinator: context.coordinator)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    installWhenAttached(uiView, coordinator: context.coordinator)
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.uninstall()
  }

  private func installWhenAttached(_ view: UIView, coordinator: Coordinator) {
    DispatchQueue.main.async { [weak view, weak coordinator] in
      guard let view, let coordinator, let window = view.window else { return }
      coordinator.install(on: window)
    }
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    private weak var hostView: UIView?
    private weak var recognizer: UITapGestureRecognizer?

    func install(on hostView: UIView) {
      guard self.hostView !== hostView else { return }
      uninstall()

      let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
      recognizer.cancelsTouchesInView = false
      recognizer.delegate = self
      hostView.addGestureRecognizer(recognizer)
      self.hostView = hostView
      self.recognizer = recognizer
    }

    func uninstall() {
      if let recognizer { hostView?.removeGestureRecognizer(recognizer) }
      recognizer = nil
      hostView = nil
    }

    @objc private func dismissKeyboard() {
      hostView?.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      var touchedView = touch.view
      while let view = touchedView {
        if view is UITextField || view is UITextView { return false }
        touchedView = view.superview
      }
      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }
}

extension View {
  /// Sizes a sheet to its laid-out content and updates the detent when that content changes.
  func contentHeightSheet() -> some View {
    modifier(ContentHeightSheetModifier())
  }
}

struct SheetContainer<Content: View>: View {
  var title: String
  var onClose: () -> Void
  var titleAlignment: Alignment = .center
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      Text(title)
        .font(DimoFont.display(18, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: titleAlignment)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .padding(.horizontal, 20)

      content()
    }
    .contentHeightSheet()
    .presentationDragIndicator(.visible)
  }
}

struct AmountKeypad: View {
  var onPress: (String) -> Void

  private let keys = [
    ["1", "2", "3"],
    ["4", "5", "6"],
    ["7", "8", "9"],
    [".", "0", "⌫"],
  ]

  var body: some View {
    VStack(spacing: 10) {
      ForEach(keys, id: \.self) { row in
        HStack(spacing: 10) {
          ForEach(row, id: \.self) { key in
            Button {
              onPress(key)
            } label: {
              Text(key)
                .font(DimoFont.display(22, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.canvasDeep)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
          }
        }
      }
    }
  }
}

struct ProgressBar: View {
  var progress: Double
  var over: Bool = false

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.bar)
        Capsule()
          .fill(over ? Theme.danger : Theme.green)
          .frame(width: max(4, geo.size.width * min(1, max(0, progress))))
      }
    }
    .frame(height: 8)
  }
}
