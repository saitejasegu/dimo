package app.dimo.android.features.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.design.AmountKeypad
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PaymentMethodField
import app.dimo.android.domain.CurrencyMeta
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.RecurringOccurrenceSelection
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.CategoryDropdown
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DateField
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.store.AppStore
import app.dimo.android.store.OverlayKey
import java.time.Instant
import java.time.LocalDate
import java.util.Locale

/** Which flow the expense editor is serving. */
enum class ExpenseEditorMode { Add, Detail }

/**
 * Add-expense and transaction-detail editor. Port of `ExpenseEditorSheet` /
 * `TxDetailSheet` in `ios-native/Dimo/Features/AddExpense/Sheets.swift`.
 */
@Composable
fun ExpenseEditorSheet(
  store: AppStore,
  mode: ExpenseEditorMode,
  onClose: () -> Unit,
  transactionId: String? = null,
  onManagePaymentMethods: (() -> Unit)? = null,
) {
  val existing = transactionId?.let { id -> store.transactions.firstOrNull { it.id == id } }
  if (mode == ExpenseEditorMode.Detail && existing == null) {
    onClose()
    return
  }

  val defaultCurrency = store.currency.wire
  var name by remember(transactionId) { mutableStateOf(existing?.name ?: store.expenseDraft.name) }
  var amount by remember(transactionId) {
    mutableStateOf(
      existing?.let { tx ->
        val value = tx.sourceAmount ?: tx.amount
        formatAmountForEditing(value)
      } ?: store.expenseDraft.amount,
    )
  }
  var categoryName by remember(transactionId) {
    mutableStateOf(existing?.category ?: store.expenseDraft.category)
  }
  var paymentMethodId by remember(transactionId) {
    mutableStateOf(existing?.paymentMethodId ?: store.expenseDraft.paymentMethodId)
  }
  var entryCurrency by remember(transactionId) {
    mutableStateOf(existing?.sourceCurrency ?: existing?.currency ?: defaultCurrency)
  }
  var dateMillis by remember(transactionId) {
    mutableStateOf(
      existing?.occurredAt ?: store.expenseDraft.date.toEpochMilli(),
    )
  }
  var frequency by remember(transactionId) { mutableStateOf<RecurringFrequency?>(null) }
  var confirmDelete by remember { mutableStateOf(false) }
  var showHistoricalPrompt by remember { mutableStateOf(false) }
  var merchantFocused by remember { mutableStateOf(false) }

  val parsedAmount = amount.toDoubleOrNull() ?: 0.0
  val categoryExists = store.categories.any { it.name == categoryName }
  val recurringNeedsName = frequency != null && name.trim().isEmpty()
  val canSave = parsedAmount > 0 && categoryExists && !recurringNeedsName
  val suggestions = remember(name, store.transactions) {
    TransactionSelectors.merchantSuggestions(store.transactions, name)
  }
  val hasPastStartDate = Instant.ofEpochMilli(dateMillis)
    .atZone(DateHelpers.zone())
    .toLocalDate()
    .isBefore(LocalDate.now(DateHelpers.zone()))

  fun saveNew(selection: RecurringOccurrenceSelection) {
    store.saveExpense(
      name = name,
      amount = parsedAmount,
      categoryName = categoryName,
      paymentMethodId = paymentMethodId,
      date = Instant.ofEpochMilli(dateMillis),
      recurringFrequency = frequency,
      occurrenceSelection = selection,
      entryCurrency = entryCurrency,
    )
  }

  DimoBottomSheet(
    onDismiss = onClose,
    compactDragHandle = true,
  ) {
    SheetHeader(
      title = if (mode == ExpenseEditorMode.Add) "Add expense" else "Edit expense",
      compact = true,
      onDelete = if (mode == ExpenseEditorMode.Detail) {
        { confirmDelete = true }
      } else {
        null
      },
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 690.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(top = 10.dp, bottom = 12.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      AmountDisplay(
        amount = amount,
        currencyCode = entryCurrency,
        onCurrencyChange = { entryCurrency = it },
        convertedCaption = convertedCaption(
          amount = parsedAmount,
          from = entryCurrency,
          to = defaultCurrency,
          store = store,
        ),
      )

      Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        DimoTextField(
          value = name,
          onValueChange = { next ->
            name = next
            merchantFocused = true
            if (mode == ExpenseEditorMode.Add) {
              store.expenseDraft = store.expenseDraft.copy(name = next)
            }
          },
          placeholder = "Merchant",
          textStyle = DimoFont.body(16f),
        )
        if (merchantFocused && suggestions.isNotEmpty()) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            suggestions.forEach { suggestion ->
              Chip(
                label = suggestion.name,
                selected = false,
                onClick = {
                  merchantFocused = false
                  name = suggestion.name
                  if (store.categories.any { it.name == suggestion.category }) {
                    categoryName = suggestion.category
                  }
                  val method = store.paymentMethods.firstOrNull {
                    it.name == suggestion.paymentMethod || it.label == suggestion.paymentMethod
                  }
                  if (method != null) paymentMethodId = method.id
                  if (mode == ExpenseEditorMode.Add) {
                    store.expenseDraft = store.expenseDraft.copy(
                      name = suggestion.name,
                      category = categoryName,
                      paymentMethodId = paymentMethodId,
                    )
                  }
                },
              )
            }
          }
        }
      }

      Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
      ) {
        CategoryDropdown(
          categories = store.categories,
          selected = categoryName,
          onSelect = { next ->
            categoryName = next
            if (mode == ExpenseEditorMode.Add) {
              store.expenseDraft = store.expenseDraft.copy(category = next)
            }
          },
          onAdd = { store.openOverlay(OverlayKey.Category) },
          modifier = Modifier.weight(1f),
        )
        PaymentMethodField(
          methods = store.paymentMethods.filter { !it.archived || it.id == paymentMethodId },
          selectedId = paymentMethodId,
          onSelect = { next ->
            paymentMethodId = next
            if (mode == ExpenseEditorMode.Add) {
              store.expenseDraft = store.expenseDraft.copy(paymentMethodId = next)
            }
          },
          onManage = onManagePaymentMethods,
          modifier = Modifier.weight(1f),
        )
      }

      DateField(
        label = "",
        millis = dateMillis,
        onChange = { next ->
          dateMillis = next
          if (mode == ExpenseEditorMode.Add) {
            store.expenseDraft = store.expenseDraft.copy(date = Instant.ofEpochMilli(next))
          }
        },
        includeTime = true,
        compact = true,
      )

      if (mode == ExpenseEditorMode.Add) {
        RecurringControl(
          frequency = frequency,
          onFrequencyChange = { frequency = it },
        )
      }

      AmountKeypad(
        onPress = { key ->
          amount = applyAmountKey(amount, key)
          if (mode == ExpenseEditorMode.Add) {
            store.expenseDraft = store.expenseDraft.copy(amount = amount)
          }
        },
      )

      PrimaryButton(
        title = if (mode == ExpenseEditorMode.Add && frequency != null) {
          "Save recurring expense"
        } else {
          "Save expense"
        },
        enabled = canSave,
        onClick = {
          if (mode == ExpenseEditorMode.Add) {
            if (frequency != null && hasPastStartDate) {
              showHistoricalPrompt = true
            } else {
              saveNew(RecurringOccurrenceSelection.SELECTED)
            }
          } else if (existing != null) {
            store.saveTransactionEdits(
              id = existing.id,
              name = name.trim().ifEmpty { categoryName },
              amount = parsedAmount,
              categoryName = categoryName,
              paymentMethodId = paymentMethodId,
              date = Instant.ofEpochMilli(dateMillis),
              entryCurrency = entryCurrency,
            )
          }
        },
      )
      Spacer(modifier = Modifier.height(4.dp))
    }
  }

  if (confirmDelete && existing != null) {
    ConfirmDialog(
      title = "Delete this expense?",
      message = "${existing.name} · ${Formatting.money(existing.amount, store.currency)}",
      confirmLabel = "Delete",
      onConfirm = { store.deleteTransaction(existing.id) },
      onDismiss = { confirmDelete = false },
    )
  }

  val promptFrequency = frequency
  if (showHistoricalPrompt && promptFrequency != null) {
    val count = DateHelpers.recurringTransactionDates(
      anchorDate = DateHelpers.localDateKey(dateMillis),
      frequency = promptFrequency,
      selection = RecurringOccurrenceSelection.ALL,
    ).size
    AlertDialog(
      onDismissRequest = { showHistoricalPrompt = false },
      containerColor = DimoColors.surface,
      title = {
        Text(
          text = "Add previous transactions?",
          style = DimoFont.display(18f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      },
      text = {
        Text(
          text = "This schedule has $count occurrence${if (count == 1) "" else "s"} through today.",
          style = DimoFont.body(14f),
          color = DimoColors.body,
        )
      },
      confirmButton = {
        Column(horizontalAlignment = Alignment.End) {
          TextButton(
            onClick = {
              showHistoricalPrompt = false
              saveNew(RecurringOccurrenceSelection.ALL)
            },
          ) {
            Text(
              text = "Add all occurrences",
              style = DimoFont.body(15f, FontWeight.SemiBold),
              color = DimoColors.green,
            )
          }
          TextButton(
            onClick = {
              showHistoricalPrompt = false
              saveNew(RecurringOccurrenceSelection.SELECTED)
            },
          ) {
            Text(
              text = "Add only this expense",
              style = DimoFont.body(15f, FontWeight.SemiBold),
              color = DimoColors.green,
            )
          }
        }
      },
      dismissButton = {
        TextButton(onClick = { showHistoricalPrompt = false }) {
          Text(
            text = "Cancel",
            style = DimoFont.body(15f),
            color = DimoColors.muted,
          )
        }
      },
    )
  }
}

@Composable
private fun AmountDisplay(
  amount: String,
  currencyCode: String,
  onCurrencyChange: (String) -> Unit,
  convertedCaption: String?,
  modifier: Modifier = Modifier,
) {
  var currencyExpanded by remember { mutableStateOf(false) }
  Column(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = 4.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(4.dp),
  ) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Box {
        Row(
          modifier = Modifier
            .clip(RoundedCornerShape(10.dp))
            .clickable { currencyExpanded = true }
            .padding(horizontal = 2.dp, vertical = 2.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(1.dp),
        ) {
          Text(
            text = CurrencyMeta.symbol(currencyCode),
            style = DimoFont.display(44f, FontWeight.Bold),
            color = if (amount.isEmpty()) DimoColors.faint else DimoColors.ink,
          )
          Icon(
            imageVector = Icons.Filled.KeyboardArrowDown,
            contentDescription = "Expense currency",
            tint = DimoColors.muted,
            modifier = Modifier.size(16.dp),
          )
        }
        DropdownMenu(
          expanded = currencyExpanded,
          onDismissRequest = { currencyExpanded = false },
        ) {
          CurrencyMeta.enterable.forEach { code ->
            DropdownMenuItem(
              text = {
                Text(
                  text = "${CurrencyMeta.symbol(code)} ${CurrencyMeta.label(code)}",
                  style = DimoFont.body(14f),
                  color = DimoColors.ink,
                )
              },
              trailingIcon = if (code == currencyCode) {
                {
                  Icon(
                    imageVector = Icons.Filled.Check,
                    contentDescription = null,
                    tint = DimoColors.green,
                  )
                }
              } else {
                null
              },
              onClick = {
                onCurrencyChange(code)
                currencyExpanded = false
              },
            )
          }
        }
      }
      Text(
        text = amount.ifEmpty { "0" },
        style = DimoFont.display(44f, FontWeight.Bold),
        color = if (amount.isEmpty()) DimoColors.faint else DimoColors.ink,
        textAlign = TextAlign.Center,
      )
    }
    Text(
      text = convertedCaption.orEmpty(),
      style = DimoFont.body(12f),
      color = if (convertedCaption == "Rates unavailable") DimoColors.danger else DimoColors.muted,
      textAlign = TextAlign.Center,
      modifier = Modifier.height(16.dp),
    )
  }
}

