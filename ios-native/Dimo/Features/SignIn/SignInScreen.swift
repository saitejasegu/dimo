import SwiftUI

struct SignInScreen: View {
  @Environment(AppEnvironment.self) private var environment
  @State private var isSigningIn = false
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
      Button {
        Task { await signIn() }
      } label: {
        HStack(spacing: 10) {
          if isSigningIn {
            ProgressView()
              .tint(Theme.onGreen)
          }
          Text(isSigningIn ? "Signing in…" : "Continue with Google")
            .font(DimoFont.body(16, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.green)
        .foregroundStyle(Theme.onGreen)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .disabled(isSigningIn)
      .padding(.horizontal, 24)
      .padding(.bottom, 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas.ignoresSafeArea())
  }

  private func signIn() async {
    isSigningIn = true
    errorMessage = nil
    defer { isSigningIn = false }
    do {
      try await environment.session.signInWithGoogle()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
