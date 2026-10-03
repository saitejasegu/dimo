import SwiftUI

struct CategorySplitPartDraft: Identifiable, Equatable {
  let id = UUID().uuidString
  /// An ID rather than a name, so duplicate names or a rename can't move the amount.
  var categoryId: String
  var value = ""
}

/// Extra categories for one purchase. The expense sheet's own category keeps
/// whatever the parts leave.
struct CategorySplitDraft: Equatable {
  var parts: [CategorySplitPartDraft] = []
  /// The main category picked in this step. The sheet tracks its category by
  /// name, which can't tell two categories with the same name apart.
  var mainCategoryId: String?

  var isActive: Bool { !parts.isEmpty }

  /// The main category's ID: the one picked here while it still carries the
  /// sheet's category name, otherwise the first category with that name.
  func resolvedMainId(name: String, in categories: [CategoryEntity]) -> String? {
    if let mainCategoryId, categories.contains(where: { $0.id == mainCategoryId && $0.name == name }) {
      return mainCategoryId
    }
    return categories.first { $0.name == name }?.id
  }

  /// What's left for the main category in minor units of `currency`, or nil
  /// when the parts don't leave it anything.
  func remainder(totalMinor: Int, currency: String) -> Int? {
    CategorySplitSelectors.remainder(
      totalMinor: totalMinor,
      partsMinor: parts.map { ExchangeRates.toMinorUnits(Double($0.value) ?? 0, currency) }
    )
  }

  /// Every row has a real category that isn't used twice. New rows can't use
  /// an archived category; the main one may keep the category it came with.
  func hasValidCategories(mainId: String?, in categories: [CategoryEntity]) -> Bool {
    guard let mainId, categories.contains(where: { $0.id == mainId }) else { return false }
    let ids = [mainId] + parts.map(\.categoryId)
    return Set(ids).count == ids.count
      && parts.allSatisfy { part in categories.contains { $0.id == part.categoryId && !$0.archived } }
  }
}

/// The category step of the expense sheet: divides one purchase across
/// categories, saved as one expense per category.
struct CategorySplitStep: View {
  var categories: [CategoryEntity]
  @Binding var mainCategory: String
  @Binding var draft: CategorySplitDraft
  var totalMinor: Int
  var currency: String
  var onDone: () -> Void

