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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.LendKind
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.Formatting
import app.dimo.android.data.model.SHARED_LEND_CONTACT_PREFIX
import app.dimo.android.domain.CurrencyMeta
import app.dimo.android.domain.LendContactSuggestion
import app.dimo.android.domain.LendSelectors
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.ContactAvatar
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
import app.dimo.android.sync.LendUser
import kotlinx.coroutines.delay
import java.util.UUID
import java.time.Instant
import kotlin.math.roundToLong

/**
 * Add / edit a lend, borrowing, or settlement. Port of
 * `ios-native/Dimo/Features/Lending/AddLendSheet.swift`.
 *
 * The contact is a typed name (matched to someone already tracked) or a Dimo
 * account found by email, which saving invites.
 * Settlements are capped at the contact's balance for that direction, excluding
 * the row being edited.
 */
@Composable
fun LendSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val draft = store.lendDraft
  val editingId = draft.editingId
  val existing = editingId?.let { id -> store.lends.firstOrNull { it.id == id } }
  // Editing never flips direction; the saved row's kind wins.
  val kind = existing?.kind ?: draft.kind
  val isEditing = editingId != null
  val isSettlement = kind == LendKind.REPAID || kind == LendKind.RETURNED
  val contactLocked = isEditing || (isSettlement && draft.contactName.isNotEmpty())
  val canChooseDirection = !isEditing && !isSettlement

  var confirmDelete by remember { mutableStateOf(false) }

  // A typed email is looked up as a Dimo account.
  val sharing = store.lendingSharing
  val typedEmail = draft.contactName.trim().lowercase().takeIf {
    draft.invite == null && sharing.sharingAvailable && sharing.isOnline && EMAIL_PATTERN.matches(it)
  }
  var lookup by remember { mutableStateOf<Pair<String, LendUser?>?>(null) }
  val currentLookup = lookup?.takeIf { it.first == typedEmail }
  LaunchedEffect(typedEmail) {
    val email = typedEmail ?: return@LaunchedEffect
    delay(350)
    runCatching { sharing.findUser(email) }.onSuccess { lookup = email to it }
  }

  fun pickDimoUser(user: LendUser) {
    val known = user.contactId
    store.lendDraft = if (known != null) {
      // Already shared, or already invited for this contact.
      draft.copy(contactName = user.name, contactId = known, invite = null)
    } else {
      val contactId = "contact_${UUID.randomUUID()}"
      draft.copy(
        contactName = user.name,
        contactId = contactId,
        invite = LendDraftInvite(user, contactId),
      )
    }
  }
  val pendingDraftInvite = draft.invite?.takeIf { it.contactId == draft.contactId }
  val sentInvite = draft.contactId?.let(sharing::pendingInvite)

  val settlementLimit = draft.contactId?.let { contactId ->
    LendSelectors.settlementLimit(
      kind = kind,
      contactId = contactId,
      lends = store.lends,
      excludingLendId = existing?.id,
    )
  } ?: if (isSettlement) 0.0 else null

  val amountValue = draft.amount.toDoubleOrNull() ?: 0.0
  val exceedsLimit = settlementLimit != null && amountValue > settlementLimit + 0.000_001
  val canSave = amountValue > 0 &&
    draft.contactName.trim().isNotEmpty() &&
    !exceedsLimit

  // Shared ledgers are offered even before either side recorded anything.
  val recentContacts = LendSelectors.recentContacts(store.lends) +
    store.lendingSharing.connections
      .filter { connection ->
        connection.isActive &&
          store.lends.none { it.contactId == connection.contactId }
      }
      .map { LendContactSuggestion(contactName = it.contactName, contactId = it.contactId) } +
    // Someone invited before any entries were recorded with them.
    store.lendingSharing.outgoingInvites
      .mapNotNull { invite ->
        invite.contactId
          ?.takeIf { id -> store.lends.none { it.contactId == id } }
          ?.let { LendContactSuggestion(contactName = invite.contactName, contactId = it) }
      }
  val isSharedContact = draft.contactId?.startsWith(SHARED_LEND_CONTACT_PREFIX) == true
  // An edited entry keeps the currency it was recorded in.
  val currencySymbol = existing?.currency?.let(CurrencyMeta::symbol)
    ?: Formatting.currencySymbol(store.currency)
  // A typed name that matches someone already tracked continues their balance.
  val knownContacts = remember(store.lends) {
    LendSelectors.recentContacts(store.lends, limit = Int.MAX_VALUE)
  }
  fun contactIdForName(name: String): String? {
    val key = name.trim().lowercase()
    if (key.isEmpty()) return null
    return (knownContacts + recentContacts).firstOrNull { it.contactName.trim().lowercase() == key }?.contactId
  }

  val sheetTitle = when {
    isEditing -> when (kind) {
      LendKind.LENT -> "Edit lend"
      LendKind.REPAID -> "Edit repayment"
      LendKind.BORROWED -> "Edit borrowing"
      LendKind.RETURNED -> "Edit payment"
    }
    else -> when (kind) {
      LendKind.LENT -> "Add lend"
      LendKind.BORROWED -> "Add borrowing"
      LendKind.REPAID -> "Got back"
      LendKind.RETURNED -> "Paid back"
    }
  }

  val contactLabel = when (kind) {
    LendKind.LENT -> "Lent to"
    LendKind.BORROWED -> "Borrowed from"
    LendKind.REPAID -> "From"
    LendKind.RETURNED -> "To"
  }

  val amountLabel = when (kind) {
    LendKind.LENT, LendKind.BORROWED -> "Amount"
    LendKind.REPAID -> "Amount got back"
    LendKind.RETURNED -> "Amount paid back"
  }

  val commentPlaceholder = when (kind) {
    LendKind.LENT -> "e.g. Dinner split, emergency"
    LendKind.BORROWED -> "e.g. Rent top-up, cab fare"
    LendKind.REPAID -> "e.g. Partial repayment"
    LendKind.RETURNED -> "e.g. Partial payment"
  }

  val saveTitle = when (kind) {
    LendKind.LENT -> "Save lend"
    LendKind.BORROWED -> "Save borrowing"
    LendKind.REPAID -> if (isEditing) "Save repayment" else "Save got back"
    LendKind.RETURNED -> if (isEditing) "Save payment" else "Save paid back"
  }

  val deleteTitle = when (kind) {
    LendKind.LENT -> "Delete this lend?"
    LendKind.REPAID -> "Delete this repayment?"
    LendKind.BORROWED -> "Delete this borrowing?"
    LendKind.RETURNED -> "Delete this payment?"
  }

  fun clampToSettlementLimit(next: String) {
    val sanitized = sanitizeDecimal(next)
    val limit = settlementLimit ?: run {
      store.lendDraft = draft.copy(amount = sanitized)
      return
    }
    val parsed = sanitized.toDoubleOrNull()
    if (parsed != null && parsed > limit) {
      val clamped = if (limit.roundToLong().toDouble() == limit) {
        limit.toLong().toString()
      } else {
        String.format("%.2f", limit)
      }
      store.lendDraft = draft.copy(amount = clamped)
    } else {
      store.lendDraft = draft.copy(amount = sanitized)
    }
  }

  DimoBottomSheet(
    onDismiss = onClose,
    compactDragHandle = true,
  ) {
    LendSheetHeader(
      title = sheetTitle,
      editing = isEditing,
      onDelete = { confirmDelete = true },
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 620.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(top = 12.dp)
        .padding(bottom = 24.dp),
      verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
      if (canChooseDirection) {
        SegmentedControl(
          options = listOf(LendKind.LENT, LendKind.BORROWED),
          selected = if (kind == LendKind.BORROWED) LendKind.BORROWED else LendKind.LENT,
          label = { if (it == LendKind.LENT) "I lent" else "I borrowed" },
          onSelect = { selected -> store.lendDraft = draft.copy(kind = selected) },
        )
      }

      Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        FieldLabel(contactLabel)
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
            ContactAvatar(
              name = draft.contactName,
              size = 28.dp,
              radius = 14.dp,
              fontSize = 11f,
              monogram = lendContactInitials(draft.contactName),
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
          DimoTextField(
            value = draft.contactName,
            onValueChange = { next ->
              store.lendDraft = draft.copy(
                contactName = next,
                contactId = contactIdForName(next),
                invite = null,
              )
            },
            placeholder = "Their name or Dimo email",
          )
        }

        if (isSharedContact) {
          Text(
            text = "Shared ledger \u2014 ${draft.contactName} sees this entry too",
            style = DimoFont.body(12f),
            color = DimoColors.green,
          )
        } else if (pendingDraftInvite != null) {
          Text(
            text = "Saving invites ${pendingDraftInvite.user.email}. This entry stays private until they accept.",
            style = DimoFont.body(12f),
            color = DimoColors.muted,
          )
        } else if (sentInvite != null) {
          Text(
            text = "Invited ${sentInvite.inviteeEmail ?: sentInvite.contactName}. This entry is shared once they accept.",
            style = DimoFont.body(12f),
            color = DimoColors.muted,
          )
        }

        if (typedEmail != null && !contactLocked) {
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(12.dp, DimoColors.popup)
              .padding(8.dp),
          ) {
            DimoUserResult(currentLookup, onPick = ::pickDimoUser)
          }
        }

        if (
          existing == null &&
          !contactLocked &&
          draft.contactName.isEmpty() &&
          recentContacts.isNotEmpty()
        ) {
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
                  .clickable {
                    store.lendDraft = draft.copy(
                      contactName = suggestion.contactName,
                      contactId = suggestion.contactId,
                      invite = null,
                    )
                  }
                  .padding(start = 5.dp, end = 12.dp, top = 5.dp, bottom = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
              ) {
                ContactAvatar(
                  name = suggestion.contactName,
                  size = 22.dp,
                  radius = 11.dp,
                  fontSize = 8f,
                  monogram = lendContactInitials(suggestion.contactName),
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

      run {
        DateField(
          label = "Date",
          millis = draft.date.toEpochMilli(),
          onChange = { millis ->
            store.lendDraft = draft.copy(date = Instant.ofEpochMilli(millis))
          },
          compact = true,
        )

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
          FieldLabel(amountLabel)
          DimoTextField(
            value = draft.amount,
            onValueChange = { next -> clampToSettlementLimit(next) },
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
        }

        LabeledTextField(
          label = "Comments (optional)",
          value = draft.comment,
          onValueChange = { store.lendDraft = draft.copy(comment = it) },
          placeholder = commentPlaceholder,
        )

        PrimaryButton(
          title = saveTitle,
          enabled = canSave,
          onClick = { store.saveLend() },
        )
      }
    }
  }

  if (confirmDelete && editingId != null) {
    ConfirmDialog(
      title = deleteTitle,
      confirmLabel = "Delete",
      onConfirm = { store.deleteLend(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}

private fun lendContactInitials(name: String): String {
  val parts = name.trim().split(Regex("\\s+")).filter(String::isNotEmpty)
  return listOfNotNull(
    parts.firstOrNull()?.firstOrNull(),
    parts.lastOrNull()?.firstOrNull()?.takeIf { parts.size > 1 },
  )
    .joinToString("")
    .uppercase()
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
        contentDescription = "Delete lending entry",
        tint = DimoColors.danger,
        modifier = Modifier.size(17.dp),
      )
    }
  }
}

private val EMAIL_PATTERN = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")

/** The Dimo account a typed email belongs to, or why it can't be picked. */
@Composable
private fun DimoUserResult(lookup: Pair<String, LendUser?>?, onPick: (LendUser) -> Unit) {
  val user = lookup?.second
  val note = when {
    lookup == null -> "Looking for a Dimo account\u2026"
    user == null -> "No Dimo account uses this email."
    user.relation == "self" -> "That\u2019s your own account."
    user.relation == "invitedYou" -> "${user.name} already invited you. Accept their invite in Lending first."
    else -> null
  }
  if (note != null || user == null) {
    Text(
      text = note.orEmpty(),
      style = DimoFont.body(13f),
      color = DimoColors.muted,
      modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
    )
    return
  }
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(10.dp))
      .clickable { onPick(user) }
      .padding(horizontal = 8.dp, vertical = 8.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(10.dp),
  ) {
    ContactAvatar(
      name = user.name,
      size = 32.dp,
      radius = 16.dp,
      fontSize = 13f,
      monogram = lendContactInitials(user.name),
    )
    Column(modifier = Modifier.weight(1f)) {
      Text(
        text = user.name,
        style = DimoFont.body(14f),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = user.email,
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Text(
      text = when (user.relation) {
        "connected" -> "Shared"
        "invited" -> "Invited"
        else -> "On Dimo"
      },
      style = DimoFont.body(12f, FontWeight.Medium),
      color = DimoColors.green,
    )
  }
}
