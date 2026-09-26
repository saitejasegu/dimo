package app.dimo.android.features.sheets

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Search
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
import androidx.compose.ui.platform.LocalContext
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
import app.dimo.android.features.common.ContactsLoader
import app.dimo.android.features.common.DateField
import app.dimo.android.features.common.DeviceContact
import app.dimo.android.features.common.DimoBottomSheet
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.LabeledTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.features.common.SegmentedControl
import app.dimo.android.features.common.cardSurface
import app.dimo.android.features.common.rememberContactPhotoUris
import app.dimo.android.store.AppStore
import java.time.Instant
import kotlin.math.roundToLong

/**
 * Add / edit a lend, borrowing, or settlement. Port of
 * `ios-native/Dimo/Features/Lending/AddLendSheet.swift`.
 *
 * Contacts come from `READ_CONTACTS`; only the identifier and name are saved.
 * Settlements are capped at the contact's balance for that direction, excluding
 * the row being edited.
 */
@Composable
fun LendSheet(
  store: AppStore,
  onClose: () -> Unit,
) {
  val context = LocalContext.current
  val draft = store.lendDraft
  val editingId = draft.editingId
  val existing = editingId?.let { id -> store.lends.firstOrNull { it.id == id } }
  // Editing never flips direction; the saved row's kind wins.
  val kind = existing?.kind ?: draft.kind
  val isEditing = editingId != null
  val isSettlement = kind == LendKind.REPAID || kind == LendKind.RETURNED
  val contactLocked = isEditing || (isSettlement && draft.contactName.isNotEmpty())
  val canChooseDirection = !isEditing && !isSettlement

  var contacts by remember { mutableStateOf<List<DeviceContact>>(emptyList()) }
  var permissionDenied by remember { mutableStateOf(false) }
  var contactQuery by remember(editingId) { mutableStateOf("") }
  var pickingContact by remember { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }
  val contactPhotos = rememberContactPhotoUris()

  val permissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission(),
  ) { granted ->
    permissionDenied = !granted
    if (granted) pickingContact = true
  }

  fun openContactPicker() {
    if (ContactsLoader.hasPermission(context)) {
      pickingContact = true
    } else {
      permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
    }
  }

  LaunchedEffect(pickingContact) {
    if (pickingContact && contacts.isEmpty()) {
      contacts = ContactsLoader.load(context)
    }
  }

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
    (draft.contactId != null || existing != null) &&
    !exceedsLimit

  // Shared ledgers are offered even before either side recorded anything.
  val recentContacts = LendSelectors.recentContacts(store.lends) +
    store.lendingSharing.connections
      .filter { connection ->
        connection.isActive &&
          store.lends.none { it.contactId == connection.contactId }
      }
      .map { LendContactSuggestion(contactName = it.contactName, contactId = it.contactId) }
  val isSharedContact = draft.contactId?.startsWith(SHARED_LEND_CONTACT_PREFIX) == true
  // An edited entry keeps the currency it was recorded in.
  val currencySymbol = existing?.currency?.let(CurrencyMeta::symbol)
    ?: Formatting.currencySymbol(store.currency)
  val filteredContacts = remember(contacts, contactQuery) {
    val query = contactQuery.trim().lowercase()
    if (query.isEmpty()) contacts.take(40) else {
      contacts.filter { it.name.lowercase().contains(query) }.take(40)
    }
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
      if (canChooseDirection && !pickingContact) {
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
              photoUri = draft.contactId?.let(contactPhotos::get),
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
        } else if (pickingContact) {
          DimoTextField(
            value = contactQuery,
            onValueChange = { contactQuery = it },
            placeholder = "Search contacts",
            leading = {
              Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = null,
                tint = DimoColors.muted,
                modifier = Modifier.size(16.dp),
              )
            },
          )
        } else {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .height(50.dp)
              .cardSurface(12.dp, DimoColors.canvas)
              .clickable(onClick = ::openContactPicker)
              .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            if (draft.contactName.isEmpty()) {
              Icon(
                imageVector = Icons.Filled.Search,
                contentDescription = null,
                tint = DimoColors.muted,
                modifier = Modifier.size(16.dp),
              )
            } else {
              ContactAvatar(
                name = draft.contactName,
                photoUri = draft.contactId?.let(contactPhotos::get),
                size = 28.dp,
                radius = 14.dp,
                fontSize = 11f,
                monogram = lendContactInitials(draft.contactName),
              )
            }
            Text(
              text = draft.contactName.ifEmpty { "Search contacts" },
              style = DimoFont.body(15f),
              color = if (draft.contactName.isEmpty()) DimoColors.faint else DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.weight(1f),
            )
            Icon(
              imageVector = Icons.Filled.KeyboardArrowDown,
              contentDescription = "Choose from contacts",
              tint = DimoColors.green,
              modifier = Modifier.size(18.dp),
            )
          }
        }

        if (isSharedContact && !pickingContact) {
          Text(
            text = "Shared ledger \u2014 ${draft.contactName} sees this entry too",
            style = DimoFont.body(12f),
            color = DimoColors.green,
          )
        }

        if (permissionDenied) {
          Text(
            text = "Contacts permission is needed to keep same-named people apart.",
            style = DimoFont.body(12f),
            color = DimoColors.danger,
          )
        }

        if (pickingContact && !contactLocked) {
          Column(
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(12.dp, DimoColors.popup)
              .padding(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
          ) {
            if (filteredContacts.isEmpty()) {
              Text(
                text = "No contacts found.",
                style = DimoFont.body(13f),
                color = DimoColors.muted,
                modifier = Modifier.padding(horizontal = 6.dp, vertical = 8.dp),
              )
            }
            filteredContacts.forEach { contact ->
              Row(
                modifier = Modifier
                  .fillMaxWidth()
                  .clip(RoundedCornerShape(10.dp))
                  .clickable {
                    store.lendDraft = draft.copy(
                      contactName = contact.name,
                      contactId = contact.id,
                    )
                    pickingContact = false
                    contactQuery = ""
                  }
                  .padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
              ) {
                ContactAvatar(
                  name = contact.name,
                  photoUri = contact.photoUri,
                  size = 32.dp,
                  radius = 16.dp,
                  fontSize = 13f,
                  monogram = lendContactInitials(contact.name),
                )
                Text(
                  text = contact.name,
                  style = DimoFont.body(14f),
                  color = DimoColors.ink,
                  maxLines = 1,
                  overflow = TextOverflow.Ellipsis,
                )
              }
            }
          }
        }

        if (
          existing == null &&
          !contactLocked &&
          !pickingContact &&
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
                    )
                    pickingContact = false
                  }
                  .padding(start = 5.dp, end = 12.dp, top = 5.dp, bottom = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
              ) {
                ContactAvatar(
                  name = suggestion.contactName,
                  photoUri = contactPhotos[suggestion.contactId],
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

      if (!pickingContact) {
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
