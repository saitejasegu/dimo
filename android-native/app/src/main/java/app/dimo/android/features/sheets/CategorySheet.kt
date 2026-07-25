package app.dimo.android.features.sheets

import androidx.compose.foundation.background
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
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.BudgetSelectors
import app.dimo.android.domain.Formatting
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.LabeledTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.WrapRow
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import kotlin.math.roundToLong

private val EMOJI_CHOICES = listOf(
  "🙂", "🍽️", "☕", "🛒", "🏠", "💡", "🚕", "🛍️", "🎬", "💊",
  "📚", "🎁", "🧺", "🏋️", "✈️", "🐾", "🎧", "💸", "🧾", "🔁",
)

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

  val suggestion = remember(editingId, store.transactions) {
    editingId?.let { id ->
      val lookback = BudgetSelectors.categoryLookbackSpend(store.transactions, categoryId = id)
      if (lookback.total > 0) lookback.monthlyAverage.roundToLong().toDouble() else null
    }
  }
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
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel("Emoji")
        WrapRow {
          EMOJI_CHOICES.forEach { emoji ->
            EmojiTile(
              emoji = emoji,
              selected = draft.emoji == emoji,
              onClick = { store.categoryDraft = draft.copy(emoji = emoji) },
            )
          }
        }
      }

      LabeledTextField(
        label = "Name",
        value = draft.name,
        onValueChange = { store.categoryDraft = draft.copy(name = it) },
        placeholder = "Groceries",
      )

      LabeledTextField(
        label = "Monthly budget (optional)",
        value = draft.limitText,
        onValueChange = { next ->
          store.categoryDraft = draft.copy(limitText = next.filter { it.isDigit() }.take(9))
        },
        placeholder = "0",
        keyboardType = KeyboardType.Number,
      )

      if (suggestion != null) {
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .cardSurface(12.dp, DimoColors.greenSoft, DimoColors.green)
            .clickable {
              store.categoryDraft = draft.copy(limitText = suggestion.roundToLong().toString())
            }
            .padding(horizontal = 14.dp, vertical = 12.dp),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          Text(
            text = "Suggested: ${Formatting.money(suggestion, store.currency)} / month",
            style = DimoFont.body(13f, FontWeight.Medium),
            color = DimoColors.greenDeep,
            modifier = Modifier.weight(1f),
          )
          Text(
            text = "Use",
            style = DimoFont.body(13f, FontWeight.SemiBold),
            color = DimoColors.greenDeep,
          )
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
        title = if (editingId == null) "Create category" else "Save changes",
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
private fun EmojiTile(
  emoji: String,
  selected: Boolean,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Box(
    modifier = modifier
      .size(44.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(if (selected) DimoColors.greenSoft else DimoColors.canvas)
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Text(text = emoji, style = DimoFont.body(20f))
  }
}
