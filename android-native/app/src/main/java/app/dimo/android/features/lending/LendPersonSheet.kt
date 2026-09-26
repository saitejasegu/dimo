package app.dimo.android.features.lending

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.Lend
import app.dimo.android.data.model.LendActor
import app.dimo.android.data.model.SHARED_LEND_CONTACT_PREFIX
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.LendFlow
import app.dimo.android.domain.LendPeople
import app.dimo.android.domain.LendPerson
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.sheets.LendResultRow
import app.dimo.android.features.sheets.lendRelationLabel
import app.dimo.android.store.AppStore
import app.dimo.android.sync.LendUser
import app.dimo.android.sync.OutgoingLendInvite
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs

/**
 * One person: their balance, "I gave / I got", their history, and sharing
 * controls. The header stays put while the history scrolls. Port of
 * `ios-native/Dimo/Features/Lending/LendPersonSheet.swift`.
 */
@Composable
fun LendPersonSheet(store: AppStore, contactId: String) {
  val sharing = store.lendingSharing
  val person = LendPeople.split(LendSelectors.allContactSummaries(store.lends), sharing.outgoingInvites)
    .all
    .firstOrNull { it.contactId == contactId }
  if (person == null) {
    // The person went away (last entry deleted, invite cancelled).
    LaunchedEffect(contactId) { store.lendPersonId = null }
    return
  }
  val entries = store.lends.filter { it.contactId == contactId }.sortedByDescending { it.occurredAt }
  val pending = sharing.pendingInvite(contactId)
  val connected = sharing.activeConnection(contactId) != null
  val stopped = !connected && sharing.stoppedConnection(contactId) != null

  val scope = rememberCoroutineScope()
  var confirmStop by remember { mutableStateOf(false) }
  var cancelTarget by remember { mutableStateOf<OutgoingLendInvite?>(null) }
  var linking by remember { mutableStateOf(false) }

  DimoBottomSheet(onDismiss = { store.lendPersonId = null }, compactDragHandle = true) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 680.dp)
        .padding(horizontal = 20.dp)
        .padding(top = 8.dp, bottom = 16.dp),
      verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
      Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
          text = person.contactName,
          style = DimoFont.display(20f, FontWeight.SemiBold),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
          modifier = Modifier.weight(1f),
        )
        MoreMenu(
          store = store,
          person = person,
          canShare = entries.isNotEmpty(),
          connected = connected,
          onStopSharing = { confirmStop = true },
        )
      }

      PersonHeader(store, person, pending = pending != null, connected = connected, stopped = stopped)

      Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        // The direction that settles the balance is highlighted.
        val settles = when {
          person.isSettled -> null
          person.balance > 0 -> LendFlow.GOT
          else -> LendFlow.GAVE
        }
        LendFlow.entries.forEach { flow ->
          FlowButton(
            title = if (flow == LendFlow.GAVE) "I gave" else "I got",
            primary = settles == flow,
            modifier = Modifier.weight(1f),
          ) { store.openAddLend(person.contactName, contactId, flow) }
        }
      }

      if (entries.isEmpty()) {
        Text(
          text = "No entries yet.",
          style = DimoFont.body(13f),
          color = DimoColors.muted,
          textAlign = TextAlign.Center,
          modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        )
      } else {
        LazyColumn(
          modifier = Modifier
            .weight(1f, fill = false)
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(DimoColors.surface)
            .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp)),
        ) {
          itemsIndexed(entries, key = { _, lend -> lend.id }) { index, lend ->
            if (index > 0) HorizontalDivider(color = DimoColors.line)
            EntryRow(store, lend)
          }
        }
      }

      when {
        connected -> Unit
        pending != null -> Text(
          text = "Cancel invite",
          style = DimoFont.body(13f, FontWeight.Medium),
          color = DimoColors.muted,
          textAlign = TextAlign.Center,
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .clickable { cancelTarget = pending }
            .padding(vertical = 6.dp),
        )
        stopped -> PromptCard(
          text = "Changes no longer reach ${person.contactName}. Share again to bring both sides back in step.",
          action = "Share again",
        ) {
          scope.launch {
            runCatching { sharing.shareAgain(contactId) }
              .onSuccess { store.showToast("Invite sent to ${person.contactName}") }
              .onFailure { store.showToast(it.message ?: "Couldn’t send the invite") }
          }
        }
        !contactId.startsWith(SHARED_LEND_CONTACT_PREFIX) -> PromptCard(
          text = "Is ${person.contactName} on Dimo? Link them and you’ll both see this history.",
          action = "Link to Dimo account",
        ) { linking = true }
      }
    }
  }

  if (confirmStop) {
    ConfirmDialog(
      title = "Stop sharing with ${person.contactName}?",
      message = "You both keep the entries so far, but new changes won’t reach each other.",
      confirmLabel = "Stop sharing",
      onConfirm = {
        confirmStop = false
        scope.launch {
          runCatching { sharing.stopSharing(contactId) }
            .onSuccess { store.showToast("Stopped sharing with ${person.contactName}") }
            .onFailure { store.showToast(it.message ?: "Couldn’t stop sharing") }
        }
      },
      onDismiss = { confirmStop = false },
    )
  }

  cancelTarget?.let { invite ->
    ConfirmDialog(
      title = "Cancel invite to ${person.contactName}?",
      message = "They won’t be able to accept it. Your entries with them stay on your side only.",
      confirmLabel = "Cancel invite",
      onConfirm = {
        cancelTarget = null
        scope.launch {
          runCatching { sharing.cancel(invite) }
            .onSuccess { store.showToast("Invite cancelled") }
            .onFailure { store.showToast(it.message ?: "Couldn’t cancel the invite") }
        }
      },
      onDismiss = { cancelTarget = null },
    )
  }

  if (linking) {
    LinkAccountSheet(store, person, onClose = { linking = false })
  }
}

