package app.dimo.android.features.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.domain.ExchangeRates
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.SplitMode
import app.dimo.android.domain.SplitSelectors
import app.dimo.android.domain.SplitShareInput
import app.dimo.android.domain.SplitShares
import app.dimo.android.features.common.DimoTextField
import app.dimo.android.features.common.PrimaryButton
import app.dimo.android.store.AppStore
import app.dimo.android.sync.LendUser
import java.util.UUID

data class SplitPersonDraft(
  val contactId: String,
  val contactName: String,
  /** What's typed for an EXACT or PERCENT split. */
  val value: String = "",
  /** Picked from Dimo search without a shared ledger yet; saving invites them. */
  val invite: LendUser? = null,
)

data class SplitDraft(
  val mode: SplitMode = SplitMode.EQUAL,
  /** null when the user paid. */
  val paidBy: String? = null,
  val people: List<SplitPersonDraft> = emptyList(),
) {
  val isActive: Boolean get() = people.isNotEmpty()

  /** Shares in minor units of [currency], or null when the split doesn't add up. */
  fun shares(totalMinor: Long, currency: String): SplitShares? = SplitSelectors.shares(
    totalMinor = totalMinor,
    mode = mode,
    people = people.map { person ->
      val typed = person.value.toDoubleOrNull() ?: 0.0
      SplitShareInput(
        contactId = person.contactId,
        value = if (mode == SplitMode.EXACT) ExchangeRates.toMinorUnits(typed, currency).toDouble() else typed,
      )
    },
  )

  /**
   * Someone else paying needs the user to have a share; the user paying needs
   * someone else to owe part of it.
   */
  fun isSavable(shares: SplitShares?): Boolean {
    if (shares == null || !isActive) return false
    return if (paidBy == null) shares.others.any { it.share > 0 } else shares.mine > 0
  }

  val title: String get() = "Split with " + people.joinToString(", ") { firstName(it.contactName) }

  val detail: String
    get() {
      val payer = people.firstOrNull { it.contactId == paidBy }
      val paid = payer?.let { "${firstName(it.contactName)} paid" } ?: "You paid"
      return "$paid · ${mode.label.lowercase()}"
    }

  private fun firstName(name: String) = name.trim().split(" ").firstOrNull().orEmpty().ifEmpty { name }
}

/**
 * The split step of the expense sheet: who shares the bill, who paid it and
 * how it divides. The expense itself records only the user's share; the rest
 * becomes lending entries. Port of `SplitStep` in
 * `ios-native/Dimo/Features/AddExpense/SplitStep.swift`.
 */
