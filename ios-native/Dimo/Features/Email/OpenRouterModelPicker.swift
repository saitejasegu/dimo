import SwiftUI

struct OpenRouterModelPicker: View {
  @Bindable var store: EmailFeatureStore
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var filter: OpenRouterModelFilter = .all
  @State private var paidCandidate: OpenRouterModel?
  @State private var nonZDRCandidate: OpenRouterModel?

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

        if filteredModels.isEmpty {
          ContentUnavailableView(
            "No matching models",
            systemImage: "magnifyingglass",
            description: Text("Refresh the catalog or change the search and privacy filters.")
          )
        } else {
          List(filteredModels) { model in
            Button {
              beginSelection(model)
            } label: {
              modelRow(model)
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
    .alert(
      "Use a paid OpenRouter model?",
      isPresented: Binding(
        get: { paidCandidate != nil },
        set: { if !$0 { paidCandidate = nil } }
      )
    ) {
      Button("Confirm model pricing") {
        guard let model = paidCandidate else { return }
        paidCandidate = nil
        continueAfterPriceConfirmation(model)
      }
      Button("Cancel", role: .cancel) { paidCandidate = nil }
    } message: {
      Text(paidCandidate.map(priceDisclosure) ?? "OpenRouter usage charges may apply.")
    }
    .alert(
      "Allow non-ZDR analysis?",
      isPresented: Binding(
        get: { nonZDRCandidate != nil },
        set: { if !$0 { nonZDRCandidate = nil } }
      )
    ) {
      Button("Allow non-ZDR and use model") {
        guard let model = nonZDRCandidate else { return }
        nonZDRCandidate = nil
        store.selectOpenRouterModel(model.id, allowNonZDR: true)
        dismiss()
      }
      Button("Cancel", role: .cancel) { nonZDRCandidate = nil }
    } message: {
      Text("This model currently has no zero-data-retention route. The provider may retain email content under its own policy. Analyzed suggestions, including email text, still sync through Dimo for restore.")
    }
  }

  private var filteredModels: [OpenRouterModel] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let queryEmpty = query.isEmpty
    return store.openRouterModels.filter { model in
      let matchesFilter: Bool
      switch filter {
      case .all: matchesFilter = true
      case .free: matchesFilter = model.isFree
      case .zdr: matchesFilter = model.hasZDREndpoint
      }
      guard matchesFilter else { return false }
      guard !queryEmpty else { return true }
      return model.name.localizedCaseInsensitiveContains(query)
        || model.id.localizedCaseInsensitiveContains(query)
    }
  }

  private func modelRow(_ model: OpenRouterModel) -> some View {
    HStack(alignment: .top, spacing: 12) {
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
          Text("\(model.contextLength.formatted()) ctx")
            .font(DimoFont.body(9))
            .foregroundStyle(Theme.faint)
        }
        if !model.isFree {
          Text(priceDisclosure(model))
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
    if !model.isFree || !model.hasKnownPrice {
      paidCandidate = model
    } else {
      continueAfterPriceConfirmation(model)
    }
  }

  private func continueAfterPriceConfirmation(_ model: OpenRouterModel) {
    if model.hasZDREndpoint {
      store.selectOpenRouterModel(model.id, allowNonZDR: false)
      dismiss()
    } else {
      nonZDRCandidate = model
    }
  }

  private func priceDisclosure(_ model: OpenRouterModel) -> String {
    guard let input = model.inputPricePerMillion,
          let output = model.outputPricePerMillion else {
      return "Pricing is unknown. OpenRouter charges may apply."
    }
    return "Input $\(input.formatted(.number.precision(.fractionLength(0...4)))) / 1M · Output $\(output.formatted(.number.precision(.fractionLength(0...4)))) / 1M tokens"
  }
}