@Composable
private fun MoreMenu(
  store: AppStore,
  person: LendPerson,
  canShare: Boolean,
  connected: Boolean,
  onStopSharing: () -> Unit,
) {
  if (!canShare && !connected) return
  val context = LocalContext.current
  var open by remember { mutableStateOf(false) }
  Box {
    Box(
      modifier = Modifier
        .size(40.dp)
        .clip(RoundedCornerShape(12.dp))
        .clickable { open = true },
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = Icons.Filled.MoreHoriz,
        contentDescription = "More options for ${person.contactName}",
        tint = DimoColors.muted,
      )
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
      if (canShare) {
        DropdownMenuItem(
          text = { Text("Share summary", style = DimoFont.body(14f), color = DimoColors.ink) },
          onClick = {
            open = false
            val intent = Intent(Intent.ACTION_SEND).apply {
              type = "text/plain"
              putExtra(Intent.EXTRA_TEXT, shareText(store, person))
            }
            context.startActivity(Intent.createChooser(intent, null))
          },
        )
      }
      if (connected) {
        DropdownMenuItem(
          text = { Text("Stop sharing", style = DimoFont.body(14f), color = DimoColors.danger) },
          onClick = {
            open = false
            onStopSharing()
          },
        )
      }
    }
  }
}

@Composable
private fun PersonHeader(
  store: AppStore,
  person: LendPerson,
  pending: Boolean,
  connected: Boolean,
  stopped: Boolean,
) {
  val status = when {
    connected -> "Shared"
    pending -> "Invite pending"
    stopped -> "Sharing stopped"
    else -> null
  }
  val subtitle = if (person.isSettled) {
    status ?: "Nothing owed either way"
  } else {
    listOfNotNull(if (person.balance > 0) "Owes you" else "You owe", status).joinToString(" · ")
  }
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    AvatarView(
      name = person.contactName,
      photoUrl = store.lendingSharing.photoUrl(person.contactId),
      size = 52.dp,
      radius = 15.dp,
      fontSize = 19f,
    )
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = if (person.isSettled) "All settled" else lendMoney(abs(person.balance), person.currency, store),
        style = DimoFont.display(26f, FontWeight.SemiBold),
        color = when {
          person.isSettled -> DimoColors.muted
          person.balance > 0 -> DimoColors.green
          else -> DimoColors.danger
        },
        maxLines = 1,
      )
      Text(text = subtitle, style = DimoFont.body(12f), color = DimoColors.muted)
    }
  }
}

@Composable
private fun FlowButton(title: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
  Box(
    modifier = modifier
      .height(46.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(if (primary) DimoColors.green else DimoColors.canvas)
      .border(1.dp, if (primary) DimoColors.green else DimoColors.line, RoundedCornerShape(12.dp))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = title,
      style = DimoFont.body(15f, FontWeight.SemiBold),
      color = if (primary) DimoColors.onGreen else DimoColors.ink,
    )
  }
}

@Composable
private fun EntryRow(store: AppStore, lend: Lend) {
  val got = LendFlow.of(lend.kind) == LendFlow.GOT
  val flowLabel = if (got) "You got" else "You gave"
  val note = lend.comment.trim()
  val detail = listOfNotNull(
    flowLabel.takeIf { note.isNotEmpty() },
    LendPeople.shortDay(lend.occurredAt),
    attribution(lend),
  ).joinToString(" · ")
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable { store.openEditLend(lend.id) }
      .padding(horizontal = 16.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = note.ifEmpty { flowLabel },
        style = DimoFont.body(15f),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = detail,
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Text(
      text = lendMoney(lend.amount, lend.currency, store),
      style = DimoFont.display(15f, FontWeight.SemiBold),
      color = if (got) DimoColors.green else DimoColors.danger,
    )
  }
}