@Composable
fun SplitStep(
  store: AppStore,
  draft: SplitDraft,
  onChange: (SplitDraft) -> Unit,
  totalMinor: Long,
  currency: String,
  onDone: () -> Unit,
) {
  val sharing = store.lendingSharing
  val (recentContacts, knownContacts) = lendPeople(store.lends, sharing)
  var query by remember { mutableStateOf("") }
  val typed = query.trim()
  val picked = draft.people.map { it.contactId }.toSet()
  val shares = if (totalMinor > 0) draft.shares(totalMinor, currency) else null
  val payer = draft.people.firstOrNull { it.contactId == draft.paidBy }
  val savable = draft.isSavable(shares)
  val canFinish = !draft.isActive || savable || totalMinor == 0L

  fun format(minor: Long?): String =
    minor?.let { Formatting.money(ExchangeRates.toMajorUnits(it, currency), currency) } ?: "—"

  fun addPerson(contactId: String, contactName: String, invite: LendUser? = null) {
    query = ""
    if (contactId in picked) return
    onChange(draft.copy(people = draft.people + SplitPersonDraft(contactId, contactName, invite = invite)))
  }

  // A typed name that matches someone already tracked continues their
  // balance; any other name starts a new person.
  fun addTyped() {
    if (typed.isEmpty()) return
    val known = knownContacts.firstOrNull { it.contactName.trim().equals(typed, ignoreCase = true) }
    if (known != null) {
      addPerson(known.contactId, known.contactName)
    } else {
      addPerson("contact_${UUID.randomUUID().toString().lowercase()}", typed)
    }
  }

  fun pickDimoUser(user: LendUser) {
    if (user.relation == "invitedYou") {
      store.showToast("${user.name} already invited you. Accept their invite in Lending first.")
      return
    }
    val known = user.contactId
    if (known != null) {
      // Already shared, or already invited for this contact.
      addPerson(known, user.name)
    } else {
      addPerson("contact_${UUID.randomUUID().toString().lowercase()}", user.name, invite = user)
    }
  }

  fun removePerson(contactId: String) {
    onChange(
      draft.copy(
        paidBy = draft.paidBy.takeIf { it != contactId },
        people = draft.people.filter { it.contactId != contactId },
      ),
    )
  }

  fun setValue(contactId: String, value: String) {
    onChange(
      draft.copy(
        people = draft.people.map { if (it.contactId == contactId) it.copy(value = sanitizeDecimal(value)) else it },
      ),
    )
  }

  val problem = when {
    !draft.isActive || totalMinor == 0L || savable -> null
    shares == null -> if (draft.mode == SplitMode.PERCENT) {
      "Shares add up to more than 100%."
    } else {
      "Shares add up to more than ${format(totalMinor)}."
    }
    payer != null -> "Your share is zero — nothing to record."
    else -> "Nobody else has a share yet."
  }
  val note = problem ?: if (payer != null && shares != null) {
    "You owe ${payer.contactName} ${format(shares.mine)}. Only your share counts as spending."
  } else {
    "Only your share counts as spending. The rest goes to Lending."
  }

  Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
    Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      Box(
        modifier = Modifier
          .size(36.dp)
          .clip(RoundedCornerShape(50))
          .clickable(onClick = onDone),
        contentAlignment = Alignment.Center,
      ) {
        Icon(
          imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
          contentDescription = "Back to expense",
          tint = DimoColors.ink,
        )
      }
      Text(
        text = if (totalMinor > 0) "Split ${format(totalMinor)}" else "Split expense",
        style = DimoFont.display(18f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
      LendContactField(
        name = query,
        searching = true,
        knownContacts = knownContacts,
        sharing = sharing,
        onEdit = { query = it },
        onPickContact = { addPerson(it.contactId, it.contactName) },
        onPickDimoUser = ::pickDimoUser,
        placeholder = "Add a name or Dimo email",
        excludedContactIds = picked,
      )
      val unpicked = recentContacts.filter { it.contactId !in picked }
      if (typed.isNotEmpty()) {
        Text(
          text = "Add “$typed”",
          style = DimoFont.body(13f, FontWeight.Medium),
          color = DimoColors.green,
          modifier = Modifier.clickable { addTyped() },
        )
      } else if (unpicked.isNotEmpty()) {
        Row(
          modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          unpicked.forEach { suggestion ->
            Chip(
              label = suggestion.contactName,
              selected = false,
              onClick = { addPerson(suggestion.contactId, suggestion.contactName) },
            )
          }
        }
      }
    }

    if (draft.isActive) {
      Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        SplitMenu(
          title = payer?.let { "${it.contactName} paid" } ?: "You paid",
          options = listOf<Pair<String, String?>>("You paid" to null) +
            draft.people.map { "${it.contactName} paid" to it.contactId },
          onSelect = { onChange(draft.copy(paidBy = it)) },
          modifier = Modifier.weight(1f),
        )
        SplitMenu(
          title = draft.mode.label,
          options = SplitMode.entries.map { it.label to it },
          onSelect = { onChange(draft.copy(mode = it)) },
          modifier = Modifier.weight(1f),
        )
      }

      Column(
        modifier = Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(12.dp))
          .background(DimoColors.surface)
          .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp)),
      ) {
        ShareRow(name = "You") {
          Text(text = format(shares?.mine), style = DimoFont.body(15f), color = DimoColors.muted)
          // Lines up with the remove buttons on everyone else's rows.
          Spacer(modifier = Modifier.width(32.dp))
        }
        draft.people.forEach { person ->
          HorizontalDivider(color = DimoColors.line)
          ShareRow(name = person.contactName) {
            if (draft.mode == SplitMode.EQUAL) {
              Text(
                text = format(shares?.shareFor(person.contactId)),
                style = DimoFont.body(15f),
                color = DimoColors.muted,
              )
            } else {
              val kind = if (draft.mode == SplitMode.PERCENT) "percentage" else "amount"
              DimoTextField(
                value = person.value,
                onValueChange = { setValue(person.contactId, it) },
                placeholder = "0",
                keyboardType = KeyboardType.Decimal,
                height = 36.dp,
                textAlign = TextAlign.End,
                trailing = if (draft.mode == SplitMode.PERCENT) {
                  { Text(text = "%", style = DimoFont.body(14f), color = DimoColors.muted) }
                } else {
                  null
                },
                modifier = Modifier
                  .width(104.dp)
                  .semantics { contentDescription = "${person.contactName}'s $kind" },
              )
            }
            Box(
              modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(50))
                .clickable { removePerson(person.contactId) },
              contentAlignment = Alignment.Center,
            ) {
              Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Remove ${person.contactName}",
                tint = DimoColors.faint,
                modifier = Modifier.size(14.dp),
              )
            }
          }
        }
      }

      Text(
        text = note,
        style = DimoFont.body(12f),
        color = if (problem == null) DimoColors.muted else DimoColors.danger,
      )
    }

    if (draft.isActive) {
      PrimaryButton(title = "Done", enabled = canFinish, onClick = onDone)
    } else {
      Text(
        text = "Cancel",
        style = DimoFont.body(16f, FontWeight.SemiBold),
        color = DimoColors.ink,
        textAlign = TextAlign.Center,
        modifier = Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(14.dp))
          .background(DimoColors.canvas)
          .border(1.dp, DimoColors.line, RoundedCornerShape(14.dp))
          .clickable(onClick = onDone)
          .padding(vertical = 16.dp),
      )
    }
  }
}

@Composable
private fun ShareRow(name: String, trailing: @Composable () -> Unit) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .heightIn(min = 48.dp)
      .padding(start = 14.dp, end = 6.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(4.dp),
  ) {
    Text(
      text = name,
      style = DimoFont.body(15f, FontWeight.Medium),
      color = DimoColors.ink,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier.weight(1f),
    )
    trailing()
  }
}

@Composable
private fun <T> SplitMenu(
  title: String,
  options: List<Pair<String, T>>,
  onSelect: (T) -> Unit,
  modifier: Modifier = Modifier,
) {
  var expanded by remember { mutableStateOf(false) }
  Box(modifier = modifier) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .height(40.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(DimoColors.surface)
        .border(1.dp, DimoColors.line, RoundedCornerShape(12.dp))
        .clickable { expanded = true }
        .padding(horizontal = 12.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      Text(
        text = title,
        style = DimoFont.body(14f, FontWeight.Medium),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.weight(1f),
      )
      Icon(
        imageVector = Icons.Filled.KeyboardArrowDown,
        contentDescription = null,
        tint = DimoColors.muted,
        modifier = Modifier.size(16.dp),
      )
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
      options.forEach { (label, value) ->
        DropdownMenuItem(
          text = { Text(text = label, style = DimoFont.body(14f), color = DimoColors.ink) },
          onClick = {
            onSelect(value)
            expanded = false
          },
        )
      }
    }
  }
}
