package app.dimo.android.features.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.TrackChanges
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Currency
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.ProgressBar
import app.dimo.android.design.StatusBadge
import app.dimo.android.domain.BudgetCategoryInput
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.GlobalBudgetAllocationIssue
import app.dimo.android.domain.GlobalBudgetCategoryInput
import app.dimo.android.domain.GlobalBudgetLimitUpdate
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.store.AppStore
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

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
  var showGlobalBudget by remember { mutableStateOf(false) }

  val budgetTransactions = TransactionSelectors.transactionsForActiveCategories(
    store.transactions,
    store.categories,
  )
  val activeLimits = TransactionSelectors.activeCategoryLimits(store.categories)
  // Totals cover all spend, matching Home. Per-category rows stay scoped: they group
  // by name, so an archived category would otherwise donate its spend to a new active
  // one sharing its name.
  val totals = BudgetSelectors.budgetTotals(store.transactions, activeLimits)
  val budgets = BudgetSelectors.categoryBudgets(budgetTransactions, activeLimits)
  val categoryByName = store.categories.associateBy { it.name }
  val archivedCategories = store.categories.filter { it.archived }
  val suggestions = BudgetSelectors.suggestedCategoryBudgetUpdates(
    budgetTransactions,
    categories = store.categories.filter { !it.archived }.map {
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
          Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            Box(
              modifier = Modifier
                .size(36.dp)
                .clickable { showGlobalBudget = true },
              contentAlignment = Alignment.Center,
            ) {
              Icon(
                imageVector = Icons.Filled.TrackChanges,
                contentDescription = "Set monthly budget",
                tint = DimoColors.green,
                modifier = Modifier.size(20.dp),
              )
            }
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

      if (archivedCategories.isNotEmpty()) {
        item("archived-header") {
          Text(
            text = "Archived",
            style = DimoFont.body(12f, FontWeight.Medium),
            color = DimoColors.muted,
            modifier = Modifier.padding(top = 8.dp),
          )
        }
        item("archived-list") {
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .clip(RoundedCornerShape(16.dp))
              .background(DimoColors.surface)
              .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp)),
          ) {
            archivedCategories.forEachIndexed { index, category ->
              Row(
                modifier = Modifier
                  .fillMaxWidth()
                  .clickable { store.openEditCategory(category.id) }
                  .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
              ) {
                Text(
                  text = "${category.emoji} ${category.name}",
                  style = DimoFont.body(14f, FontWeight.Medium),
                  color = DimoColors.ink,
                  maxLines = 1,
                  overflow = TextOverflow.Ellipsis,
                  modifier = Modifier.weight(1f),
                )
                StatusBadge(label = "Archived")
              }
              if (index != archivedCategories.lastIndex) {
                Box(
                  modifier = Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(DimoColors.lineSoft),
                )
              }
            }
          }
        }
        item("archived-footnote") {
          Text(
            text = "Archived categories stay attached to past transactions.",
            style = DimoFont.body(11f),
            color = DimoColors.muted,
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

  if (showGlobalBudget) {
    GlobalBudgetSheet(
      store = store,
      onClose = { showGlobalBudget = false },
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
private fun GlobalBudgetSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val activeCategories = store.categories.filter { !it.archived }
  val currentMinor = activeCategories.sumOf { it.monthlyBudgetMinor ?: 0 }
  val initialAmount = remember {
    if (currentMinor > 0) (currentMinor.toDouble() / 100).roundToLong().toString() else ""
  }
  var amount by remember { mutableStateOf(initialAmount) }
  var drafts by remember { mutableStateOf<Map<String, String>?>(null) }
  val parsedAmount = amount.toLongOrNull()?.takeIf {
    amount.isNotEmpty() && amount.all(Char::isDigit) && it > 0 && it <= Long.MAX_VALUE / 100
  }
  val allocation = remember(store.transactions, activeCategories, parsedAmount) {
    BudgetSelectors.globalBudgetAllocation(
      store.transactions,
      categories = activeCategories.map {
        GlobalBudgetCategoryInput(it.id, it.name, it.sortOrder, it.monthlyBudgetMinor)
      },
      totalBudget = parsedAmount ?: 0,
    )
  }
  val customizing = drafts != null
  val proposing = !customizing && amount != initialAmount
  val displayedLimits = allocation.allocations.map { item ->
    GlobalBudgetLimitUpdate(
      id = item.id,
      allocatedLimit = if (customizing) {
        parseGlobalBudgetLimit(drafts?.get(item.id))
      } else if (proposing) {
        item.allocatedLimit
      } else {
        wholeCurrentLimit(item.currentLimit)
      },
    )
  }
  val changedCount = allocation.allocations.zip(displayedLimits).count { (item, displayed) ->
    globalBudgetCurrentDiffers(item.currentLimit, displayed.allocatedLimit)
  }
  val canApply = activeCategories.isNotEmpty() &&
    parsedAmount != null &&
    changedCount > 0 &&
    (customizing || allocation.canApply)
  val validationMessage = when {
    activeCategories.isEmpty() -> "Create a category before setting a total budget."
    proposing && allocation.issue == GlobalBudgetAllocationIssue.NO_HISTORY ->
      "No spending was found in the last 6 completed months. Enter amounts on each category below, or wait until there is enough history for a split."
    amount.isNotEmpty() && parsedAmount == null -> "Enter a whole monthly amount greater than zero."
    (proposing || customizing) && parsedAmount != null && changedCount == 0 -> "Your category budgets already match these amounts."
    else -> null
  }
  val firstMonth = DateHelpers.localDate(allocation.window.start)
  val lastMonth = DateHelpers.localDate(allocation.window.end).minusMonths(1)
  val monthFormatter = DateTimeFormatter.ofPattern("MMM", Locale.getDefault())
  val monthYearFormatter = DateTimeFormatter.ofPattern("MMM yyyy", Locale.getDefault())
  val lookbackLabel = if (firstMonth.year == lastMonth.year) {
    "${firstMonth.format(monthFormatter)}–${lastMonth.format(monthYearFormatter)}"
  } else {
    "${firstMonth.format(monthYearFormatter)}–${lastMonth.format(monthYearFormatter)}"
  }

  DimoBottomSheet(onDismiss = onClose, compactDragHandle = true) {
    SheetHeader(title = "Set monthly budget", compact = true)
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 760.dp)
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Text(
        text = "Set one monthly total to split from spending in $lookbackLabel, or edit any category — the total follows the sum.",
        style = DimoFont.body(13f),
        color = DimoColors.muted,
      )

      Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        FieldLabel("Monthly total")
        DimoTextField(
          value = amount,
          onValueChange = { next ->
            amount = digitsOnlyGlobalBudget(next)
            drafts = null
          },
          placeholder = "Amount",
          keyboardType = KeyboardType.Number,
          leading = {
            Text(
              text = Formatting.currencySymbol(store.currency),
              style = DimoFont.body(16f),
              color = DimoColors.muted,
            )
          },
        )
        if (validationMessage != null) {
          Text(
            text = validationMessage,
            style = DimoFont.body(12f),
            color = DimoColors.muted,
          )
        }
      }

      LazyColumn(
        modifier = Modifier
          .weight(1f)
          .cardSurface(16.dp, DimoColors.canvas),
      ) {
        items(allocation.allocations, key = { "global-${it.id}" }) { item ->
          val category = store.categories.firstOrNull { it.id == item.id }
          val value = if (customizing) {
            drafts?.get(item.id).orEmpty()
          } else if (proposing) {
            globalBudgetFieldValue(item.allocatedLimit)
          } else {
            globalBudgetFieldValue(wholeCurrentLimit(item.currentLimit))
          }
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            Box(
              modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(11.dp))
                .background(DimoColors.canvasDeep),
              contentAlignment = Alignment.Center,
            ) {
              Text(
                text = store.categoryEmoji(category?.emoji, category?.id, item.name),
                style = DimoFont.body(18f),
              )
            }
            Column(
              modifier = Modifier.weight(1f),
              verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
              Text(
                text = item.name,
                style = DimoFont.body(14f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
              Text(
                text = if (item.sixMonthSpend > 0) {
                  "${Formatting.money(item.monthlyAverage, store.currency)} monthly average · ${item.share}%"
                } else {
                  "No spending history · no allocation"
                },
                style = DimoFont.body(11f),
                color = DimoColors.faint,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
              )
            }
            Column(
              horizontalAlignment = Alignment.End,
              verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
              Row(
                modifier = Modifier
                  .clip(RoundedCornerShape(8.dp))
                  .border(1.dp, DimoColors.line, RoundedCornerShape(8.dp))
                  .background(DimoColors.canvas)
                  .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
              ) {
                Text(
                  text = Formatting.currencySymbol(store.currency),
                  style = DimoFont.body(13f),
                  color = DimoColors.muted,
                )
                BasicTextField(
                  value = value,
                  onValueChange = { next ->
                    val digits = digitsOnlyGlobalBudget(next)
                    val snapshot = (drafts ?: snapshotGlobalBudgetLimits(displayedLimits))
                      .toMutableMap()
                    snapshot[item.id] = digits
                    drafts = snapshot
                    val total = sumGlobalBudgetLimits(snapshot)
                    amount = if (total > 0) total.toString() else ""
                  },
                  singleLine = true,
                  textStyle = DimoFont.body(14f, FontWeight.SemiBold).copy(
                    color = DimoColors.ink,
                    textAlign = TextAlign.End,
                  ),
                  cursorBrush = SolidColor(DimoColors.green),
                  keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                  modifier = Modifier
                    .width(92.dp)
                    .semantics { contentDescription = "${item.name} monthly budget" },
                  decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterEnd) {
                      if (value.isEmpty()) {
                        Text(
                          text = "0",
                          style = DimoFont.body(14f, FontWeight.SemiBold),
                          color = DimoColors.faint,
                        )
                      }
                      inner()
                    }
                  },
                )
              }
              Text(
                text = if (item.sixMonthSpend > 0 && proposing) "PROPOSED" else "BUDGET",
                style = DimoFont.body(9f, FontWeight.SemiBold),
                color = if (item.sixMonthSpend > 0 && proposing) DimoColors.green else DimoColors.muted,
              )
            }
          }
        }
        if (allocation.allocations.isEmpty()) {
          item("global-empty") {
            Text(
              text = "No categories yet.",
              style = DimoFont.body(14f),
              color = DimoColors.muted,
              textAlign = TextAlign.Center,
              modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 28.dp),
            )
          }
        }
      }

      Text(
        text = "Changing the total proposes a new split. Editing a category updates the total to match. Apply replaces every category budget with the amounts shown here.",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        modifier = Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(12.dp))
          .background(DimoColors.canvasDeep)
          .padding(13.dp),
      )

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
          title = when {
            (proposing || customizing) && parsedAmount != null && changedCount == 0 -> "Already applied"
            customizing -> "Apply budgets"
            else -> "Apply split"
          },
          enabled = canApply,
          onClick = {
            if (!canApply) return@PrimaryButton
            store.applyGlobalBudget(displayedLimits)
            onClose()
          },
          modifier = Modifier.weight(0.72f),
        )
      }
    }
  }
}

