package app.dimo.android.features.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PillDropdown
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.MonthBar
import app.dimo.android.domain.MonthBars
import app.dimo.android.domain.StatsConstants
import app.dimo.android.domain.StatsSelectors
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.StatBarTrack
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.store.AppStore

private const val COLLAPSED_LIMIT = 5

/**
 * Stats. Port of `StatsScreen` in
 * `ios-native/Dimo/Features/Stats/FeatureScreens.swift`.
 */
@Composable
fun StatsScreen(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  val scope = StatsSelectors.statsScope(store.statsRange, store.transactions)
  val bars = StatsSelectors.trendBars(store.statsRange, store.transactions, store.selectedMonth)
  val (categories, categoryTotal) = StatsSelectors.statCategories(
    scope,
    if (store.categoriesExpanded) Int.MAX_VALUE else COLLAPSED_LIMIT,
  )
  val (merchants, merchantTotal) = StatsSelectors.topMerchants(
    scope,
    if (store.merchantsExpanded) Int.MAX_VALUE else COLLAPSED_LIMIT,
  )

  LazyColumn(
    modifier = modifier.fillMaxWidth(),
    contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 8.dp, bottom = 120.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    item("header") {
      ScreenHeader(
        title = "Stats",
        modifier = Modifier.statusBarsPadding(),
        trailing = {
          PillDropdown(
            options = StatsConstants.ranges,
            selected = store.statsRange,
            label = { StatsConstants.rangeLabel[it] ?: it.wire },
            onSelect = { range ->
              store.statsRange = range
              store.selectedMonth = null
            },
          )
        },
      )
    }

    store.syncMeta?.error?.let { error ->
      item("sync-error") { SyncErrorBanner(error) }
    }

    item("hero") {
      HeroCard {
        HeroLabel(scope.spentLabel)
        HeroAmount(Formatting.money(scope.scopeTotal, store.currency))
        HeroCaption(scope.averageLabel)
      }
    }

    if (scope.transactions.isEmpty()) {
      item("empty") {
        DimoCard {
          EmptyState(
            title = "No spending in this range",
            message = "Pick a longer range or add an expense.",
          )
        }
      }
      return@LazyColumn
    }

    if (bars.visible) {
      item("trend") {
        DimoCard {
          Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel(bars.title, modifier = Modifier.weight(1f))
            Text(
              text = bars.caption,
              style = DimoFont.body(12f, FontWeight.Medium),
              color = DimoColors.muted,
            )
          }
          TrendBars(
            bars = bars,
            onSelect = { key ->
              store.selectedMonth = if (store.selectedMonth == key) null else key
            },
          )
        }
      }
    }

    item("categories") {
      DimoCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
          SectionLabel("Categories", modifier = Modifier.weight(1f))
          if (categoryTotal > COLLAPSED_LIMIT) {
            Text(
              text = if (store.categoriesExpanded) "Show less" else "Show all $categoryTotal",
              style = DimoFont.body(12f, FontWeight.Medium),
              color = DimoColors.green,
              modifier = Modifier.clickable {
                store.categoriesExpanded = !store.categoriesExpanded
              },
            )
          }
        }
        categories.forEach { entry ->
          Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text(
                text = entry.category,
                style = DimoFont.body(14f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
              )
              Text(
                text = entry.caption,
                style = DimoFont.body(12f),
                color = DimoColors.muted,
              )
            }
            StatBarTrack(relative = entry.relative, primary = entry.primary)
          }
        }
      }
    }

    item("merchants") {
      DimoCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
          SectionLabel("Top merchants", modifier = Modifier.weight(1f))
          if (merchantTotal > COLLAPSED_LIMIT) {
            Text(
              text = if (store.merchantsExpanded) "Show less" else "Show all $merchantTotal",
              style = DimoFont.body(12f, FontWeight.Medium),
              color = DimoColors.green,
              modifier = Modifier.clickable {
                store.merchantsExpanded = !store.merchantsExpanded
              },
            )
          }
        }
        merchants.forEach { merchant ->
          Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            CategoryTintView(
              emoji = merchant.emoji ?: "💸",
              green = merchant.green,
              size = 34.dp,
              radius = 10.dp,
              fontSize = 15f,
            )
            Column(
              modifier = Modifier.weight(1f),
              verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
              Text(
                text = merchant.name,
                style = DimoFont.body(14f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
              Text(
                text = merchant.sub,
                style = DimoFont.body(12f),
                color = DimoColors.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
              StatBarTrack(relative = merchant.relative, height = 4.dp)
            }
            Text(
              text = Formatting.money(merchant.amount, store.currency),
              style = DimoFont.display(14f, FontWeight.SemiBold),
              color = DimoColors.ink,
            )
          }
        }
      }
    }
  }
}

@Composable
private fun TrendBars(
  bars: MonthBars,
  onSelect: (String) -> Unit,
  modifier: Modifier = Modifier,
) {
  val barWidth = if (bars.bars.firstOrNull()?.wide == true) 26.dp else 38.dp
  Row(
    modifier = modifier
      .fillMaxWidth()
      .horizontalScroll(rememberScrollState()),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
    verticalAlignment = Alignment.Bottom,
  ) {
    bars.bars.forEach { bar ->
      TrendBar(bar = bar, width = barWidth, onSelect = { onSelect(bar.key) })
    }
  }
}

@Composable
private fun TrendBar(
  bar: MonthBar,
  width: Dp,
  onSelect: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val maxHeight = 116.dp
  val height = maxHeight * bar.heightRatio.coerceIn(0.02, 1.0).toFloat()
  Column(
    modifier = modifier
      .width(width)
      .clickable(onClick = onSelect),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Text(
      text = bar.display,
      style = DimoFont.body(9f, FontWeight.Medium),
      color = if (bar.selected) DimoColors.ink else DimoColors.faint,
      maxLines = 1,
      textAlign = TextAlign.Center,
    )
    Box(
      modifier = Modifier
        .width(width)
        .height(maxHeight),
      contentAlignment = Alignment.BottomCenter,
    ) {
      Box(
        modifier = Modifier
          .fillMaxWidth()
          .height(height)
          .clip(RoundedCornerShape(topStart = 8.dp, topEnd = 8.dp, bottomStart = 3.dp, bottomEnd = 3.dp))
          .background(if (bar.selected) DimoColors.green else DimoColors.bar),
      )
    }
    Text(
      text = bar.label,
      style = DimoFont.body(10f, if (bar.selected) FontWeight.SemiBold else FontWeight.Normal),
      color = if (bar.selected) DimoColors.ink else DimoColors.muted,
      maxLines = 1,
      textAlign = TextAlign.Center,
    )
  }
}
