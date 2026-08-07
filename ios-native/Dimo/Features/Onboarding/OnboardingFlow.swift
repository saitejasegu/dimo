import SwiftUI

/// First-run walkthrough shown ahead of `SignInScreen`. Every exit path —
/// Skip, "Not now", and "Turn on reminders" — funnels through `onFinish`.
struct OnboardingFlow: View {
  var onFinish: () -> Void

  @State private var pageIndex: Int? = 0
  @State private var isRequestingNotifications = false

  private let pages: [OnboardingPage] = OnboardingCopy.pages + [OnboardingCopy.remindersPage]

  private var currentIndex: Int { pageIndex ?? 0 }
  private var isLastPage: Bool { currentIndex >= pages.count - 1 }

  var body: some View {
    VStack(spacing: 0) {
      skipBar
      carousel
      dots
        .padding(.top, 8)
      actions
        .padding(.top, 28)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.canvas.ignoresSafeArea())
  }

  private var skipBar: some View {
    HStack {
      Spacer()
      Button {
        onFinish()
      } label: {
        Text("Skip")
          .font(DimoFont.body(15, weight: .semibold))
          .foregroundStyle(Theme.muted)
      }
      .buttonStyle(.plain)
      .opacity(isLastPage ? 0 : 1)
      .disabled(isLastPage)
    }
    .padding(.horizontal, 22)
    .frame(minHeight: 44)
    .animation(.snappy(duration: 0.2), value: isLastPage)
  }

  private var carousel: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 0) {
        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
          pageView(page)
            .containerRelativeFrame(.horizontal)
            .id(index)
        }
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.paging)
    .scrollIndicators(.hidden)
    .scrollPosition(id: $pageIndex)
  }

  private func pageView(_ page: OnboardingPage) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Theme.greenSoft)
          .frame(width: 64, height: 64)
        Image(systemName: page.icon)
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(Theme.green)
      }
      Text(page.title)
        .font(DimoFont.display(26, weight: .bold))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
        .padding(.top, 24)
      Text(page.body)
        .font(DimoFont.body(15))
        .foregroundStyle(Theme.body)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .padding(.top, 10)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 32)
    .frame(maxWidth: .infinity)
  }

  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(pages.indices, id: \.self) { index in
        Capsule()
          .fill(index == currentIndex ? Theme.green : Theme.lineSoft)
          .frame(width: index == currentIndex ? 22 : 7, height: 7)
      }
    }
    .animation(.snappy(duration: 0.25), value: currentIndex)
    .accessibilityHidden(true)
  }

  private var actions: some View {
    VStack(spacing: 6) {
      ActionButton(
        title: primaryTitle,
        variant: .accent,
        enabled: !isRequestingNotifications
      ) {
        if isLastPage {
          Task { await enableReminders() }
        } else {
          advance()
        }
      }

      // Always rendered so the button stack does not resize on the last swipe.
      Button {
        onFinish()
      } label: {
        Text("Not now")
          .font(DimoFont.body(15, weight: .semibold))
          .foregroundStyle(Theme.muted)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .opacity(isLastPage ? 1 : 0)
      .disabled(!isLastPage || isRequestingNotifications)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .animation(.snappy(duration: 0.2), value: isLastPage)
  }

  private var primaryTitle: String {
    guard isLastPage else { return "Continue" }
    return isRequestingNotifications ? "Turning on…" : "Turn on reminders"
  }

  private func advance() {
    let next = currentIndex + 1
    guard next < pages.count else { return }
    withAnimation(.snappy(duration: 0.3)) { pageIndex = next }
  }

  private func enableReminders() async {
    isRequestingNotifications = true
    let granted = await ExpenseReminderScheduler.requestAuthorizationIfNeeded()
    // The reminder setting is userId-scoped, so it cannot be written yet.
    // AppStore.start() redeems this on the first sign-in.
    if granted { OnboardingStore.setPendingReminderOptIn() }
    isRequestingNotifications = false
    onFinish()
  }
}
