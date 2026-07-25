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
import app.dimo.android.features.common.SheetHeader
import app.dimo.android.features.common.WrapRow
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import java.time.Instant

/**
 * Add / edit a lend or repayment. Port of
 * `ios-native/Dimo/Features/Lending/AddLendSheet.swift`.
 *
 * Contacts come from `READ_CONTACTS`; only the identifier and name are saved.
 * Repayments are capped at the contact's outstanding balance, excluding the row
 * being edited.
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
  val kind = existing?.kind ?: draft.kind
  val isRepayment = kind == LendKind.REPAID

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

  val outstanding = draft.contactId?.let { contactId ->
    LendSelectors.outstandingAmount(
      contactId = contactId,
      lends = store.lends,
      excludingLendId = existing?.id,
    )
  } ?: 0.0
  val amountValue = draft.amount.toDoubleOrNull() ?: 0.0
  val exceedsOutstanding = isRepayment && amountValue > outstanding + 0.000_001
  val canSave = amountValue > 0 &&
    draft.contactName.trim().isNotEmpty() &&
    (draft.contactId != null || existing != null) &&
    !exceedsOutstanding

  val recentContacts = LendSelectors.recentContacts(store.lends)
  val filteredContacts = remember(contacts, contactQuery) {
    val query = contactQuery.trim().lowercase()
    if (query.isEmpty()) contacts.take(40) else {
      contacts.filter { it.name.lowercase().contains(query) }.take(40)
    }
  }

  DimoBottomSheet(onDismiss = onClose) {
    SheetHeader(
      title = when {
        editingId != null && isRepayment -> "Edit repayment"
        editingId != null -> "Edit lend"
        isRepayment -> "Got money back"
        else -> "Lend money"
      },
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
      Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FieldLabel("Person")
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
            if (existing == null) {
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
        } else {
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

        if (pickingContact) {
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

        if (existing == null && recentContacts.isNotEmpty()) {
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
        label = if (isRepayment) "Amount received" else "Amount lent",
        value = draft.amount,
        onValueChange = { next -> store.lendDraft = draft.copy(amount = sanitizeDecimal(next)) },
        placeholder = "0",
        keyboardType = KeyboardType.Decimal,
      )

      if (isRepayment) {
        Text(
          text = if (exceedsOutstanding) {
            "Repayment cannot exceed ${Formatting.money(outstanding, store.currency)} outstanding."
          } else {
            "${Formatting.money(outstanding, store.currency)} outstanding."
          },
          style = DimoFont.body(12f),
          color = if (exceedsOutstanding) DimoColors.danger else DimoColors.muted,
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
        placeholder = "Dinner, cab fare…",
      )

      PrimaryButton(
        title = when {
          editingId != null -> "Save changes"
          isRepayment -> "Record repayment"
          else -> "Save lend"
        },
        enabled = canSave,
        onClick = { store.saveLend() },
      )
      Spacer(modifier = Modifier.height(4.dp))
    }
  }

  if (confirmDelete && editingId != null) {
    ConfirmDialog(
      title = if (isRepayment) "Delete this repayment?" else "Delete this lend?",
      message = "${draft.contactName} · ${Formatting.money(amountValue, store.currency)}",
      confirmLabel = "Delete",
      onConfirm = { store.deleteLend(editingId) },
      onDismiss = { confirmDelete = false },
    )
  }
}
