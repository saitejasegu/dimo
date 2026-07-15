package app.dimo.android.features.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.design.ActionButton
import app.dimo.android.design.DimoColors
import app.dimo.android.design.ProgressBar
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.Formatting
import app.dimo.android.store.AppStore

@Composable
fun BudgetsScreen(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  val totals = remember(state.categories, state.transactions) {
    BudgetSelectors.budgetTotals(state.categories, state.transactions)
  }
  val budgets = remember(state.categories, state.transactions) {
    BudgetSelectors.categoryBudgets(state.categories, state.transactions)
  }
  val suggestions = remember(state.categories, state.transactions) {
    BudgetSelectors.suggestedCategoryBudgetUpdates(state.categories, state.transactions)
  }

  LazyColumn(
    modifier = Modifier.fillMaxSize(),
    contentPadding = PaddingValues(start = 22.dp, top = 16.dp, end = 22.dp, bottom = 96.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    item(key = "header") {
      Text("Budgets", style = MaterialTheme.typography.titleLarge)
      Spacer(Modifier.height(12.dp))
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(16.dp))
          .background(MaterialTheme.colorScheme.surface)
          .padding(16.dp),
      ) {
        Text("This month", style = MaterialTheme.typography.labelLarge, color = DimoColors.mutedLight)
        Spacer(Modifier.height(4.dp))
        Text(
          Formatting.money(totals.spent, state.currency),
          style = MaterialTheme.typography.titleLarge,
        )
        Text(
          if (totals.limit > 0) {
            "${Formatting.money(totals.left.coerceAtLeast(0.0), state.currency)} left of ${Formatting.money(totals.limit, state.currency)}"
          } else {
            "No budgets set"
          },
          style = MaterialTheme.typography.bodyMedium,
          color = if (totals.over) MaterialTheme.colorScheme.error else DimoColors.mutedLight,
        )
        if (totals.limit > 0) {
          Spacer(Modifier.height(10.dp))
          ProgressBar(
            progress = (totals.spent / totals.limit).toFloat(),
            over = totals.over,
          )
        }
      }
    }

    if (suggestions.isNotEmpty()) {
      item(key = "suggested") {
        ActionButton(
          label = "Apply suggested budgets",
          onClick = {
            store.applySuggestedBudgets(
              suggestions.map { it.categoryId to it.suggestedLimit },
            )
            store.showToast("Budgets updated")
          },
        )
      }
    }

    item(key = "list-header") {
      Spacer(Modifier.height(4.dp))
      Text("Categories", style = MaterialTheme.typography.titleMedium)
    }

    if (budgets.isEmpty()) {
      item(key = "empty") {
        Text(
          "Add categories to track monthly budgets.",
          color = DimoColors.mutedLight,
          modifier = Modifier.padding(vertical = 12.dp),
        )
      }
    } else {
      items(budgets, key = { it.id }) { budget ->
        val category = state.categories.firstOrNull { it.id == budget.id }
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable(enabled = category != null) {
              category?.let { store.beginEditCategory(it) }
            }
            .padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(budget.emoji)
          Spacer(Modifier.width(10.dp))
          Column(Modifier.weight(1f)) {
            Text(budget.name, fontWeight = FontWeight.SemiBold)
            Text(
              if (budget.limit > 0) {
                "${Formatting.money(budget.spent, state.currency)} of ${Formatting.money(budget.limit, state.currency)}"
              } else {
                "${Formatting.money(budget.spent, state.currency)} spent · no limit"
              },
              style = MaterialTheme.typography.bodyMedium,
              color = if (budget.over) MaterialTheme.colorScheme.error else DimoColors.mutedLight,
            )
            if (budget.limit > 0) {
              Spacer(Modifier.height(8.dp))
              ProgressBar(
                progress = budget.pct / 100f,
                over = budget.over,
              )
            }
          }
        }
      }
    }
  }
}
