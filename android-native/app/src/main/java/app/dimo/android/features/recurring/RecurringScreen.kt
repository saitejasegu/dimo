package app.dimo.android.features.recurring

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.RecurringSelectors
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import app.dimo.android.store.OverlayKey

/**
 * Recurring bills. Reachable from Home (not a tab), matching the iOS
 * `RecurringScreen` in `Features/Stats/FeatureScreens.swift`.
 */
@Composable
fun RecurringScreen(
  store: AppStore,
  onBack: () -> Unit,
  modifier: Modifier = Modifier,
) {
  val bills = RecurringSelectors.allUpcomingBills(store.recurring, store.transactions)
  val monthlyTotal = RecurringSelectors.monthlyRecurringTotal(store.recurring) { rec ->
    ExchangeRates.recurringAmountInDefault(rec, store.currency.wire, store.rates)
  }
  val activeCount = RecurringSelectors.activeRecurring(store.recurring).size

  LazyColumn(
    modifier = modifier.fillMaxWidth(),
    contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 8.dp, bottom = 120.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    item("header") {
      ScreenHeader(
        title = "Recurring",
        onBack = onBack,
        modifier = Modifier.statusBarsPadding(),
      )
    }

    store.syncMeta?.error?.let { error ->
      item("sync-error") { SyncErrorBanner(error) }
    }

    item("hero") {
      HeroCard {
        HeroLabel("Monthly commitment")
        HeroAmount(Formatting.money(monthlyTotal, store.currency))
        HeroCaption(
          if (activeCount == 1) "1 active bill" else "$activeCount active bills",
        )
      }
    }

    item("add") {
      Box(modifier = Modifier.fillMaxWidth()) {
        PrimaryButton(
          title = "Add recurring bill",
          onClick = { store.openOverlay(OverlayKey.Recurring) },
        )
      }
    }

    if (bills.isEmpty()) {
      item("empty") {
        DimoCard {
          EmptyState(
            title = "No recurring bills",
            message = "Add rent, subscriptions or utilities and Dimo will track them monthly.",
          )
        }
      }
    } else {
      item("list-label") { SectionLabel("All bills") }
      items(bills, key = { "rec-${it.id}" }) { bill ->
        RecurringRow(store = store, bill = bill)
      }
    }
  }
}

@Composable
private fun RecurringRow(
  store: AppStore,
  bill: Recurring,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .clickable { store.openEditRecurring(bill.id) }
      .padding(horizontal = 14.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    CategoryTintView(
      emoji = store.categoryEmoji(bill.emoji, bill.categoryId, bill.category),
      green = bill.green,
    )
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
          text = bill.name,
          style = DimoFont.body(15f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        if (bill.frequency == RecurringFrequency.YEARLY) {
          StatusBadge(label = "Yearly")
        }
      }
      Text(
        text = RecurringSelectors.recurringSubtitle(bill),
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(
        text = Formatting.money(bill.amount, bill.currency ?: store.currency.wire),
        style = DimoFont.display(15f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
      StatusBadge(
        label = if (bill.paused) "Resume" else "Pause",
        tone = if (bill.paused) StatusBadgeTone.Green else StatusBadgeTone.Muted,
        modifier = Modifier.clickable { store.toggleRecurring(bill.id) },
      )
    }
  }
}
