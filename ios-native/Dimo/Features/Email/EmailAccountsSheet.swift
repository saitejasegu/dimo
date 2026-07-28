import SwiftUI

struct EmailSettingsSection: View {
  @Bindable var store: EmailFeatureStore
  @State private var disconnectCandidate: EmailUIAccount?
  @State private var confirmReanalyseAll = false
  @State private var modelPickerPresented = false
  @State private var confirmSelectedModelNonZDR = false

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      accountsSection
      analyzerSection
      privacySection
    }
    .sheet(isPresented: $modelPickerPresented) {
      OpenRouterModelPicker(store: store)
    }
    .onAppear {
      if case .connected = store.openRouterConnectionState, store.openRouterModels.isEmpty {
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
      Text("Dimo will delete this account's device-only Gmail credential and all local email suggestions. Existing Dimo transactions are unchanged. Prefer Reconnect Gmail when access expires so pending local suggestions stay on this iPhone. Reviewed suggestions remain in sync and return if you reconnect the same account.")
    }
    .alert(
      "Reanalyse all emails?",
      isPresented: $confirmReanalyseAll
    ) {
      Button("Reanalyse all emails") { store.reanalyzeAllEmails() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Dimo will rerun OpenRouter for every unreviewed email whose content is still retained. Reviewed suggestions and existing Dimo transactions are unchanged.")
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
      Text("OpenRouter or the selected provider may retain email content under its own policy. Analyzed suggestions, including email text, still sync through Dimo for restore.")
    }
    .alert(
      "Email action failed",
      isPresented: Binding(
        get: { store.lastActionError != nil },
        set: { if !$0 { store.clearError() } }
      )
    ) {
      if let accountID = store.pendingReconnectAccountID {
        Button("Reconnect Gmail") {
          store.clearError()
          store.reconnectAccount(accountID)
        }
      }
      Button("OK", role: .cancel) { store.clearError() }
    } message: {
      Text(store.lastActionError ?? "Please try again.")
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
            Text("Choose how far back Dimo reads Gmail on this iPhone. Analyzed suggestions still sync through Dimo for restore.")
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
            .foregroundStyle(accountNeedsAttention(account) ? Theme.danger : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 6)

        if account.syncState == .syncing {
          ProgressView().controlSize(.small).tint(Theme.green)
        } else {
          Text(account.syncState.title)
            .font(DimoFont.body(10, weight: .medium))
            .foregroundStyle(accountNeedsAttention(account) ? Theme.danger : Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accountNeedsAttention(account) ? Theme.dangerSoft : Theme.canvasDeep)
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
        if account.syncState == .needsReconnect {
          Button {
            store.reconnectAccount(account.id)
          } label: {
            Label("Reconnect Gmail", systemImage: "person.badge.key")
              .font(DimoFont.body(12, weight: .medium))
              .foregroundStyle(Theme.green)
          }
          .buttonStyle(.plain)

          Spacer()

          Button(role: .destructive) {
            disconnectCandidate = account
          } label: {
            Text("Disconnect")
              .font(DimoFont.body(12, weight: .medium))
              .foregroundStyle(Theme.danger)
          }
          .buttonStyle(.plain)
        } else if account.syncState != .disconnected {
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
          "Email analysis is not configured. Connect OpenRouter with a valid key and choose a model. Fetched emails wait on this iPhone until analyzed; analyzed suggestions then sync through Dimo for restore.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.body)
        .emailSettingsCard()
      }

      openRouterCard

      VStack(alignment: .leading, spacing: 8) {
        Text("Reanalyse email suggestions")
          .font(DimoFont.body(13, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text("Resets every eligible unreviewed email, updates the UI, then reruns OpenRouter analysis.")
          .font(DimoFont.body(11))
          .foregroundStyle(Theme.muted)
          .fixedSize(horizontal: false, vertical: true)
        ActionButton(
          title: store.isReanalyzing ? "Reanalysing emails…" : "Reanalyse all emails",
          variant: .secondary,
          enabled: !store.isReanalyzing && !store.accounts.isEmpty && store.isOpenRouterReady
        ) {
          confirmReanalyseAll = true
        }
      }
      .emailSettingsCard()
    }
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
          Text(openRouterSubtitle)
            .font(DimoFont.body(11))
            .foregroundStyle(Theme.muted)
        }
        Spacer()
        openRouterStatusBadge
      }

      Picker(
        "OpenRouter access",
        selection: Binding(
          get: { store.openRouterAccessMode },
          set: { store.selectOpenRouterAccessMode($0) }
        )
      ) {
        Text("Free models").tag(OpenRouterAccessMode.freeShared)
        Text("Bring your own key").tag(OpenRouterAccessMode.bringYourOwnKey)
      }
      .pickerStyle(.segmented)

      switch store.openRouterAccessMode {
      case .freeShared:
        freeOpenRouterBody
      case .bringYourOwnKey:
        byokOpenRouterBody
      }
    }
    .emailSettingsCard()
  }

  private var openRouterSubtitle: String {
    switch store.openRouterAccessMode {
    case .freeShared:
      return "Free models via Dimo · no personal key · suggestions sync through Dimo"
    case .bringYourOwnKey:
      return "Bring your own key · Analysis via OpenRouter · suggestions sync through Dimo"
    }
  }

  @ViewBuilder
  private var freeOpenRouterBody: some View {
    switch store.openRouterConnectionState {
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(DimoFont.body(10, weight: .medium))
        .foregroundStyle(Theme.danger)
        .fixedSize(horizontal: false, vertical: true)
      Text("Free models need an online Dimo session. No OpenRouter key is stored on this iPhone.")
        .font(DimoFont.body(10))
        .foregroundStyle(Theme.muted)
      ActionButton(title: "Retry free models", variant: .accent) {
        store.retryOpenRouterConnection()
      }
    case .disconnected:
      Text("Connect to Dimo sync to load free OpenRouter models. Selected email text is sent through Dimo’s servers to OpenRouter for analysis.")
        .font(DimoFont.body(10))
        .foregroundStyle(Theme.muted)
      ActionButton(title: "Load free models", variant: .accent) {
        store.retryOpenRouterConnection()
      }
    case .validating:
      HStack { ProgressView().controlSize(.small); Text("Loading free OpenRouter models…") }
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.muted)
    case .connected:
      openRouterConnectedControls(showRemoveKey: false)
    }
  }

  @ViewBuilder
  private var byokOpenRouterBody: some View {
    switch store.openRouterConnectionState {
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(DimoFont.body(10, weight: .medium))
        .foregroundStyle(Theme.danger)
        .fixedSize(horizontal: false, vertical: true)
      ActionButton(title: "Retry OpenRouter", variant: .accent) {
        store.retryOpenRouterConnection()
      }
      SecureField("sk-or-v1-…", text: $store.openRouterAPIKeyInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(DimoFont.body(12))
        .padding(12)
        .background(Theme.canvasDeep)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      Text("Retry uses the key already saved on this iPhone. Enter a different key only if you want to replace it.")
        .font(DimoFont.body(10))
        .foregroundStyle(Theme.muted)
      ActionButton(title: "Validate and save key", variant: .secondary, enabled: !store.openRouterAPIKeyInput.isEmpty) {
        store.saveOpenRouterKey()
      }
    case .disconnected:
      SecureField("sk-or-v1-…", text: $store.openRouterAPIKeyInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(DimoFont.body(12))
        .padding(12)
        .background(Theme.canvasDeep)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
      Text("Use a dedicated, revocable OpenRouter key with a spending limit. The key stays in this iPhone's Keychain. Analysis goes from this iPhone to OpenRouter; analyzed suggestions sync through Dimo.")
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
      openRouterConnectedControls(showRemoveKey: true)
    }
  }

  @ViewBuilder
  private func openRouterConnectedControls(showRemoveKey: Bool) -> some View {
    if store.selectedProvider == .openRouter,
       openRouterNeedsManualRetry {
      Label(store.analysisStatusDetail, systemImage: "exclamationmark.triangle.fill")
        .font(DimoFont.body(10, weight: .medium))
        .foregroundStyle(Theme.danger)
        .fixedSize(horizontal: false, vertical: true)
      ActionButton(title: "Retry OpenRouter analysis", variant: .accent) {
        store.retryOpenRouterAnalysis()
      }
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
      Label(
        "Non-ZDR enabled for analysis. Analyzed suggestions still sync through Dimo with their email text.",
        systemImage: "exclamationmark.shield.fill"
      )
      .font(DimoFont.body(10, weight: .medium))
      .foregroundStyle(Theme.danger)
      .fixedSize(horizontal: false, vertical: true)
    } else {
      Label(
        "Zero-data-retention routes for analysis. Analyzed suggestions still sync through Dimo with their email text.",
        systemImage: "lock.shield.fill"
      )
      .font(DimoFont.body(10, weight: .medium))
      .foregroundStyle(Theme.green)
      .fixedSize(horizontal: false, vertical: true)
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
      if showRemoveKey {
        compactAction("Remove key", tint: Theme.danger) { store.removeOpenRouterKey() }
      }
    }
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
    case .openRouter:
      switch store.openRouterAccessMode {
      case .freeShared:
        return "Selected email content is sent from this iPhone through Dimo’s servers to OpenRouter for free-model analysis. Analyzed suggestions, including the full email text, then sync through Dimo. No personal OpenRouter key is stored on this iPhone."
      case .bringYourOwnKey:
        return "Selected email content is sent from this iPhone to OpenRouter and the chosen model provider for analysis. Analyzed suggestions, including the full email text, then sync through Dimo. OpenRouter keys stay in this iPhone's Keychain."
      }
    case nil:
      return "Gmail is contacted directly from this iPhone. Credentials stay on-device. Email content stays local until you configure OpenRouter; analyzed suggestions later sync through Dimo for restore."
    }
  }

  private var openRouterNeedsManualRetry: Bool {
    let detail = store.analysisStatusDetail.lowercased()
    return detail.contains("unavailable")
      || detail.contains("insufficient")
      || detail.contains("rate limit")
      || detail.contains("waiting to retry")
      || detail.contains("could not be reached")
      || detail.contains("timed out")
      || detail.contains("forbidden")
      || detail.contains("invalid")
      || detail.contains("analysis failed")
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

  private func accountNeedsAttention(_ account: EmailUIAccount) -> Bool {
    account.syncState == .failed || account.syncState == .needsReconnect
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
