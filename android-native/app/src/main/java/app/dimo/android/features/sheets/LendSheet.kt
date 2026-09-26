package app.dimo.android.features.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.CurrencyMeta
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.LendContactSuggestion
import app.dimo.android.domain.LendFlow
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DateField
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.LabeledTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import app.dimo.android.store.LendDraftInvite
import app.dimo.android.store.LendingSharingStore
import app.dimo.android.sync.LendUser
import kotlinx.coroutines.delay
import java.time.Instant
import java.util.UUID
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Add or edit a lending entry as "I gave" / "I got". Port of
 * `ios-native/Dimo/Features/Lending/AddLendSheet.swift`.
 *
 * Whether it's a new loan or a repayment follows from the balance with that
 * person, so users never pick between lent, borrowed, got back and paid back.
 */
@Composable
fun LendSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val draft = store.lendDraft
  val editingId = draft.editingId
  val existing = editingId?.let { id -> store.lends.firstOrNull { it.id == id } }
  val isEditing = editingId != null
  val contactLocked = isEditing || draft.contactLocked
  val sharing = store.lendingSharing

  var confirmDelete by remember { mutableStateOf(false) }

  // Shared people and invites are offered even before any entries.
  val extraContacts = sharing.connections
    .filter { it.isActive }
    .map { LendContactSuggestion(contactName = it.contactName, contactId = it.contactId) } +
    sharing.outgoingInvites.mapNotNull { invite ->
      invite.contactId?.let { LendContactSuggestion(contactName = invite.contactName, contactId = it) }
    }
  fun withExtras(base: List<LendContactSuggestion>): List<LendContactSuggestion> =
    base + extraContacts.filter { extra -> base.none { it.contactId == extra.contactId } }
      .distinctBy { it.contactId }
  val recentContacts = withExtras(LendSelectors.recentContacts(store.lends))
  // Everyone in lend history plus shared and invited people, for matching.
  val knownContacts = withExtras(LendSelectors.recentContacts(store.lends, limit = Int.MAX_VALUE))

  // An edited entry keeps the currency it was recorded in.
  val currencySymbol = existing?.currency?.let(CurrencyMeta::symbol)
    ?: Formatting.currencySymbol(store.currency)

  val isSharedContact = draft.contactId?.let { sharing.activeConnection(it) != null } == true
  val pendingDraftInvite = draft.invite?.takeIf { it.contactId == draft.contactId }
  val sentInvite = draft.contactId?.let(sharing::pendingInvite)

  // "Priya owes you ₹100" / "You owe Priya ₹50", before this entry.
  val balanceText = draft.contactId?.let { contactId ->
    val balance = LendSelectors.netBalance(contactId, store.lends, editingId)
    if (abs(balance) <= 0.0001) return@let null
    val name = draft.contactName.trim()
    val amount = "$currencySymbol${amountText(abs(balance))}"
    if (balance > 0) {
      "${name.ifEmpty { "They" }} owes you $amount"
    } else {
      "You owe ${name.ifEmpty { "them" }} $amount"
    }
  }

  val canSave = (draft.amount.toDoubleOrNull() ?: 0.0) > 0 && draft.contactName.trim().isNotEmpty()

  // A typed name that matches someone already tracked continues their balance.
  fun editContactName(name: String) {
    val key = name.trim().lowercase()
    store.lendDraft = store.lendDraft.copy(
      contactName = name,
      invite = null,
      contactId = if (key.isEmpty()) {
        null
      } else {
        knownContacts.firstOrNull { it.contactName.trim().lowercase() == key }?.contactId
      },
    )
  }

  fun pickContact(contact: LendContactSuggestion) {
    store.lendDraft = store.lendDraft.copy(
      contactName = contact.contactName,
      contactId = contact.contactId,
      invite = null,
    )
  }

  fun pickDimoUser(user: LendUser) {
    if (user.relation == "invitedYou") {
      store.showToast("${user.name} already invited you. Accept their invite in Lending first.")
      return
    }
    val known = user.contactId
    store.lendDraft = if (known != null) {
      // Already shared, or already invited for this contact.
      store.lendDraft.copy(contactName = user.name, contactId = known, invite = null)
    } else {
      val contactId = "contact_${UUID.randomUUID().toString().lowercase()}"
      store.lendDraft.copy(
        contactName = user.name,
        contactId = contactId,
        invite = LendDraftInvite(user, contactId),
      )
    }
  }

  DimoBottomSheet(
    onDismiss = onClose,
    compactDragHandle = true,
  ) {
    LendSheetHeader(
      title = if (isEditing) "Edit entry" else "Add entry",
      editing = isEditing,
      onDelete = { confirmDelete = true },
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 640.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(top = 12.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      SegmentedControl(
        options = LendFlow.entries,
        selected = draft.flow,
        label = { if (it == LendFlow.GAVE) "I gave" else "I got" },
        onSelect = { store.lendDraft = store.lendDraft.copy(flow = it) },
      )

      Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FieldLabel(if (draft.flow == LendFlow.GAVE) "To" else "From")
        if (contactLocked) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .height(50.dp)
              .cardSurface(12.dp, DimoColors.canvas)
              .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            AvatarView(
              name = draft.contactName,
              photoUrl = draft.contactId?.let(sharing::photoUrl),
              size = 28.dp,
              radius = 9.dp,
              fontSize = 12f,
            )
            Text(
              text = draft.contactName,
              style = DimoFont.body(15f),
              color = DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.weight(1f),
            )
          }
        } else {
          LendContactField(
            name = draft.contactName,
            searching = draft.contactId == null && draft.invite == null,
            knownContacts = knownContacts,
            sharing = sharing,
            onEdit = ::editContactName,
            onPickContact = ::pickContact,
            onPickDimoUser = ::pickDimoUser,
          )
          if (draft.contactName.isEmpty() && recentContacts.isNotEmpty()) {
            Row(
              modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState())
                .padding(top = 4.dp, bottom = 1.dp),
              horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
              recentContacts.forEach { suggestion ->
                Row(
                  modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .cardSurface(50.dp, DimoColors.canvas)
                    .clickable { pickContact(suggestion) }
                    .padding(start = 5.dp, end = 12.dp, top = 5.dp, bottom = 5.dp),
                  verticalAlignment = Alignment.CenterVertically,
                  horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                  AvatarView(
                    name = suggestion.contactName,
                    photoUrl = sharing.photoUrl(suggestion.contactId),
                    size = 22.dp,
                    radius = 11.dp,
                    fontSize = 10f,
                  )
                  Text(
                    text = suggestion.contactName,
                    style = DimoFont.body(13f, FontWeight.Medium),
                    color = DimoColors.ink,
                    maxLines = 1,
                  )
                }
              }
            }
          }
        }

        val note = when {
          isSharedContact -> "Shared with ${draft.contactName} — they see this entry too"
          pendingDraftInvite != null ->
            "Saving invites ${pendingDraftInvite.user.email ?: pendingDraftInvite.user.name}. " +
              "This entry stays private until they accept."
          sentInvite != null ->
            "Invited ${sentInvite.inviteeEmail ?: sentInvite.contactName}. This entry is shared once they accept."
          else -> null
        }
        if (note != null) {
          Text(
            text = note,
            style = DimoFont.body(12f),
            color = if (isSharedContact) DimoColors.green else DimoColors.muted,
          )
        }
      }

      DateField(
        label = "Date",
        millis = draft.date.toEpochMilli(),
        onChange = { millis ->
          store.lendDraft = store.lendDraft.copy(date = Instant.ofEpochMilli(millis))
        },
        compact = true,
      )

      Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FieldLabel("Amount")
        DimoTextField(
          value = draft.amount,
          onValueChange = { store.lendDraft = store.lendDraft.copy(amount = sanitizeDecimal(it)) },
          placeholder = "0",
          keyboardType = KeyboardType.Decimal,
          leading = {
            Text(
              text = currencySymbol,
              style = DimoFont.body(15f),
              color = DimoColors.muted,
            )
          },
        )
        if (balanceText != null) {
          Text(
            text = balanceText,
            style = DimoFont.body(12f),
            color = DimoColors.faint,
          )
        }
      }

      LabeledTextField(
        label = "Note (optional)",
        value = draft.comment,
        onValueChange = { store.lendDraft = store.lendDraft.copy(comment = it) },
        placeholder = "e.g. Dinner, cab fare",
      )

      PrimaryButton(
        title = "Save",
        enabled = canSave,
        onClick = { store.saveLend() },
      )
    }
  }

  if (confirmDelete && editingId != null) {
    ConfirmDialog(
      title = "Delete this entry?",
      message = if (isSharedContact) {
        "This also removes it for ${draft.contactName}."
      } else {
        "This can’t be undone."
      },
      confirmLabel = "Delete",
      onConfirm = { store.deleteLend(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}

internal fun amountText(amount: Double): String =
  if (amount.roundToLong().toDouble() == amount) amount.toLong().toString() else String.format("%.2f", amount)

/** Short label for a Dimo user's relationship to you. */
internal fun lendRelationLabel(user: LendUser): String = when (user.relation) {
  "connected" -> "Shared"
  "invited" -> "Invited"
  "invitedYou" -> "Invited you"
  else -> "On Dimo"
}

/**
 * Typed name that searches your people as you type and, from two letters,
 * Dimo accounts by name or email. Picking a Dimo account makes saving invite
 * them.
 */
@Composable
private fun LendContactField(
  name: String,
  /** False once someone is picked, which hides the results. */
  searching: Boolean,
  knownContacts: List<LendContactSuggestion>,
  sharing: LendingSharingStore,
  onEdit: (String) -> Unit,
  onPickContact: (LendContactSuggestion) -> Unit,
  onPickDimoUser: (LendUser) -> Unit,
) {
  val query = name.trim()
  val searchQuery = query.takeIf { searching && sharing.isOnline && it.length >= 2 }
  var results by remember { mutableStateOf<Pair<String, List<LendUser>>?>(null) }
  LaunchedEffect(searchQuery) {
    val next = searchQuery ?: return@LaunchedEffect
    delay(250)
    runCatching { sharing.searchUsers(next) }.onSuccess { results = next to it }
  }
  val dimoUsers = results?.takeIf { it.first == searchQuery }?.second
  // A Dimo result already stands for the contact it's shared or invited as.
  val linked = dimoUsers.orEmpty().mapNotNull { it.contactId }.toSet()
  val matchingContacts = if (searching && query.isNotEmpty()) {
    knownContacts
      .filter { it.contactName.contains(query, ignoreCase = true) && it.contactId !in linked }
      .take(5)
  } else {
    emptyList()
  }
  val showsResults = searching && query.isNotEmpty() && (matchingContacts.isNotEmpty() || dimoUsers != null)

  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(12.dp))
      .background(DimoColors.canvas)
      .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp)),
  ) {
    DimoTextField(
      value = name,
      onValueChange = onEdit,
      placeholder = "Their name or Dimo email",
    )
    if (showsResults) {
      HorizontalDivider(color = DimoColors.line)
      matchingContacts.forEach { contact ->
        LendResultRow(
          name = contact.contactName,
          detail = null,
          photoUrl = sharing.photoUrl(contact.contactId),
          badge = if (sharing.activeConnection(contact.contactId) != null) "Shared" else "Your contact",
          badgeTint = DimoColors.muted,
          onClick = { onPickContact(contact) },
        )
      }
      dimoUsers.orEmpty().forEach { user ->
        LendResultRow(
          name = user.name,
          detail = user.email,
          photoUrl = user.photoUrl,
          badge = lendRelationLabel(user),
          badgeTint = DimoColors.green,
          onClick = { onPickDimoUser(user) },
        )
      }
      if (dimoUsers != null && dimoUsers.isEmpty() && matchingContacts.isEmpty()) {
        Text(
          text = "No one named “$query” yet. Saving adds them as a new person.",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
          modifier = Modifier.padding(14.dp),
        )
      }
    }
  }
}

