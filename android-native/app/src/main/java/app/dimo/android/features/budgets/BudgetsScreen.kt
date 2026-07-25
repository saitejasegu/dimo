package app.dimo.android.features.budgets

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.ProgressBar
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.BudgetCategoryInput
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.Formatting
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore

/**
 * Budgets. Port of `BudgetsScreen` in
 * `ios-native/Dimo/Features/Stats/FeatureScreens.swift`: month hero, per-category
 * progress, and the suggested-budgets sheet backed by `applySuggestedBudgets`.
 */
@Composable
fun BudgetsScreen(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  var showSuggestions by remember { mutableStateOf(false) }
  var pendingDelete by remember { mutableStateOf<CategoryEntity?>(null) }

  val totals = BudgetSelectors.budgetTotals(store.transactions, store.limits)
  val budgets = BudgetSelectors.categoryBudgets(store.transactions, store.limits)
  val categoryByName = store.categories.associateBy { it.name }
  val suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
    store.transactions,
    categories = store.categories.map {
      BudgetCategoryInput(it.id, it.name, it.monthlyBudgetMinor)
    },
  )

  LazyColumn(
    modifier = modifier.fillMaxWidth(),
    contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 8.dp, bottom = 120.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    item("header") {
      ScreenHeader(title = "Budgets", modifier = Modifier.statusBarsPadding())
    }

    store.syncMeta?.error?.let { error ->
      item("sync-error") { SyncErrorBanner(error) }
    }

    item("hero") {
      HeroCard {
        HeroLabel("This month")
        HeroAmount(Formatting.money(totals.totalSpent, store.currency))
        HeroCaption(
          when {
            totals.totalLimit <= 0 -> "No monthly limits set yet"
            totals.left >= 0 ->
              "${Formatting.money(totals.left, store.currency)} left of " +
                Formatting.money(totals.totalLimit, store.currency)
            else -> "${Formatting.money(-totals.left, store.currency)} over budget"
          },
        )
        if (totals.totalLimit > 0) {
          Spacer(modifier = Modifier.height(6.dp))
          ProgressBar(progress = totals.pct / 100.0, over = totals.over)
        }
      }
    }

    if (suggestions.isNotEmpty()) {
      item("suggestions-cta") {
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .cardSurface(14.dp, DimoColors.greenSoft, DimoColors.green)
            .clickable { showSuggestions = true }
            .padding(horizontal = 14.dp, vertical = 14.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
              text = "Suggested budgets",
              style = DimoFont.body(15f, FontWeight.SemiBold),
              color = DimoColors.greenDeep,
            )
            Text(
              text = "Based on your last 6 months of spending",
              style = DimoFont.body(12f),
              color = DimoColors.greenDeep,
            )
          }
          Text(
            text = "${suggestions.size}",
            style = DimoFont.display(16f, FontWeight.Bold),
            color = DimoColors.greenDeep,
          )
        }
      }
    }

    if (budgets.isEmpty()) {
      item("empty") {
        DimoCard {
          EmptyState(
            title = "No categories yet",
            message = "Tap + to create your first category and give it a monthly budget.",
          )
        }
      }
    } else {
      item("list-label") { SectionLabel("Categories") }
      items(budgets, key = { "budget-${it.category}" }) { budget ->
        val category = categoryByName[budget.category]
        BudgetCard(
          store = store,
          categoryName = budget.category,
          emoji = store.categoryEmoji(category?.emoji, category?.id, budget.category),
          green = category?.tint == CategoryTint.GREEN,
          spent = budget.spent,
          limit = budget.limit,
          hasLimit = budget.hasLimit,
          pct = budget.pct,
          over = budget.over,
          onEdit = { category?.let { store.openEditCategory(it.id) } },
          onDelete = { category?.let { pendingDelete = it } },
        )
      }
    }
  }

  if (showSuggestions) {
    SuggestedBudgetsSheet(
      store = store,
      onClose = { showSuggestions = false },
    )
  }

  pendingDelete?.let { category ->
    val linked = store.transactions.count { it.categoryId == category.id }
    ConfirmDialog(
      title = "Delete ${category.name}?",
      message = if (linked == 0) {
        "This category has no transactions."
      } else {
        val suffix = if (linked == 1) "" else "s"
        "$linked transaction$suffix in this category will also be deleted."
      },
      confirmLabel = "Delete",
      onConfirm = { store.deleteCategoryAndTransactions(category.id) },
      onDismiss = { pendingDelete = null },
    )
  }
}

