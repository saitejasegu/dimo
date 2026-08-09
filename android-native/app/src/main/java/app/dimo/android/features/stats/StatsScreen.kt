package app.dimo.android.features.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Transaction
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PillDropdown
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.MonthBar
import app.dimo.android.domain.MonthBars
import app.dimo.android.domain.StatsConstants
import app.dimo.android.domain.StatsSelectors
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.StatBarTrack
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import kotlin.math.abs

private const val COLLAPSED_LIMIT = 5

/** Minimum horizontal travel before a flick counts as a period change, matching iOS. */
private val PeriodSwipeThreshold = 80.dp

/** Which stats row opened the transaction drill-down sheet. */
private sealed interface StatsDrillDown {
  val title: String

  data class Category(override val title: String) : StatsDrillDown
  data class Merchant(override val title: String) : StatsDrillDown
}

/**
 * Stats. Port of `StatsScreen` in
 * `ios-native/Dimo/Features/Stats/FeatureScreens.swift`, including period
 * navigation (`statsPeriodOffset`) and the tap-through transaction sheet.
 */
@Composable
fun StatsScreen(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  var drillDown by remember { mutableStateOf<StatsDrillDown?>(null) }
  val listState = rememberLazyListState()

  val scope = StatsSelectors.statsScope(
    range = store.statsRange,
    transactions = store.transactions,
    offset = store.statsPeriodOffset,
  )
  val bars = StatsSelectors.trendBars(
    range = store.statsRange,
    transactions = store.transactions,
    selectedKey = store.selectedMonth,
    offset = store.statsPeriodOffset,
  )
  val (categories, categoryTotal) = StatsSelectors.statCategories(
    scope,
    if (store.categoriesExpanded) Int.MAX_VALUE else COLLAPSED_LIMIT,
  )
  val (merchants, merchantTotal) = StatsSelectors.topMerchants(
    scope,
    if (store.merchantsExpanded) Int.MAX_VALUE else COLLAPSED_LIMIT,
  )

  val isCurrentPeriod = store.statsPeriodOffset == 0
  val canGoBack = StatsSelectors.hasEarlierData(
    transactions = store.transactions,
    range = store.statsRange,
    offset = store.statsPeriodOffset,
  )

  fun goBack() {
    if (canGoBack) store.statsPeriodOffset -= 1
  }

  fun goForward() {
    if (!isCurrentPeriod) store.statsPeriodOffset += 1
  }

  // A new range reinterprets the offset's length, so snap back to current. The
  // previous range is remembered rather than keyed on, so re-entering the tab
  // does not clear a selected bar the way a bare LaunchedEffect would.
  var lastRange by remember { mutableStateOf(store.statsRange) }
  LaunchedEffect(store.statsRange) {
    if (store.statsRange != lastRange) {
      lastRange = store.statsRange
      store.statsPeriodOffset = 0
      store.selectedMonth = null
    }
  }

  // Returning to the top keeps the new period's hero in view after a swipe.
  LaunchedEffect(store.statsPeriodOffset) {
    listState.scrollToItem(0)
  }

  val swipeThresholdPx = with(LocalDensity.current) { PeriodSwipeThreshold.toPx() }

  LazyColumn(
    state = listState,
    modifier = modifier
      .fillMaxWidth()
      // Swipe right → older period (left chevron); swipe left → newer.
      // Vertical drags reach the list first, so scrolling is unaffected.
      .pointerInput(canGoBack, isCurrentPeriod, swipeThresholdPx) {
        var travelled = 0f
        detectHorizontalDragGestures(
          onDragStart = { travelled = 0f },
          onDragEnd = {
            if (abs(travelled) >= swipeThresholdPx) {
              if (travelled > 0) goBack() else goForward()
            }
          },
          onDragCancel = { travelled = 0f },
        ) { _, delta -> travelled += delta }
      },
    contentPadding = PaddingValues(start = ScreenContentPadding, end = ScreenContentPadding, top = 12.dp, bottom = 110.dp),
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
            onSelect = { range -> store.statsRange = range },
          )
        },
      )
    }

    store.syncMeta?.error?.let { error ->
      item("sync-error") { SyncErrorBanner(error) }
    }

    item("period-nav") {
      PeriodNav(
        label = scope.periodLabel,
        canGoBack = canGoBack,
        canGoForward = !isCurrentPeriod,
        onBack = { goBack() },
        onForward = { goForward() },
        onReset = { store.statsPeriodOffset = 0 },
      )
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
            title = if (isCurrentPeriod) {
              "No spending in this range"
            } else {
              "Nothing recorded in this period"
            },
            message = if (isCurrentPeriod) {
              "Pick a longer range or add an expense."
            } else {
              "Swipe or use the arrows to browse another period."
            },
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
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .clickable { drillDown = StatsDrillDown.Category(entry.category) }
              .padding(vertical = 2.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
          ) {
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
            modifier = Modifier
              .fillMaxWidth()
              .clickable { drillDown = StatsDrillDown.Merchant(merchant.name) }
              .padding(vertical = 2.dp),
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

  drillDown?.let { selection ->
    val matching = scope.transactions.filter { transaction ->
      when (selection) {
        is StatsDrillDown.Category -> transaction.category == selection.title
        is StatsDrillDown.Merchant -> transaction.name == selection.title
      }
    }
    StatsTransactionsSheet(
      store = store,
      title = selection.title,
      transactions = matching,
      onClose = { drillDown = null },
    )
  }
}

/**
 * One bordered row rather than free-floating chevrons, matching the iOS and web
 * period nav. Tapping the label returns to the current period.
 */
@Composable
private fun PeriodNav(
  label: String,
  canGoBack: Boolean,
  canGoForward: Boolean,
  onBack: () -> Unit,
  onForward: () -> Unit,
  onReset: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(12.dp)
      .padding(horizontal = 6.dp, vertical = 4.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    PeriodStep(
      icon = Icons.Filled.ChevronLeft,
      contentDescription = "Previous period",
      enabled = canGoBack,
      onClick = onBack,
    )
    Text(
      text = label,
      style = DimoFont.body(14f, FontWeight.SemiBold),
      color = DimoColors.ink,
      textAlign = TextAlign.Center,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier
        .weight(1f)
        .clickable(enabled = canGoForward, onClick = onReset)
        .padding(vertical = 8.dp),
    )
    PeriodStep(
      icon = Icons.Filled.ChevronRight,
      contentDescription = "Next period",
      enabled = canGoForward,
      onClick = onForward,
    )
  }
}

@Composable
private fun PeriodStep(
  icon: androidx.compose.ui.graphics.vector.ImageVector,
  contentDescription: String,
  enabled: Boolean,
  onClick: () -> Unit,
) {
  Box(
    modifier = Modifier
      .size(32.dp)
      .clip(RoundedCornerShape(9.dp))
      .clickable(enabled = enabled, onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Icon(
      imageVector = icon,
      contentDescription = contentDescription,
      tint = if (enabled) DimoColors.ink else DimoColors.disabled,
      modifier = Modifier.size(18.dp),
    )
  }
}

/** Read-only list of the scoped transactions behind a stats row. */
@Composable
private fun StatsTransactionsSheet(
  store: AppStore,
  title: String,
  transactions: List<Transaction>,
  onClose: () -> Unit,
) {
  val groups = remember(transactions) { TransactionSelectors.groupByDay(transactions) }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(title = title)
    LazyColumn(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 520.dp),
      contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      if (groups.isEmpty()) {
        item("empty") {
          EmptyState(title = "No transactions here")
        }
      }
      groups.forEach { group ->
        item("day-${group.label}") {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(top = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            SectionLabel(group.label, modifier = Modifier.weight(1f))
            Text(
              text = Formatting.spent(group.total, store.currency),
              style = DimoFont.body(12f),
              color = DimoColors.faint,
            )
          }
        }
        items(group.items, key = { "stats-tx-${it.id}" }) { transaction ->
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(14.dp)
              .padding(horizontal = 12.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            CategoryTintView(
              emoji = store.categoryEmoji(
                transaction.emoji,
                transaction.categoryId,
                transaction.category,
              ),
              green = transaction.green,
            )
            Column(
              modifier = Modifier.weight(1f),
              verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
              Text(
                text = transaction.name,
                style = DimoFont.body(15f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
              Text(
                text = listOfNotNull(
                  transaction.category.takeIf { it.isNotEmpty() },
                  transaction.time.takeIf { it.isNotEmpty() },
                ).joinToString(" · "),
                style = DimoFont.body(12f),
                color = DimoColors.muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
              )
            }
            Text(
              text = Formatting.spent(transaction.amount, store.currency),
              style = DimoFont.display(15f, FontWeight.SemiBold),
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
  val scrollState = rememberScrollState()

  // Land on the most recent bar the way the iOS scroll view does.
  LaunchedEffect(bars.bars.size, bars.bars.lastOrNull()?.key) {
    scrollState.scrollTo(scrollState.maxValue)
  }

  Row(
    modifier = modifier
      .fillMaxWidth()
      .horizontalScroll(scrollState),
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