@Composable
internal fun LendResultRow(
  name: String,
  detail: String?,
  photoUrl: String?,
  badge: String,
  badgeTint: Color,
  onClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .height(54.dp)
      .clickable(onClick = onClick)
      .padding(horizontal = 14.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    AvatarView(name = name, photoUrl = photoUrl, size = 32.dp, radius = 10.dp, fontSize = 13f)
    Column(modifier = Modifier.weight(1f)) {
      Text(
        text = name,
        style = DimoFont.body(15f),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      if (detail != null) {
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
      text = badge,
      style = DimoFont.body(12f, FontWeight.Medium),
      color = badgeTint,
    )
  }
}

@Composable
private fun LendSheetHeader(
  title: String,
  editing: Boolean,
  onDelete: () -> Unit,
) {
  if (!editing) {
    Box(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 20.dp, vertical = 10.dp),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        text = title,
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
    }
    return
  }

  Row(
    modifier = Modifier
      .fillMaxWidth()
      .padding(horizontal = 20.dp, vertical = 10.dp),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      text = title,
      style = DimoFont.display(18f, FontWeight.SemiBold),
      color = DimoColors.ink,
      modifier = Modifier.weight(1f),
    )
    Box(
      modifier = Modifier
        .size(42.dp)
        .clip(RoundedCornerShape(13.dp))
        .background(DimoColors.dangerSoft)
        .border(1.dp, DimoColors.dangerLine, RoundedCornerShape(13.dp))
        .clickable(onClick = onDelete),
      contentAlignment = Alignment.Center,
    ) {
      Icon(
        imageVector = Icons.Filled.DeleteOutline,
        contentDescription = "Delete entry",
        tint = DimoColors.danger,
        modifier = Modifier.size(17.dp),
      )
    }
  }
}
