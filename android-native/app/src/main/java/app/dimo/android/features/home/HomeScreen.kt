package app.dimo.android.features.home

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.Recurring
import app.dimo.android.data.model.Transaction
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.DailyBudgetAllowance
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.Greeting
import app.dimo.android.domain.RecurringSelectors
import app.dimo.android.domain.TransactionFilter
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.CategoryTintView
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.LoadingRow
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
  modifier: Modifier = Modifier,
) {
  var showFilters by remember { mutableStateOf(false) }
  var pageSize by remember { mutableStateOf(TransactionSelectors.HOME_PAGE_SIZE) }
  var selection by remember { mutableStateOf(setOf<String>()) }
  var confirmBulkDelete by remember { mutableStateOf(false) }
  var showUpcoming by remember { mutableStateOf(false) }
  var upcomingShowAll by remember { mutableStateOf(false) }
  val scope = rememberCoroutineScope()

  val filtered = TransactionSelectors.filterTransactions(store.transactions, store.filter)
  val (paged, hasMore) = TransactionSelectors.paginateTransactionsByDay(filtered, pageSize)
  val groups = TransactionSelectors.groupByDay(paged)
  val totals = BudgetSelectors.budgetTotals(store.transactions, store.limits)
  val dailyAllowance = BudgetSelectors.dailyBudgetAllowance(totals)
  val upcomingThisMonth = RecurringSelectors.upcomingBills(store.recurring, store.transactions)
  val upcomingAll = RecurringSelectors.allUpcomingBills(store.recurring, store.transactions)
  val upcomingThisMonthTotal = upcomingTotal(upcomingThisMonth, store)
  val filterActive = store.filter != TransactionFilter()

  Box(modifier = modifier.fillMaxSize()) {
    Column(modifier = Modifier.fillMaxSize()) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .padding(horizontal = ScreenContentPadding)
          .padding(top = 12.dp, bottom = 14.dp),
      ) {
        HomeHeader(
          store = store,
          onOpenSettings = onOpenSettings,
          modifier = Modifier
            .statusBarsPadding()
            .heightIn(min = 56.dp),
        )
        Spacer(modifier = Modifier.height(16.dp))
        HomeHero(
          monthName = LocalDate.now().month.getDisplayName(TextStyle.FULL, Locale.getDefault()),
          totalSpent = totals.totalSpent,
          budgetLeft = totals.left,
          dailyAllowance = dailyAllowance,
          transactionCount = totals.transactionCount,
          store = store,
        )
      }

      LazyColumn(
        modifier = Modifier
          .fillMaxWidth()
          .weight(1f),
        contentPadding = PaddingValues(
          start = ScreenContentPadding,
          end = ScreenContentPadding,
          top = 16.dp,
          bottom = 110.dp,
        ),
      ) {
        store.syncMeta?.error?.let { error ->
          item("sync-error") {
            SyncErrorBanner(error, modifier = Modifier.padding(bottom = 22.dp))
          }
        }

        if (upcomingAll.isNotEmpty()) {
          item("upcoming") {
            UpcomingSummaryRow(
              total = upcomingThisMonthTotal,
              currency = store.currency,
              onClick = {
                upcomingShowAll = false
                showUpcoming = true
              },
              modifier = Modifier.padding(bottom = 22.dp),
            )
          }
        }

        item("transactions-header") {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            SectionTitle("Transactions", modifier = Modifier.weight(1f))
            Box(
              modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(8.dp))
                .clickable { showFilters = true },
              contentAlignment = Alignment.Center,
            ) {
              Icon(
                imageVector = Icons.Filled.FilterList,
                contentDescription = "Filter",
                tint = if (filterActive) DimoColors.green else DimoColors.muted,
                modifier = Modifier.size(18.dp),
              )
            }
          }
        }

        if (filterActive) {
          item("filter-chips") {
            val tags = filterTags(store.filter, store.categories)
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(bottom = 14.dp),
              horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
              tags.forEach { tag ->
                RemovableFilterChip(
                  label = tag.label,
                  onRemove = {
                    store.filter = removeFilterTag(store.filter, tag.id)
                    pageSize = TransactionSelectors.HOME_PAGE_SIZE
                  },
                )
              }
            }
          }
        }

        if (groups.isEmpty()) {
          item("transactions-empty") {
            Text(
              text = "No transactions match.",
              style = DimoFont.body(14f),
              color = DimoColors.faint,
              textAlign = TextAlign.Center,
              modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 48.dp),
            )
          }
        }

        groups.forEach { group ->
          item("day-${group.label}") {
            Column(
              modifier = Modifier.padding(bottom = 18.dp),
              verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
              Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
              ) {
                SectionLabel(
                  group.label.uppercase(Locale.getDefault()),
                  modifier = Modifier.weight(1f),
                )
                Text(
                  text = Formatting.spent(group.total, store.currency),
                  style = DimoFont.body(12f),
                  color = DimoColors.faint,
                )
              }
              group.items.forEach { transaction ->
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
          }
        }

        if (hasMore) {
          item("load-more") {
            // Advancing on composition gives the iOS auto-load behaviour: the row
            // only enters composition once the list is scrolled to it.
            LaunchedEffect(pageSize) {
              val next = minOf(pageSize + TransactionSelectors.HOME_PAGE_SIZE, filtered.size)
              if (next > pageSize) pageSize = next
            }
            LoadingRow()
          }
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
    FilterSheet(
      store = store,
      onApply = { applied ->
        store.filter = applied
        pageSize = TransactionSelectors.HOME_PAGE_SIZE
        showFilters = false
      },
      onClose = { showFilters = false },
    )
  }

  if (showUpcoming) {
    UpcomingBillsSheet(
      store = store,
      thisMonth = upcomingThisMonth,
      all = upcomingAll,
      showAll = upcomingShowAll,
      onShowAllChange = { upcomingShowAll = it },
      onOpenBill = { id ->
        showUpcoming = false
        scope.launch {
          delay(250)
          store.openEditRecurring(id)
        }
      },
      onClose = { showUpcoming = false },
    )
  }
}