@Composable
private fun RecurringControl(
  frequency: RecurringFrequency?,
  onFrequencyChange: (RecurringFrequency?) -> Unit,
) {
  var frequencyExpanded by remember { mutableStateOf(false) }
  val isRecurring = frequency != null
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .height(50.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(DimoColors.canvas)
      .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
      .padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Box(
      modifier = Modifier
        .size(21.dp)
        .clip(RoundedCornerShape(3.dp))
        .background(if (isRecurring) DimoColors.green else DimoColors.canvas)
        .border(
          2.dp,
          if (isRecurring) DimoColors.green else DimoColors.muted,
          RoundedCornerShape(3.dp),
        )
        .clickable {
          onFrequencyChange(if (isRecurring) null else RecurringFrequency.MONTHLY)
        },
      contentAlignment = Alignment.Center,
    ) {
      if (isRecurring) {
        Icon(
          imageVector = Icons.Filled.Check,
          contentDescription = null,
          tint = DimoColors.onGreen,
          modifier = Modifier.size(15.dp),
        )
      }
    }
    Text(
      text = "Recurring",
      style = DimoFont.body(15f, FontWeight.Medium),
      color = DimoColors.ink,
      modifier = Modifier.clickable {
        onFrequencyChange(if (isRecurring) null else RecurringFrequency.MONTHLY)
      },
    )
    Spacer(modifier = Modifier.weight(1f))
    if (frequency != null) {
      Box {
        Row(
          modifier = Modifier
            .height(36.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(DimoColors.surface)
            .border(1.dp, DimoColors.line, RoundedCornerShape(9.dp))
            .clickable { frequencyExpanded = true }
            .padding(horizontal = 12.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
          Text(
            text = if (frequency == RecurringFrequency.MONTHLY) "Monthly" else "Yearly",
            style = DimoFont.body(14f, FontWeight.SemiBold),
            color = DimoColors.ink,
          )
          Icon(
            imageVector = Icons.Filled.KeyboardArrowDown,
            contentDescription = "Recurring frequency",
            tint = DimoColors.muted,
            modifier = Modifier.size(14.dp),
          )
        }
        DropdownMenu(
          expanded = frequencyExpanded,
          onDismissRequest = { frequencyExpanded = false },
        ) {
          listOf(RecurringFrequency.MONTHLY, RecurringFrequency.YEARLY).forEach { option ->
            DropdownMenuItem(
              text = {
                Text(
                  text = if (option == RecurringFrequency.MONTHLY) "Monthly" else "Yearly",
                  style = DimoFont.body(14f),
                  color = DimoColors.ink,
                )
              },
              onClick = {
                onFrequencyChange(option)
                frequencyExpanded = false
              },
            )
          }
        }
      }
    }
  }
}

private fun convertedCaption(
  amount: Double,
  from: String,
  to: String,
  store: AppStore,
): String? {
  if (from == to || amount <= 0) return null
  val rate = ExchangeRates.rateBetween(from, to, store.rates) ?: return "Rates unavailable"
  val minor = ExchangeRates.toMinorUnits(amount, from)
  val converted = ExchangeRates.convertMinor(minor, from = from, to = to, rates = store.rates)
    ?: return "Rates unavailable"
  val source = Formatting.decimal(amount, maximumFractionDigits = 2)
  val ratio = Formatting.decimal(rate, maximumFractionDigits = 4)
  val convertedAmount = Formatting.money(ExchangeRates.toMajorUnits(converted, to), to)
  return "${CurrencyMeta.symbol(from)}$source × $ratio = $convertedAmount"
}

private fun formatAmountForEditing(value: Double): String =
  if (value == value.toLong().toDouble()) {
    value.toLong().toString()
  } else {
    String.format(Locale.ROOT, "%.2f", value)
  }

private fun applyAmountKey(current: String, key: String): String {
  if (key == "⌫") return if (current.isEmpty()) "" else current.dropLast(1)
  if (key == ".") {
    return when {
      current.contains(".") -> current
      current.isEmpty() -> "0."
      else -> "$current."
    }
  }
  val fractionalCount = current.substringAfter('.', missingDelimiterValue = "").length
  if (current.contains('.') && fractionalCount >= 2) return current
  if (current.count(Char::isDigit) >= 7) return current
  return if (current == "0") key else current + key
}