  private var remainder: Int? {
    draft.remainder(totalMinor: totalMinor, currency: currency)
  }
  private var mainCategoryId: String? {
    draft.resolvedMainId(name: mainCategory, in: categories)
  }
  private var savable: Bool {
    remainder != nil && draft.hasValidCategories(mainId: mainCategoryId, in: categories)
  }
  private var sortedCategories: [CategoryEntity] {
    categories.filter { !$0.archived }.sorted { $0.sortOrder < $1.sortOrder }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 6) {
        Button(action: finish) {
          Image(systemName: "chevron.left")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to expense")
        Text(totalMinor > 0 ? "Split \(format(totalMinor)) by category" : "Split by category")
          .font(DimoFont.display(18, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
      .padding(.leading, -8)

      VStack(spacing: 0) {
        partRow {
          categoryMenu(
            selectedId: mainCategoryId,
            options: TransactionSelectors.pickerCategories(categories, selectedName: mainCategory),
            excluding: draft.parts.map(\.categoryId)
          ) {
            draft.mainCategoryId = $0.id
            mainCategory = $0.name
          }
        } trailing: {
          HStack(spacing: 4) {
            Text(format(remainder))
              .foregroundStyle(Theme.muted)
            // Lines up with the remove buttons on the other rows.
            Color.clear.frame(width: 32, height: 32)
          }
        }
        ForEach($draft.parts) { $part in
          Divider().overlay(Theme.line)
          partRow {
            categoryMenu(
              selectedId: part.categoryId,
              options: sortedCategories,
              excluding: [mainCategoryId].compactMap { $0 }
                + draft.parts.filter { $0.id != part.id }.map(\.categoryId)
            ) { part.categoryId = $0.id }
          } trailing: {
            HStack(spacing: 4) {
              CategoryAmountField(value: $part.value)
                .accessibilityLabel("Amount for \(categoryName(part.categoryId))")
              Button { removePart(part.id) } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(Theme.faint)
                  .frame(width: 32, height: 32)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove \(categoryName(part.categoryId))")
            }
          }
        }
      }
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))

      if nextCategory != nil {
        Button("+ Add category", action: addPart)
          .font(DimoFont.body(14, weight: .medium))
          .foregroundStyle(Theme.green)
          .buttonStyle(.plain)
      }

      if draft.isActive {
        Text(note)
          .font(DimoFont.body(12))
          .foregroundStyle(problem == nil ? Theme.muted : Theme.danger)
      }

      Button(action: finish) {
        Text(draft.isActive ? "Done" : "Cancel")
          .font(DimoFont.body(16, weight: .semibold))
          .foregroundStyle(draft.isActive ? Theme.onGreen : Theme.ink)
          .frame(maxWidth: .infinity)
          .frame(height: 54)
          .background(
            draft.isActive ? (canFinish ? Theme.green : Theme.disabled) : Theme.canvas
          )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(Theme.line, lineWidth: draft.isActive ? 0 : 1)
          )
      }
      .buttonStyle(.plain)
      .disabled(!canFinish)
    }
    .onAppear {
      if !draft.isActive { addPart() }
    }
  }

  private var canFinish: Bool { !draft.isActive || savable || totalMinor == 0 }

  private var problem: String? {
    guard draft.isActive, totalMinor > 0, !savable else { return nil }
    if mainCategoryId == nil {
      return "Pick a category for the first row."
    }
    if !draft.hasValidCategories(mainId: mainCategoryId, in: categories) {
      return "Pick a different category for each row."
    }
    if draft.parts.contains(where: { (Double($0.value) ?? 0) <= 0 }) {
      return "Enter an amount for each category."
    }
    return "Leave some of \(format(totalMinor)) for \(mainCategory)."
  }

  private var note: String {
    if let problem { return problem }
    let count = draft.parts.count + 1
    return "Saved as \(count) expenses. \(mainCategory.isEmpty ? "The first category" : mainCategory) gets what's left."
  }

  /// The first category no row uses yet.
  private var nextCategory: String? {
    let used = Set([mainCategoryId].compactMap { $0 } + draft.parts.map(\.categoryId))
    return sortedCategories.first { !used.contains($0.id) }?.id
  }

  private func categoryName(_ id: String) -> String {
    categories.first { $0.id == id }?.name ?? "category"
  }

  private func format(_ minor: Int?) -> String {
    guard let minor else { return "—" }
    return Formatting.money(ExchangeRates.toMajorUnits(minor, currency), currencyCode: currency)
  }

  private func categoryMenu(
    selectedId: String?,
    options: [CategoryEntity],
    excluding: [String],
    onSelect: @escaping (CategoryEntity) -> Void
  ) -> some View {
    let excluded = Set(excluding)
    let selectedCategory = categories.first { $0.id == selectedId }
    return Menu {
      ForEach(
        options.sorted { $0.sortOrder < $1.sortOrder }.filter { !excluded.contains($0.id) }
      ) { category in
        Button {
          onSelect(category)
        } label: {
          if category.id == selectedId {
            Label("\(category.emoji) \(category.name)", systemImage: "checkmark")
          } else {
            Text("\(category.emoji) \(category.name)")
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(selectedCategory.map { "\($0.emoji) \($0.name)" } ?? "Select category")
          .font(DimoFont.body(15, weight: .medium))
          .foregroundStyle(selectedCategory == nil ? Theme.muted : Theme.ink)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(Theme.muted)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Category")
    .accessibilityValue(selectedCategory?.name ?? "None")
  }

  private func partRow<Leading: View, Trailing: View>(
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 8) {
      leading()
      Spacer(minLength: 8)
      trailing()
        .font(DimoFont.body(15))
    }
    .padding(.leading, 14)
    .padding(.trailing, 6)
    .frame(minHeight: 48)
  }

  /// Leaving before typing any amount drops the untouched rows.
  private func finish() {
    if draft.parts.allSatisfy({ $0.value.trimmingCharacters(in: .whitespaces).isEmpty }) {
      draft = CategorySplitDraft()
    }
    onDone()
  }

  private func addPart() {
    guard let nextCategory else { return }
    draft.parts.append(CategorySplitPartDraft(categoryId: nextCategory))
  }

  private func removePart(_ id: String) {
    draft.parts.removeAll { $0.id == id }
  }
}

/// A part's amount field. It keeps its own text so a rejected keystroke is
/// taken back on screen too: when the cleaned value equals the stored one,
/// writing through a binding alone wouldn't redraw the field.
private struct CategoryAmountField: View {
  @Binding var value: String
  @State private var text = ""

  var body: some View {
    TextField("0", text: $text)
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      .padding(.horizontal, 10)
      .frame(width: 96, height: 34)
      .background(Theme.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line))
      .onAppear { text = value }
      .onChange(of: text) { _, typed in
        let cleaned = CategorySplitSelectors.sanitizedAmount(typed)
        if cleaned != typed { text = cleaned }
        if cleaned != value { value = cleaned }
      }
  }
}
