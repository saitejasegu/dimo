package app.dimo.android.features.lending

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.SHARED_LEND_CONTACT_PREFIX
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.LendContactSuggestion
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.store.AppStore
import app.dimo.android.store.LedgerSharingSheet
import app.dimo.android.sync.LendHistoryChoice
import app.dimo.android.sync.LendInviteCode
import app.dimo.android.sync.LendInviteLinks
import app.dimo.android.sync.LendInvitePreview
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/** Hosts whichever sharing sheet is open. Port of the iOS tab-shell sheet. */
@Composable
fun LedgerSharingSheetHost(store: AppStore) {
  when (val sheet = store.lendingSharing.sheet) {
    is LedgerSharingSheet.Invite -> LedgerInviteSheet(store, sheet.contactId, sheet.contactName)
    is LedgerSharingSheet.Join -> JoinLedgerSheet(store, sheet.code)
    null -> Unit
  }
}

/** Existing, not-yet-shared lending contacts whose history can come along. */
private fun shareableContacts(store: AppStore): List<LendContactSuggestion> =
  LendSelectors.recentContacts(store.lends, limit = 20)
    .filterNot { it.contactId.startsWith(SHARED_LEND_CONTACT_PREFIX) }

/**
 * Invites another Dimo account to share a lending ledger, by link/code and
 * optionally by their verified email.
 */
@Composable
private fun LedgerInviteSheet(store: AppStore, initialContactId: String?, initialContactName: String) {
  val sharing = store.lendingSharing
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  var contactName by remember { mutableStateOf(initialContactName) }
  var contactId by remember { mutableStateOf(initialContactId) }
  var email by remember { mutableStateOf("") }
  var invite by remember {
    mutableStateOf(
      initialContactId?.let { sharing.pendingInvite(it) }?.let { LendInviteCode(it.code, it.expiresAt) },
    )
  }
  var sentByEmail by remember { mutableStateOf(false) }
  var working by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }
  val suggestions = remember(store.lends) { shareableContacts(store) }
  val close = { sharing.sheet = null }

  DimoBottomSheet(onDismiss = close, compactDragHandle = true) {
    SheetTitle(if (invite == null) "Share a ledger" else "Invite ready")
    SheetColumn {
      val current = invite
      if (current == null) {
        Muted("You and the other person see the same entries, and either of you can add, edit or delete them.")
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          FieldLabel("Who are you sharing with?")
          DimoTextField(
            value = contactName,
            onValueChange = { next ->
              contactName = next
              // Typing a new name detaches a previously tapped contact.
              if (suggestions.none { it.contactId == contactId && it.contactName == next }) {
                if (initialContactId == null) contactId = null
              }
            },
            placeholder = "Their name",
            enabled = initialContactId == null,
          )
          if (initialContactId == null && suggestions.isNotEmpty()) {
            ChipRow {
              suggestions.forEach { suggestion ->
                Chip(suggestion.contactName, selected = contactId == suggestion.contactId) {
                  contactName = suggestion.contactName
                  contactId = suggestion.contactId
                }
              }
            }
          }
          if (contactId != null) Muted("Your past entries with $contactName will be shared too.", 12f)
        }
        if (sharing.emailInvitesAvailable) {
          Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FieldLabel("Their Dimo email (optional)")
            DimoTextField(
              value = email,
              onValueChange = { email = it },
              placeholder = "name@example.com",
              keyboardType = KeyboardType.Email,
            )
            Muted(
              "If they use Dimo with this email, the invite appears in their Lending tab. You can also share the link.",
              12f,
            )
          }
        }
        PrimaryButton(
          title = if (working) "Creating…" else "Create invite",
          enabled = contactName.isNotBlank() && !working,
          onClick = {
            scope.launch {
              working = true
              errorMessage = null
              runCatching { sharing.createInvite(contactId, contactName, email) }
                .onSuccess {
                  invite = it
                  sentByEmail = email.isNotBlank()
                }
                .onFailure { errorMessage = it.message }
              working = false
            }
          },
        )
      } else {
        if (sentByEmail) {
          Muted("If $contactName uses Dimo with that email, they’ll see your invite in their Lending tab.")
        }
        Column(
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(DimoColors.canvas)
            .border(1.dp, DimoColors.line, RoundedCornerShape(14.dp))
            .padding(vertical = 18.dp),
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
          Text(
            text = LendInviteLinks.grouped(current.code),
            style = DimoFont.display(28f, FontWeight.SemiBold),
            color = DimoColors.ink,
          )
          Muted("Expires ${DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(current.expiresAt.toLong()))}", 12f)
        }
        PrimaryButton(
          title = "Share invite",
          onClick = {
            val intent = Intent(Intent.ACTION_SEND).apply {
              type = "text/plain"
              putExtra(Intent.EXTRA_TEXT, LendInviteLinks.message(store.profileName, current.code))
            }
            context.startActivity(Intent.createChooser(intent, null))
          },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          SecondaryAction("Copy code", modifier = Modifier.weight(1f)) {
            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("Dimo invite code", current.code))
            store.showToast("Invite code copied")
          }
          SecondaryAction("Cancel invite", destructive = true, modifier = Modifier.weight(1f)) {
            scope.launch {
              runCatching { sharing.cancel(current.code) }
                .onSuccess {
                  store.showToast("Invite cancelled")
                  close()
                }
                .onFailure { errorMessage = it.message }
            }
          }
        }
      }
      errorMessage?.let { ErrorText(it) }
    }
  }
}

