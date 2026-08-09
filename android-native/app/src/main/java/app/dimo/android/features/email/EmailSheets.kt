package app.dimo.android.features.email

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.SheetContainer
import app.dimo.android.design.StatusBadge
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting

/**
 * Ports of `EmailDetailSheet`, `SourceEmailsSheet`, `EmailSuggestionReview` and
 * `RefundReviewSheet` from `ios-native/Dimo/Features/Email/`.
 */

@Composable
fun EmailDetailSheet(detail: EmailUIEmailDetail, onClose: () -> Unit) {
  SheetContainer(title = "Email", onClose = onClose) {
    Column(
      verticalArrangement = Arrangement.spacedBy(12.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 560.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      EmailDetailContent(detail)
      ActionButton(title = "Close", onClick = onClose)
    }
  }
}

/** Shared body used by the single-email sheet and each page of the sources sheet. */
@Composable
fun EmailDetailContent(detail: EmailUIEmailDetail) {
  Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
    Text(
      text = detail.subject.ifBlank { "(no subject)" },
      style = DimoFont.display(17f, FontWeight.SemiBold),
      color = DimoColors.ink,
    )
    Text(
      text = "${detail.sender} · ${detail.senderAddress}",
      style = DimoFont.body(12f),
      color = DimoColors.muted,
    )
    Text(
      text = DateHelpers.formatTransactionDay(detail.receivedAt) + " · " +
        DateHelpers.formatTransactionTime(detail.receivedAt),
      style = DimoFont.body(11f),
      color = DimoColors.faint,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      StatusBadge(label = detail.analysisState.title)
      detail.classification?.let { StatusBadge(label = it.title) }
    }
    detail.analyzer?.let {
      Text(
        text = it.provenanceTitle(detail.modelVersion),
        style = DimoFont.body(11f),
        color = DimoColors.faint,
      )
    }
    Text(
      text = detail.bodyText.ifBlank { "This email's text is no longer stored on this device." },
      style = DimoFont.body(13f),
      color = DimoColors.body,
      modifier = Modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(12.dp))
        .background(DimoColors.canvasDeep)
        .padding(12.dp),
    )
    if (!detail.isBodyRetained) {
      // Retention drops the body once a row is compacted; only the snippet is left.
      Text(
        text = "Only the preview is kept for this email.",
        style = DimoFont.body(11f),
        color = DimoColors.muted,
      )
    }
  }
}

@Composable
fun SourceEmailsSheet(
  presentation: EmailUISourceEmailsPresentation,
  onClose: () -> Unit,
  onShowSeparately: (() -> Unit)?,
) {
  val title = if (presentation.emails.size == 1) "Source email" else "Source emails"
  SheetContainer(title = title, onClose = onClose) {
    Column(
      verticalArrangement = Arrangement.spacedBy(16.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 560.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      presentation.emails.forEach { detail ->
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .border(1.dp, DimoColors.line, RoundedCornerShape(14.dp))
            .padding(14.dp),
        ) {
          EmailDetailContent(detail)
        }
      }
      if (onShowSeparately != null) {
        ActionButton(title = "These are separate purchases", onClick = onShowSeparately)
      }
      ActionButton(title = "Close", onClick = onClose)
    }
  }
}

@Composable
fun EmailPurchaseReviewSheet(
  store: EmailFeatureStore,
  draft: EmailUIPurchaseReviewDraft,
  onClose: () -> Unit,
) {
  var working by remember(draft.suggestionId) { mutableStateOf(draft) }
  SheetContainer(title = "Review purchase", onClose = onClose) {
    Column(
      verticalArrangement = Arrangement.spacedBy(14.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 620.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      EmailLabeledField("Merchant", working.merchant) { working = working.copy(merchant = it) }
      EmailLabeledField("Amount", working.amount) { working = working.copy(amount = it) }

      working.currencyWarning?.let {
        Text(text = it, style = DimoFont.body(11f), color = DimoColors.warn)
      }
      if (working.possibleDuplicateDescriptions.isNotEmpty()) {
        Text(
          text = "Possible duplicate of " +
            working.possibleDuplicateDescriptions.joinToString(", "),
          style = DimoFont.body(11f),
          color = DimoColors.warn,
        )
      }

      EmailSectionLabel("Category")
      EmailChipRow(
        options = store.categories.map { it.id to "${it.emoji} ${it.name}" },
        selectedId = working.categoryId,
        onSelect = { working = working.copy(categoryId = it) },
      )

      EmailSectionLabel("Payment method")
      EmailChipRow(
        options = store.paymentMethods.filter { !it.archived }.map { it.id to it.label },
        selectedId = working.paymentMethodId,
        onSelect = { working = working.copy(paymentMethodId = it) },
      )

      EmailSectionLabel("Also track as a recurring bill")
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(
          label = "One-off",
          selected = !working.isRecurring,
          onClick = { working = working.copy(isRecurring = false) },
        )
        Chip(
          label = "Monthly",
          selected = working.isRecurring &&
            working.recurringFrequency == RecurringFrequency.MONTHLY,
          onClick = {
            working = working.copy(
              isRecurring = true,
              recurringFrequency = RecurringFrequency.MONTHLY,
            )
          },
        )
        Chip(
          label = "Yearly",
          selected = working.isRecurring &&
            working.recurringFrequency == RecurringFrequency.YEARLY,
          onClick = {
            working = working.copy(
              isRecurring = true,
              recurringFrequency = RecurringFrequency.YEARLY,
            )
          },
        )
      }

      Text(
        text = DateHelpers.formatTransactionDay(working.occurredAt) +
          " · ${working.accountEmail}",
        style = DimoFont.body(11f),
        color = DimoColors.faint,
      )

      ActionButton(
        title = "Add expense",
        onClick = { store.acceptPurchase(working) },
        variant = ActionButtonVariant.Accent,
        enabled = working.categoryId != null && working.amount.isNotBlank(),
      )
      ActionButton(title = "Cancel", onClick = onClose)
    }
  }
}