/** One active-filter pill; [id] encodes which part of the filter it clears. */
private data class FilterTag(val id: String, val label: String)

private fun filterTags(
  filter: TransactionFilter,
  categories: List<CategoryEntity>,
): List<FilterTag> {
  val tags = mutableListOf<FilterTag>()
  filter.categories.forEach { name ->
    // The default face carries no meaning, so it is dropped from the pill.
    val emoji = categories.firstOrNull { it.name == name }?.emoji?.takeIf { it != "🙂" }
    tags.add(
      FilterTag(
        id = "category:$name",
        label = listOfNotNull(emoji, name).joinToString(" "),
      ),
    )
  }
  if (filter.paymentMethod != "All") {
    tags.add(FilterTag(id = "payment", label = filter.paymentMethod))
  }
  val query = filter.query.trim()
  if (query.isNotEmpty()) {
    tags.add(FilterTag(id = "query", label = "“$query”"))
  }
  if (filter.startDate != null || filter.endDate != null) {
    tags.add(FilterTag(id = "dates", label = dateRangeLabel(filter)))
  }
  return tags
}

private fun dateRangeLabel(filter: TransactionFilter): String {
  val start = filter.startDate?.let { DateHelpers.formatShortMonthDay(it) }
  val end = filter.endDate?.let { DateHelpers.formatShortMonthDay(it) }
  return when {
    start != null && end != null -> if (start == end) start else "$start – $end"
    start != null -> "From $start"
    end != null -> "Until $end"
    else -> ""
  }
}

private fun removeFilterTag(filter: TransactionFilter, tagId: String): TransactionFilter = when {
  tagId == "payment" -> filter.copy(paymentMethod = "All")
  tagId == "query" -> filter.copy(query = "")
  tagId == "dates" -> filter.copy(startDate = null, endDate = null)
  tagId.startsWith("category:") -> {
    val name = tagId.removePrefix("category:")
    filter.copy(categories = filter.categories.filterNot { it == name })
  }
  else -> filter
}

