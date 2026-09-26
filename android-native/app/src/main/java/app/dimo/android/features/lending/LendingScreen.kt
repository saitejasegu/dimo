package app.dimo.android.features.lending

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.outlined.IosShare
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.runtime.rememberCoroutineScope
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
import app.dimo.android.domain.LendDirection
import app.dimo.android.domain.LendSelectors
import app.dimo.android.data.model.LendActor
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.ContactAvatar
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.EmptyState
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCaption
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.LoadingRow
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.store.AppStore
import app.dimo.android.store.LedgerSharingSheet
import app.dimo.android.sync.IncomingLendInvite
import app.dimo.android.sync.OutgoingLendInvite
import kotlinx.coroutines.launch
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
  var visibleLimit by remember { mutableStateOf(LendSelectors.historyPageSize) }
  val summaries = LendSelectors.contactSummaries(store.lends)
  val totals = LendSelectors.totals(summaries)
  val sharing = store.lendingSharing
  val scope = rememberCoroutineScope()
  fun cancelInvite(invite: OutgoingLendInvite) {
    scope.launch {
      runCatching { sharing.cancel(invite) }
        .onSuccess { store.showToast("Invite cancelled") }
        .onFailure { store.showToast(it.message ?: "Couldn’t cancel the invite") }
    }
  }
  var stopSharingTarget by remember { mutableStateOf<LendContactSummary?>(null) }

  // A fresh section starts at the first page, matching the iOS reset.
  LaunchedEffect(section) { visibleLimit = LendSelectors.historyPageSize }
  LaunchedEffect(Unit) { sharing.refresh() }

  stopSharingTarget?.let { target ->
    ConfirmDialog(
      title = "Stop sharing with ${target.contactName}?",
      message = "You both keep the entries so far, but new changes won\u2019t reach each other.",
      confirmLabel = "Stop sharing",
      onConfirm = {
        stopSharingTarget = null
        scope.launch {
          runCatching { sharing.stopSharing(target.contactId) }
            .onSuccess { store.showToast("Stopped sharing with ${target.contactName}") }
            .onFailure { store.showToast(it.message ?: "Could not stop sharing") }
        }
      },
      onDismiss = { stopSharingTarget = null },
    )
  }

  Column(modifier = modifier.fillMaxWidth()) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = ScreenContentPadding)
        .padding(top = 12.dp, bottom = 14.dp),
    ) {
      ScreenHeader(
        title = "Lending",
        modifier = Modifier.statusBarsPadding(),
      )
      HeroCard(modifier = Modifier.padding(top = 16.dp)) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
          Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            HeroLabel("Owed to me")
            HeroAmount(Formatting.money(totals.owedToMe, store.currency), size = 26f)
          }
          Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            HeroLabel("I owe")
            HeroAmount(Formatting.money(totals.iOwe, store.currency), size = 26f)
          }
        }
        HeroCaption(
          when {
            store.lends.isEmpty() -> "Nothing recorded yet"
            else -> {
              val contactWord = if (summaries.size == 1) "contact" else "contacts"
              val entryWord = if (store.lends.size == 1) "entry" else "entries"
              "${summaries.size} $contactWord · ${store.lends.size} $entryWord"
            }
          },
        )
      }
      SegmentedControl(
        options = LendingSection.entries.toList(),
        selected = section,
        label = { it.title },
        onSelect = { section = it },
        modifier = Modifier.padding(top = 14.dp),
      )
    }

    LazyColumn(
      modifier = Modifier.fillMaxWidth(),
      contentPadding = PaddingValues(
        start = ScreenContentPadding,
        end = ScreenContentPadding,
        top = 16.dp,
        bottom = 110.dp,
      ),
      verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      store.syncMeta?.error?.let { error ->
        item("sync-error") { SyncErrorBanner(error) }
      }
      items(sharing.incomingInvites, key = { "invite-${it.inviteId}" }) { invite ->
        IncomingInviteBanner(
          invite = invite,
          onAccept = { sharing.sheet = LedgerSharingSheet.Accept(invite) },
          onDecline = {
            scope.launch {
              runCatching { sharing.decline(invite) }
                .onSuccess { store.showToast("Invite declined") }
                .onFailure { store.showToast(it.message ?: "Couldn’t decline the invite") }
            }
          },
        )
      }
      if (section == LendingSection.Summary) {
        // Sent invites whose contact has no outstanding balance to show a row for.
        val invitedOnly = sharing.outgoingInvites.filter { invite ->
          summaries.none { it.contactId == invite.contactId }
        }
        items(invitedOnly, key = { "invited-${it.inviteId}" }) { invite ->
          InvitedRow(invite) { cancelInvite(invite) }
        }
      }

      when (section) {
        LendingSection.Summary -> {
          if (store.lends.isEmpty()) {
            item("summary-empty") {
              DimoCard {
                EmptyState(
                  title = "Nothing recorded yet",
                  message = "Tap + to record money you lend or borrow.",
                )
              }
            }
          } else if (summaries.isEmpty()) {
            item("summary-settled") {
              DimoCard {
                EmptyState(
                  title = "All settled",
                  message = "Nothing outstanding either way.",
                )
              }
            }
          } else {
            items(summaries, key = { "contact-${it.contactId}" }) { summary ->
              ContactSummaryRow(
                store = store,
                summary = summary,
                onStopSharing = { stopSharingTarget = summary },
                onCancelInvite = ::cancelInvite,
              )
            }
          }
        }

        LendingSection.Transactions -> {
          val (paged, hasMore) = LendSelectors.paginateByDay(store.lends, visibleLimit)
          val groups = LendSelectors.groupByDay(paged)
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
                SectionLabel(
                  group.label.uppercase(Locale.getDefault()),
                  modifier = Modifier.weight(1f),
                )
                Text(
                  text = Formatting.money(group.total, store.currency),
                  style = DimoFont.body(12f),
                  color = DimoColors.faint,
                )
              }
            }
            items(group.items, key = { "lend-${it.id}" }) { lend ->
              LendRow(
                store = store,
                lend = lend,
              )
            }
          }
          if (hasMore) {
            item("lend-load-more") {
              LaunchedEffect(visibleLimit) {
                val next = minOf(visibleLimit + LendSelectors.historyPageSize, store.lends.size)
                if (next > visibleLimit) visibleLimit = next
              }
              LoadingRow()
            }
          }
        }
      }
    }
  }
}

