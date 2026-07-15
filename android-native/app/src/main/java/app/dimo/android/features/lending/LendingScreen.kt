package app.dimo.android.features.lending

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.data.model.LendKind
import app.dimo.android.design.Avatar
import app.dimo.android.design.DimoColors
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.LendSelectors
import app.dimo.android.store.AppStore
import app.dimo.android.store.LendDraft
import app.dimo.android.store.OverlayKey

@Composable
fun LendingScreen(store: AppStore) {
  val state by store.state.collectAsStateWithLifecycle()
  val context = LocalContext.current
  val summaries = remember(state.lends) { LendSelectors.contactSummaries(state.lends) }
  val recent = remember(state.lends) { state.lends.take(20) }
  val totalOutstanding = remember(state.lends) { LendSelectors.totalLent(state.lends).coerceAtLeast(0.0) }

  LazyColumn(
    modifier = Modifier.fillMaxSize(),
    contentPadding = PaddingValues(horizontal = 22.dp, top = 16.dp, bottom = 96.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    item(key = "header") {
      Text("Lending", style = MaterialTheme.typography.titleLarge)
      Spacer(Modifier.height(8.dp))
      Text(
        Formatting.money(totalOutstanding, state.currency),
        style = MaterialTheme.typography.displayLarge,
      )
      Text(
        "Outstanding across contacts",
        style = MaterialTheme.typography.bodyMedium,
        color = DimoColors.mutedLight,
      )
    }

    item(key = "contacts-header") {
      Spacer(Modifier.height(8.dp))
      Text("People", style = MaterialTheme.typography.titleMedium)
    }

    if (summaries.isEmpty()) {
      item(key = "contacts-empty") {
        Text(
          "No open balances. Add a lend to get started.",
          color = DimoColors.mutedLight,
          modifier = Modifier.padding(vertical = 8.dp),
        )
      }
    } else {
      items(summaries, key = { "contact-${it.contactId}" }) { summary ->
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable {
              store.beginAddLend()
              store.updateLendDraft {
                it.copy(
                  contactId = summary.contactId,
                  contactName = summary.contactName,
                  kind = LendKind.lent,
                )
              }
            }
            .padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Avatar(initials = summary.contactName)
          Spacer(Modifier.width(12.dp))
          Column(Modifier.weight(1f)) {
            Text(summary.contactName, fontWeight = FontWeight.SemiBold)
            Text(
              Formatting.money(summary.total, state.currency),
              style = MaterialTheme.typography.bodyMedium,
              color = DimoColors.green,
            )
          }
          TextButton(
            onClick = {
              val contactLends = state.lends.filter { it.contactId == summary.contactId }
              val text = LendSelectors.shareText(
                contactLends,
                summary.contactName,
                Formatting.symbol(state.currency),
              )
              val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
              }
              context.startActivity(Intent.createChooser(intent, "Share unsettled"))
            },
          ) {
            Text("Share")
          }
        }
      }
    }

    item(key = "recent-header") {
      Spacer(Modifier.height(8.dp))
      Text("Recent", style = MaterialTheme.typography.titleMedium)
    }

    if (recent.isEmpty()) {
      item(key = "recent-empty") {
        Text("No lending history yet", color = DimoColors.mutedLight)
      }
    } else {
      items(recent, key = { it.id }) { lend ->
        val signed = LendSelectors.signedAmount(lend)
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surface)
            .clickable {
              store.showOverlay(OverlayKey.lend)
              store.updateLendDraft {
                LendDraft(
                  id = lend.id,
                  contactName = lend.contactName,
                  contactId = lend.contactId,
                  amount = lend.amount.toString(),
                  comment = lend.comment,
                  kind = lend.kind,
                  occurredAt = lend.occurredAt,
                )
              }
            }
            .padding(14.dp),
          verticalAlignment = Alignment.CenterVertically,
        ) {
          Column(Modifier.weight(1f)) {
            Text(lend.contactName, fontWeight = FontWeight.SemiBold)
            Text(
              buildString {
                append(if (lend.kind == LendKind.repaid) "Repaid" else "Lent")
                append(" · ")
                append(DateHelpers.formatTransactionDay(lend.occurredAt))
                if (lend.comment.isNotBlank()) {
                  append(" · ")
                  append(lend.comment)
                }
              },
              style = MaterialTheme.typography.bodyMedium,
              color = DimoColors.mutedLight,
            )
          }
          Text(
            buildString {
              append(if (signed >= 0) "+" else "−")
              append(Formatting.money(kotlin.math.abs(signed), state.currency).removePrefix("−"))
            },
            fontWeight = FontWeight.Medium,
            color = if (signed >= 0) DimoColors.green else MaterialTheme.colorScheme.onSurface,
          )
        }
      }
    }
  }
}
