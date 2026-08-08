package app.dimo.android.features.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.Formatting
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.WrapRow
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import kotlin.math.roundToLong

private val BUDGET_PRESETS = listOf(1000, 2500, 5000, 10000)

/**
 * Create / edit category. Port of `NewCategorySheet` in
 * `ios-native/Dimo/Features/AddExpense/Sheets.swift`.
 */
@Composable
fun CategorySheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val draft = store.categoryDraft
  val editingId = draft.editingId
  var confirmDelete by remember { mutableStateOf(false) }

  val lookback = remember(editingId, store.transactions) {
    editingId?.let { id ->
      BudgetSelectors.categoryLookbackSpend(store.transactions, categoryId = id)
        .takeIf { it.total > 0 }
    }
  }
  val suggestion = lookback?.monthlyAverage?.roundToLong()?.toDouble()
  val canSave = draft.name.trim().isNotEmpty()

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(
      title = if (editingId == null) "New category" else "Edit category",
      onDelete = if (editingId == null) null else ({ confirmDelete = true }),
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 560.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp)
        .padding(bottom = 22.dp),
      verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel("Name")
        Row(
          horizontalArrangement = Arrangement.spacedBy(10.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          BasicTextField(
            value = draft.emoji,
            onValueChange = { next ->
              // Keep a single grapheme-ish emoji entry, matching the iOS 50×50 well.
              store.categoryDraft = draft.copy(emoji = next.take(4).ifEmpty { "🙂" })
            },
            singleLine = true,
            textStyle = DimoFont.body(22f).copy(
              color = DimoColors.ink,
              textAlign = TextAlign.Center,
            ),
            cursorBrush = SolidColor(DimoColors.green),
            modifier = Modifier
              .size(50.dp)
              .clip(RoundedCornerShape(12.dp))
              .background(DimoColors.canvas)
              .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
              .padding(horizontal = 4.dp),
            decorationBox = { inner ->
              Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxWidth()) {
                inner()
              }
            },
          )
          DimoTextField(
            value = draft.name,
            onValueChange = { store.categoryDraft = draft.copy(name = it) },
            placeholder = "e.g. Pets, Travel, Health",
            modifier = Modifier.weight(1f),
          )
        }
      }

      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel("Monthly budget (optional)")
        if (lookback != null) {
          Text(
            text = "${Formatting.money(lookback.total, store.currency)} spent over the last 6 months",
            style = DimoFont.body(12f),
            color = DimoColors.faint,
          )
        }
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .height(50.dp)
            .cardSurface(12.dp, DimoColors.canvas)
            .padding(horizontal = 14.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          Text(
            text = Formatting.currencySymbol(store.currency),
            style = DimoFont.body(16f),
            color = DimoColors.muted,
          )
          BasicTextField(
            value = draft.limitText,
            onValueChange = { next ->
              store.categoryDraft = draft.copy(limitText = next.filter { it.isDigit() }.take(9))
            },
            singleLine = true,
            textStyle = DimoFont.body(15f).copy(color = DimoColors.ink),
            cursorBrush = SolidColor(DimoColors.green),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.weight(1f),
            decorationBox = { inner ->
              Box {
                if (draft.limitText.isEmpty()) {
                  Text(text = "Amount", style = DimoFont.body(15f), color = DimoColors.faint)
                }
                inner()
              }
            },
          )
        }

        WrapRow {
          if (suggestion != null) {
            BudgetPresetChip(
              label = Formatting.money(suggestion, store.currency),
              suggested = true,
              onClick = {
                store.categoryDraft = draft.copy(limitText = suggestion.roundToLong().toString())
              },
            )
          }
          BUDGET_PRESETS.forEach { amount ->
            BudgetPresetChip(
              label = Formatting.money(amount.toDouble(), store.currency),
              suggested = false,
              onClick = {
                store.categoryDraft = draft.copy(limitText = amount.toString())
              },
            )
          }
        }
      }

      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("Tint")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
          Chip(
            label = "Neutral",
            selected = draft.tint == CategoryTint.NEUTRAL,
            onClick = { store.categoryDraft = draft.copy(tint = CategoryTint.NEUTRAL) },
          )
          Chip(
            label = "Green",
            selected = draft.tint == CategoryTint.GREEN,
            onClick = { store.categoryDraft = draft.copy(tint = CategoryTint.GREEN) },
          )
        }
      }

      PrimaryButton(
        title = if (editingId == null) "Create category" else "Save category",
        enabled = canSave,
        onClick = { store.saveCategory() },
      )
      Spacer(modifier = Modifier.height(4.dp))
    }
  }

  if (confirmDelete && editingId != null) {
    val linked = store.transactions.count { it.categoryId == editingId }
    ConfirmDialog(
      title = "Delete ${draft.name}?",
      message = if (linked == 0) {
        "This category has no transactions."
      } else {
        val suffix = if (linked == 1) "" else "s"
        "$linked transaction$suffix in this category will also be deleted."
      },
      confirmLabel = "Delete",
      onConfirm = { store.deleteCategoryAndTransactions(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}

@Composable
private fun BudgetPresetChip(
  label: String,
  suggested: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Row(
    modifier = modifier
      .height(38.dp)
      .clip(RoundedCornerShape(50))
      .background(if (suggested) DimoColors.ink else DimoColors.canvas)
      .then(
        if (suggested) Modifier else Modifier.border(1.dp, DimoColors.line, RoundedCornerShape(50)),
      )
      .clickable(onClick = onClick)
      .padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(7.dp),
  ) {
    Text(
      text = label,
      style = DimoFont.body(12f, if (suggested) FontWeight.SemiBold else FontWeight.Medium),
      color = if (suggested) DimoColors.canvas else DimoColors.muted,
    )
    if (suggested) {
      Text(
        text = "SUGGESTED",
        style = DimoFont.body(9f, FontWeight.SemiBold),
        color = DimoColors.canvas,
        modifier = Modifier
          .clip(RoundedCornerShape(50))
          .background(DimoColors.canvas.copy(alpha = 0.2f))
          .padding(horizontal = 7.dp, vertical = 4.dp),
      )
    }
  }
}