@Composable
private fun IncomingInviteBanner(
  invite: IncomingLendInvite,
  onAccept: () -> Unit,
  onDecline: () -> Unit,
) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(14.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.green.copy(alpha = 0.5f), RoundedCornerShape(14.dp))
      .padding(12.dp),
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Box(
        modifier = Modifier
          .size(38.dp)
          .clip(RoundedCornerShape(11.dp))
          .background(DimoColors.greenSoft),
        contentAlignment = Alignment.Center,
      ) {
        Icon(Icons.Filled.People, contentDescription = null, tint = DimoColors.green, modifier = Modifier.size(18.dp))
      }
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          text = "${invite.inviterName} wants to share a ledger",
          style = DimoFont.body(14f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        invite.inviterEmail?.let {
          Text(text = it, style = DimoFont.body(12f), color = DimoColors.muted, maxLines = 1)
        }
      }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      InviteAction("Decline", primary = false, modifier = Modifier.weight(1f), onClick = onDecline)
      InviteAction("Accept", primary = true, modifier = Modifier.weight(1f), onClick = onAccept)
    }
  }
}

@Composable
private fun InviteAction(title: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
  Box(
    modifier = modifier
      .height(38.dp)
      .clip(RoundedCornerShape(50))
      .background(if (primary) DimoColors.green else DimoColors.canvas)
      .border(1.dp, if (primary) DimoColors.green else DimoColors.line, RoundedCornerShape(50))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = title,
      style = DimoFont.body(14f, FontWeight.SemiBold),
      color = if (primary) DimoColors.onGreen else DimoColors.ink,
    )
  }
}