@Composable
private fun RemovableFilterChip(
  label: String,
  onRemove: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .clip(RoundedCornerShape(50))
      .background(DimoColors.greenSoft)
      .padding(start = 12.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(6.dp),
  ) {
    Text(
      text = label,
      style = DimoFont.body(12f, FontWeight.Medium),
      color = DimoColors.greenDeep,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Icon(
      imageVector = Icons.Filled.Close,
      contentDescription = "Remove $label filter",
      tint = DimoColors.greenDeep,
      modifier = Modifier
        .size(18.dp)
        .clip(RoundedCornerShape(50))
        .clickable(onClick = onRemove)
        .padding(3.dp),
    )
  }
}

@Composable
private fun HomeHero(
  monthName: String,
  totalSpent: Double,
  budgetLeft: Double,
  dailyAllowance: DailyBudgetAllowance?,
  transactionCount: Int,
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(20.dp))
      .background(DimoColors.inverse)
      .padding(22.dp),
  ) {
    Text(
      text = "Spent in $monthName",
      style = DimoFont.body(13f),
      color = DimoColors.sideMuted,
      modifier = Modifier.padding(bottom = 8.dp),
    )
    Text(
      text = Formatting.money(totalSpent, store.currency),
      style = DimoFont.display(34f, FontWeight.SemiBold),
      color = DimoColors.sideText,
      modifier = Modifier.padding(bottom = 8.dp),
    )
    Row(
      modifier = Modifier.fillMaxWidth(),
      verticalAlignment = Alignment.Bottom,
      horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      Text(
        text = "$transactionCount transactions",
        style = DimoFont.body(12f),
        color = DimoColors.sideSub,
        modifier = Modifier.weight(1f),
      )
      Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(2.dp),
      ) {
        Text(
          text = "Budget left",
          style = DimoFont.body(11f),
          color = DimoColors.sideMuted,
        )
        Text(
          text = Formatting.money(budgetLeft, store.currency),
          style = DimoFont.display(18f, FontWeight.SemiBold),
          color = if (budgetLeft < 0) DimoColors.danger else DimoColors.greenBright,
        )
      }
    }
    if (dailyAllowance != null) {
      Spacer(modifier = Modifier.height(16.dp))
      Box(
        modifier = Modifier
          .fillMaxWidth()
          .height(1.dp)
          .background(DimoColors.sideText.copy(alpha = 0.12f)),
      )
      Spacer(modifier = Modifier.height(16.dp))
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
          Text(
            text = "Available to spend per day",
            style = DimoFont.body(11f),
            color = DimoColors.sideMuted,
          )
          Text(
            text = if (dailyAllowance.daysRemaining == 1) {
              "Today"
            } else {
              "${dailyAllowance.daysRemaining} days left, including today"
            },
            style = DimoFont.body(10f),
            color = DimoColors.sideSub,
          )
        }
        Row(
          verticalAlignment = Alignment.Bottom,
          horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
          Text(
            text = Formatting.money(dailyAllowance.amount, store.currency),
            style = DimoFont.display(18f, FontWeight.SemiBold),
            color = DimoColors.greenBright,
          )
          Text(
            text = "/ day",
            style = DimoFont.body(10f, FontWeight.Medium),
            color = DimoColors.sideMuted,
            modifier = Modifier.padding(bottom = 2.dp),
          )
        }
      }
    }
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
      .fillMaxWidth(),
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
        text = store.profileName.ifEmpty { "there" },
        style = DimoFont.display(22f, FontWeight.SemiBold),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    AvatarView(
      name = store.profileName.ifEmpty { "there" },
      photoUrl = store.profilePhotoUrl,
      size = 40.dp,
      modifier = Modifier.clickable(onClick = onOpenSettings),
    )
  }
}

