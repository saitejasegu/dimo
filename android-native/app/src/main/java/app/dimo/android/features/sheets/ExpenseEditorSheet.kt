package app.dimo.android.features.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.design.AmountKeypad
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PaymentMethodField
import app.dimo.android.domain.CurrencyMeta
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.RecurringOccurrenceSelection
import app.dimo.android.domain.TransactionSelectors
import app.dimo.android.features.common.CategoryDropdown
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DateField
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.LabeledDropdown
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.store.AppStore
import app.dimo.android.store.OverlayKey
import java.time.Instant
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
  var includeHistory by remember(transactionId) { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }
  var merchantFocused by remember { mutableStateOf(false) }

  val parsedAmount = amount.toDoubleOrNull() ?: 0.0
  val categoryExists = store.categories.any { it.name == categoryName }
  val recurringNeedsName = frequency != null && name.trim().isEmpty()
  val canSave = parsedAmount > 0 && categoryExists && !recurringNeedsName
  val suggestions = remember(name, store.transactions) {
    TransactionSelectors.merchantSuggestions(store.transactions, name)
  }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(
      title = if (mode == ExpenseEditorMode.Add) "Add expense" else "Edit expense",
      onDelete = if (mode == ExpenseEditorMode.Detail) {
        { confirmDelete = true }
      } else {
        null
      },
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 620.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(top = 10.dp, bottom = 12.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      AmountDisplay(
        amount = amount,
        currencyCode = entryCurrency,
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

      LabeledDropdown(
        label = "Currency",
        options = CurrencyMeta.enterable,
        selected = entryCurrency,
        optionLabel = { code -> "${CurrencyMeta.symbol(code)}  ${CurrencyMeta.label(code)}" },
        onSelect = { entryCurrency = it },
      )

      DateField(
        label = "When",
        millis = dateMillis,
        onChange = { next ->
          dateMillis = next
          if (mode == ExpenseEditorMode.Add) {
            store.expenseDraft = store.expenseDraft.copy(date = Instant.ofEpochMilli(next))
          }
        },
        includeTime = true,
      )

      if (mode == ExpenseEditorMode.Add) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          FieldLabel("Repeat")
          SegmentedControl(
            options = listOf<RecurringFrequency?>(
              null,
              RecurringFrequency.MONTHLY,
              RecurringFrequency.YEARLY,
            ),
            selected = frequency,
            label = { option ->
              when (option) {
                null -> "One-off"
                RecurringFrequency.MONTHLY -> "Monthly"
                RecurringFrequency.YEARLY -> "Yearly"
              }
            },
            onSelect = { frequency = it },
          )
          if (frequency != null) {
            Text(
              text = "Recurring bills need a name.",
              style = DimoFont.body(12f),
              color = if (recurringNeedsName) DimoColors.danger else DimoColors.muted,
            )
            SegmentedControl(
              options = listOf(false, true),
              selected = includeHistory,
              label = { if (it) "Backfill history" else "This occurrence" },
              onSelect = { includeHistory = it },
            )
          }
        }
      }

      if (mode == ExpenseEditorMode.Add) {
        AmountKeypad(
          onPress = { key ->
            store.pressAmountKey(key)
            amount = store.expenseDraft.amount
          },
        )
      } else {
        DimoTextField(
          value = amount,
          onValueChange = { next -> amount = sanitizeDecimal(next) },
          placeholder = "0",
          keyboardType = KeyboardType.Decimal,
        )
      }

      PrimaryButton(
        title = if (mode == ExpenseEditorMode.Add) "Save expense" else "Save changes",
        enabled = canSave,
        onClick = {
          if (mode == ExpenseEditorMode.Add) {
            store.saveExpense(
              name = name,
              amount = parsedAmount,
              categoryName = categoryName,
              paymentMethodId = paymentMethodId,
              date = Instant.ofEpochMilli(dateMillis),
              recurringFrequency = frequency,
              occurrenceSelection = if (includeHistory) {
                RecurringOccurrenceSelection.ALL
              } else {
                RecurringOccurrenceSelection.SELECTED
              },
              entryCurrency = entryCurrency,
            )
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
}

@Composable
private fun AmountDisplay(
  amount: String,
  currencyCode: String,
  convertedCaption: String?,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxWidth()
      .padding(vertical = 4.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(4.dp),
  ) {
    Text(
      text = CurrencyMeta.symbol(currencyCode) + amount.ifEmpty { "0" },
      style = DimoFont.display(44f, FontWeight.Bold),
      color = if (amount.isEmpty()) DimoColors.faint else DimoColors.ink,
      textAlign = TextAlign.Center,
    )
    Text(
      text = convertedCaption.orEmpty(),
      style = DimoFont.body(12f),
      color = DimoColors.muted,
      textAlign = TextAlign.Center,
      modifier = Modifier.height(16.dp),
    )
  }
}

private fun convertedCaption(
  amount: Double,
  from: String,
  to: String,
  store: AppStore,
): String? {
  if (from == to || amount <= 0) return null
  val minor = ExchangeRates.toMinorUnits(amount, from)
  val converted = ExchangeRates.convertMinor(minor, from = from, to = to, rates = store.rates)
    ?: return "Exchange rate unavailable — connect to save"
  return "≈ ${Formatting.money(ExchangeRates.toMajorUnits(converted, to), to)}"
}

private fun formatAmountForEditing(value: Double): String =
  if (value == value.toLong().toDouble()) {
    value.toLong().toString()
  } else {
    String.format(Locale.ROOT, "%.2f", value)
  }