@Composable
private fun PromptCard(text: String, action: String, onClick: () -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.canvas)
      .padding(14.dp),
    horizontalAlignment = Alignment.CenterHorizontally,
    verticalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    Text(
      text = text,
      style = DimoFont.body(13f),
      color = DimoColors.muted,
      textAlign = TextAlign.Center,
    )
    Box(
      modifier = Modifier
        .height(40.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(DimoColors.surface)
        .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
        .clickable(onClick = onClick)
        .padding(horizontal = 18.dp),
      contentAlignment = Alignment.Center,
    ) {
      Text(text = action, style = DimoFont.body(14f, FontWeight.SemiBold), color = DimoColors.ink)
    }
  }
}

/**
 * Finds the Dimo account for someone already tracked and invites them for
 * this person, so accepting shares the existing history.
 */
@Composable
private fun LinkAccountSheet(store: AppStore, person: LendPerson, onClose: () -> Unit) {
  val sharing = store.lendingSharing
  val scope = rememberCoroutineScope()
  var query by remember { mutableStateOf(person.contactName) }
  var results by remember { mutableStateOf<Pair<String, List<LendUser>>?>(null) }
  var sending by remember { mutableStateOf(false) }
  val trimmed = query.trim()
  val users = results?.takeIf { it.first == trimmed }?.second

  LaunchedEffect(trimmed) {
    if (trimmed.length < 2) return@LaunchedEffect
    delay(250)
    runCatching { sharing.searchUsers(trimmed) }.onSuccess { results = trimmed to it }
  }

  fun link(user: LendUser) {
    when (user.relation) {
      "connected" -> return store.showToast("You already share with ${user.name}")
      "invitedYou" -> return store.showToast("${user.name} already invited you. Accept their invite first.")
    }
    if (sending) return
    sending = true
    scope.launch {
      runCatching { sharing.sendInvite(user, person.contactId, user.name) }
        .onSuccess {
          // They're known by their account name, even before accepting.
          store.renameLendContact(person.contactId, user.name)
          store.showToast("Invite sent to ${user.name}")
          onClose()
        }
        .onFailure { store.showToast(it.message ?: "Couldn’t send the invite") }
      sending = false
    }
  }

  DimoBottomSheet(onDismiss = onClose, compactDragHandle = true) {
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 20.dp)
        .padding(top = 8.dp, bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Text(
        text = "Link to Dimo account",
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
      )
      Text(
        text = "Find ${person.contactName} on Dimo. Once they accept, your entries with them are shared " +
          "and either of you can add or edit them.",
        style = DimoFont.body(13f),
        color = DimoColors.muted,
      )
      DimoTextField(value = query, onValueChange = { query = it }, placeholder = "Name or email")
      if (!users.isNullOrEmpty()) {
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(DimoColors.canvas)
            .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp)),
        ) {
          users.forEachIndexed { index, user ->
            if (index > 0) HorizontalDivider(color = DimoColors.line)
            LendResultRow(
              name = user.name,
              detail = user.email,
              photoUrl = user.photoUrl,
              badge = if (user.relation == "none") "Link" else lendRelationLabel(user),
              badgeTint = DimoColors.green,
              onClick = { link(user) },
            )
          }
        }
      } else if (users != null) {
        Text(
          text = "No one on Dimo matches “$trimmed”.",
          style = DimoFont.body(13f),
          color = DimoColors.muted,
        )
      }
    }
  }
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

/**
 * Plain-text summary of the current unsettled cycle, byte-compatible with the
 * iOS share sheet: no comments, `+`/`-` amounts, `dd-MMM-yyyy` dates.
 */
private fun shareText(store: AppStore, person: LendPerson): String {
  val formatter = DateTimeFormatter.ofPattern("dd-MMM-yyyy", Locale.US)
  val zone = DateHelpers.zone()
  val lines = LendSelectors.unsettledTransactions(person.contactId, store.lends).map { lend ->
    val sign = if (lend.isIncoming) "-" else "+"
    val date = Instant.ofEpochMilli(lend.occurredAt).atZone(zone).format(formatter)
    "• $date · $sign${lendMoney(lend.amount, lend.currency, store)}"
  }
  val balance = lendMoney(abs(person.balance), person.currency, store)
  val headline = when {
    person.isSettled -> "All settled"
    person.balance > 0 -> "Outstanding: $balance"
    else -> "I owe you: $balance"
  }
  return buildString {
    append("Hi ${person.contactName}, here’s our lending summary:\n\n")
    append("$headline\n\n")
    append(lines.joinToString("\n"))
  }
}
