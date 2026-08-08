package app.dimo.android.features.sheets

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.Formatting
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
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.WrapRow
import app.dimo.android.features.common.cardSurface
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

  val permissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission(),
  ) { granted ->
    permissionDenied = !granted
    if (granted) pickingContact = true
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

  val recentContacts = LendSelectors.recentContacts(store.lends)
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

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(
      title = sheetTitle,
      onDelete = if (editingId == null) null else ({ confirmDelete = true }),
    )
    Column(
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 620.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
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

      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel(contactLabel)
        if (draft.contactName.isNotEmpty()) {
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(12.dp, DimoColors.canvas)
              .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            ContactAvatar(name = draft.contactName, size = 34.dp, radius = 11.dp)
            Text(
              text = draft.contactName,
              style = DimoFont.body(15f, FontWeight.Medium),
              color = DimoColors.ink,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
              modifier = Modifier.weight(1f),
            )
            if (!contactLocked) {
              Text(
                text = "Change",
                style = DimoFont.body(13f, FontWeight.Medium),
                color = DimoColors.green,
                modifier = Modifier.clickable {
                  if (ContactsLoader.hasPermission(context)) {
                    pickingContact = true
                  } else {
                    permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                  }
                },
              )
            }
          }
        } else if (!contactLocked) {
          Text(
            text = "Choose from contacts",
            style = DimoFont.body(15f, FontWeight.Medium),
            color = DimoColors.green,
            modifier = Modifier
              .fillMaxWidth()
              .cardSurface(12.dp, DimoColors.canvas)
              .clickable {
                if (ContactsLoader.hasPermission(context)) {
                  pickingContact = true
                } else {
                  permissionLauncher.launch(Manifest.permission.READ_CONTACTS)
                }
              }
              .padding(horizontal = 14.dp, vertical = 15.dp),
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
            DimoTextField(
              value = contactQuery,
              onValueChange = { contactQuery = it },
              placeholder = "Search contacts",
              height = 44.dp,
            )
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
                  radius = 10.dp,
                  fontSize = 13f,
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

        if (existing == null && !contactLocked && recentContacts.isNotEmpty()) {
          WrapRow {
            recentContacts.forEach { suggestion ->
              Chip(
                label = suggestion.contactName,
                selected = draft.contactId == suggestion.contactId,
                onClick = {
                  store.lendDraft = draft.copy(
                    contactName = suggestion.contactName,
                    contactId = suggestion.contactId,
                  )
                  pickingContact = false
                },
              )
            }
          }
        }
      }

      LabeledTextField(
        label = amountLabel,
        value = draft.amount,
        onValueChange = { next -> clampToSettlementLimit(next) },
        placeholder = "0",
        keyboardType = KeyboardType.Decimal,
      )

      if (settlementLimit != null) {
        Text(
          text = if (exceedsLimit) {
            when (kind) {
              LendKind.REPAID ->
                "Repayment cannot exceed ${Formatting.money(settlementLimit, store.currency)} outstanding."
              LendKind.RETURNED ->
                "Payment cannot exceed ${Formatting.money(settlementLimit, store.currency)} owed."
              else ->
                "Amount cannot exceed ${Formatting.money(settlementLimit, store.currency)}."
            }
          } else {
            when (kind) {
              LendKind.REPAID ->
                "${Formatting.money(settlementLimit, store.currency)} outstanding."
              LendKind.RETURNED ->
                "${Formatting.money(settlementLimit, store.currency)} owed."
              else ->
                "${Formatting.money(settlementLimit, store.currency)} available."
            }
          },
          style = DimoFont.body(12f),
          color = if (exceedsLimit) DimoColors.danger else DimoColors.muted,
        )
      }

      DateField(
        label = "When",
        millis = draft.date.toEpochMilli(),
        onChange = { millis ->
          store.lendDraft = draft.copy(date = Instant.ofEpochMilli(millis))
        },
      )

      LabeledTextField(
        label = "Note (optional)",
        value = draft.comment,
        onValueChange = { store.lendDraft = draft.copy(comment = it) },
        placeholder = commentPlaceholder,
      )

      PrimaryButton(
        title = saveTitle,
        enabled = canSave,
        onClick = { store.saveLend() },
      )
      Spacer(modifier = Modifier.height(4.dp))
    }
  }

  if (confirmDelete && editingId != null) {
    ConfirmDialog(
      title = deleteTitle,
      message = "${draft.contactName} · ${Formatting.money(amountValue, store.currency)}",
      confirmLabel = "Delete",
      onConfirm = { store.deleteLend(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}