@Composable
private fun BudgetCard(
  store: AppStore,
  categoryName: String,
  emoji: String,
  green: Boolean,
  spent: Double,
  limit: Double?,
  hasLimit: Boolean,
  pct: Int,
  over: Boolean,
  onEdit: () -> Unit,
  onDelete: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(16.dp)
      .clickable(onClick = onEdit)
      .padding(16.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      CategoryTintView(emoji = emoji, green = green)
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
          text = categoryName,
          style = DimoFont.body(15f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          text = if (hasLimit && limit != null) {
            "${Formatting.money(spent, store.currency)} of ${Formatting.money(limit, store.currency)}"
          } else {
            "${Formatting.money(spent, store.currency)} spent · no limit"
          },
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
      if (hasLimit) {
        StatusBadge(
          label = "$pct%",
          tone = if (over) StatusBadgeTone.Muted else StatusBadgeTone.Green,
        )
      }
      Box(
        modifier = Modifier
          .size(30.dp)
          .cardSurface(9.dp, DimoColors.dangerSoft, DimoColors.dangerLine)
          .clickable(onClick = onDelete),
        contentAlignment = Alignment.Center,
      ) {
        Text(text = "✕", style = DimoFont.body(11f, FontWeight.SemiBold), color = DimoColors.danger)
      }
    }
    if (hasLimit) {
      ProgressBar(progress = pct / 100.0, over = over)
    }
  }
}

@Composable
private fun SuggestedBudgetsSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val suggestions = remember(store.transactions, store.categories) {
    BudgetSelectors.suggestedCategoryBudgetUpdates(
      store.transactions,
      categories = store.categories.map {
        BudgetCategoryInput(it.id, it.name, it.monthlyBudgetMinor)
      },
    )
  }
  var selected by remember(suggestions) { mutableStateOf(suggestions.map { it.id }.toSet()) }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(title = "Suggested budgets")
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        text = "Monthly averages from the last 6 months. Pick the ones to apply.",
        style = DimoFont.body(13f),
        color = DimoColors.muted,
      )
      suggestions.forEach { suggestion ->
        val isSelected = selected.contains(suggestion.id)
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .cardSurface(
              radius = 12.dp,
              background = if (isSelected) DimoColors.greenSoft else DimoColors.canvas,
              borderColor = if (isSelected) DimoColors.green else DimoColors.line,
            )
            .clickable {
              selected = if (isSelected) selected - suggestion.id else selected + suggestion.id
            }
            .padding(horizontal = 14.dp, vertical = 12.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
              text = suggestion.name,
              style = DimoFont.body(14f, FontWeight.Medium),
              color = DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
            )
            Text(
              text = buildString {
                append(Formatting.money(suggestion.suggestedLimit, store.currency))
                append(" / month")
                suggestion.currentLimit?.let { current ->
                  append(" · now ")
                  append(Formatting.money(current, store.currency))
                }
              },
              style = DimoFont.body(12f),
              color = DimoColors.muted,
            )
          }
          if (isSelected) {
            Icon(
              imageVector = Icons.Filled.Check,
              contentDescription = null,
              tint = DimoColors.green,
              modifier = Modifier.size(18.dp),
            )
          }
        }
      }
      PrimaryButton(
        title = if (selected.isEmpty()) "Apply" else "Apply ${selected.size}",
        enabled = selected.isNotEmpty(),
        onClick = {
          store.applySuggestedBudgets(selected)
          onClose()
        },
      )
    }
  }
}
