import SwiftUI

struct SignInScreen: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var signingInWith: AuthProviderKind?
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 28) {
      Spacer()
      ZStack {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(Theme.green)
          .frame(width: 88, height: 88)
        Text("D")
          .font(DimoFont.display(44, weight: .bold))
          .foregroundStyle(Theme.onGreen)
      }
      VStack(spacing: 8) {
        Text("Welcome to Dimo")
          .font(DimoFont.display(28, weight: .bold))
          .foregroundStyle(Theme.ink)
        Text("Track spending with a calm, local-first ledger.")
          .font(DimoFont.body(15))
          .foregroundStyle(Theme.muted)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 36)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.danger)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }
      Spacer()
      VStack(spacing: 12) {
        // Apple first: Sign in with Apple must be shown no less prominently
        // than other providers.
        ProviderButton(
          title: "Sign in with Apple",
          busyTitle: "Signing in…",
          icon: .symbol("applelogo"),
          background: Theme.ink,
          foreground: Theme.canvas,
          isBusy: signingInWith == .apple,
          enabled: signingInWith == nil
        ) {
          Task { await signIn(with: .apple) }
        }
        ProviderButton(
          title: "Sign in with Google",
          busyTitle: "Signing in…",
          icon: .asset("GoogleG"),
          background: Theme.green,
          foreground: Theme.onGreen,
          isBusy: signingInWith == .google,
          enabled: signingInWith == nil
        ) {
          Task { await signIn(with: .google) }
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas.ignoresSafeArea())
  }

  private func signIn(with provider: AuthProviderKind) async {
    signingInWith = provider
    errorMessage = nil
    defer { signingInWith = nil }
    do {
      try await environment.session.signIn(with: provider)
    } catch AuthError.cancelled {
      // Dismissing the web sheet is not an error worth shouting about.
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// Provider mark shown ahead of the title. Asset marks render as templates so
/// they pick up the button's foreground colour.
private enum ProviderIcon {
  case symbol(String)
  case asset(String)
}

private struct ProviderButton: View {
  var title: String
  var busyTitle: String
  var icon: ProviderIcon?
  var background: Color
  var foreground: Color
  var isBusy: Bool
  var enabled: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if isBusy {
          ProgressView()
            .tint(foreground)
        } else {
          switch icon {
          case .symbol(let name):
            Image(systemName: name)
              .font(.system(size: 17, weight: .medium))
          case .asset(let name):
            Image(name)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
              .frame(width: 18, height: 18)
          case nil:
            EmptyView()
          }
        }
        Text(isBusy ? busyTitle : title)
          .font(DimoFont.body(16, weight: .semibold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background(background)
      .foregroundStyle(foreground)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .opacity(enabled || isBusy ? 1 : 0.55)
  }
}