@Composable
private fun InvitedRow(invite: OutgoingLendInvite, onCancel: () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .padding(12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    ContactAvatar(name = invite.contactName, size = 38.dp, radius = 11.dp, fontSize = 15f)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = invite.contactName,
        style = DimoFont.body(14f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = "Invited · ${invite.inviteeEmail ?: "waiting for them to accept"}",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Text(
      text = "Cancel",
      style = DimoFont.body(13f, FontWeight.Medium),
      color = DimoColors.muted,
      modifier = Modifier
        .clip(RoundedCornerShape(8.dp))
        .clickable(onClick = onCancel)
        .padding(horizontal = 6.dp, vertical = 4.dp),
    )
  }
}

/** Formats in the entry's own currency when it has one, else the display currency. */
private fun lendMoney(amount: Double, currencyCode: String?, store: AppStore): String =
  if (!currencyCode.isNullOrEmpty()) {
    Formatting.money(amount, currencyCode)
  } else {
    Formatting.money(amount, store.currency)
  }

/** Who recorded or last changed a shared entry, when it was the other person. */
private fun attribution(lend: Lend): String? {
  if (!lend.isShared) return null
  val firstName = lend.contactName.split(" ").firstOrNull()?.takeIf { it.isNotEmpty() } ?: lend.contactName
  return when {
    lend.createdBy == LendActor.CONTACT -> "Added by $firstName"
    lend.lastEditedBy == LendActor.CONTACT -> "Edited by $firstName"
    else -> null
  }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ContactSummaryRow(
  store: AppStore,
  summary: LendContactSummary,
  onStopSharing: () -> Unit,
  onCancelInvite: (OutgoingLendInvite) -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val sharing = store.lendingSharing
  var menuOpen by remember { mutableStateOf(false) }
  val owedToMe = summary.direction == LendDirection.OWED_TO_ME
  val directionLabel = if (owedToMe) "Owes you" else "You owe"
  val entryWord = if (summary.count == 1) "entry" else "entries"
  val lastDay = DateHelpers.formatTransactionDay(summary.lastOccurredAt).lowercase(Locale.getDefault())
  val pendingInvite = sharing.pendingInvite(summary.contactId)
  val sharingLabel = when {
    summary.isShared -> "Shared · "
    pendingInvite != null -> "Invited · "
    else -> ""
  }

  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Row(
      modifier = Modifier
        .weight(1f)
        .combinedClickable(
          onClick = {
            store.openAddSettlement(
              contactName = summary.contactName,
              contactId = summary.contactId,
              direction = summary.direction,
            )
          },
          onLongClick = { menuOpen = true },
        )
        .padding(start = 12.dp, top = 12.dp, bottom = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      ContactAvatar(
        name = summary.contactName,
        size = 38.dp,
        radius = 11.dp,
        fontSize = 15f,
      )
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          text = summary.contactName,
          style = DimoFont.body(14f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          text = "$directionLabel · $sharingLabel${summary.count} $entryWord · last $lastDay",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
      Text(
        text = lendMoney(summary.magnitude, summary.currency, store),
        style = DimoFont.display(15f, FontWeight.SemiBold),
        color = if (owedToMe) DimoColors.ink else DimoColors.danger,
      )
      DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
        if (summary.isShared) {
          if (sharing.activeConnection(summary.contactId) != null) {
            DropdownMenuItem(
              text = { Text("Stop sharing", style = DimoFont.body(14f), color = DimoColors.danger) },
              onClick = {
                menuOpen = false
                onStopSharing()
              },
            )
          }
        } else if (pendingInvite != null) {
          DropdownMenuItem(
            text = { Text("Cancel invite", style = DimoFont.body(14f), color = DimoColors.danger) },
            onClick = {
              menuOpen = false
              onCancelInvite(pendingInvite)
            },
          )
        }
      }
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
        imageVector = Icons.Outlined.IosShare,
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
  val detailBase = lend.comment.ifEmpty { fallbackDetail(lend.kind).orEmpty() }
  val detail = listOfNotNull(
    detailBase.takeIf { it.isNotEmpty() },
    attribution(lend),
    lend.time.takeIf { it.isNotEmpty() }?.uppercase(Locale.getDefault()),
  ).joinToString(" · ")

  Row(
    modifier = modifier
      .fillMaxWidth()
      .cardSurface(14.dp)
      .clickable { store.openEditLend(lend.id) }
      .padding(horizontal = 12.dp, vertical = 11.dp),
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
      if (detail.isNotEmpty()) {
        Text(
          text = detail,
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
      }
    }
    Text(
      text = lendMoney(lend.signedAmount, lend.currency, store),
      style = DimoFont.display(15f, FontWeight.SemiBold),
      color = if (lend.isIncoming) DimoColors.green else DimoColors.ink,
    )
  }
}

/** Stands in for an empty comment so a row still says what it was. */
private fun fallbackDetail(kind: LendKind): String? = when (kind) {
  LendKind.LENT -> null
  LendKind.REPAID -> "Got back"
  LendKind.BORROWED -> "Borrowed"
  LendKind.RETURNED -> "Paid back"
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
    val sign = if (lend.isIncoming) "-" else "+"
    val amount = lendMoney(lend.amount, lend.currency, store)
    val date = Instant.ofEpochMilli(lend.occurredAt).atZone(zone).format(formatter)
    "• $date · $sign$amount"
  }
  val balance = lendMoney(summary.magnitude, summary.currency, store)
  val headline = if (summary.direction == LendDirection.OWED_TO_ME) {
    "Outstanding: $balance"
  } else {
    "I owe you: $balance"
  }
  return buildString {
    append("Hi ${summary.contactName}, here\u2019s our lending summary:\n\n")
    append("$headline\n\n")
    append(lines.joinToString("\n"))
  }
}