@Composable
fun RefundReviewSheet(
  review: EmailUIRefundReview,
  activeCurrency: Currency,
  onCancel: () -> Unit,
  onMarkReviewed: (EmailUIRefundReview) -> Unit,
  onConfirm: (EmailUIRefundReview) -> Unit,
) {
  var working by remember(review.suggestionId) { mutableStateOf(review) }
  SheetContainer(title = "Review refund", onClose = onCancel) {
    Column(
      verticalArrangement = Arrangement.spacedBy(14.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 560.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      Text(
        text = working.merchant,
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
      working.amount?.let {
        Text(
          text = Formatting.money(it.toDouble(), (working.currency ?: activeCurrency).wire),
          style = DimoFont.display(22f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      }

      if (!working.isFullRefund) {
        // Deleting the expense would be wrong for a partial credit, so only the
        // "mark reviewed" path is offered.
        Text(
          text = "This looks like a partial refund. Dimo only removes an expense for an " +
            "exact, full refund — adjust the original expense yourself if needed.",
          style = DimoFont.body(12f),
          color = DimoColors.warn,
        )
      } else if (working.candidates.isEmpty()) {
        Text(
          text = "No matching expense was found within 120 days at this exact amount and " +
            "currency.",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
        )
      } else {
        EmailSectionLabel("Remove which expense?")
        working.candidates.forEach { candidate ->
          val selected = working.selectedTransactionId == candidate.id
          Column(
            verticalArrangement = Arrangement.spacedBy(2.dp),
            modifier = Modifier
              .fillMaxWidth()
              .clip(RoundedCornerShape(12.dp))
              .background(if (selected) DimoColors.greenSoft else DimoColors.canvasDeep)
              .border(
                1.dp,
                if (selected) DimoColors.green else DimoColors.line,
                RoundedCornerShape(12.dp),
              )
              .clickable { working = working.copy(selectedTransactionId = candidate.id) }
              .padding(12.dp),
          ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
              Text(
                text = candidate.merchant,
                style = DimoFont.body(14f, FontWeight.Medium),
                color = DimoColors.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
              )
              Text(
                text = Formatting.money(candidate.amount.toDouble(), candidate.currency.wire),
                style = DimoFont.body(14f, FontWeight.SemiBold),
                color = DimoColors.ink,
              )
            }
            Text(
              text = listOfNotNull(
                DateHelpers.formatTransactionDay(candidate.occurredAt),
                candidate.categoryName,
                candidate.paymentMethodLabel,
              ).joinToString(" · "),
              style = DimoFont.body(11f),
              color = DimoColors.muted,
            )
            candidate.matchReason?.let {
              Text(text = it, style = DimoFont.body(10f), color = DimoColors.faint)
            }
          }
        }
      }

      if (working.isFullRefund && working.candidates.isNotEmpty()) {
        ActionButton(
          title = "Remove expense",
          onClick = { onConfirm(working) },
          variant = ActionButtonVariant.Danger,
          enabled = working.selectedTransactionId != null,
        )
      }
      ActionButton(title = "Mark reviewed", onClick = { onMarkReviewed(working) })
      ActionButton(title = "Cancel", onClick = onCancel)
    }
  }
}

// MARK: - Small shared pieces

@Composable
internal fun EmailSectionLabel(text: String) {
  Text(
    text = text.uppercase(),
    style = DimoFont.body(11f, FontWeight.Medium),
    color = DimoColors.muted,
  )
}

@Composable
private fun EmailLabeledField(
  label: String,
  value: String,
  onChange: (String) -> Unit,
) {
  Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
    EmailSectionLabel(label)
    androidx.compose.material3.OutlinedTextField(
      value = value,
      onValueChange = onChange,
      singleLine = true,
      textStyle = DimoFont.body(15f),
      modifier = Modifier.fillMaxWidth(),
    )
  }
}

/** Horizontal wrap of selectable chips; `null` id means "no selection". */
@Composable
private fun EmailChipRow(
  options: List<Pair<String, String>>,
  selectedId: String?,
  onSelect: (String) -> Unit,
) {
  LazyColumn(
    verticalArrangement = Arrangement.spacedBy(6.dp),
    modifier = Modifier.heightIn(max = 168.dp),
  ) {
    items(options, key = { it.first }) { (id, label) ->
      Chip(
        label = label,
        selected = selectedId == id,
        onClick = { onSelect(id) },
        modifier = Modifier.fillMaxWidth(),
      )
    }
  }
}
