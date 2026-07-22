import SwiftUI

struct EmailScreen: View {
  @Bindable var store: EmailFeatureStore
  var onOpenSettings: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          if store.accounts.isEmpty {
            connectAccountCard
          } else {
            accountAndAnalyzerStrip
            filters

            if store.selectedFilter.displaysMessages {
              if store.filteredEmails.isEmpty {
                emptyState
              } else {
                ForEach(store.filteredEmails) { email in
                  EmailMessageStatusCard(
                    email: email,
                    onOpen: { store.presentEmail(id: email.id) },
                    onRestore: email.analysisState == .dismissed
                      ? { store.restoreSuggestion(email.id) }
                      : nil,
                    onRetry: email.analysisState == .failed
                      ? { store.retryAnalysis(messageID: email.id) }
                      : nil,
                    onRetryWithAlternate: email.analysisState == .failed
                      ? { store.retryWithAlternateProvider(messageID: email.id) }
                      : nil
                  )
                }
              }
            } else if store.filteredSuggestions.isEmpty {
              emptyState
            } else {
              ForEach(store.filteredSuggestions) { suggestion in
                EmailSuggestionCard(
                  suggestion: suggestion,
                  onOpen: { store.presentEmail(id: suggestion.id) },
                  onReview: { store.review(suggestion) },
                  onDismiss: { store.dismissSuggestion(suggestion.id) },
                  onRestore: suggestion.status == .dismissed
                    ? { store.restoreSuggestion(suggestion.id) }
                    : nil
                )
              }
            }

            privacyNote
          }
        }
        // Message and suggestion rows share the same underlying email key as
        // their ForEach identity. Re-key the lazy container per filter so it
        // never reuses cached cells of the other card type across tab switches.
        .id(store.selectedFilter)
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 34)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .sheet(item: $store.emailDetail) { detail in
      EmailDetailSheet(detail: detail, onClose: store.dismissEmailDetail)
    }
    .sheet(item: $store.refundReview) { initialReview in
      RefundReviewSheet(
        review: Binding(
          get: { store.refundReview ?? initialReview },
          set: { store.refundReview = $0 }
        ),
        activeCurrency: store.activeCurrency,
        onCancel: { store.refundReview = nil },
        onMarkReviewed: {
          store.dismissSuggestion($0.suggestionID)
          store.refundReview = nil
        },
        onConfirm: { store.applyFullRefund($0) }
      )
    }
    .alert(
      "Email action failed",
      isPresented: Binding(
        get: { store.lastActionError != nil },
        set: { if !$0 { store.clearError() } }
      )
    ) {
      Button("OK") { store.clearError() }
    } message: {
      Text(store.lastActionError ?? "Please try again.")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Email")
          .font(DimoFont.display(24, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text("Purchase and refund suggestions")
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.muted)
      }

      Spacer()

      if store.hasFailedAnalyses {
        Button(action: store.reanalyzeAllEmails) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 42, height: 42)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.line))
        }
        .buttonStyle(.plain)
        .disabled(store.isReanalyzing)
        .accessibilityLabel(
          store.isReanalyzing ? "Reanalysing failed emails" : "Reanalyse failed emails"
        )
      }

      Button(action: onOpenSettings) {
        Image(systemName: "gearshape")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .frame(width: 42, height: 42)
          .background(Theme.surface)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.line))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Email accounts and analyzer settings")
    }
    .frame(minHeight: 64)
    .padding(.horizontal, 22)
    .padding(.top, 8)
  }

  private var connectAccountCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Image(systemName: "envelope.badge")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(Theme.green)
        .frame(width: 48, height: 48)
        .background(Theme.greenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

      Text("Find expenses in Gmail")
        .font(DimoFont.display(20, weight: .semibold))
        .foregroundStyle(Theme.ink)

      Text("Connect one or more Gmail accounts. Dimo reads the latest \(store.syncWindow.title) directly on this iPhone. You choose Local Gemma or OpenRouter for analysis; analyzed suggestions sync through Dimo for restore.")
        .font(DimoFont.body(14))
        .foregroundStyle(Theme.body)
        .fixedSize(horizontal: false, vertical: true)

      ActionButton(title: "Connect Gmail", variant: .accent) {
        store.connectAccount()
      }

      Text("Read-only Gmail access. Gmail credentials stay on this iPhone. You approve every transaction change.")
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding(20)
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line))
  }

  private var accountAndAnalyzerStrip: some View {
    HStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(store.accounts) { account in
            Button {
              store.refreshAccount(account.id)
            } label: {
              HStack(spacing: 8) {
                accountRefreshIcon(account.syncState)
                VStack(alignment: .leading, spacing: 1) {
                  Text(account.emailAddress)
                    .font(DimoFont.body(11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                  Text(account.statusDetail ?? account.syncState.title)
                    .font(DimoFont.body(10))
                    .foregroundStyle(account.syncState == .failed ? Theme.danger : Theme.muted)
                    .lineLimit(1)
                }
              }
              .padding(.horizontal, 10)
              .frame(height: 52)
              .background(Theme.surface)
              .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.line))
            }
            .buttonStyle(.plain)
            .disabled(account.syncState == .syncing)
            .accessibilityHint("Refresh this Gmail account")
          }
        }
      }
      .frame(maxWidth: .infinity)

      Button(action: onOpenSettings) {
        HStack(spacing: 8) {
          Image(systemName: analyzerIcon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(store.selectedProvider != nil ? Theme.green : Theme.muted)
            .frame(width: 28, height: 28)
            .background(store.selectedProvider != nil ? Theme.greenSoft : Theme.canvasDeep)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

          VStack(alignment: .leading, spacing: 1) {
            Text(store.activeAnalyzerTitle)
              .font(DimoFont.body(11, weight: .semibold))
              .foregroundStyle(Theme.ink)
              .lineLimit(1)
            Text(compactAnalyzerDetail)
              .font(DimoFont.body(10))
              .foregroundStyle(Theme.muted)
              .lineLimit(1)
          }

          if let progress = store.modelState.progress {
            Text(progress.formatted(.percent.precision(.fractionLength(0))))
              .font(DimoFont.body(10, weight: .semibold))
              .foregroundStyle(Theme.green)
          }

          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.line))
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .accessibilityHint("Choose and configure the email analyzer")
    }
  }

  private func accountRefreshIcon(_ state: EmailUIAccountSyncState) -> some View {
    Group {
      if state == .syncing {
        ProgressView().controlSize(.mini).tint(Theme.green)
      } else {
        Image(systemName: state == .failed ? "exclamationmark.arrow.circlepath" : "arrow.clockwise")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(state == .failed ? Theme.danger : Theme.green)
      }
    }
    .frame(width: 28, height: 28)
    .background(state == .failed ? Theme.danger.opacity(0.12) : Theme.greenSoft)
    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    .accessibilityHidden(true)
  }

  private var compactAnalyzerDetail: String {
    if store.selectedProvider != .gemma {
      return store.analysisStatusDetail
    }
    switch store.modelState {
    case .notInstalled:
      return "Tap to download"
    case .checkingStorage:
      return "Checking storage…"
    case .downloading:
      return "Downloading…"
    case .paused:
      return "Download paused"
    case .verifying:
      return "Verifying…"
    case .installed(let version):
      if let detail = store.gemmaStatusDetail {
        return detail
      }
      return store.isGemmaAnalyzerAvailable ? "v\(version)" : "Analysis unavailable"
    case .failed(let message), .unavailable(let message):
      return message
    }
  }

  private var analyzerIcon: String {
    switch store.selectedProvider {
    case .gemma: return "cpu"
    case .openRouter: return "cloud"
    case nil: return "text.magnifyingglass"
    }
  }

  private var filters: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(EmailSuggestionFilter.allCases) { filter in
          Button {
            withAnimation(.easeOut(duration: 0.18)) {
              store.selectedFilter = filter
            }
          } label: {
            HStack(spacing: 6) {
              Text(filter.title)
              let count = suggestionCount(for: filter)
              if count > 0 {
                Text("\(count)")
                  .font(.system(size: 10, weight: .bold))
                  .padding(.horizontal, 5)
                  .padding(.vertical, 2)
                  .background(store.selectedFilter == filter ? Theme.canvas.opacity(0.2) : Theme.canvasDeep)
                  .clipShape(Capsule())
              }
            }
            .font(DimoFont.body(12, weight: .medium))
            .foregroundStyle(store.selectedFilter == filter ? Theme.canvas : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(store.selectedFilter == filter ? Theme.ink : Theme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: store.selectedFilter == filter ? 0 : 1))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: emptyStateIcon)
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(Theme.faint)
      Text(emptyStateTitle)
        .font(DimoFont.body(15, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text(emptyStateDetail)
        .font(DimoFont.body(13))
        .foregroundStyle(Theme.muted)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.vertical, 44)
  }

  private var emptyStateIcon: String {
    switch store.selectedFilter {
    case .all: return "tray.full"
    case .purchases: return "cart"
    case .refunds: return "arrow.uturn.backward.circle"
    case .awaitingAnalysis: return "hourglass"
    case .reviewed: return "checkmark.circle"
    }
  }

  private var emptyStateTitle: String {
    switch store.selectedFilter {
    case .all: return "No scanned emails yet"
    case .purchases: return "No purchase suggestions"
    case .refunds: return "No refund suggestions"
    case .awaitingAnalysis: return "No emails awaiting analysis"
    case .reviewed: return "Nothing reviewed yet"
    }
  }

  private var emptyStateDetail: String {
    switch store.selectedFilter {
    case .all:
      return "Scanned messages and their local analysis status will appear here."
    case .purchases, .refunds:
      return "Email scanning is best effort and is not real time. Tap an account above to refresh."
    case .awaitingAnalysis:
      return "Fetched emails waiting for analysis will appear here."
    case .reviewed:
      return "Suggestions you add, dismiss, or apply will appear here."
    }
  }

  private var privacyNote: some View {
    Label(privacyNoteText, systemImage: "lock.shield.fill")
    .font(DimoFont.body(11))
    .foregroundStyle(Theme.muted)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 4)
  }

  private var privacyNoteText: String {
    switch store.selectedProvider {
    case .gemma:
      return "Local Gemma analyzes email on this iPhone. Gmail credentials stay on-device. Analyzed suggestions and their email text sync through Dimo so they restore across your devices. You still approve every transaction change."
    case .openRouter:
      return "Analysis goes from this iPhone to OpenRouter and the selected provider. Analyzed suggestions and their email text then sync through Dimo so they restore across your devices. You still approve every transaction change."
    case nil:
      return "Gmail credentials and pending email content stay on this iPhone until you configure an analyzer. Analyzed suggestions later sync through Dimo for restore."
    }
  }

  private func suggestionCount(for filter: EmailSuggestionFilter) -> Int {
    switch filter {
    case .all:
      return store.allEmails.count
    case .purchases:
      return store.suggestions.count { suggestion in
        if suggestion.status == .pendingPurchase,
           suggestion.kind == .purchase || suggestion.kind == .debit {
          return true
        }
        return false
      }
    case .refunds:
      return store.suggestions.count {
        $0.status == .pendingRefund && $0.kind == .refund
      }
    case .awaitingAnalysis:
      return store.allEmails.count { $0.analysisState == .pending }
    case .reviewed:
      return store.suggestions.count { $0.status.isReviewed }
    }
  }
}
