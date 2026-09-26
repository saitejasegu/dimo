package app.dimo.android.features.lending

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.SHARED_LEND_CONTACT_PREFIX
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.LendContactSuggestion
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.store.AppStore
import app.dimo.android.store.LedgerSharingSheet
import app.dimo.android.sync.IncomingLendInvite
import app.dimo.android.sync.LendHistoryChoice
import kotlinx.coroutines.launch

/** Hosts whichever sharing sheet is open. Port of the iOS tab-shell sheet. */
@Composable
fun LedgerSharingSheetHost(store: AppStore) {
  when (val sheet = store.lendingSharing.sheet) {
    is LedgerSharingSheet.Accept -> AcceptInviteSheet(store, sheet.invite)
    null -> Unit
  }
}

/** Existing, not-yet-shared lending contacts whose history can come along. */
private fun shareableContacts(store: AppStore): List<LendContactSuggestion> =
  LendSelectors.recentContacts(store.lends, limit = 20)
    .filterNot { it.contactId.startsWith(SHARED_LEND_CONTACT_PREFIX) }

/**
 * Accepts or declines an invite, optionally linking a contact already tracked
 * here so its history joins the shared ledger.
 */
@Composable
private fun AcceptInviteSheet(store: AppStore, invite: IncomingLendInvite) {
  val sharing = store.lendingSharing
  val scope = rememberCoroutineScope()
  var linkedContactId by remember { mutableStateOf<String?>(null) }
  var contactName by remember { mutableStateOf(invite.inviterName) }
  var history by remember { mutableStateOf(LendHistoryChoice.BOTH) }
  var working by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }
  val linkable = remember(store.lends) { shareableContacts(store) }
  val close = { sharing.sheet = null }

  fun run(done: String, action: suspend () -> Unit) {
    scope.launch {
      working = true
      errorMessage = null
      runCatching { action() }
        .onSuccess {
          store.showToast(done)
          close()
        }
        .onFailure { errorMessage = it.message }
      working = false
    }
  }

  DimoBottomSheet(onDismiss = close, compactDragHandle = true) {
    SheetTitle("Shared ledger invite")
    SheetColumn {
      val from = invite.inviterEmail?.let { "${invite.inviterName} ($it)" } ?: invite.inviterName
      Text(
        text = "$from wants to keep a shared lending ledger with you. " +
          "You’ll both see the same entries, and either of you can edit them.",
        style = DimoFont.body(14f),
        color = DimoColors.ink,
      )
      if (linkable.isNotEmpty()) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          FieldLabel("Already tracking ${invite.inviterName} here?")
          ChipRow {
            Chip("No", selected = linkedContactId == null) {
              linkedContactId = null
              contactName = invite.inviterName
            }
            linkable.forEach { contact ->
              Chip(contact.contactName, selected = linkedContactId == contact.contactId) {
                linkedContactId = contact.contactId
                contactName = contact.contactName
              }
            }
          }
        }
      }
      if (linkedContactId != null) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          FieldLabel("If you both recorded the same loans")
          SegmentedControl(
            options = LendHistoryChoice.entries.toList(),
            selected = history,
            label = {
              when (it) {
                LendHistoryChoice.BOTH -> "Keep both"
                LendHistoryChoice.INVITER -> "Keep theirs"
                LendHistoryChoice.ACCEPTER -> "Keep mine"
              }
            },
            onSelect = { history = it },
          )
          Muted(
            when (history) {
              LendHistoryChoice.BOTH -> "Both of your past entries are added to the shared ledger."
              LendHistoryChoice.INVITER ->
                "Only ${invite.inviterName}’s past entries are kept; yours with them are deleted so nothing is counted twice."
              LendHistoryChoice.ACCEPTER ->
                "Only your past entries are kept; ${invite.inviterName}’s are deleted so nothing is counted twice."
            },
            12f,
          )
        }
      }
      Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        SecondaryAction("Decline", modifier = Modifier.weight(1f)) {
          run("Invite declined") { sharing.decline(invite) }
        }
        Box(modifier = Modifier.weight(1f)) {
          PrimaryButton(
            title = if (working) "Accepting…" else "Accept",
            enabled = !working,
            onClick = {
              run("Ledger shared with ${contactName.trim()}") {
                sharing.accept(
                  invite = invite,
                  contactId = linkedContactId,
                  contactName = contactName.trim(),
                  history = if (linkedContactId == null) LendHistoryChoice.BOTH else history,
                )
              }
            },
          )
        }
      }
      errorMessage?.let { ErrorText(it) }
    }
  }
}

@Composable
private fun SheetTitle(title: String) {
  Box(
    modifier = Modifier
      .fillMaxWidth()
      .padding(horizontal = 20.dp, vertical = 10.dp),
    contentAlignment = Alignment.Center,
  ) {
    Text(text = title, style = DimoFont.display(18f, FontWeight.SemiBold), color = DimoColors.ink)
  }
}

@Composable
private fun SheetColumn(content: @Composable ColumnScope.() -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(max = 620.dp)
      .verticalScroll(rememberScrollState())
      .padding(horizontal = 20.dp)
      .padding(top = 12.dp, bottom = 24.dp),
    verticalArrangement = Arrangement.spacedBy(16.dp),
    content = content,
  )
}

@Composable
private fun Muted(text: String, size: Float = 13f) {
  Text(text = text, style = DimoFont.body(size), color = DimoColors.muted)
}

@Composable
private fun ErrorText(text: String) {
  Text(text = text, style = DimoFont.body(13f), color = DimoColors.danger)
}

@Composable
private fun ChipRow(content: @Composable () -> Unit) {
  Row(
    modifier = Modifier.horizontalScroll(rememberScrollState()),
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) { content() }
}

@Composable
private fun Chip(title: String, selected: Boolean, onClick: () -> Unit) {
  Text(
    text = title,
    style = DimoFont.body(13f, FontWeight.Medium),
    color = if (selected) DimoColors.canvas else DimoColors.ink,
    modifier = Modifier
      .clip(RoundedCornerShape(50))
      .background(if (selected) DimoColors.ink else DimoColors.canvas)
      .border(1.dp, if (selected) DimoColors.ink else DimoColors.line, RoundedCornerShape(50))
      .clickable(onClick = onClick)
      .padding(horizontal = 12.dp, vertical = 7.dp),
  )
}

@Composable
private fun SecondaryAction(
  title: String,
  modifier: Modifier = Modifier.fillMaxWidth(),
  destructive: Boolean = false,
  onClick: () -> Unit,
) {
  Box(
    modifier = modifier
      .height(48.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(if (destructive) DimoColors.dangerSoft else DimoColors.canvas)
      .border(1.dp, if (destructive) DimoColors.dangerLine else DimoColors.line, RoundedCornerShape(12.dp))
      .clickable(onClick = onClick),
    contentAlignment = Alignment.Center,
  ) {
    Text(
      text = title,
      style = DimoFont.body(15f, FontWeight.SemiBold),
      color = if (destructive) DimoColors.danger else DimoColors.ink,
    )
  }
}
