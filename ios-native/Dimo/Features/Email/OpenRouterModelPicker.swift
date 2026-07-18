import Foundation
import SwiftUI

struct OpenRouterModelPicker: View {
  @Bindable var store: EmailFeatureStore
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var filter: OpenRouterModelFilter = .all
  @State private var catalogRows: [OpenRouterModelPickerRow] = []
  @State private var visibleRows: [OpenRouterModelPickerRow] = []
  @State private var catalogGeneration = 0
  @State private var isPreparingCatalog = true
  @State private var confirmationCandidate: OpenRouterModel?

  var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Picker("Model filter", selection: $filter) {
          ForEach(OpenRouterModelFilter.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)

        if isPreparingCatalog, visibleRows.isEmpty {
          ProgressView("Preparing models…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleRows.isEmpty {
          ContentUnavailableView(
            "No matching models",
            systemImage: "magnifyingglass",
            description: Text("Refresh the catalog or change the search and privacy filters.")
          )
        } else {
          List(visibleRows) { row in
            Button {
              beginSelection(row.model)
            } label: {
              modelRow(row)
            }
            .buttonStyle(.plain)
          }
          .listStyle(.plain)
        }
      }
      .background(Theme.canvas.ignoresSafeArea())
      .navigationTitle("OpenRouter model")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $search, prompt: "Search models")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            store.refreshOpenRouterModels()
          } label: {
            if store.isRefreshingOpenRouterModels {
              ProgressView().controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
            }
          }
          .disabled(store.isRefreshingOpenRouterModels)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .foregroundStyle(Theme.green)
        }
      }
    }
    .task {
      await rebuildCatalog()
    }
    .task(id: filterRequest) {
      await updateVisibleRows()
    }
    .onChange(of: store.isRefreshingOpenRouterModels) { wasRefreshing, isRefreshing in
      guard wasRefreshing, !isRefreshing else { return }
      Task { await rebuildCatalog() }
    }
    .alert(
      confirmationTitle,
      isPresented: Binding(
        get: { confirmationCandidate != nil },
        set: { if !$0 { confirmationCandidate = nil } }
      )
    ) {
      Button(confirmationActionTitle) {
        guard let model = confirmationCandidate else { return }
        confirmationCandidate = nil
        select(model)
      }
      Button("Cancel", role: .cancel) { confirmationCandidate = nil }
    } message: {
      Text(confirmationMessage)
    }
  }

  private var filterRequest: OpenRouterModelFilterRequest {
    OpenRouterModelFilterRequest(
      search: search,
      filter: filter,
      catalogGeneration: catalogGeneration
    )
  }

  private var confirmationTitle: String {
    guard let model = confirmationCandidate else { return "Confirm OpenRouter model" }
    if model.requiresPriceConfirmation, !model.hasZDREndpoint {
      return "Use a paid non-ZDR model?"
    }
    if model.requiresPriceConfirmation {
      return "Use a paid OpenRouter model?"
    }
    return "Allow non-ZDR analysis?"
  }

  private var confirmationActionTitle: String {
    guard let model = confirmationCandidate else { return "Use model" }
    if model.requiresPriceConfirmation, !model.hasZDREndpoint {
      return "Confirm pricing and non-ZDR use"
    }
    if model.requiresPriceConfirmation {
      return "Confirm model pricing"
    }
    return "Allow non-ZDR and use model"
  }

  private var confirmationMessage: String {
    guard let model = confirmationCandidate else { return "OpenRouter usage charges may apply." }
    let privacyDisclosure =
      "This model currently has no zero-data-retention route. The provider may retain email content under its own policy. Analyzed suggestions, including email text, still sync through Dimo for restore."
    if model.requiresPriceConfirmation, !model.hasZDREndpoint {
      return "\(OpenRouterModelPickerRow.priceDisclosure(model))\n\n\(privacyDisclosure)"
    }
    if model.requiresPriceConfirmation {
      return OpenRouterModelPickerRow.priceDisclosure(model)
    }
    return privacyDisclosure
  }

  private func rebuildCatalog() async {
    let models = store.openRouterModels
    if catalogRows.isEmpty {
      isPreparingCatalog = true
    }
    let rows = await Task.detached(priority: .userInitiated) {
      models.map(OpenRouterModelPickerRow.init)
    }.value
    guard !Task.isCancelled else { return }
    catalogRows = rows
    catalogGeneration &+= 1
    isPreparingCatalog = false
  }

  private func updateVisibleRows() async {
    // Let the search field and keyboard render first, and coalesce rapid
    // keystrokes before searching the full catalog.
    if !search.isEmpty {
      try? await Task.sleep(for: .milliseconds(100))
    }
    guard !Task.isCancelled else { return }

    let rows = catalogRows
    let query = OpenRouterModelPickerRow.normalized(search)
    let selectedFilter = filter
    let matches = await Task.detached(priority: .userInitiated) {
      rows.filter { row in
        switch selectedFilter {
        case .all: break
        case .free: guard row.model.isFree else { return false }
        case .zdr: guard row.model.hasZDREndpoint else { return false }
        }
        return query.isEmpty || row.searchText.contains(query)
      }
    }.value
    guard !Task.isCancelled else { return }
    visibleRows = matches
  }

  private func modelRow(_ row: OpenRouterModelPickerRow) -> some View {
    let model = row.model
    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: store.selectedOpenRouterModelID == model.id ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(store.selectedOpenRouterModelID == model.id ? Theme.green : Theme.faint)
      VStack(alignment: .leading, spacing: 5) {
        Text(model.name)
          .font(DimoFont.body(13, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text(model.id)
          .font(DimoFont.body(10))
          .foregroundStyle(Theme.muted)
          .lineLimit(1)
        HStack(spacing: 6) {
          badge(model.isFree ? "Free" : "Paid", green: model.isFree)
          badge(model.hasZDREndpoint ? "ZDR" : "Non-ZDR", green: model.hasZDREndpoint)
          Text(row.contextDescription)
            .font(DimoFont.body(9))
            .foregroundStyle(Theme.faint)
        }
        if let priceDescription = row.priceDescription {
          Text(priceDescription)
            .font(DimoFont.body(9))
            .foregroundStyle(Theme.muted)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }

  private func badge(_ text: String, green: Bool) -> some View {
    Text(text)
      .font(DimoFont.body(9, weight: .semibold))
      .foregroundStyle(green ? Theme.green : Theme.muted)
      .padding(.horizontal, 6)
      .padding(.vertical, 3)
      .background(green ? Theme.greenSoft : Theme.canvasDeep)
      .clipShape(Capsule())
  }

  private func beginSelection(_ model: OpenRouterModel) {
    if model.requiresPriceConfirmation || !model.hasZDREndpoint {
      confirmationCandidate = model
    } else {
      select(model)
    }
  }

  private func select(_ model: OpenRouterModel) {
    store.selectOpenRouterModel(model.id, allowNonZDR: !model.hasZDREndpoint)
    dismiss()
  }
}

private struct OpenRouterModelFilterRequest: Hashable {
  var search: String
  var filter: OpenRouterModelFilter
  var catalogGeneration: Int
}

private struct OpenRouterModelPickerRow: Identifiable, Sendable {
  let model: OpenRouterModel
  let searchText: String
  let contextDescription: String
  let priceDescription: String?

  var id: String { model.id }

  init(model: OpenRouterModel) {
    self.model = model
    searchText = Self.normalized("\(model.name)\n\(model.id)")
    contextDescription = "\(model.contextLength.formatted()) ctx"
    priceDescription = model.isFree ? nil : Self.priceDisclosure(model)
  }

  static func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  static func priceDisclosure(_ model: OpenRouterModel) -> String {
    guard let input = model.inputPricePerMillion,
          let output = model.outputPricePerMillion else {
      return "Pricing is unknown. OpenRouter charges may apply."
    }
    return "Input $\(input.formatted(.number.precision(.fractionLength(0...4)))) / 1M · Output $\(output.formatted(.number.precision(.fractionLength(0...4)))) / 1M tokens"
  }
}

private extension OpenRouterModel {
  var requiresPriceConfirmation: Bool {
    !isFree || !hasKnownPrice
  }
}
