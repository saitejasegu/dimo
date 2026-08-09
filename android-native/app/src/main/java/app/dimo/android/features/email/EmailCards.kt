package app.dimo.android.features.email

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Currency
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting

/**
 * Ports of `EmailSuggestionCard.swift` and `EmailMessageStatusCard.swift`.
 *
 * Both card types are keyed by the same email id, so the list re-keys itself per
 * filter (see [EmailScreen]) rather than reusing one card's slot for the other.
 */

@Composable
fun EmailSuggestionCard(
  suggestion: EmailUISuggestion,
  activeCurrency: Currency,
  onOpen: () -> Unit,
  onReview: () -> Unit,
  onDismiss: () -> Unit,
  onRestore: (() -> Unit)?,
  onLinkLate: (() -> Unit)?,
  onKeepLateSeparate: (() -> Unit)?,
) {
  EmailCardShell {
    Row(verticalAlignment = Alignment.Top) {
      Column(modifier = Modifier.weight(1f)) {
        Text(
          text = suggestion.merchant?.takeIf { it.isNotBlank() } ?: suggestion.subject,
          style = DimoFont.body(15f, FontWeight.SemiBold),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          text = suggestion.sender,
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
      val amount = suggestion.amount
      if (amount != null) {
        Text(
          text = Formatting.money(
            amount.toDouble(),
            (suggestion.currency ?: activeCurrency).wire,
          ),
          style = DimoFont.display(16f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      StatusBadge(
        label = suggestion.kind.title,
        tone = if (suggestion.kind == EmailUISuggestionKind.REFUND) {
          StatusBadgeTone.Muted
        } else {
          StatusBadgeTone.Green
        },
      )
      StatusBadge(label = suggestion.status.title)
      suggestion.categoryName?.let { StatusBadge(label = it) }
    }

    Text(
      text = DateHelpers.formatTransactionDay(suggestion.occurredAt ?: suggestion.receivedAt),
      style = DimoFont.body(12f),
      color = DimoColors.muted,
    )

    suggestion.currencyWarning?.let { EmailWarningText(it) }
    suggestion.possibleDuplicateDescriptions.takeIf { it.isNotEmpty() }?.let { duplicates ->
      EmailWarningText("Possible duplicate of ${duplicates.joinToString(", ")}")
    }

    // A grouped receipt + bank debit is shown as one expense; name both senders
    // so the pairing is never silent.
    if (suggestion.sourceSenders.size > 1) {
      Text(
        text = "Grouped from ${suggestion.sourceSenders.joinToString(" · ")}",
        style = DimoFont.body(11f),
        color = DimoColors.muted,
      )
    }

    val lateMatch = suggestion.lateMatch
    if (lateMatch != null && onLinkLate != null && onKeepLateSeparate != null) {
      Text(
        text = "This looks like the bank alert for “${lateMatch.transactionName}”.",
        style = DimoFont.body(12f),
        color = DimoColors.body,
      )
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ActionButton(
          title = "Same purchase",
          onClick = onLinkLate,
          modifier = Modifier.weight(1f),
        )
        ActionButton(
          title = "Separate",
          onClick = onKeepLateSeparate,
          modifier = Modifier.weight(1f),
        )
      }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      if (!suggestion.status.isReviewed) {
        ActionButton(
          title = "Review",
          onClick = onReview,
          modifier = Modifier.weight(1f),
          variant = ActionButtonVariant.Accent,
        )
        ActionButton(
          title = "Dismiss",
          onClick = onDismiss,
          modifier = Modifier.weight(1f),
        )
      } else if (onRestore != null) {
        ActionButton(title = "Restore", onClick = onRestore, modifier = Modifier.weight(1f))
      }
      ActionButton(
        title = if (suggestion.actionMessageIds.size > 1) "Emails" else "Email",
        onClick = onOpen,
        modifier = Modifier.weight(1f),
      )
    }

    EmailProvenanceText(suggestion.analyzer, suggestion.modelVersion, suggestion.accountEmail)
  }
}

@Composable
fun EmailMessageStatusCard(
  email: EmailUIMessage,
  onOpen: () -> Unit,
  onRestore: (() -> Unit)?,
  onRetry: (() -> Unit)?,
) {
  EmailCardShell(onClick = onOpen) {
    Text(
      text = email.subject.ifBlank { "(no subject)" },
      style = DimoFont.body(14f, FontWeight.SemiBold),
      color = DimoColors.ink,
      maxLines = 2,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      text = email.sender,
      style = DimoFont.body(12f),
      color = DimoColors.muted,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    if (email.snippet.isNotBlank()) {
      Text(
        text = email.snippet,
        style = DimoFont.body(12f),
        color = DimoColors.body,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
      StatusBadge(
        label = email.analysisState.title,
        tone = if (email.analysisState == EmailUIMessageAnalysisState.FAILED) {
          StatusBadgeTone.Muted
        } else {
          StatusBadgeTone.Green
        },
      )
      email.classification?.let { StatusBadge(label = it.title) }
    }
    Text(
      text = DateHelpers.formatTransactionDay(email.receivedAt),
      style = DimoFont.body(11f),
      color = DimoColors.muted,
    )

    if (onRetry != null || onRestore != null) {
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        onRetry?.let {
          ActionButton(
            title = "Retry analysis",
            onClick = it,
            modifier = Modifier.weight(1f),
            variant = ActionButtonVariant.Accent,
          )
        }
        onRestore?.let {
          ActionButton(title = "Restore", onClick = it, modifier = Modifier.weight(1f))
        }
      }
    }

    EmailProvenanceText(email.analyzer, email.modelVersion, email.accountEmail)
  }
}

@Composable
private fun EmailCardShell(
  onClick: (() -> Unit)? = null,
  content: @Composable () -> Unit,
) {
  Column(
    verticalArrangement = Arrangement.spacedBy(10.dp),
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp))
      .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
      .padding(16.dp),
  ) {
    content()
  }
}

@Composable
private fun EmailWarningText(text: String) {
  Text(text = text, style = DimoFont.body(11f), color = DimoColors.warn)
}

/** Which analyzer produced this row, and which inbox it came from. */
@Composable
private fun EmailProvenanceText(
  analyzer: EmailUIAnalyzer?,
  modelVersion: String?,
  accountEmail: String,
) {
  val provenance = analyzer?.provenanceTitle(modelVersion)
  Text(
    text = listOfNotNull(provenance, accountEmail).joinToString(" · "),
    style = DimoFont.body(10f),
    color = DimoColors.faint,
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
  )
}