@Composable
private fun UpcomingSummaryRow(
  total: Double,
  currency: app.dimo.android.data.model.Currency,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .clickable(onClick = onClick)
      .padding(horizontal = 12.dp, vertical = 11.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Text(
      text = "Upcoming this month",
      style = DimoFont.display(16f, FontWeight.SemiBold),
      color = DimoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Text(
      text = Formatting.money(total, currency),
      style = DimoFont.body(13f, FontWeight.Medium),
      color = DimoColors.muted,
    )
    Icon(
      imageVector = Icons.Filled.ChevronRight,
      contentDescription = null,
      tint = DimoColors.faint,
      modifier = Modifier.size(16.dp),
    )
  }
}

@Composable
private fun UpcomingBillsSheet(
  store: AppStore,
  thisMonth: List<Recurring>,
  all: List<Recurring>,
  showAll: Boolean,
  onShowAllChange: (Boolean) -> Unit,
  onOpenBill: (String) -> Unit,
  onClose: () -> Unit,
) {
  val bills = if (showAll) all else thisMonth
  val canShowAll = all.size > thisMonth.size
  val total = upcomingTotal(bills, store)

  DimoBottomSheet(onDismiss = onClose, containerColor = DimoColors.canvas) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 22.dp)
        .padding(top = 8.dp, bottom = 22.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Text(
        text = if (showAll) "Upcoming" else "Upcoming this month",
        style = DimoFont.display(19f, FontWeight.SemiBold),
        color = DimoColors.ink,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
      )
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
          text = Formatting.money(total, store.currency),
          style = DimoFont.body(13f, FontWeight.Medium),
          color = DimoColors.muted,
        )
        Spacer(modifier = Modifier.weight(1f))
        if (canShowAll || showAll) {
          Text(
            text = if (showAll) "This month" else "Show all (${all.size})",
            style = DimoFont.body(12f, FontWeight.Medium),
            color = DimoColors.green,
            modifier = Modifier
              .clip(RoundedCornerShape(8.dp))
              .clickable { onShowAllChange(!showAll) }
              .padding(horizontal = 4.dp, vertical = 3.dp),
          )
        }
      }

      if (bills.isEmpty()) {
        Text(
          text = "None",
          style = DimoFont.body(14f),
          color = DimoColors.faint,
          textAlign = TextAlign.Center,
          modifier = Modifier
            .fillMaxWidth()
            .cardSurface(14.dp)
            .padding(vertical = 18.dp),
        )
      } else {
        LazyColumn(
          modifier = Modifier
            .fillMaxWidth()
            .height(upcomingListHeight(bills).dp),
          verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          items(bills, key = { "upcoming-${it.id}" }) { bill ->
            UpcomingBillRow(
              store = store,
              bill = bill,
              onClick = { onOpenBill(bill.id) },
            )
          }
        }
      }
    }
  }
}

