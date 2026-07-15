package app.dimo.android.features.sheets

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.data.model.LendKind
import app.dimo.android.design.ActionButton
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.features.lending.rememberContactPicker
import app.dimo.android.store.AppStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseEditorSheet(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  val draft = state.expenseDraft
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val methods = state.paymentMethods.filter { !it.archived }

  ModalBottomSheet(
    onDismissRequest = { store.showOverlay(null) },
    sheetState = sheetState,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .imePadding()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp)
        .padding(bottom = 28.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        if (draft.id == null) "Add expense" else "Edit expense",
        style = MaterialTheme.typography.titleLarge,
      )
      OutlinedTextField(
        value = draft.name,
        onValueChange = { value -> store.updateExpenseDraft { it.copy(name = value) } },
        label = { Text("Name") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
      )
      OutlinedTextField(
        value = draft.amount,
        onValueChange = { value -> store.updateExpenseDraft { it.copy(amount = value) } },
        label = { Text("Amount") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
      )
      OutlinedTextField(
        value = draft.category,
        onValueChange = { value -> store.updateExpenseDraft { it.copy(category = value) } },
        label = { Text("Category") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        supportingText = {
          if (state.categories.isNotEmpty()) {
            Text(
              "Suggestions: " + state.categories.take(5).joinToString { it.name },
              color = DimoColors.mutedLight,
            )
          }
        },
      )
      Text("Payment method", style = MaterialTheme.typography.labelLarge)
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        methods.forEach { method ->
          Chip(
            label = method.name,
            selected = draft.paymentMethodId == method.id,
            onClick = { store.updateExpenseDraft { it.copy(paymentMethodId = method.id) } },
          )
        }
      }
      Spacer(Modifier.height(4.dp))
      ActionButton(label = "Save", onClick = { store.saveExpense() })
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CategoryEditorSheet(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  val draft = state.categoryDraft
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

  ModalBottomSheet(
    onDismissRequest = { store.showOverlay(null) },
    sheetState = sheetState,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .imePadding()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp)
        .padding(bottom = 28.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        if (draft.id == null) "Add category" else "Edit category",
        style = MaterialTheme.typography.titleLarge,
      )
      OutlinedTextField(
        value = draft.name,
        onValueChange = { value -> store.updateCategoryDraft { it.copy(name = value) } },
        label = { Text("Name") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
      )
      OutlinedTextField(
        value = draft.emoji,
        onValueChange = { value -> store.updateCategoryDraft { it.copy(emoji = value) } },
        label = { Text("Emoji") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
      )
      OutlinedTextField(
        value = draft.monthlyBudget,
        onValueChange = { value -> store.updateCategoryDraft { it.copy(monthlyBudget = value) } },
        label = { Text("Monthly budget") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
      )
      Spacer(Modifier.height(4.dp))
      ActionButton(label = "Save", onClick = { store.saveCategory() })
      val editingId = draft.id
      if (editingId != null) {
        androidx.compose.material3.TextButton(
          onClick = {
            store.deleteCategoryAndTransactions(editingId)
            store.showOverlay(null)
          },
        ) {
          Text("Delete category", color = MaterialTheme.colorScheme.error)
        }
      }
    }
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LendEditorSheet(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  val draft = state.lendDraft
  val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val pickContact = rememberContactPicker { picked ->
    store.updateLendDraft {
      it.copy(contactId = picked.contactId, contactName = picked.displayName)
    }
  }

  ModalBottomSheet(
    onDismissRequest = { store.showOverlay(null) },
    sheetState = sheetState,
  ) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .navigationBarsPadding()
        .imePadding()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp)
        .padding(bottom = 28.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        if (draft.id == null) "Add lend" else "Edit lend",
        style = MaterialTheme.typography.titleLarge,
      )

      Text(
        "Contacts: photos stay on-device and are never synced.",
        style = MaterialTheme.typography.labelLarge,
        color = DimoColors.mutedLight,
      )
      ActionButton(label = "Pick from contacts", onClick = pickContact)
      OutlinedTextField(
        value = draft.contactName,
        onValueChange = { value -> store.updateLendDraft { it.copy(contactName = value) } },
        label = { Text("Contact name") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
      )
      OutlinedTextField(
        value = draft.contactId,
        onValueChange = { value -> store.updateLendDraft { it.copy(contactId = value) } },
        label = { Text("Contact ID") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        supportingText = {
          Text("Grouped by contactId, never display name alone.")
        },
      )
      OutlinedTextField(
        value = draft.amount,
        onValueChange = { value -> store.updateLendDraft { it.copy(amount = value) } },
        label = { Text("Amount") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
      )
      Text("Kind", style = MaterialTheme.typography.labelLarge)
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(
          label = "Lent",
          selected = draft.kind == LendKind.lent,
          onClick = { store.updateLendDraft { it.copy(kind = LendKind.lent) } },
        )
        Chip(
          label = "Repaid",
          selected = draft.kind == LendKind.repaid,
          onClick = { store.updateLendDraft { it.copy(kind = LendKind.repaid) } },
        )
      }
      OutlinedTextField(
        value = draft.comment,
        onValueChange = { value -> store.updateLendDraft { it.copy(comment = value) } },
        label = { Text("Comment") },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
      )
      Spacer(Modifier.height(4.dp))
      ActionButton(
        label = "Save",
        onClick = {
          if (draft.contactId.isBlank() && draft.contactName.isNotBlank()) {
            store.updateLendDraft {
              it.copy(contactId = "manual-${it.contactName.trim().lowercase()}")
            }
          }
          store.saveLend()
        },
      )
    }
  }
}
