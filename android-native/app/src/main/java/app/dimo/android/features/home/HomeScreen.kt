package app.dimo.android.features.home

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.Transaction
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.Greeting
import app.dimo.android.domain.RecurringSelectors
import app.dimo.android.domain.TransactionFilter
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.OptionalDateField
import app.dimo.android.features.common.FilterCategoryDropdown
import app.dimo.android.features.common.FilterPaymentDropdown
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SectionTitle
import app.dimo.android.features.common.SettingsToggleRow
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

/**
 * Home / Activity. Port of `ios-native/Dimo/Features/Home/HomeScreen.swift`:
 * greeting header, month hero, upcoming bills entry point, then the filtered
 * activity list with long-press multi-select.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
  store: AppStore,
  onOpenSettings: () -> Unit,
  onOpenRecurring: () -> Unit,
  modifier: Modifier = Modifier,
) {
  var showFilters by remember { mutableStateOf(false) }
  var pageSize by remember { mutableStateOf(TransactionSelectors.HOME_PAGE_SIZE) }
  var selection by remember { mutableStateOf(setOf<String>()) }
  var confirmBulkDelete by remember { mutableStateOf(false) }

  val filtered = TransactionSelectors.filterTransactions(store.transactions, store.filter)
  val (paged, hasMore) = TransactionSelectors.paginateTransactionsByDay(filtered, pageSize)
  val groups = TransactionSelectors.groupByDay(paged)
  val totals = BudgetSelectors.budgetTotals(store.transactions, store.limits)
  val upcoming = RecurringSelectors.upcomingBills(
    store.recurring,
    store.transactions,
    limit = 3,
  )
  val filterActive = store.filter != TransactionFilter()

  Box(modifier = modifier.fillMaxWidth()) {
    LazyColumn(
      modifier = Modifier.fillMaxWidth(),
      contentPadding = PaddingValues(
        start = ScreenContentPadding,
        end = ScreenContentPadding,
        top = 12.dp,
        bottom = 110.dp,
      ),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      item("header") {
        HomeHeader(
          store = store,
          onOpenSettings = onOpenSettings,
          modifier = Modifier.statusBarsPadding(),
        )
      }

      store.syncMeta?.error?.let { error ->
        item("sync-error") { SyncErrorBanner(error) }
      }

      item("hero") {
        HeroCard {
          HeroLabel(
            "Spent in ${
              LocalDate.now().month.getDisplayName(TextStyle.FULL, Locale.getDefault())
            }",
          )
          HeroAmount(Formatting.money(totals.totalSpent, store.currency))
          HeroCaption(
            if (totals.totalLimit > 0) {
              val left = totals.totalLimit - totals.totalSpent
              if (left >= 0) {
                "${Formatting.money(left, store.currency)} left of " +
                  Formatting.money(totals.totalLimit, store.currency)
              } else {
                "${Formatting.money(-left, store.currency)} over budget"
              }
            } else {
              "Set category budgets to track a monthly limit"
            },
          )
        }
      }

      if (upcoming.isNotEmpty()) {
        item("upcoming") {
          UpcomingBillsCard(
            store = store,
            bills = upcoming,
            onOpenRecurring = onOpenRecurring,
          )
        }
      } else {
        item("upcoming-empty") {
          RecurringEntryRow(onOpenRecurring = onOpenRecurring)
        }
      }

      item("activity-header") {
        Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          SectionTitle("Activity", modifier = Modifier.weight(1f))
          if (filterActive) {
            Text(
              text = "Clear",
              style = DimoFont.body(13f, FontWeight.Medium),
              color = DimoColors.green,
              modifier = Modifier.clickable { store.filter = TransactionFilter() },
            )
          }
          Box(
            modifier = Modifier
              .size(36.dp)
              .cardSurface(11.dp, if (filterActive) DimoColors.greenSoft else DimoColors.surface)
              .clickable { showFilters = true },
            contentAlignment = Alignment.Center,
          ) {
            Icon(
              imageVector = Icons.Filled.FilterList,
              contentDescription = "Filters",
              tint = if (filterActive) DimoColors.green else DimoColors.ink,
              modifier = Modifier.size(18.dp),
            )
          }
        }
      }

      if (groups.isEmpty()) {
        item("activity-empty") {
          DimoCard {
            EmptyState(
              title = if (store.transactions.isEmpty()) {
                "No expenses yet"
              } else {
                "Nothing matches these filters"
              },
              message = if (store.transactions.isEmpty()) {
                "Tap + to record your first expense."
              } else {
                "Try widening the date range or clearing filters."
              },
            )
          }
        }
      }

      groups.forEach { group ->
        item("day-${group.label}") {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(top = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            SectionLabel(group.label, modifier = Modifier.weight(1f))
            Text(
              text = Formatting.spent(group.total, store.currency),
              style = DimoFont.body(12f, FontWeight.Medium),
              color = DimoColors.muted,
            )
          }
        }
        items(group.items, key = { "tx-${it.id}" }) { transaction ->
          TransactionRow(
            store = store,
            transaction = transaction,
            selected = selection.contains(transaction.id),
            selectionActive = selection.isNotEmpty(),
            onClick = {
              if (selection.isEmpty()) {
                store.openDetail(transaction.id)
              } else {
                selection = if (selection.contains(transaction.id)) {
                  selection - transaction.id
                } else {
                  selection + transaction.id
                }
              }
            },
            onLongClick = { selection = selection + transaction.id },
          )
        }
      }

      if (hasMore) {
        item("load-more") {
          Text(
            text = "Load more",
            style = DimoFont.body(14f, FontWeight.Medium),
            color = DimoColors.green,
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(12.dp)
              .clickable { pageSize += TransactionSelectors.HOME_PAGE_SIZE }
              .padding(vertical = 14.dp),
          )
        }
      }
    }

    if (selection.isNotEmpty()) {
      SelectionBar(
        count = selection.size,
        onClear = { selection = emptySet() },
        onDelete = { confirmBulkDelete = true },
        modifier = Modifier
          .align(Alignment.BottomCenter)
          .navigationBarsPadding()
          .padding(horizontal = ScreenContentPadding, vertical = 14.dp),
      )
    }
  }

  if (confirmBulkDelete) {
    ConfirmDialog(
      title = if (selection.size == 1) "Delete transaction?" else "Delete ${selection.size} transactions?",
      message = "This cannot be undone.",
      confirmLabel = "Delete",
      onConfirm = {
        store.deleteTransactions(selection.toList())
        selection = emptySet()
      },
      onDismiss = { confirmBulkDelete = false },
    )
  }

  if (showFilters) {
    FilterSheet(store = store, onClose = { showFilters = false })
  }
}

@Composable
private fun HomeHeader(
  store: AppStore,
  onOpenSettings: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = Greeting.greetingFor(),
        style = DimoFont.body(13f),
        color = DimoColors.muted,
      )
      Text(
        text = store.profileName.ifEmpty { "Dimo" },
        style = DimoFont.display(22f, FontWeight.SemiBold),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    AvatarView(
      name = store.profileName.ifEmpty { "D" },
      photoUrl = store.profilePhotoUrl,
      size = 42.dp,
      modifier = Modifier.clickable(onClick = onOpenSettings),
    )
  }
}

@Composable
private fun RecurringEntryRow(onOpenRecurring: () -> Unit, modifier: Modifier = Modifier) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .clickable(onClick = onOpenRecurring)
      .padding(horizontal = 14.dp, vertical = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Box(
      modifier = Modifier
        .size(38.dp)
        .clip(RoundedCornerShape(11.dp))
        .background(DimoColors.canvasDeep),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = Icons.Filled.Autorenew,
        contentDescription = null,
        tint = DimoColors.ink,
        modifier = Modifier.size(18.dp),
      )
    }
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = "Recurring bills",
        style = DimoFont.body(15f, FontWeight.Medium),
        color = DimoColors.ink,
      )
      Text(
        text = "No bills due this month",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
      )
    }
    Text(text = "›", style = DimoFont.display(18f, FontWeight.Medium), color = DimoColors.faint)
  }
}

@Composable
private fun UpcomingBillsCard(
  store: AppStore,
  bills: List<Recurring>,
  onOpenRecurring: () -> Unit,
  modifier: Modifier = Modifier,
) {
  DimoCard(modifier = modifier, verticalSpacing = 10.dp) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      SectionLabel("Upcoming", modifier = Modifier.weight(1f))
      Text(
        text = "See all",
        style = DimoFont.body(12f, FontWeight.Medium),
        color = DimoColors.green,
        modifier = Modifier.clickable(onClick = onOpenRecurring),
      )
    }
    bills.forEach { bill ->
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .clickable { store.openEditRecurring(bill.id) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        CategoryTintView(
          emoji = store.categoryEmoji(bill.emoji, bill.categoryId, bill.category),
          green = bill.green,
          size = 34.dp,
          radius = 10.dp,
          fontSize = 15f,
        )
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
          Text(
            text = bill.name,
            style = DimoFont.body(14f, FontWeight.Medium),
            color = DimoColors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
          Text(
            text = RecurringSelectors.recurringSubtitle(bill),
            style = DimoFont.body(12f),
            color = DimoColors.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
        }
        Text(
          text = Formatting.money(bill.amount, bill.currency ?: store.currency.wire),
          style = DimoFont.display(14f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      }
    }
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TransactionRow(
  store: AppStore,
  transaction: Transaction,
  selected: Boolean,
  selectionActive: Boolean,
  onClick: () -> Unit,
  onLongClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(
        radius = 14.dp,
        background = if (selected) DimoColors.greenSoft else DimoColors.surface,
        borderColor = if (selected) DimoColors.green else DimoColors.line,
      )
      .combinedClickable(onClick = onClick, onLongClick = onLongClick)
      .padding(horizontal = 12.dp, vertical = 11.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    CategoryTintView(
      emoji = store.categoryEmoji(transaction.emoji, transaction.categoryId, transaction.category),
      green = transaction.green,
    )
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
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
          transaction.paymentMethod,
          transaction.time.takeIf { it.isNotEmpty() },
        ).joinToString(" · "),
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Text(
        text = Formatting.spent(transaction.amount, store.currency),
        style = DimoFont.display(15f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
      val source = transaction.sourceAmount
      val sourceCurrency = transaction.sourceCurrency
      if (source != null && sourceCurrency != null) {
        Text(
          text = Formatting.money(source, sourceCurrency),
          style = DimoFont.body(11f),
          color = DimoColors.faint,
        )
      } else if (selectionActive && selected) {
        StatusBadge(label = "Selected", tone = StatusBadgeTone.Green)
      }
    }
  }
}

@Composable
private fun SelectionBar(
  count: Int,
  onClear: () -> Unit,
  onDelete: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.inverse)
      .padding(horizontal = 16.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Icon(
      imageVector = Icons.Filled.Close,
      contentDescription = "Clear selection",
      tint = DimoColors.sideText,
      modifier = Modifier
        .size(20.dp)
        .clickable(onClick = onClear),
    )
    Text(
      text = if (count == 1) "1 selected" else "$count selected",
      style = DimoFont.body(14f, FontWeight.Medium),
      color = DimoColors.sideText,
      modifier = Modifier.weight(1f),
    )
    Text(
      text = "Delete",
      style = DimoFont.body(14f, FontWeight.SemiBold),
      color = DimoColors.dangerHover,
      modifier = Modifier
        .clip(RoundedCornerShape(50))
        .clickable(onClick = onDelete)
        .padding(horizontal = 12.dp, vertical = 6.dp),
    )
  }
}

@Composable
private fun FilterSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val filter = store.filter
  var dateFilterEnabled by remember(filter.startDate, filter.endDate) {
    mutableStateOf(filter.startDate != null || filter.endDate != null)
  }
  val matchCount = remember(filter, store.transactions) {
    TransactionSelectors.filterTransactions(store.transactions, filter).size
  }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(title = "Filter transactions")
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 22.dp)
        .padding(bottom = 22.dp),
      verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("Search")
        DimoTextField(
          value = filter.query,
          onValueChange = { store.filter = filter.copy(query = it) },
          placeholder = "Search merchant or category",
          imeAction = ImeAction.Search,
          textStyle = DimoFont.body(16f),
          leading = {
            Icon(
              imageVector = Icons.Filled.Search,
              contentDescription = null,
              tint = DimoColors.faint,
              modifier = Modifier.size(17.dp),
            )
          },
        )
      }

      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SettingsToggleRow(
          label = "Date range",
          checked = dateFilterEnabled,
          onCheckedChange = { enabled ->
            dateFilterEnabled = enabled
            if (!enabled) {
              store.filter = store.filter.copy(startDate = null, endDate = null)
            }
          },
        )
        if (dateFilterEnabled) {
          Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OptionalDateField(
              label = "From",
              date = filter.startDate,
              onChange = { store.filter = store.filter.copy(startDate = it) },
              modifier = Modifier.weight(1f),
            )
            OptionalDateField(
              label = "To",
              date = filter.endDate,
              onChange = { store.filter = store.filter.copy(endDate = it) },
              modifier = Modifier.weight(1f),
            )
          }
        }
      }

      if (store.categories.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          SectionLabel("Categories")
          FilterCategoryDropdown(
            categories = store.categories,
            selected = filter.categories.toSet(),
            onChange = { store.filter = filter.copy(categories = it.toList()) },
          )
        }
      }

      if (store.paymentMethods.any { !it.archived }) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          SectionLabel("Payment methods")
          FilterPaymentDropdown(
            methods = store.paymentMethods.filter { !it.archived },
            selection = filter.paymentMethod,
            onSelect = { store.filter = filter.copy(paymentMethod = it) },
          )
        }
      }

      Text(
        text = "$matchCount transaction${if (matchCount == 1) "" else "s"} match",
        style = DimoFont.body(13f),
        color = DimoColors.muted,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
      )

      Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
          text = "Clear",
          style = DimoFont.body(15f, FontWeight.SemiBold),
          color = DimoColors.ink,
          modifier = Modifier
            .weight(1f)
            .cardSurface(14.dp, DimoColors.canvas)
            .clickable {
              store.filter = TransactionFilter()
              dateFilterEnabled = false
            }
            .padding(vertical = 15.dp),
          textAlign = TextAlign.Center,
        )
        Box(modifier = Modifier.weight(1f)) {
          PrimaryButton(title = "Apply", onClick = onClose)
        }
      }
      Spacer(modifier = Modifier.height(4.dp))
    }
  }
}
