package app.dimo.android.features.lending

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.dimo.android.data.model.SHARED_LEND_CONTACT_PREFIX
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.LendPeople
import app.dimo.android.domain.LendPerson
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.HeroAmount
import app.dimo.android.features.common.HeroCard
import app.dimo.android.features.common.HeroLabel
import app.dimo.android.features.common.ScreenContentPadding
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.store.AppStore
import app.dimo.android.sync.IncomingLendInvite
import kotlinx.coroutines.launch

/**
 * Lending. Port of `ios-native/Dimo/Features/Lending/LendingScreen.swift`.
 *
 * One list of people: those with a balance first, then settled ones. Tapping
 * someone opens their page ([LendPersonSheet]).
 */
@Composable
fun LendingScreen(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  val sharing = store.lendingSharing
  val summaries = LendSelectors.allContactSummaries(store.lends)
  val totals = LendSelectors.totals(summaries.filter { it.magnitude > 0.0001 })
  val people = LendPeople.split(summaries, sharing.outgoingInvites)

  LaunchedEffect(Unit) { sharing.refresh() }

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
      }
    }

    LazyColumn(
      modifier = Modifier.fillMaxWidth(),
      contentPadding = PaddingValues(
        start = ScreenContentPadding,
        end = ScreenContentPadding,
        top = 16.dp,
        // Clears the floating add button overlaying the list's bottom edge.
        bottom = 110.dp,
      ),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      store.syncMeta?.error?.let { error ->
        item("sync-error") { SyncErrorBanner(error) }
      }
      items(sharing.incomingInvites, key = { "invite-${it.inviteId}" }) { invite ->
        IncomingInviteCard(store, invite)
      }
      if (people.active.isNotEmpty()) {
        item("people-active") { PeopleCard(store, people.active) }
      }
      if (people.settled.isNotEmpty()) {
        item("people-settled") {
          Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
              text = "SETTLED",
              style = DimoFont.body(12f, FontWeight.Medium).copy(letterSpacing = 0.8.sp),
              color = DimoColors.muted,
              modifier = Modifier.padding(horizontal = 4.dp),
            )
            PeopleCard(store, people.settled)
          }
        }
      }
      if (people.active.isEmpty() && people.settled.isEmpty()) {
        item("empty") {
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .padding(vertical = 44.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            Text(
              text = "Nothing recorded yet",
              style = DimoFont.body(15f, FontWeight.SemiBold),
              color = DimoColors.ink,
            )
            Text(
              text = "Add an entry when you give or get money. Pick someone on Dimo and you’ll both see it.",
              style = DimoFont.body(13f),
              color = DimoColors.muted,
              textAlign = TextAlign.Center,
            )
          }
        }
      }
    }
  }
}

@Composable
private fun PeopleCard(store: AppStore, people: List<LendPerson>) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp)),
  ) {
    people.forEachIndexed { index, person ->
      if (index > 0) HorizontalDivider(color = DimoColors.line)
      PersonRow(store, person)
    }
  }
}

@Composable
private fun PersonRow(store: AppStore, person: LendPerson) {
  val sharing = store.lendingSharing
  val lastDay = if (person.entryCount > 0) LendPeople.shortDay(person.lastOccurredAt) else null
  var shared = false
  val status = when {
    sharing.pendingInvite(person.contactId) != null -> "Invite pending"
    sharing.activeConnection(person.contactId) != null -> {
      shared = true
      listOfNotNull("Shared", lastDay).joinToString(" · ")
    }
    sharing.stoppedConnection(person.contactId) != null ->
      listOfNotNull("Sharing stopped", lastDay).joinToString(" · ")
    else -> {
      val count = "${person.entryCount} ${if (person.entryCount == 1) "entry" else "entries"}"
      listOfNotNull(count, lastDay).joinToString(" · ")
    }
  }

  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clickable { store.lendPersonId = person.contactId }
      .padding(horizontal = 16.dp, vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    AvatarView(
      name = person.contactName,
      photoUrl = sharing.photoUrl(person.contactId),
      size = 40.dp,
      radius = 12.dp,
      fontSize = 15f,
    )
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = person.contactName,
        style = DimoFont.body(15f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = status,
        style = DimoFont.body(12f),
        color = if (shared) DimoColors.green else DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    if (!person.isSettled) {
      Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          text = lendMoney(kotlin.math.abs(person.balance), person.currency, store),
          style = DimoFont.display(15f, FontWeight.SemiBold),
          color = if (person.balance > 0) DimoColors.green else DimoColors.danger,
        )
        Text(
          text = if (person.balance > 0) "owes you" else "you owe",
          style = DimoFont.body(11f),
          color = DimoColors.faint,
        )
      }
    }
  }
}

