package app.dimo.android.features.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Currency
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.ProgressBar
import app.dimo.android.domain.BudgetCategoryInput
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.store.AppStore
import java.time.LocalDate

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

  val totals = BudgetSelectors.budgetTotals(store.transactions, store.limits)
  val budgets = BudgetSelectors.categoryBudgets(store.transactions, store.limits)
  val categoryByName = store.categories.associateBy { it.name }
  val suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
    store.transactions,
    categories = store.categories.map {
      BudgetCategoryInput(it.id, it.name, it.monthlyBudgetMinor)
    },
  )

  Column(modifier = modifier.fillMaxWidth()) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = ScreenContentPadding)
        .padding(top = 12.dp, bottom = 14.dp),
    ) {
      ScreenHeader(
        title = "Budgets",
        modifier = Modifier.statusBarsPadding(),
        trailing = {
          Box(
            modifier = Modifier
              .size(36.dp)
              .clickable(enabled = suggestions.isNotEmpty()) { showSuggestions = true },
            contentAlignment = Alignment.Center,
          ) {
            Icon(
              imageVector = Icons.Filled.AutoAwesome,
              contentDescription = "Suggested budgets",
              tint = if (suggestions.isEmpty()) DimoColors.faint else DimoColors.green,
              modifier = Modifier.size(20.dp),
            )
          }
        },
      )
      BudgetHero(
        spent = totals.totalSpent,
        limit = totals.totalLimit,
        left = totals.left,
        pct = totals.pct,
        over = totals.over,
        currency = store.currency,
        modifier = Modifier.padding(top = 16.dp),
      )
    }

    LazyColumn(
      modifier = Modifier.fillMaxWidth(),
      contentPadding = PaddingValues(
        start = ScreenContentPadding,
        end = ScreenContentPadding,
        top = 16.dp,
        bottom = 110.dp,
      ),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      store.syncMeta?.error?.let { error ->
        item("sync-error") { SyncErrorBanner(error) }
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
        items(budgets, key = { "budget-${it.category}" }) { budget ->
          val category = categoryByName[budget.category]
          BudgetCard(
            store = store,
            categoryName = budget.category,
            emoji = store.categoryEmoji(category?.emoji, category?.id, budget.category),
            spent = budget.spent,
            limit = budget.limit,
            hasLimit = budget.hasLimit,
            pct = budget.pct,
            over = budget.over,
            onEdit = { category?.let { store.openEditCategory(it.id) } },
          )
        }
      }
    }
  }

  if (showSuggestions) {
    SuggestedBudgetsSheet(
      store = store,
      onClose = { showSuggestions = false },
    )
  }

}

@Composable
private fun BudgetHero(
  spent: Double,
  limit: Double,
  left: Double,
  pct: Int,
  over: Boolean,
  currency: Currency,
  modifier: Modifier = Modifier,
) {
  val today = LocalDate.now(DateHelpers.zone())
  val daysToGo = today.lengthOfMonth() - today.dayOfMonth
  Column(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(20.dp))
      .background(DimoColors.inverse)
      .padding(20.dp),
  ) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
      Text("Monthly budget", style = DimoFont.body(13f), color = DimoColors.sideMuted)
      Spacer(modifier = Modifier.weight(1f))
      Text("$pct% used", style = DimoFont.body(12f), color = DimoColors.sideSub)
    }
    Row(
      modifier = Modifier.padding(top = 8.dp),
      verticalAlignment = Alignment.Bottom,
      horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      Text(
        text = Formatting.money(spent, currency),
        style = DimoFont.display(30f, FontWeight.SemiBold),
        color = DimoColors.sideText,
      )
      Text(
        text = "of ${Formatting.money(limit, currency)}",
        style = DimoFont.body(16f, FontWeight.Medium),
        color = DimoColors.sideSub,
        modifier = Modifier.padding(bottom = 4.dp),
      )
    }
    ProgressBar(
      progress = if (limit > 0) pct / 100.0 else 0.0,
      over = over,
      modifier = Modifier.padding(top = 12.dp),
    )
    Text(
      text = "${Formatting.money(left, currency)} left · $daysToGo days to go",
      style = DimoFont.body(12f),
      color = DimoColors.sideSub,
      modifier = Modifier.padding(top = 8.dp),
    )
  }
}

@Composable
private fun BudgetCard(
  store: AppStore,
  categoryName: String,
  emoji: String,
  spent: Double,
  limit: Double?,
  hasLimit: Boolean,
  pct: Int,
  over: Boolean,
  onEdit: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(16.dp)
      .clickable(onClick = onEdit)
      .padding(16.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = "$emoji $categoryName",
        style = DimoFont.body(14f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      Text(
        text = if (hasLimit && limit != null) {
          "${Formatting.money(spent, store.currency)} of ${Formatting.money(limit, store.currency)}"
        } else {
          "${Formatting.money(spent, store.currency)} · no budget"
        },
        style = DimoFont.body(13f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
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

  DimoBottomSheet(
    onDismiss = onClose,
    compactDragHandle = true,
  ) {
    SheetHeader(title = "Suggested budgets", compact = true)
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 690.dp)
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        text = "Based on the last 6 months of spend. Choose which categories to update.",
        style = DimoFont.body(15f),
        color = DimoColors.muted,
      )
      LazyColumn(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        items(suggestions, key = { "suggestion-${it.id}" }) { suggestion ->
          val isSelected = selected.contains(suggestion.id)
          val category = store.categories.firstOrNull { it.id == suggestion.id }
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(14.dp, DimoColors.canvas)
              .clickable {
                selected = if (isSelected) selected - suggestion.id else selected + suggestion.id
              }
              .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            Box(
              modifier = Modifier
                .size(28.dp)
                .clip(RoundedCornerShape(7.dp))
                .background(if (isSelected) DimoColors.green else DimoColors.canvasDeep),
              contentAlignment = Alignment.Center,
            ) {
              if (isSelected) {
                Icon(
                  imageVector = Icons.Filled.Check,
                  contentDescription = null,
                  tint = DimoColors.onGreen,
                  modifier = Modifier.size(18.dp),
                )
              }
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
              Text(
                text = "${store.categoryEmoji(category?.emoji, category?.id, suggestion.name)} ${suggestion.name}",
                style = DimoFont.body(14f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
              suggestion.currentLimit?.let { current ->
                Text(
                  text = "Now ${Formatting.money(current, store.currency)}",
                  style = DimoFont.body(12f),
                  color = DimoColors.faint,
                )
              }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
              Text(
                text = Formatting.money(suggestion.suggestedLimit, store.currency),
                style = DimoFont.display(15f, FontWeight.SemiBold),
                color = DimoColors.ink,
              )
              Text(
                text = "SUGGESTED",
                style = DimoFont.body(11f, FontWeight.SemiBold),
                color = DimoColors.green,
              )
            }
          }
        }
      }
      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        Text(
          text = "Cancel",
          style = DimoFont.body(15f, FontWeight.SemiBold),
          color = DimoColors.ink,
          textAlign = TextAlign.Center,
          modifier = Modifier
            .weight(0.28f)
            .height(54.dp)
            .cardSurface(14.dp, DimoColors.canvas)
            .clickable(onClick = onClose)
            .padding(vertical = 15.dp),
        )
        PrimaryButton(
          title = if (selected.isEmpty()) "Update budgets" else "Update ${selected.size} budgets",
          enabled = selected.isNotEmpty(),
          onClick = {
            store.applySuggestedBudgets(selected)
            onClose()
          },
          modifier = Modifier.weight(0.72f),
        )
      }
    }
  }
}
