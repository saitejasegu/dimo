package app.dimo.android.features.home

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material3.TextButton
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
import app.dimo.android.data.model.Currency
import app.dimo.android.design.ActionButton
import app.dimo.android.design.Avatar
import app.dimo.android.design.DimoColors
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.RecurringSelectors
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.store.AppStore
import app.dimo.android.store.UiRecurring
import app.dimo.android.store.UiTransaction

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  var selectedIds by remember { mutableStateOf(setOf<String>()) }
  val selecting = selectedIds.isNotEmpty()

  val filtered = remember(state.transactions, state.filter) {
    TransactionSelectors.filterTransactions(state.transactions, state.filter)
  }
  val (visible, hasMore) = remember(filtered, state.homeVisibleCount) {
    TransactionSelectors.paginateTransactionsByDay(filtered, state.homeVisibleCount)
  }
  val dayGroups = remember(visible) { TransactionSelectors.groupByDay(visible) }
  val upcoming = remember(state.recurring) {
    RecurringSelectors.upcomingBills(state.recurring, limit = 3)
  }
  val initials = state.profileName
    .split(" ")
    .mapNotNull { it.firstOrNull()?.toString() }
    .take(2)
    .joinToString("")
    .ifBlank { "DU" }

  Column(Modifier.fillMaxSize()) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 22.dp, vertical = 16.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Column(Modifier.weight(1f)) {
        Text(
          state.greeting,
          style = MaterialTheme.typography.titleLarge,
          color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
          if (state.profileName.isBlank()) "Your spending" else state.profileName,
          style = MaterialTheme.typography.bodyMedium,
          color = DimoColors.mutedLight,
        )
      }
      if (selecting) {
        TextButton(onClick = {
          store.deleteTransactions(selectedIds)
          selectedIds = emptySet()
        }) {
          Text("Delete (${selectedIds.size})", color = MaterialTheme.colorScheme.error)
        }
        TextButton(onClick = { selectedIds = emptySet() }) {
          Text("Cancel")
        }
      } else {
        Avatar(
          initials = initials,
          modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .combinedClickable(onClick = { store.openSettings() }),
        )
      }
    }

    LazyColumn(
      modifier = Modifier.fillMaxSize(),
      contentPadding = PaddingValues(horizontal = 22.dp, bottom = 96.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      if (upcoming.isNotEmpty()) {
        item(key = "upcoming-header") {
          Text(
            "Upcoming bills",
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 4.dp, bottom = 4.dp),
          )
        }
        items(upcoming, key = { "bill-${it.id}" }) { bill ->
          UpcomingBillRow(bill = bill, currency = state.currency)
        }
        item(key = "activity-header") {
          Spacer(Modifier.height(12.dp))
          Text("Activity", style = MaterialTheme.typography.titleMedium)
        }
      }

      if (dayGroups.isEmpty()) {
        item(key = "empty") {
          Text(
            "No transactions yet",
            style = MaterialTheme.typography.bodyLarge,
            color = DimoColors.mutedLight,
            modifier = Modifier.padding(vertical = 24.dp),
          )
        }
      } else {
        dayGroups.forEach { group ->
          item(key = "day-${group.label}") {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp, bottom = 4.dp),
              horizontalArrangement = Arrangement.SpaceBetween,
            ) {
              Text(group.label, style = MaterialTheme.typography.labelLarge)
              Text(
                Formatting.money(group.total, state.currency),
                style = MaterialTheme.typography.labelLarge,
              )
            }
          }
          items(group.items, key = { it.id }) { tx ->
            TransactionRow(
              tx = tx,
              currency = state.currency,
              selected = tx.id in selectedIds,
              selecting = selecting,
              onClick = {
                if (selecting) {
                  selectedIds =
                    if (tx.id in selectedIds) selectedIds - tx.id else selectedIds + tx.id
                } else {
                  store.beginEditTransaction(tx)
                }
              },
              onLongClick = {
                selectedIds =
                  if (tx.id in selectedIds) selectedIds - tx.id else selectedIds + tx.id
              },
            )
          }
        }
      }

      if (hasMore) {
        item(key = "load-more") {
          Spacer(Modifier.height(8.dp))
          ActionButton(label = "Load more", onClick = { store.loadMoreHome() })
        }
      }
    }
  }
}

@Composable
private fun UpcomingBillRow(bill: UiRecurring, currency: Currency) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(14.dp))
      .background(MaterialTheme.colorScheme.surface)
      .padding(14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(bill.emoji)
    Spacer(Modifier.width(10.dp))
    Column(Modifier.weight(1f)) {
      Text(bill.name, fontWeight = FontWeight.SemiBold)
      Text(
        RecurringSelectors.recurringSubtitle(bill),
        style = MaterialTheme.typography.bodyMedium,
        color = DimoColors.mutedLight,
      )
    }
    Text(Formatting.money(bill.amount, currency), fontWeight = FontWeight.Medium)
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TransactionRow(
  tx: UiTransaction,
  currency: Currency,
  selected: Boolean,
  selecting: Boolean,
  onClick: () -> Unit,
  onLongClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(14.dp))
      .background(
        if (selected) DimoColors.greenSoft else MaterialTheme.colorScheme.surface,
      )
      .combinedClickable(onClick = onClick, onLongClick = onLongClick)
      .padding(14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(tx.emoji)
    Spacer(Modifier.width(10.dp))
    Column(Modifier.weight(1f)) {
      Text(tx.name, fontWeight = FontWeight.SemiBold)
      Text(
        buildString {
          append(tx.category)
          tx.paymentMethod?.let {
            append(" · ")
            append(it)
          }
          if (selecting && selected) append(" · selected")
        },
        style = MaterialTheme.typography.bodyMedium,
        color = DimoColors.mutedLight,
      )
    }
    Text(Formatting.spent(tx.amount, currency), fontWeight = FontWeight.Medium)
  }
}