@Composable
private fun UpcomingBillRow(
  store: AppStore,
  bill: Recurring,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(
        radius = 14.dp,
        background = if (bill.paused) DimoColors.canvasDeep.copy(alpha = 0.7f) else DimoColors.surface,
        borderColor = if (bill.paused) DimoColors.hairline else DimoColors.line,
      )
      .clickable(onClick = onClick)
      .padding(horizontal = 12.dp, vertical = 11.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    CategoryTintView(
      emoji = store.categoryEmoji(bill.emoji, bill.categoryId, bill.category),
      green = bill.green,
      modifier = Modifier.alpha(if (bill.paused) 0.6f else 1f),
    )
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = bill.name,
        style = DimoFont.body(14f, FontWeight.Medium),
        color = if (bill.paused) DimoColors.muted else DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      if (bill.paused) {
        StatusBadge(label = "Paused", tone = StatusBadgeTone.Muted)
      } else {
        Text(
          text = bill.due,
          style = DimoFont.body(12f, if (bill.urgent == true) FontWeight.Medium else FontWeight.Normal),
          color = if (bill.urgent == true) DimoColors.warn else DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
    }
    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
      Text(
        text = Formatting.money(bill.amount, bill.currency ?: store.currency.wire),
        style = DimoFont.display(15f, FontWeight.SemiBold),
        color = if (bill.paused) DimoColors.muted else DimoColors.ink,
      )
      bill.convertedEstimateLabel?.let { estimate ->
        Text(
          text = estimate,
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
    }
  }
}

private fun upcomingTotal(items: List<Recurring>, store: AppStore): Double =
  items.sumOf { bill ->
    if (bill.paused) {
      0.0
    } else {
      ExchangeRates.recurringAmountInDefault(
        bill,
        defaultCurrency = store.currency.wire,
        rates = store.rates,
      )
    }
  }

private fun upcomingListHeight(items: List<Recurring>): Int {
  val rows = items.size * 60
  val spacing = maxOf(0, items.size - 1) * 8
  val estimates = items.count { it.convertedEstimateLabel != null } * 19
  return minOf(rows + spacing + estimates, 460)
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
        background = if (selected) DimoColors.greenSoft.copy(alpha = 0.4f) else DimoColors.surface,
        borderColor = if (selected) DimoColors.green else DimoColors.line,
      )
      .combinedClickable(onClick = onClick, onLongClick = onLongClick)
      .padding(horizontal = 12.dp, vertical = 11.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    if (selectionActive) {
      Box(
        modifier = Modifier
          .size(20.dp)
          .clip(RoundedCornerShape(6.dp))
          .background(if (selected) DimoColors.green else DimoColors.surface)
          .border(
            2.dp,
            if (selected) DimoColors.green else DimoColors.line,
            RoundedCornerShape(6.dp),
          ),
        contentAlignment = Alignment.Center,
      ) {
        if (selected) {
          Icon(
            imageVector = Icons.Filled.Check,
            contentDescription = null,
            tint = DimoColors.onGreen,
            modifier = Modifier.size(10.dp),
          )
        }
      }
    } else {
      CategoryTintView(
        emoji = store.categoryEmoji(transaction.emoji, transaction.categoryId, transaction.category),
        green = transaction.green,
      )
    }
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = transaction.name,
        style = DimoFont.body(14f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = listOf(
          transaction.category,
          transaction.time.uppercase(Locale.getDefault()),
        ).filter { it.isNotEmpty() }.joinToString(" · "),
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

/**
 * Edits a local draft and only writes it back to the store on Apply, so
 * dismissing the sheet abandons the edit. Port of the iOS `FilterSheet`.
 */
@Composable
private fun FilterSheet(
  store: AppStore,
  onApply: (TransactionFilter) -> Unit,
  onClose: () -> Unit,
) {
  var filter by remember { mutableStateOf(store.filter) }
  var dateFilterEnabled by remember {
    mutableStateOf(store.filter.startDate != null || store.filter.endDate != null)
  }
  // Debounced so dragging a date or typing a query does not re-scan the list on
  // every keystroke; the count is advisory, not the applied result.
  var matchCount by remember {
    mutableStateOf(TransactionSelectors.filterTransactions(store.transactions, store.filter).size)
  }
  LaunchedEffect(filter, store.transactions) {
    delay(180)
    matchCount = TransactionSelectors.filterTransactions(store.transactions, filter).size
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
          onValueChange = { filter = filter.copy(query = it) },
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
              filter = filter.copy(startDate = null, endDate = null)
            }
          },
        )
        if (dateFilterEnabled) {
          Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OptionalDateField(
              label = "From",
              date = filter.startDate,
              onChange = { next ->
                // Keep the range ordered the way the iOS pickers clamp it.
                val end = filter.endDate
                filter = filter.copy(
                  startDate = next,
                  endDate = if (next != null && end != null && end < next) next else end,
                )
              },
              modifier = Modifier.weight(1f),
            )
            OptionalDateField(
              label = "To",
              date = filter.endDate,
              onChange = { next ->
                val start = filter.startDate
                filter = filter.copy(
                  startDate = if (next != null && start != null && start > next) next else start,
                  endDate = next,
                )
              },
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
            onChange = { filter = filter.copy(categories = it.toList()) },
          )
        }
      }

      if (store.paymentMethods.any { !it.archived }) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          SectionLabel("Payment methods")
          FilterPaymentDropdown(
            methods = store.paymentMethods.filter { !it.archived },
            selection = filter.paymentMethod,
            onSelect = { filter = filter.copy(paymentMethod = it) },
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
            // Clear commits an empty filter and closes, matching iOS.
            .clickable { onApply(TransactionFilter()) }
            .padding(vertical = 15.dp),
          textAlign = TextAlign.Center,
        )
        Box(modifier = Modifier.weight(1f)) {
          PrimaryButton(title = "Apply", onClick = { onApply(filter) })
        }
      }
      Spacer(modifier = Modifier.height(4.dp))
    }
  }
}
