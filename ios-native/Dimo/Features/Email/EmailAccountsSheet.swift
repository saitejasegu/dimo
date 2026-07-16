import SwiftUI

struct EmailAccountsSheet: View {
  @Bindable var store: EmailFeatureStore
  @Environment(\.dismiss) private var dismiss
  @State private var disconnectCandidate: EmailUIAccount?
  @State private var confirmDeleteModel = false
  @State private var confirmCellularDownload = false
  @State private var confirmReanalyseAll = false
  @State private var modelPickerPresented = false
  @State private var confirmSelectedModelNonZDR = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          accountsSection
          analyzerSection
          privacySection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("Email settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .font(DimoFont.body(15, weight: .semibold))
            .foregroundStyle(Theme.green)
        }
      }
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.canvas)
    .sheet(isPresented: $modelPickerPresented) {
      OpenRouterModelPicker(store: store)
    }
    .onAppear {
      if case .connected = store.openRouterConnectionState {
        store.refreshOpenRouterModels()
      }
    }
    .alert(
      "Disconnect \(disconnectCandidate?.emailAddress ?? "this account")?",
      isPresented: Binding(
        get: { disconnectCandidate != nil },
        set: { if !$0 { disconnectCandidate = nil } }
      )
    ) {
      Button("Disconnect Gmail", role: .destructive) {
        guard let account = disconnectCandidate else { return }
        store.disconnectAccount(account.id)
        disconnectCandidate = nil
      }
      Button("Cancel", role: .cancel) { disconnectCandidate = nil }
    } message: {
      Text("Dimo will delete this account's device-only Gmail credential and all local email suggestions. Existing Dimo transactions are unchanged. Reviewed suggestions remain in sync and return if you reconnect the same account.")
    }
    .alert(
      "Use cellular data?",
      isPresented: $confirmCellularDownload
    ) {
      Button("Download using cellular") {
        store.downloadModel(allowCellular: true)
      }
      Button("Wait for Wi-Fi", role: .cancel) {}
    } message: {
      Text("Gemma is \(store.modelDownloadSizeDescription). Carrier data charges may apply.")
    }
    .alert(
      "Delete downloaded Gemma model?",
      isPresented: $confirmDeleteModel
    ) {
      Button("Delete model", role: .destructive) { store.deleteModel() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("If Local Gemma is selected, email analysis will become unconfigured. Gmail accounts and reviewed suggestions are not removed.")
    }
    .alert(
      "Reanalyse all emails?",
      isPresented: $confirmReanalyseAll
    ) {
      Button("Reanalyse all emails") { store.reanalyzeAllEmails() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Dimo will rerun the selected analyzer for every unreviewed email whose content is still retained. Reviewed suggestions and existing Dimo transactions are unchanged.")
    }
    .alert(
      "Allow non-ZDR analysis?",
      isPresented: $confirmSelectedModelNonZDR
    ) {
      Button("Allow non-ZDR") {
        if let model = store.selectedOpenRouterModel {
          store.selectOpenRouterModel(model.id, allowNonZDR: true)
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("OpenRouter or the selected provider may retain email content under its own policy.")
    }
  }

  private var accountsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeading("Gmail accounts", detail: "Read-only · latest \(store.syncWindow.title)")

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Sync email from")
              .font(DimoFont.body(13, weight: .semibold))
              .foregroundStyle(Theme.ink)
            Text("Choose how far back Dimo reads and keeps Gmail messages on this iPhone.")
              .font(DimoFont.body(11))
              .foregroundStyle(Theme.muted)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 12)

          if store.isUpdatingSyncWindow {
            ProgressView()
              .controlSize(.small)
              .tint(Theme.green)
          } else {
            Picker(
              "Sync email from",
              selection: Binding(
                get: { store.syncWindow },
                set: { store.selectSyncWindow($0) }
              )
            ) {
              ForEach(EmailSyncWindow.allCases, id: \.self) { window in
                Text(window.title).tag(window)
              }
            }
            .pickerStyle(.menu)
            .tint(Theme.green)
          }
        }
      }
      .emailSettingsCard()

      if store.accounts.isEmpty {
        Text("No Gmail accounts connected.")
          .font(DimoFont.body(13))
          .foregroundStyle(Theme.muted)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 20)
          .emailSettingsCard()
      } else {
        ForEach(store.accounts) { account in
          accountRow(account)
        }
      }

      ActionButton(title: "Connect another Gmail account", variant: .secondary) {
        store.connectAccount()
      }
    }
  }

  private func accountRow(_ account: EmailUIAccount) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "envelope.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.green)
          .frame(width: 36, height: 36)
          .background(Theme.greenSoft)
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          Text(account.emailAddress)
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(accountStatus(account))
            .font(DimoFont.body(11))
            .foregroundStyle(account.syncState == .failed ? Theme.danger : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 6)

        if account.syncState == .syncing {
          ProgressView().controlSize(.small).tint(Theme.green)
        } else {
          Text(account.syncState.title)
            .font(DimoFont.body(10, weight: .medium))
            .foregroundStyle(account.syncState == .failed ? Theme.danger : Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(account.syncState == .failed ? Theme.dangerSoft : Theme.canvasDeep)
            .clipShape(Capsule())
        }
      }

      if let error = account.lastError, !error.isEmpty {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(DimoFont.body(11))
          .foregroundStyle(Theme.danger)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider().overlay(Theme.lineSoft)

      HStack(spacing: 12) {
        if account.syncState != .disconnected {
          Button {
            store.refreshAccount(account.id)
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
              .font(DimoFont.body(12, weight: .medium))
              .foregroundStyle(Theme.green)
          }
          .buttonStyle(.plain)
          .disabled(account.syncState == .syncing)

          Spacer()

          Button(role: .destructive) {
            disconnectCandidate = account
          } label: {
            Text("Disconnect")
              .font(DimoFont.body(12, weight: .medium))
              .foregroundStyle(Theme.danger)
          }
          .buttonStyle(.plain)
        } else {
          Text("Reconnect from Connect Gmail to resume sync.")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
      }
    }
    .emailSettingsCard()
  }

  private var analyzerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeading("Email analyzer", detail: store.selectedProvider == nil ? "Not configured" : store.activeAnalyzerTitle)

      if store.selectedProvider == nil {
        Label(
          "Email analysis is not configured. Choose Local Gemma or OpenRouter. Synced emails will wait safely on this iPhone.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.body)
        .emailSettingsCard()
      }

      gemmaCard
      openRouterCard

      VStack(alignment: .leading, spacing: 8) {
        Text("Reanalyse email suggestions")
          .font(DimoFont.body(13, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text("Resets every eligible unreviewed email, updates the UI, then starts the selected analyzer. Processing is limited to ten emails per minute.")
          .font(DimoFont.body(11))
          .foregroundStyle(Theme.muted)
          .fixedSize(horizontal: false, vertical: true)
        ActionButton(
          title: store.isReanalyzing ? "Reanalysing emails…" : "Reanalyse all emails",
          variant: .secondary,
          enabled: !store.isReanalyzing && !store.accounts.isEmpty && store.selectedProvider != nil
        ) {
          confirmReanalyseAll = true
        }
      }
      .emailSettingsCard()
    }
  }

  private var gemmaCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: store.selectedProvider == .gemma ? "checkmark.circle.fill" : "cpu")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(store.selectedProvider == .gemma ? Theme.green : Theme.muted)
          .frame(width: 40, height: 40)
          .background(store.selectedProvider == .gemma ? Theme.greenSoft : Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text("Local Gemma")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Text("Gemma 3 270M IT · 8-bit · Runs privately on this iPhone")
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
        }
        Spacer()
      }

      Text(modelTitle)
        .font(DimoFont.body(12, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text(modelDetail)
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)

      if let progress = store.modelState.progress {
        ProgressView(value: min(max(progress, 0), 1)).tint(Theme.green)
      }

      if store.selectedProvider != .gemma {
        ActionButton(title: "Use Local Gemma", variant: .secondary) {
          store.selectGemma()
        }
      }

      modelActions

      HStack(spacing: 16) {
        if let termsURL = store.modelTermsURL { Link("Gemma terms", destination: termsURL) }
        if let attributionURL = store.modelAttributionURL { Link("Attribution", destination: attributionURL) }
      }
      .font(DimoFont.body(11, weight: .medium))
      .foregroundStyle(Theme.green)
    }
    .emailSettingsCard()
  }

  private var openRouterCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: store.selectedProvider == .openRouter ? "checkmark.circle.fill" : "cloud")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(store.selectedProvider == .openRouter ? Theme.green : Theme.muted)
          .frame(width: 40, height: 40)
          .background(store.selectedProvider == .openRouter ? Theme.greenSoft : Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
          Text("OpenRouter")
            .font(DimoFont.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
          Text("Bring your own key · Cloud analysis")
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
        }
        Spacer()
        openRouterStatusBadge
      }

      switch store.openRouterConnectionState {
      case .disconnected, .failed:
        SecureField("sk-or-v1-…", text: $store.openRouterAPIKeyInput)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .font(DimoFont.body(12))
          .padding(12)
          .background(Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        Text("Use a dedicated, revocable OpenRouter key with a spending limit. It stays in this iPhone's device-only Keychain.")
          .font(DimoFont.body(10))
          .foregroundStyle(Theme.muted)
        ActionButton(title: "Validate and save key", variant: .accent, enabled: !store.openRouterAPIKeyInput.isEmpty) {
          store.saveOpenRouterKey()
        }
      case .validating:
        HStack { ProgressView().controlSize(.small); Text("Validating key and loading models…") }
          .font(DimoFont.body(11))
          .foregroundStyle(Theme.muted)
      case .connected:
        if store.selectedProvider == .openRouter,
           store.analysisStatusDetail.localizedCaseInsensitiveContains("unavailable") {
          Label(store.analysisStatusDetail, systemImage: "exclamationmark.triangle.fill")
            .font(DimoFont.body(10, weight: .medium))
            .foregroundStyle(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
        }

        Button {
          modelPickerPresented = true
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(store.selectedOpenRouterModel?.name ?? "Choose an OpenRouter model")
                .font(DimoFont.body(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
              Text(store.selectedOpenRouterModelID ?? OpenRouterClient.defaultModelID)
                .font(DimoFont.body(9))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
          }
          .padding(12)
          .background(Theme.canvasDeep)
          .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)

        if store.selectedProvider != .openRouter,
           let selectedModel = store.selectedOpenRouterModel {
          ActionButton(title: "Use OpenRouter", variant: .accent) {
            if selectedModel.hasZDREndpoint {
              store.selectOpenRouterModel(selectedModel.id, allowNonZDR: false)
            } else {
              confirmSelectedModelNonZDR = true
            }
          }
        }

        if store.openRouterPrivacyMode == .allowNonZDR {
          Label("Non-ZDR enabled for the selected model", systemImage: "exclamationmark.shield.fill")
            .font(DimoFont.body(10, weight: .medium))
            .foregroundStyle(Theme.danger)
        } else {
          Label("Zero-data-retention routes only", systemImage: "lock.shield.fill")
            .font(DimoFont.body(10, weight: .medium))
            .foregroundStyle(Theme.green)
        }

        if let selectedModel = store.selectedOpenRouterModel {
          Toggle(
            "Zero-data-retention routes only",
            isOn: Binding(
              get: { store.openRouterPrivacyMode == .zdrOnly },
              set: { enabled in
                if enabled {
                  store.selectOpenRouterModel(selectedModel.id, allowNonZDR: false)
                } else {
                  confirmSelectedModelNonZDR = true
                }
              }
            )
          )
          .font(DimoFont.body(11, weight: .medium))
          .tint(Theme.green)
          .disabled(!selectedModel.hasZDREndpoint)
          if !selectedModel.hasZDREndpoint {
            Text("Choose a model with a ZDR badge to enable this protection.")
              .font(DimoFont.body(9))
              .foregroundStyle(Theme.muted)
          }
        }

        HStack(spacing: 10) {
          compactAction("Refresh models", tint: Theme.green) { store.refreshOpenRouterModels() }
          compactAction("Remove key", tint: Theme.danger) { store.removeOpenRouterKey() }
        }
      }
    }
    .emailSettingsCard()
  }

  @ViewBuilder
  private var openRouterStatusBadge: some View {
    switch store.openRouterConnectionState {
    case .connected(let label, let limit, let remaining):
      VStack(alignment: .trailing, spacing: 2) {
        Text(label.isEmpty ? "Connected" : label)
        if let limit, let remaining {
          Text("$\(remaining.formatted(.number.precision(.fractionLength(0...2)))) left · $\(limit.formatted(.number.precision(.fractionLength(0...2)))) limit")
            .font(DimoFont.body(8))
            .foregroundStyle(Theme.muted)
        } else if let remaining {
          Text("$\(remaining.formatted(.number.precision(.fractionLength(0...2)))) credit left")
            .font(DimoFont.body(8))
            .foregroundStyle(Theme.muted)
        }
      }
      .font(DimoFont.body(9, weight: .semibold))
      .foregroundStyle(Theme.green)
    case .validating:
      ProgressView().controlSize(.mini)
    case .failed:
      Text("Needs attention").font(DimoFont.body(9)).foregroundStyle(Theme.danger)
    case .disconnected:
      Text("Not connected").font(DimoFont.body(9)).foregroundStyle(Theme.muted)
    }
  }

  @ViewBuilder
  private var modelActions: some View {
    switch store.modelState {
    case .notInstalled:
      ActionButton(title: "Download Gemma", variant: .accent) {
        if store.requiresCellularDownloadConfirmation {
          confirmCellularDownload = true
        } else {
          store.downloadModel(allowCellular: false)
        }
      }

    case .checkingStorage, .verifying:
      HStack(spacing: 10) {
        ProgressView().controlSize(.small).tint(Theme.green)
        Text(store.modelState == .checkingStorage ? "Checking storage…" : "Verifying download…")
          .font(DimoFont.body(12, weight: .medium))
          .foregroundStyle(Theme.muted)
      }

    case .downloading:
      ActionButton(title: "Pause download", variant: .secondary) {
        store.pauseModelDownload()
      }

    case .paused:
      HStack(spacing: 10) {
        compactAction("Resume", tint: Theme.green) { requestModelRetry() }
        compactAction("Cancel", tint: Theme.danger) { store.cancelModelDownload() }
      }

    case .installed:
      VStack(spacing: 10) {
        ActionButton(title: "Retry Gemma analysis", variant: .accent) {
          store.retryGemmaAnalysis()
        }
        ActionButton(title: "Delete downloaded model", variant: .danger) {
          confirmDeleteModel = true
        }
      }

    case .failed:
      HStack(spacing: 10) {
        compactAction("Retry", tint: Theme.green) { requestModelRetry() }
        compactAction("Delete", tint: Theme.danger) { confirmDeleteModel = true }
      }

    case .unavailable:
      Text("Email analysis is unavailable on this device.")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
    }
  }

  private var privacySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeading("Privacy", detail: nil)
      Label(
        privacyDescription,
        systemImage: "lock.shield.fill"
      )
      .font(DimoFont.body(12))
      .foregroundStyle(Theme.body)
      .fixedSize(horizontal: false, vertical: true)
      .emailSettingsCard()
    }
  }

  private var privacyDescription: String {
    switch store.selectedProvider {
    case .gemma:
      return "Email analysis runs locally on this iPhone. Email content is not sent to an AI provider or Dimo sync."
    case .openRouter:
      return "Selected email content is sent directly from this iPhone to OpenRouter and the chosen model provider. It is never sent through Dimo's Convex backend."
    case nil:
      return "Gmail is contacted directly from this iPhone. Email content stays pending locally until you choose an analyzer."
    }
  }

  private func sectionHeading(_ title: String, detail: String?) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title.uppercased())
        .font(DimoFont.body(12, weight: .medium))
        .kerning(0.8)
        .foregroundStyle(Theme.muted)
      Spacer()
      if let detail {
        Text(detail)
          .font(DimoFont.body(10))
          .foregroundStyle(Theme.faint)
      }
    }
  }

  private func accountStatus(_ account: EmailUIAccount) -> String {
    if let detail = account.statusDetail, !detail.isEmpty { return detail }
    if let lastSync = account.lastSuccessfulSyncAt {
      return "Last refreshed \(lastSync.formatted(.relative(presentation: .named)))"
    }
    return account.initialScanComplete ? "Ready to refresh" : "Seven-day scan not complete"
  }

  private var modelTitle: String {
    switch store.modelState {
    case .notInstalled: return "Gemma is not downloaded"
    case .checkingStorage: return "Preparing download"
    case .downloading: return "Downloading Gemma"
    case .paused: return "Download paused"
    case .verifying: return "Verifying Gemma"
    case .installed(let version): return "Gemma \(version) installed"
    case .failed: return "Gemma download failed"
    case .unavailable: return "Gemma unavailable"
    }
  }

  private var modelDetail: String {
    switch store.modelState {
    case .notInstalled:
      return "Download Gemma to analyze email suggestions. \(store.modelDownloadSizeDescription) download; \(store.modelStorageRequirementDescription). Wi-Fi is preferred."
    case .checkingStorage:
      return store.modelStorageRequirementDescription
    case .downloading:
      return "You can pause and resume. New emails wait for Gemma before analysis."
    case .paused:
      return "The partial download remains staged on this iPhone."
    case .verifying:
      return "Checking the exact file size and SHA-256 digest before installation."
    case .installed:
      if let detail = store.gemmaStatusDetail {
        return detail
      }
      return store.isGemmaAnalyzerAvailable
        ? "Gemma is ready and analyzes one message at a time on this iPhone."
        : "The model file is installed. Tap Retry Gemma analysis to initialize it and retry failed emails."
    case .failed(let message), .unavailable(let message):
      return message
    }
  }

  private func compactAction(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(DimoFont.body(13, weight: .semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.line))
    }
    .buttonStyle(.plain)
  }

  private func requestModelRetry() {
    if store.requiresCellularDownloadConfirmation {
      // Starting again is intentional here: resume data retains the original
      // Wi-Fi-only request policy and cannot safely be mutated to allow cellular.
      confirmCellularDownload = true
    } else {
      store.retryModelDownload()
    }
  }
}

private extension View {
  func emailSettingsCard() -> some View {
    padding(15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
  }
}