/**
 * Someone inviting you to track lending together. Accept is one tap; only
 * when you already track someone by that name are you asked about merging.
 */
@Composable
private fun IncomingInviteCard(store: AppStore, invite: IncomingLendInvite) {
  val sharing = store.lendingSharing
  val scope = rememberCoroutineScope()
  var askMerge by remember { mutableStateOf(false) }
  // A private person you already track under the inviter's name.
  val sameName = run {
    val name = invite.inviterName.trim().lowercase()
    LendSelectors.recentContacts(store.lends, limit = Int.MAX_VALUE).firstOrNull {
      !it.contactId.startsWith(SHARED_LEND_CONTACT_PREFIX) && it.contactName.trim().lowercase() == name
    }
  }

  fun accept(mergeWith: String?) {
    scope.launch {
      runCatching { sharing.accept(invite, mergeWith) }
        .onSuccess { store.showToast("You’re now tracking lending with ${invite.inviterName}") }
        .onFailure { store.showToast(it.message ?: "Couldn’t accept the invite") }
    }
  }

  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp))
      .padding(16.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      AvatarView(
        name = invite.inviterName,
        photoUrl = invite.inviterPhotoUrl,
        size = 40.dp,
        radius = 12.dp,
        fontSize = 15f,
      )
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
          text = invite.inviterName,
          style = DimoFont.body(15f, FontWeight.SemiBold),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          text = if (invite.reconnect) {
            "Wants to share with you again"
          } else {
            "Invited you to track lending together"
          },
          style = DimoFont.body(12f),
          color = DimoColors.muted,
        )
        invite.inviterEmail?.let {
          Text(text = it, style = DimoFont.body(12f), color = DimoColors.faint, maxLines = 1)
        }
      }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      InviteAction("Decline", primary = false, modifier = Modifier.weight(1f)) {
        scope.launch {
          runCatching { sharing.decline(invite) }
            .onSuccess { store.showToast("Invite declined") }
            .onFailure { store.showToast(it.message ?: "Couldn’t decline the invite") }
        }
      }
      InviteAction("Accept", primary = true, modifier = Modifier.weight(1f)) {
        if (sameName != null && !invite.reconnect) askMerge = true else accept(null)
      }
    }
  }

  if (askMerge && sameName != null) {
    MergeDialog(
      name = sameName.contactName,
      onMerge = {
        askMerge = false
        accept(sameName.contactId)
      },
      onKeepSeparate = {
        askMerge = false
        accept(null)
      },
      onDismiss = { askMerge = false },
    )
  }
}

@Composable
private fun MergeDialog(
  name: String,
  onMerge: () -> Unit,
  onKeepSeparate: () -> Unit,
  onDismiss: () -> Unit,
) {
  androidx.compose.material3.AlertDialog(
    onDismissRequest = onDismiss,
    containerColor = DimoColors.surface,
    title = {
      Text(
        text = "Merge with your “$name”?",
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
    },
    text = {
      Text(
        text = "Your entries with them are shared too, so you both see one history.",
        style = DimoFont.body(14f),
        color = DimoColors.body,
      )
    },
    confirmButton = {
      androidx.compose.material3.TextButton(onClick = onMerge) {
        Text("Merge", style = DimoFont.body(14f, FontWeight.SemiBold), color = DimoColors.green)
      }
    },
    dismissButton = {
      androidx.compose.material3.TextButton(onClick = onKeepSeparate) {
        Text("Keep separate", style = DimoFont.body(14f, FontWeight.Medium), color = DimoColors.ink)
      }
    },
  )
}

@Composable
private fun InviteAction(title: String, primary: Boolean, modifier: Modifier, onClick: () -> Unit) {
  Box(
    modifier = modifier
      .height(42.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(if (primary) DimoColors.green else DimoColors.canvas)
      .border(1.dp, if (primary) DimoColors.green else DimoColors.line, RoundedCornerShape(12.dp))
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

/** Formats in the entry's own currency when it has one, else the display currency. */
internal fun lendMoney(amount: Double, currencyCode: String?, store: AppStore): String =
  if (!currencyCode.isNullOrEmpty()) {
    Formatting.money(amount, currencyCode)
  } else {
    Formatting.money(amount, store.currency)
  }
