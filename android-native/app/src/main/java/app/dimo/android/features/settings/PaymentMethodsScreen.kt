package app.dimo.android.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.SeedData
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.domain.Formatting
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.DimoDivider
import app.dimo.android.features.common.LabeledTextField
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionLabel
import app.dimo.android.features.common.SectionTitle
import app.dimo.android.features.common.WrapRow
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore

/**
 * Standalone payment methods route. The same content is embedded in
 * [SettingsScreen] as a card, mirroring `PaymentMethodsManager` on iOS.
 */
@Composable
fun PaymentMethodsScreen(
  store: AppStore,
  onBack: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Column(
    modifier = modifier
      .fillMaxSize()
      .background(DimoColors.canvas)
      .verticalScroll(rememberScrollState())
      .padding(horizontal = 20.dp)
      .padding(top = 12.dp, bottom = 40.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    ScreenHeader(
      title = "Payment methods",
      onBack = onBack,
      modifier = Modifier.statusBarsPadding(),
    )
    PaymentMethodsCard(store = store)
  }
}

/**
 * Add, edit, archive and default-select payment methods. At least one method
 * must stay active and Cash can never be archived — both rules live in
 * `AppStore.setPaymentMethodArchived`, so failures surface as toasts.
 */
@Composable
fun PaymentMethodsCard(
  store: AppStore,
  modifier: Modifier = Modifier,
) {
  var editingId by remember { mutableStateOf<String?>(null) }
  var isNew by remember { mutableStateOf(false) }
  var draftName by remember { mutableStateOf("") }
  var draftType by remember { mutableStateOf(PaymentMethodType.UPI) }
  var draftDetail by remember { mutableStateOf("") }
  var error by remember { mutableStateOf("") }
  var confirmArchiveId by remember { mutableStateOf<String?>(null) }

  val active = store.paymentMethods.filter { !it.archived }
  val archived = store.paymentMethods.filter { it.archived }
  val editing = isNew || editingId != null
  val currencySymbol = Formatting.currencySymbol(store.currency)

  fun resetEditor() {
    isNew = false
    editingId = null
    error = ""
  }

  DimoCard(modifier = modifier, verticalSpacing = 14.dp) {
    Row(verticalAlignment = Alignment.CenterVertically) {
      Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        SectionTitle("Payment methods")
        Text(
          text = "Choose how new expenses are paid.",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
        )
      }
      if (!editing) {
        Text(
          text = "Add",
          style = DimoFont.body(14f, FontWeight.SemiBold),
          color = DimoColors.onGreen,
          modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .background(DimoColors.green)
            .clickable {
              isNew = true
              editingId = null
              draftName = ""
              draftType = PaymentMethodType.UPI
              draftDetail = ""
              error = ""
            }
            .padding(horizontal = 18.dp, vertical = 11.dp),
        )
      }
    }

    if (editing) {
      Column(
        modifier = Modifier
          .fillMaxWidth()
          .cardSurface(16.dp, DimoColors.canvas)
          .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
      ) {
        SectionTitle(if (isNew) "New payment method" else "Edit payment method")

        LabeledTextField(
          label = "Display name",
          value = draftName,
          onValueChange = { draftName = it },
          placeholder = "e.g. HDFC Debit",
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          SectionLabel("Type")
          WrapRow {
            PaymentMethodType.entries.forEach { type ->
              Chip(
                label = type.wire,
                selected = draftType == type,
                onClick = {
                  draftType = type
                  if (type == PaymentMethodType.CASH) draftDetail = ""
                },
              )
            }
          }
        }

        if (draftType != PaymentMethodType.CASH) {
          LabeledTextField(
            label = "Identifier",
            value = draftDetail,
            onValueChange = { draftDetail = it },
            placeholder = if (draftType == PaymentMethodType.UPI) {
              "e.g. aarav@upi or ..42"
            } else {
              "e.g. ..42"
            },
          )
        }

        if (error.isNotEmpty()) {
          Text(text = error, style = DimoFont.body(12f), color = DimoColors.danger)
        }

        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
          ActionButton(
            title = "Cancel",
            onClick = { resetEditor() },
            modifier = Modifier.weight(1f),
          )
          ActionButton(
            title = "Save method",
            onClick = {
              val message = store.savePaymentMethod(
                id = if (isNew) null else editingId,
                name = draftName,
                type = draftType,
                detail = draftDetail,
              )
              if (message != null) error = message else resetEditor()
            },
            modifier = Modifier.weight(1f),
            variant = ActionButtonVariant.Accent,
          )
        }
      }
    }

    Column {
      active.forEachIndexed { index, method ->
        MethodRow(
          method = method,
          currencySymbol = currencySymbol,
          onSetDefault = { store.setDefaultPaymentMethod(method.id) },
          onEdit = {
            isNew = false
            editingId = method.id
            draftName = method.name
            draftType = method.type
            draftDetail = method.detail
            error = ""
          },
          onArchive = { confirmArchiveId = method.id },
          onRestore = null,
        )
        if (index != active.lastIndex) DimoDivider()
      }
    }

    if (archived.isNotEmpty()) {
      SectionLabel("Archived")
      Column {
        archived.forEachIndexed { index, method ->
          MethodRow(
            method = method,
            currencySymbol = currencySymbol,
            onSetDefault = null,
            onEdit = null,
            onArchive = null,
            onRestore = { store.setPaymentMethodArchived(method.id, archived = false) },
          )
          if (index != archived.lastIndex) DimoDivider()
        }
      }
    }

    Text(
      text = "Archived methods stay attached to past transactions.",
      style = DimoFont.body(11f),
      color = DimoColors.muted,
    )
  }

  val archiveId = confirmArchiveId
  if (archiveId != null) {
    val name = store.paymentMethods.firstOrNull { it.id == archiveId }?.name ?: "this method"
    ConfirmDialog(
      title = "Archive $name?",
      message = "It stays on past transactions but won't be offered for new ones.",
      confirmLabel = "Archive",
      onConfirm = { store.setPaymentMethodArchived(archiveId, archived = true) },
      onDismiss = { confirmArchiveId = null },
    )
  }
}

