import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: Hashable {
  case preferences
  case email

  var title: String {
    switch self {
    case .preferences: return "Preferences"
    case .email: return "Email"
    }
  }
}

struct SettingsScreen: View {
  @Bindable var store: AppStore
  var onOpenAccount: () -> Void
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var selectedSection: SettingsSection
  @State private var importPresented = false
  @State private var exportURL: URL?
  @State private var confirmDeleteHistory = false

  init(
    store: AppStore,
    initialSection: SettingsSection = .preferences,
    onOpenAccount: @escaping () -> Void
  ) {
    self.store = store
    self.onOpenAccount = onOpenAccount
    _selectedSection = State(initialValue: initialSection)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button { closeSettings() } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 38, height: 38)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        Text("Settings")
          .font(DimoFont.display(24, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Spacer()
      }
      .frame(minHeight: 56)
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 10)

      VStack(spacing: 10) {
        accountCard

        Picker("Settings section", selection: $selectedSection) {
          Text(SettingsSection.preferences.title).tag(SettingsSection.preferences)
          Text(SettingsSection.email.title).tag(SettingsSection.email)
        }
        .pickerStyle(.segmented)
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 12)

      ScrollView {
        if selectedSection == .preferences {
          LazyVStack(alignment: .leading, spacing: 14) {
            preferencesCard

            PaymentMethodsManager(store: store)

            transactionDataCard
          }
        } else {
          EmailSettingsSection(store: store.emailFeatureStore)
        }
      }
      .contentMargins(.horizontal, 22, for: .scrollContent)
      .contentMargins(.top, 16, for: .scrollContent)
      .safeAreaPadding(.bottom, 24)
    }
    .background(Theme.canvas.ignoresSafeArea())
    .edgeSwipeBack(action: closeSettings)
    .onAppear { environment.applyTheme(store.theme) }
    .fileImporter(
      isPresented: $importPresented,
      allowedContentTypes: [.commaSeparatedText, .plainText],
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let url = urls.first {
        importFile(url)
      }
    }
    .alert("Delete history?", isPresented: $confirmDeleteHistory) {
      Button("Delete", role: .destructive) { store.deleteHistory() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently deletes your transaction history. This action cannot be undone.")
    }
  }

  private func closeSettings() {
    dismiss()
  }

  private var accountCard: some View {
    Button(action: onOpenAccount) {
      HStack(spacing: 14) {
        AvatarView(
          name: store.profileName,
          photoUrl: store.profilePhotoUrl,
          size: 52,
          radius: 16,
          fontSize: 22
        )
        VStack(alignment: .leading, spacing: 3) {
          Text(store.profileName.isEmpty ? "Account" : store.profileName)
            .font(DimoFont.display(16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text(store.profileEmail)
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.faint)
      }
      .settingsCard()
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Account, \(store.profileName), \(store.profileEmail)")
    .accessibilityHint("Opens account settings")
  }

  private var preferencesCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Preferences")
        .font(DimoFont.display(16, weight: .semibold))
        .foregroundStyle(Theme.ink)

      HStack {
        Text("Appearance")
          .font(DimoFont.body(13, weight: .medium))
          .foregroundStyle(Theme.ink)
        Spacer()
        PillDropdown(
          options: [ThemePreference.system, .light, .dark],
          selected: store.theme,
          label: { $0.rawValue.capitalized }
        ) { value in
          store.updatePreferences { $0.theme = value }
          environment.applyTheme(value)
        }
      }

      HStack {
        Text("Default stats range")
          .font(DimoFont.body(13, weight: .medium))
          .foregroundStyle(Theme.ink)
        Spacer()
        PillDropdown(
          options: StatsConstants.ranges,
          selected: store.defaultStatsRange,
          label: { StatsConstants.rangeLabel[$0] ?? $0.rawValue }
        ) { value in
          store.updatePreferences { $0.defaultStatsRange = value }
          store.statsRange = value
        }
      }

      HStack {
        Text("Currency")
          .font(DimoFont.body(13, weight: .medium))
          .foregroundStyle(Theme.ink)
        Spacer()
        PillDropdown(
          options: Currency.allCases,
          selected: store.currency,
          label: { "\(Formatting.currencySymbol($0)) \($0.rawValue)" }
        ) { option in
          store.updatePreferences { $0.currency = option }
        }
      }
    }
    .settingsCard()
  }

  private var transactionDataCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Transaction data")
        .font(DimoFont.display(16, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.bottom, 4)
      Text("Export all expenses as CSV, or import from Dimo's template.")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
        .padding(.bottom, 16)

      VStack(spacing: 10) {
        ActionButton(title: "Import transactions", variant: .accent) {
          importPresented = true
        }
        ActionButton(
          title: store.transactions.isEmpty ? "No transactions to export" : "Export transactions",
          variant: .secondary,
          enabled: !store.transactions.isEmpty
        ) {
          exportCSV()
        }
        ActionButton(title: "Export CSV template", variant: .secondary) {
          share(text: TransactionCSV.template)
        }
      }

      Divider()
        .overlay(Theme.lineSoft)
        .padding(.vertical, 16)

      ActionButton(
        title: store.deletingHistory
          ? "Deleting history…"
          : (store.transactions.isEmpty ? "No history to delete" : "Delete history"),
        variant: .danger,
        enabled: !store.transactions.isEmpty && !store.deletingHistory
      ) {
        confirmDeleteHistory = true
      }
    }
    .settingsCard()
  }

  private func exportCSV() {
    share(text: store.exportCSV())
  }

  private func share(text: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dimo-transactions.csv")
    try? text.write(to: url, atomically: true, encoding: .utf8)
    let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController?
      .present(av, animated: true)
  }

  private func importFile(_ url: URL) {
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      try store.importCSV(text)
    } catch {
      store.showToast(error.localizedDescription)
    }
  }
}

