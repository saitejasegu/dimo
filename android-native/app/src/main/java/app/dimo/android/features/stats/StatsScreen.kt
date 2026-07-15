package app.dimo.android.features.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.data.model.StatsRange
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.StatsSelectors
import app.dimo.android.store.AppStore

@Composable
fun StatsScreen(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  var selectedBarKey by remember { mutableStateOf<String?>(null) }

  val scope = remember(state.transactions, state.statsRange) {
    StatsSelectors.statsScope(state.transactions, state.statsRange)
  }
  val bars = remember(scope, state.statsRange, selectedBarKey) {
    StatsSelectors.buildBars(scope, state.statsRange, selectedBarKey)
  }
  val categories = remember(scope) { StatsSelectors.statCategories(scope) }
  val merchants = remember(scope) { StatsSelectors.topMerchants(scope) }

  LazyColumn(
    modifier = Modifier.fillMaxSize(),
    contentPadding = PaddingValues(start = 22.dp, top = 16.dp, end = 22.dp, bottom = 96.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    item(key = "header") {
      Text("Stats", style = MaterialTheme.typography.titleLarge)
      Spacer(Modifier.height(12.dp))
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        StatsRange.entries.forEach { range ->
          Chip(
            label = range.wire,
            selected = state.statsRange == range,
            onClick = {
              selectedBarKey = null
              store.setStatsRange(range)
            },
          )
        }
      }
    }

    item(key = "totals") {
      Spacer(Modifier.height(8.dp))
      Text(
        Formatting.money(scope.scopeTotal, state.currency),
        style = MaterialTheme.typography.displayLarge,
        color = MaterialTheme.colorScheme.onBackground,
      )
      Text(
        "Avg ${Formatting.money(scope.averagePerDay, state.currency)} / day",
        style = MaterialTheme.typography.bodyMedium,
        color = DimoColors.mutedLight,
      )
    }

    item(key = "bars") {
      Spacer(Modifier.height(8.dp))
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .height(160.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.Bottom,
      ) {
        bars.forEach { bar ->
          Column(
            modifier = Modifier
              .weight(1f)
              .fillMaxHeight()
              .clickable { selectedBarKey = bar.key },
            horizontalAlignment = Alignment.CenterHorizontally,
          ) {
            Box(
              modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
              contentAlignment = Alignment.BottomCenter,
            ) {
              Box(
                modifier = Modifier
                  .fillMaxWidth()
                  .fillMaxHeight(bar.heightRatio.coerceIn(0.04f, 1f))
                  .clip(RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp))
                  .background(if (bar.selected) DimoColors.green else DimoColors.greenSoft),
              )
            }
            Spacer(Modifier.height(6.dp))
            Text(
              bar.label,
              style = MaterialTheme.typography.labelLarge,
              color = if (bar.selected) DimoColors.green else DimoColors.mutedLight,
            )
          }
        }
      }
    }

    item(key = "categories-header") {
      Spacer(Modifier.height(12.dp))
      Text("Categories", style = MaterialTheme.typography.titleMedium)
    }
    if (categories.isEmpty()) {
      item(key = "categories-empty") {
        Text("No spending in this range", color = DimoColors.mutedLight)
      }
    } else {
      items(categories, key = { "cat-${it.name}" }) { cat ->
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(cat.emoji)
          Spacer(Modifier.width(10.dp))
          Column(Modifier.weight(1f)) {
            Text(cat.name, fontWeight = FontWeight.SemiBold)
            Box(
              modifier = Modifier
                .padding(top = 6.dp)
                .fillMaxWidth(cat.relative / 100f)
                .height(6.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(DimoColors.green),
            )
          }
          Text(Formatting.money(cat.amount, state.currency), fontWeight = FontWeight.Medium)
        }
      }
    }

    item(key = "merchants-header") {
      Spacer(Modifier.height(12.dp))
      Text("Merchants", style = MaterialTheme.typography.titleMedium)
    }
    if (merchants.isEmpty()) {
      item(key = "merchants-empty") {
        Text("No merchants yet", color = DimoColors.mutedLight)
      }
    } else {
      items(merchants, key = { "merch-${it.name}" }) { merchant ->
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(merchant.emoji ?: "🛍️")
          Spacer(Modifier.width(10.dp))
          Column(Modifier.weight(1f)) {
            Text(merchant.name, fontWeight = FontWeight.SemiBold)
            Box(
              modifier = Modifier
                .padding(top = 6.dp)
                .fillMaxWidth(merchant.relative / 100f)
                .height(6.dp)
                .clip(RoundedCornerShape(999.dp))
                .background(if (merchant.green) DimoColors.green else DimoColors.greenSoft),
            )
          }
          Text(Formatting.money(merchant.amount, state.currency), fontWeight = FontWeight.Medium)
        }
      }
    }
  }
}