@Composable
private fun MethodRow(
  method: PaymentMethodOption,
  currencySymbol: String,
  onSetDefault: (() -> Unit)?,
  onEdit: (() -> Unit)?,
  onArchive: (() -> Unit)?,
  onRestore: (() -> Unit)?,
) {
  Row(
    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Box(
      modifier = Modifier
        .size(40.dp)
        .clip(RoundedCornerShape(12.dp))
        .background(DimoColors.canvasDeep),
      contentAlignment = Alignment.Center,
    ) {
      Text(
        text = if (method.type == PaymentMethodType.CASH) {
          currencySymbol
        } else {
          method.name.take(1).uppercase()
        },
        style = DimoFont.display(14f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
    }
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
      ) {
        Text(
          text = method.name,
          style = DimoFont.body(14f, FontWeight.Medium),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        if (method.isDefault && !method.archived) {
          StatusBadge(label = "Default", tone = StatusBadgeTone.Green)
        }
        if (method.archived) StatusBadge(label = "Archived")
      }
      val subtitle = listOf(method.type.wire, method.detail)
        .filter { it.isNotEmpty() }
        .joinToString(" · ")
      Text(text = subtitle, style = DimoFont.body(12f), color = DimoColors.muted)
    }
    Column(
      horizontalAlignment = Alignment.End,
      verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
      if (onRestore != null) {
        RowAction(label = "Restore", color = DimoColors.green, onClick = onRestore)
      }
      if (onSetDefault != null && !method.isDefault) {
        RowAction(label = "Set default", color = DimoColors.green, onClick = onSetDefault)
      }
      if (onEdit != null) {
        RowAction(label = "Edit", color = DimoColors.body, onClick = onEdit)
      }
      if (onArchive != null && method.id != SeedData.CASH_PAYMENT_METHOD.id) {
        RowAction(label = "Archive", color = DimoColors.danger, onClick = onArchive)
      }
    }
  }
}

@Composable
private fun RowAction(
  label: String,
  color: Color,
  onClick: () -> Unit,
) {
  Text(
    text = label,
    style = DimoFont.body(12f, FontWeight.Medium),
    color = color,
    modifier = Modifier
      .clip(RoundedCornerShape(8.dp))
      .clickable(onClick = onClick)
      .padding(horizontal = 6.dp, vertical = 2.dp),
  )
}
