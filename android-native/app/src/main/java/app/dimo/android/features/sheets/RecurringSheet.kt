package app.dimo.android.features.sheets

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PaymentMethodField
import app.dimo.android.domain.CurrencyMeta
import app.dimo.android.domain.DateHelpers
import app.dimo.android.features.common.CategoryDropdown
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DateField
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.LabeledDropdown
import app.dimo.android.features.common.LabeledTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.SettingsToggleRow
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.store.AppStore
import app.dimo.android.store.OverlayKey

/**
 * Create / edit recurring bill. Port of `AddRecurringSheet` in
 * `ios-native/Dimo/Features/AddExpense/Sheets.swift`.
 */
@Composable
fun RecurringSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val draft = store.recurringDraft
  val editingId = draft.editingId
  var includeHistory by remember(editingId) { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }

  val anchorMillis = remember(draft.anchorDate) {
    DateHelpers.startOfDayMillis(DateHelpers.parseLocalDate(draft.anchorDate))
  }
  val amountValue = draft.amount.toDoubleOrNull() ?: 0.0
  val canSave = amountValue > 0 &&
    draft.name.trim().isNotEmpty() &&
    store.categories.any { it.name == draft.category }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(
      title = if (editingId == null) "New recurring bill" else "Edit recurring bill",
      onDelete = if (editingId == null) null else ({ confirmDelete = true }),
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 620.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      LabeledTextField(
        label = "Name",
        value = draft.name,
        onValueChange = { store.recurringDraft = draft.copy(name = it) },
        placeholder = "Rent, Netflix, insurance…",
      )

      LabeledTextField(
        label = "Amount",
        value = draft.amount,
        onValueChange = { next ->
          store.recurringDraft = draft.copy(amount = sanitizeDecimal(next))
        },
        placeholder = "0",
        keyboardType = KeyboardType.Decimal,
      )

      LabeledDropdown(
        label = "Currency",
        options = CurrencyMeta.enterable,
        selected = draft.currency ?: store.currency.wire,
        optionLabel = { code -> "${CurrencyMeta.symbol(code)}  ${CurrencyMeta.label(code)}" },
        onSelect = { store.recurringDraft = draft.copy(currency = it) },
      )

      CategoryDropdown(
        categories = store.categories,
        selected = draft.category.takeIf { name -> store.categories.any { it.name == name } }.orEmpty(),
        onSelect = { store.recurringDraft = draft.copy(category = it) },
        onAdd = { store.openOverlay(OverlayKey.Category) },
      )

      PaymentMethodField(
        methods = store.paymentMethods.filter { !it.archived || it.id == draft.paymentMethodId },
        selectedId = draft.paymentMethodId,
        onSelect = { store.recurringDraft = draft.copy(paymentMethodId = it) },
      )

      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel("Repeats")
        SegmentedControl(
          options = listOf(RecurringFrequency.MONTHLY, RecurringFrequency.YEARLY),
          selected = draft.frequency,
          label = { if (it == RecurringFrequency.MONTHLY) "Monthly" else "Yearly" },
          onSelect = { store.recurringDraft = draft.copy(frequency = it) },
        )
      }

      DateField(
        label = "First charge",
        millis = anchorMillis,
        onChange = { millis ->
          store.recurringDraft = draft.copy(anchorDate = DateHelpers.localDateKey(millis))
        },
        // Bills may start in the future, unlike one-off expenses.
        maxToday = false,
      )

      SettingsToggleRow(
        label = "Paused",
        caption = "Paused bills stay in the list but stop counting towards totals.",
        checked = draft.paused,
        onCheckedChange = { store.recurringDraft = draft.copy(paused = it) },
      )

      if (editingId == null) {
        SettingsToggleRow(
          label = "Backfill past charges",
          caption = "Also create transactions for every occurrence since the first charge.",
          checked = includeHistory,
          onCheckedChange = { includeHistory = it },
        )
      }

      if (store.categories.isEmpty()) {
        Text(
          text = "Create a category before adding a bill.",
          style = DimoFont.body(12f),
          color = DimoColors.danger,
        )
      }

      PrimaryButton(
        title = if (editingId == null) "Add bill" else "Save changes",
        enabled = canSave,
        onClick = { store.saveRecurring(includeHistoricalTransactions = includeHistory) },
      )
      Spacer(modifier = Modifier.height(4.dp))
    }
  }

  if (confirmDelete && editingId != null) {
    ConfirmDialog(
      title = "Delete this bill?",
      message = "${draft.name} will stop being tracked. Past transactions stay.",
      confirmLabel = "Delete",
      onConfirm = { store.deleteRecurring(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}

internal fun sanitizeDecimal(input: String): String {
  val filtered = input.filter { it.isDigit() || it == '.' }
  val firstDot = filtered.indexOf('.')
  if (firstDot < 0) return filtered.take(9)
  val head = filtered.substring(0, firstDot + 1)
  val tail = filtered.substring(firstDot + 1).filter { it.isDigit() }.take(2)
  return (head + tail).take(12)
}
