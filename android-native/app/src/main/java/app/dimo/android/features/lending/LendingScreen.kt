package app.dimo.android.features.lending

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Lend
import app.dimo.android.data.model.LendKind
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.LendContactSummary
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.ContactAvatar
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
private enum class LendingSection(val title: String) {
  Summary("Summary"),
  Transactions("Transactions"),
}

/**
 * Lending. Port of `ios-native/Dimo/Features/Lending/LendingScreen.swift`.
 *
 * Groups by address-book `contactId` through `LendSelectors`; the share action
 * sends the current unsettled cycle as plain text.
 */
@Composable
fun LendingScreen(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  var section by remember { mutableStateOf(LendingSection.Summary) }
  val summaries = LendSelectors.contactSummaries(store.lends)
  val outstanding = LendSelectors.totalLent(store.lends)

  LazyColumn(
    modifier = modifier.fillMaxWidth(),
    contentPadding = PaddingValues(start = 18.dp, end = 18.dp, top = 8.dp, bottom = 120.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    item("header") {
      ScreenHeader(title = "Lending", modifier = Modifier.statusBarsPadding())
    }

    store.syncMeta?.error?.let { error ->
      item("sync-error") { SyncErrorBanner(error) }
    }

    item("hero") {
      HeroCard {
        HeroLabel("Outstanding")
        HeroAmount(Formatting.money(outstanding, store.currency))
        HeroCaption(
          when {
            summaries.isEmpty() -> "Everyone is settled up"
            summaries.size == 1 -> "1 person owes you"
            else -> "${summaries.size} people owe you"
          },
        )
      }
    }

    item("section") {
      SegmentedControl(
        options = LendingSection.entries.toList(),
        selected = section,
        label = { it.title },
        onSelect = { section = it },
      )
    }

    when (section) {
      LendingSection.Summary -> {
        if (summaries.isEmpty()) {
          item("summary-empty") {
            DimoCard {
              EmptyState(
                title = "Nothing outstanding",
                message = "Tap + to record money you lent someone.",
              )
            }
          }
        } else {
          items(summaries, key = { "contact-${it.contactId}" }) { summary ->
            ContactSummaryRow(store = store, summary = summary)
          }
        }
      }

      LendingSection.Transactions -> {
        val groups = LendSelectors.groupByDay(store.lends)
        if (groups.isEmpty()) {
          item("tx-empty") {
            DimoCard {
              EmptyState(title = "No lending history yet")
            }
          }
        }
        groups.forEach { group ->
          item("lend-day-${group.label}") {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
              verticalAlignment = Alignment.CenterVertically,
            ) {
              SectionLabel(group.label, modifier = Modifier.weight(1f))
              Text(
                text = Formatting.money(group.total, store.currency),
                style = DimoFont.body(12f, FontWeight.Medium),
                color = DimoColors.faint,
              )
            }
          }
          items(group.items, key = { "lend-${it.id}" }) { lend ->
            LendRow(store = store, lend = lend)
          }
        }
      }
    }
  }
}

@Composable
private fun ContactSummaryRow(
  store: AppStore,
  summary: LendContactSummary,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Row(
      modifier = Modifier
        .weight(1f)
        .clickable {
          store.openAddRepayment(
            contactName = summary.contactName,
            contactId = summary.contactId,
          )
        }
        .padding(start = 14.dp, top = 12.dp, bottom = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      ContactAvatar(name = summary.contactName)
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
          text = summary.contactName,
          style = DimoFont.body(15f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          text = if (summary.count == 1) "1 entry" else "${summary.count} entries",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
        )
      }
      Text(
        text = Formatting.money(summary.total, store.currency),
        style = DimoFont.display(15f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
    }
    Box(
      modifier = Modifier
        .size(48.dp)
        .clickable {
          val message = shareText(store, summary)
          val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, message)
          }
          context.startActivity(Intent.createChooser(intent, null))
        },
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = Icons.Filled.Share,
        contentDescription = "Share lending summary with ${summary.contactName}",
        tint = DimoColors.green,
        modifier = Modifier.size(18.dp),
      )
    }
  }
}

@Composable
private fun LendRow(
  store: AppStore,
  lend: Lend,
  modifier: Modifier = Modifier,
) {
  val repaid = lend.kind == LendKind.REPAID
  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .clickable { store.openEditLend(lend.id) }
      .padding(horizontal = 14.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    ContactAvatar(name = lend.contactName, size = 38.dp, radius = 11.dp)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
      Text(
        text = lend.contactName,
        style = DimoFont.body(15f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = listOfNotNull(
          lend.comment.ifEmpty { if (repaid) "Got back" else "" }.takeIf { it.isNotEmpty() },
          lend.time.takeIf { it.isNotEmpty() },
        ).joinToString(" · "),
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Text(
      text = Formatting.money(lend.signedAmount, store.currency),
      style = DimoFont.display(15f, FontWeight.SemiBold),
      color = if (repaid) DimoColors.green else DimoColors.ink,
    )
  }
}

/**
 * Plain-text summary shared through `Intent.ACTION_SEND`, byte-compatible with
 * the iOS share sheet: current unsettled cycle only, no comments, `+`/`-`
 * amounts, `dd-MMM-yyyy` dates.
 */
private fun shareText(store: AppStore, summary: LendContactSummary): String {
  val formatter = DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.US)
  val zone = DateHelpers.zone()
  val lines = LendSelectors.unsettledTransactions(summary.contactId, store.lends).map { lend ->
    val sign = if (lend.kind == LendKind.REPAID) "-" else "+"
    val amount = Formatting.money(lend.amount, store.currency)
    val date = Instant.ofEpochMilli(lend.occurredAt).atZone(zone).format(formatter)
    "• $date · $sign$amount"
  }
  return buildString {
    append("Hi ${summary.contactName}, here\u2019s our lending summary:\n\n")
    append("Outstanding: ${Formatting.money(summary.total, store.currency)}\n\n")
    append(lines.joinToString("\n"))
  }
}