/**
 * Joins a ledger someone shared: preview the invite, optionally link an
 * existing contact, choose whose history to keep, then accept.
 */
@Composable
private fun JoinLedgerSheet(store: AppStore, initialCode: String) {
  val sharing = store.lendingSharing
  val scope = rememberCoroutineScope()
  var code by remember { mutableStateOf(initialCode) }
  var preview by remember { mutableStateOf<LendInvitePreview?>(null) }
  var previewedCode by remember { mutableStateOf<String?>(null) }
  var linkedContactId by remember { mutableStateOf<String?>(null) }
  var contactName by remember { mutableStateOf("") }
  var history by remember { mutableStateOf(LendHistoryChoice.BOTH) }
  var working by remember { mutableStateOf(false) }
  var errorMessage by remember { mutableStateOf<String?>(null) }
  val linkable = remember(store.lends) { shareableContacts(store) }
  val close = { sharing.sheet = null }
  val normalized = LendInviteLinks.normalize(code)
  val isIncoming = sharing.incomingInvites.any { it.code == normalized }

  suspend fun lookUp() {
    working = true
    errorMessage = null
    runCatching { sharing.preview(code) }
      .onSuccess { found ->
        if (found == null) {
          errorMessage = "No invite matches that code."
        } else {
          preview = found
          previewedCode = LendInviteLinks.normalize(code)
          if (contactName.isEmpty()) contactName = found.inviterName
        }
      }
      .onFailure { errorMessage = it.message }
    working = false
  }

  LaunchedEffect(Unit) {
    if (initialCode.isNotEmpty()) lookUp()
  }

  DimoBottomSheet(onDismiss = close, compactDragHandle = true) {
    SheetTitle("Join a shared ledger")
    SheetColumn {
      val current = preview?.takeIf { previewedCode == normalized }
      if (current == null) {
        Muted("Enter the code from the invite someone shared with you.")
        DimoTextField(
          value = code,
          onValueChange = { code = it },
          placeholder = "ABCDE-12345",
          textStyle = DimoFont.display(20f, FontWeight.SemiBold),
        )
        PrimaryButton(
          title = if (working) "Checking…" else "Continue",
          enabled = normalized.length >= 6 && !working,
          onClick = { scope.launch { lookUp() } },
        )
      } else if (!current.isAcceptable()) {
        Muted(
          when {
            current.isOwnInvite -> "This is your own invite. Share it with the other person instead."
            current.status == "accepted" -> "This invite has already been used."
            current.status == "revoked" -> "This invite was cancelled."
            else -> "This invite has expired. Ask ${current.inviterName} for a new one."
          },
          14f,
        )
        SecondaryAction("Try another code") {
          preview = null
          previewedCode = null
        }
      } else {
        Text(
          text = "${current.inviterName} wants to keep a shared lending ledger with you. " +
            "You’ll both see the same entries, and either of you can edit them.",
          style = DimoFont.body(14f),
          color = DimoColors.ink,
        )
        if (linkable.isNotEmpty()) {
          Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FieldLabel("Already tracking ${current.inviterName} here?")
            ChipRow {
              Chip("No", selected = linkedContactId == null) {
                linkedContactId = null
                contactName = current.inviterName
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
                  "Only ${current.inviterName}’s past entries are kept; yours with them are deleted so nothing is counted twice."
                LendHistoryChoice.ACCEPTER ->
                  "Only your past entries are kept; ${current.inviterName}’s are deleted so nothing is counted twice."
              },
              12f,
            )
          }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          FieldLabel("Show them as")
          DimoTextField(
            value = contactName,
            onValueChange = { contactName = it },
            placeholder = current.inviterName,
          )
        }
        PrimaryButton(
          title = if (working) "Joining…" else "Join ledger",
          enabled = !working,
          onClick = {
            scope.launch {
              working = true
              errorMessage = null
              runCatching {
                sharing.accept(
                  code = code,
                  contactId = linkedContactId,
                  contactName = contactName.trim(),
                  history = if (linkedContactId == null) LendHistoryChoice.BOTH else history,
                )
              }
                .onSuccess {
                  store.showToast("Ledger shared with ${contactName.trim()}")
                  close()
                }
                .onFailure { errorMessage = it.message }
              working = false
            }
          },
        )
        if (isIncoming) {
          SecondaryAction("Decline", destructive = true) {
            scope.launch {
              runCatching { sharing.decline(normalized) }
                .onSuccess { close() }
                .onFailure { errorMessage = it.message }
            }
          }
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