/// Bordered white settings card matching the web Card (p-5, rounded-2xl).
struct SettingsCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      )
  }
}

extension View {
  func settingsCard() -> some View {
    modifier(SettingsCardModifier())
  }
}

struct AccountScreen: View {
  @Bindable var store: AppStore
  var onClose: (() -> Void)?
  @Environment(AppEnvironment.self) private var environment
  @Environment(\.dismiss) private var dismiss
  @State private var confirmSignOut = false
  @State private var confirmDelete = false

  init(store: AppStore, onClose: (() -> Void)? = nil) {
    self.store = store
    self.onClose = onClose
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Button { closeAccount() } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 38, height: 38)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        Text("Account")
          .font(DimoFont.display(24, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Spacer()
      }
      .frame(minHeight: 56)
      .padding(.horizontal, 22)
      .padding(.top, 12)
      .padding(.bottom, 12)

      ScrollView {
        VStack(spacing: 14) {
          profileCard
          syncCard
          sessionCard
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 40)
      }
    }
    .background(Theme.canvas.ignoresSafeArea())
    .edgeSwipeBack(action: closeAccount)
    .confirmationDialog("Sign out?", isPresented: $confirmSignOut) {
      Button("Sign out", role: .destructive) {
        Task {
          do {
            try await environment.session.signOut()
          } catch {
            store.showToast("Could not remove local account data: \(error.localizedDescription)")
          }
        }
      }
    }
    .confirmationDialog("Delete account and cloud data?", isPresented: $confirmDelete) {
      Button("Delete account", role: .destructive) {
        Task {
          try? await environment.session.deleteAccount()
        }
      }
    }
  }

  private func closeAccount() {
    if let onClose {
      onClose()
    } else {
      store.closeAccount()
      dismiss()
    }
  }

  private var profileCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 16) {
        AvatarView(
          name: store.profileName,
          photoUrl: store.profilePhotoUrl,
          size: 60,
          radius: 18,
          fontSize: 26
        )
        VStack(alignment: .leading, spacing: 2) {
          Text(store.profileName)
            .font(DimoFont.display(17, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
          Text("Managed by your sign-in provider")
            .font(DimoFont.body(12))
            .foregroundStyle(Theme.muted)
        }
      }
      .padding(.bottom, 4)

      readOnlyField("Full name", value: store.profileName)
      readOnlyField("Email", value: store.profileEmail)
    }
    .settingsCard()
  }

  private var syncCard: some View {
    let syncing = store.syncMeta?.syncing == true
    let offline = store.syncMeta?.error == "Offline"
    let error = store.syncMeta?.error ?? ""
    let label: String = syncing
      ? "Syncing"
      : offline
        ? "Offline"
        : (!error.isEmpty || store.blockedCount > 0)
          ? "Error"
          : store.pendingCount > 0 ? "Pending" : "Synced"
    let blockedSuffix = store.blockedCount > 0 ? " · \(store.blockedCount) blocked" : ""

    return VStack(spacing: 0) {
      Text("Cloud sync")
        .font(DimoFont.display(16, weight: .semibold))
        .foregroundStyle(Theme.ink)
      Text("\(label) · \(store.pendingCount) pending\(blockedSuffix)")
        .font(DimoFont.body(12))
        .foregroundStyle(Theme.muted)
        .padding(.top, 4)
      Text("Last successful sync: \(lastSyncLabel)")
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.faint)
        .padding(.top, 4)
      Button {
        store.syncNow()
      } label: {
        Text(syncing ? "Syncing…" : "Sync now")
          .font(DimoFont.body(14, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .padding(.horizontal, 18)
          .padding(.vertical, 11)
          .background(Theme.canvas)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(Theme.line, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .padding(.top, 12)
      ActionButton(
        title: "Sync now (full replace)",
        variant: .danger,
        enabled: true
      ) {
        store.requestFullSync()
      }
      .padding(.top, 10)
      if !error.isEmpty, !offline {
        Text(error)
          .font(DimoFont.body(12))
          .foregroundStyle(Theme.danger)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Theme.dangerSoft)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .padding(.top, 12)
      }
    }
    .frame(maxWidth: .infinity)
    .settingsCard()
  }

  private var sessionCard: some View {
    VStack(spacing: 12) {
      ActionButton(title: "Sign out", variant: .secondary) { confirmSignOut = true }
      ActionButton(title: "Delete account", variant: .danger) { confirmDelete = true }
      Text("Delete account permanently removes your data from this device and the cloud.")
        .font(DimoFont.body(11))
        .foregroundStyle(Theme.faint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .settingsCard()
  }

  private var lastSyncLabel: String {
    guard let at = store.syncMeta?.lastSyncedAt else { return "Not synced yet" }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(at) / 1000))
  }

  private func readOnlyField(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(DimoFont.body(12)).foregroundStyle(Theme.muted)
      Text(value.isEmpty ? "—" : value)
        .font(DimoFont.body(16))
        .foregroundStyle(Theme.body)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        )
    }
  }
}

private extension View {
  func edgeSwipeBack(action: @escaping () -> Void) -> some View {
    simultaneousGesture(
      DragGesture(minimumDistance: 20, coordinateSpace: .global)
        .onEnded { value in
          let horizontalDistance = value.translation.width
          let verticalDistance = abs(value.translation.height)
          guard value.startLocation.x <= 28,
                horizontalDistance >= 80,
                horizontalDistance > verticalDistance * 1.25
          else { return }
          action()
        }
    )
  }
}