@Composable
private fun SuggestedBudgetsSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val suggestions = remember(store.transactions, store.categories) {
    val active = store.categories.filter { !it.archived }
    BudgetSelectors.suggestedCategoryBudgetUpdates(
      TransactionSelectors.transactionsForActiveCategories(store.transactions, store.categories),
      categories = active.map {
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

private fun digitsOnlyGlobalBudget(value: String, max: Int = 15): String =
  value.filter(Char::isDigit).take(max)

private fun parseGlobalBudgetLimit(value: String?): Long? {
  if (value.isNullOrEmpty()) return null
  if (!value.all(Char::isDigit)) return null
  val amount = value.toLongOrNull() ?: return null
  if (amount <= 0L || amount > Long.MAX_VALUE / 100) return null
  return amount
}

private fun snapshotGlobalBudgetLimits(
  allocations: List<GlobalBudgetLimitUpdate>,
): Map<String, String> = allocations.associate { item ->
  item.id to globalBudgetFieldValue(item.allocatedLimit)
}

private fun wholeCurrentLimit(current: Double?): Long? {
  if (current == null || !current.isFinite() || current <= 0.0) return null
  val rounded = current.roundToLong()
  return rounded.takeIf { it > 0L }
}

private fun globalBudgetFieldValue(limit: Long?): String =
  if (limit != null && limit > 0L) limit.toString() else ""

private fun sumGlobalBudgetLimits(drafts: Map<String, String>): Long =
  drafts.values.sumOf { parseGlobalBudgetLimit(it) ?: 0L }

private fun globalBudgetCurrentDiffers(current: Double?, allocated: Long?): Boolean = when {
  current == null && allocated == null -> false
  current == null || allocated == null -> true
  else -> current != allocated.toDouble()
}
