package app.dimo.android.features.email

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailSyncWindow
import app.dimo.android.data.model.OpenRouterAccessMode
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.SheetContainer
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.email.openrouter.OpenRouterModel

/**
 * Port of `EmailAccountsSheet.swift` plus `OpenRouterModelPicker.swift`.
 *
 * Combines Gmail account management, the sync window, and OpenRouter provider
 * setup into one sheet, matching the single gear entry point on the Email tab.
 */
@Composable
fun EmailSettingsSheet(
  store: EmailFeatureStore,
  gmailConfigured: Boolean,
  onClose: () -> Unit,
) {
  var disconnectCandidate by remember { mutableStateOf<EmailUIAccount?>(null) }
  var confirmReanalyse by remember { mutableStateOf(false) }
  var showModelPicker by remember { mutableStateOf(false) }

  SheetContainer(title = "Email settings", onClose = onClose) {
    Column(
      verticalArrangement = Arrangement.spacedBy(18.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 640.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 28.dp),
    ) {
      // Accounts
      EmailSectionLabel("Gmail accounts")
      if (!gmailConfigured) {
        SettingsNote(
          "Gmail OAuth is not configured for this build. Add android-native/gmail.properties " +
            "with an OAuth client for this package and signing key.",
        )
      }
      if (store.accounts.isEmpty()) {
        SettingsNote("No Gmail accounts connected.")
      } else {
        store.accounts.forEach { account ->
          AccountRow(
            account = account,
            onReconnect = { store.reconnectAccount(account.id) },
            onDisconnect = { disconnectCandidate = account },
          )
        }
      }
      ActionButton(
        title = "Connect Gmail",
        onClick = store::connectAccount,
        variant = ActionButtonVariant.Accent,
        enabled = gmailConfigured,
      )

      // Sync window
      EmailSectionLabel("Sync email from")
      SettingsNote(
        "Choose how far back Dimo reads Gmail on this device. Analyzed suggestions still " +
          "sync through Dimo for restore.",
      )
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        EmailSyncWindow.entries.forEach { window ->
          Chip(
            label = window.title,
            selected = store.syncWindow == window,
            onClick = { store.selectSyncWindow(window) },
          )
        }
      }

      // Analyzer
      EmailSectionLabel("Analysis")
      SettingsNote(store.analysisStatusDetail)
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(
          label = "Off",
          selected = store.selectedProvider == null,
          onClick = { store.selectProvider(null) },
        )
        Chip(
          label = "Use OpenRouter",
          selected = store.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER,
          onClick = { store.selectProvider(EmailAnalysisProvider.OPEN_ROUTER) },
        )
      }

      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Chip(
          label = "Free models",
          selected = store.openRouterAccessMode == OpenRouterAccessMode.FREE_SHARED,
          onClick = { store.selectOpenRouterAccessMode(OpenRouterAccessMode.FREE_SHARED) },
        )
        Chip(
          label = "Bring your own key",
          selected = store.openRouterAccessMode == OpenRouterAccessMode.BRING_YOUR_OWN_KEY,
          onClick = {
            store.selectOpenRouterAccessMode(OpenRouterAccessMode.BRING_YOUR_OWN_KEY)
          },
        )
      }

      OpenRouterStatusRow(store)

      when (store.openRouterAccessMode) {
        OpenRouterAccessMode.FREE_SHARED -> SettingsNote(
          "Free models need an online Dimo session. No OpenRouter key is stored on this " +
            "device; selected email text is sent through Dimo's servers to OpenRouter.",
        )

        OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> {
          SettingsNote(
            "Use a dedicated, revocable OpenRouter key with a spending limit. The key stays " +
              "in this device's encrypted storage. Analysis goes from this device to " +
              "OpenRouter; analyzed suggestions sync through Dimo.",
          )
          OutlinedTextField(
            value = store.openRouterApiKeyInput,
            onValueChange = { store.openRouterApiKeyInput = it },
            singleLine = true,
            label = { Text("OpenRouter API key") },
            textStyle = DimoFont.body(14f),
            modifier = Modifier.fillMaxWidth(),
          )
          Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionButton(
              title = "Save key",
              onClick = store::saveOpenRouterKey,
              modifier = Modifier.weight(1f),
              variant = ActionButtonVariant.Accent,
              enabled = store.openRouterApiKeyInput.isNotBlank(),
            )
            ActionButton(
              title = "Remove key",
              onClick = store::removeOpenRouterKey,
              modifier = Modifier.weight(1f),
              variant = ActionButtonVariant.Danger,
            )
          }
        }
      }

      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ActionButton(
          title = if (store.isRefreshingOpenRouterModels) "Loading…" else "Refresh models",
          onClick = store::refreshOpenRouterModels,
          modifier = Modifier.weight(1f),
          enabled = !store.isRefreshingOpenRouterModels,
        )
        ActionButton(
          title = "Choose model",
          onClick = { showModelPicker = true },
          modifier = Modifier.weight(1f),
          enabled = store.openRouterModels.isNotEmpty(),
        )
      }
      store.selectedOpenRouterModel?.let { model ->
        SettingsNote("Selected model: ${model.name}")
      }

      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        ActionButton(
          title = "Retry connection",
          onClick = store::retryOpenRouterConnection,
          modifier = Modifier.weight(1f),
        )
        ActionButton(
          title = "Retry analysis",
          onClick = store::retryOpenRouterAnalysis,
          modifier = Modifier.weight(1f),
        )
      }

      EmailSectionLabel("Maintenance")
      SettingsNote(
        "Resets every eligible unreviewed email, updates the UI, then reruns OpenRouter " +
          "analysis.",
      )
      ActionButton(
        title = "Reanalyse email suggestions",
        onClick = { confirmReanalyse = true },
        enabled = !store.isReanalyzing,
      )

      ActionButton(title = "Done", onClick = onClose)
    }
  }

  disconnectCandidate?.let { account ->
    AlertDialog(
      onDismissRequest = { disconnectCandidate = null },
      title = { Text("Disconnect ${account.emailAddress}?") },
      text = {
        Text(
          "Dimo will delete this account's device-only Gmail credential and all local email " +
            "suggestions. Existing Dimo transactions are unchanged. Prefer Reconnect Gmail " +
            "when access expires so pending local suggestions stay on this device. Reviewed " +
            "suggestions remain in sync and return if you reconnect the same account.",
          style = DimoFont.body(13f),
        )
      },
      confirmButton = {
        TextButton(onClick = {
          store.disconnectAccount(account.id)
          disconnectCandidate = null
        }) { Text("Disconnect") }
      },
      dismissButton = {
        TextButton(onClick = { disconnectCandidate = null }) { Text("Cancel") }
      },
      containerColor = DimoColors.surface,
    )
  }

  if (confirmReanalyse) {
    AlertDialog(
      onDismissRequest = { confirmReanalyse = false },
      title = { Text("Reanalyse email suggestions?") },
      text = {
        Text(
          "Dimo will rerun OpenRouter for every unreviewed email whose content is still " +
            "retained. Reviewed suggestions and existing Dimo transactions are unchanged.",
          style = DimoFont.body(13f),
        )
      },
      confirmButton = {
        TextButton(onClick = {
          store.reanalyzeAllEmails()
          confirmReanalyse = false
        }) { Text("Reanalyse") }
      },
      dismissButton = {
        TextButton(onClick = { confirmReanalyse = false }) { Text("Cancel") }
      },
      containerColor = DimoColors.surface,
    )
  }

  if (showModelPicker) {
    OpenRouterModelPickerSheet(
      store = store,
      onClose = { showModelPicker = false },
    )
  }
}

@Composable
private fun AccountRow(
  account: EmailUIAccount,
  onReconnect: () -> Unit,
  onDisconnect: () -> Unit,
) {
  Column(
    verticalArrangement = Arrangement.spacedBy(8.dp),
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(14.dp))
      .background(DimoColors.canvasDeep)
      .padding(14.dp),
  ) {
    Text(
      account.emailAddress,
      style = DimoFont.body(14f, FontWeight.Medium),
      color = DimoColors.ink,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
    )
    Text(
      account.statusDetail ?: account.syncState.title,
      style = DimoFont.body(11f),
      color = if (account.syncState == EmailUIAccountSyncState.FAILED ||
        account.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT
      ) {
        DimoColors.danger
      } else {
        DimoColors.muted
      },
    )
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
      ActionButton(title = "Reconnect", onClick = onReconnect, modifier = Modifier.weight(1f))
      ActionButton(
        title = "Disconnect",
        onClick = onDisconnect,
        modifier = Modifier.weight(1f),
        variant = ActionButtonVariant.Danger,
      )
    }
  }
}

@Composable
private fun OpenRouterStatusRow(store: EmailFeatureStore) {
  when (val state = store.openRouterConnectionState) {
    is OpenRouterUIConnectionState.Connected -> {
      val credit = state.limitRemaining?.let { remaining ->
        state.creditLimit?.let { limit ->
          "$%.2f left · $%.2f limit".format(remaining, limit)
        } ?: "$%.2f credit left".format(remaining)
      }
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        StatusBadge(label = state.label, tone = StatusBadgeTone.Green)
        credit?.let {
          Text(it, style = DimoFont.body(11f), color = DimoColors.muted)
        }
      }
    }

    is OpenRouterUIConnectionState.Validating -> Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
      CircularProgressIndicator(
        strokeWidth = 2.dp,
        color = DimoColors.green,
        modifier = Modifier.size(14.dp),
      )
      Text("Validating…", style = DimoFont.body(11f), color = DimoColors.muted)
    }

    is OpenRouterUIConnectionState.Failed ->
      Text(state.message, style = DimoFont.body(11f), color = DimoColors.danger)

    OpenRouterUIConnectionState.Disconnected ->
      Text("Not connected", style = DimoFont.body(11f), color = DimoColors.muted)
  }
}

/**
 * Port of `OpenRouterModelPicker.swift`. Selecting a model without a
 * zero-data-retention route requires explicit consent, which is what the
 * `allowNonZDR` flag carries into the controller.
 */
@Composable
fun OpenRouterModelPickerSheet(store: EmailFeatureStore, onClose: () -> Unit) {
  var filter by remember { mutableStateOf(OpenRouterModelFilter.ALL) }
  var nonZDRCandidate by remember { mutableStateOf<OpenRouterModel?>(null) }

  val models = store.openRouterModels.filter { model ->
    when (filter) {
      OpenRouterModelFilter.ALL -> true
      OpenRouterModelFilter.FREE -> model.isFree
      OpenRouterModelFilter.ZDR -> model.hasZDREndpoint
    }
  }

  SheetContainer(title = "OpenRouter model", onClose = onClose) {
    Column(
      verticalArrangement = Arrangement.spacedBy(12.dp),
      modifier = Modifier
        .fillMaxWidth()
        .heightIn(max = 560.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 24.dp),
    ) {
      Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OpenRouterModelFilter.entries.forEach { option ->
          Chip(
            label = option.title,
            selected = filter == option,
            onClick = { filter = option },
          )
        }
      }
      if (models.isEmpty()) {
        SettingsNote("No models match this filter. Refresh models in Email settings.")
      }
      models.forEach { model ->
        val selected = store.selectedOpenRouterModelId == model.id
        Column(
          verticalArrangement = Arrangement.spacedBy(4.dp),
          modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (selected) DimoColors.greenSoft else DimoColors.canvasDeep)
            .border(
              1.dp,
              if (selected) DimoColors.green else DimoColors.line,
              RoundedCornerShape(12.dp),
            )
            .clickable {
              if (model.hasZDREndpoint) {
                store.selectOpenRouterModel(model.id, allowNonZDR = false)
                onClose()
              } else {
                nonZDRCandidate = model
              }
            }
            .padding(12.dp),
        ) {
          Text(
            model.name,
            style = DimoFont.body(14f, FontWeight.Medium),
            color = DimoColors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
          Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (model.isFree) StatusBadge(label = "FREE", tone = StatusBadgeTone.Green)
            if (model.hasZDREndpoint) StatusBadge(label = "ZDR", tone = StatusBadgeTone.Green)
            if (!model.isFree && model.hasKnownPrice) {
              val input = model.inputPricePerMillion ?: 0.0
              val output = model.outputPricePerMillion ?: 0.0
              StatusBadge(label = "$%.2f/$%.2f per M".format(input, output))
            }
          }
          Text(model.id, style = DimoFont.body(10f), color = DimoColors.faint)
        }
      }
      ActionButton(title = "Close", onClick = onClose)
    }
  }

  nonZDRCandidate?.let { model ->
    AlertDialog(
      onDismissRequest = { nonZDRCandidate = null },
      title = { Text("Use a non-ZDR model?") },
      text = {
        Text(
          "OpenRouter or the selected provider may retain email content under its own " +
            "policy. Analyzed suggestions, including email text, still sync through Dimo " +
            "for restore.",
          style = DimoFont.body(13f),
        )
      },
      confirmButton = {
        TextButton(onClick = {
          store.selectOpenRouterModel(model.id, allowNonZDR = true)
          nonZDRCandidate = null
          onClose()
        }) { Text("Use anyway") }
      },
      dismissButton = {
        TextButton(onClick = { nonZDRCandidate = null }) { Text("Cancel") }
      },
      containerColor = DimoColors.surface,
    )
  }
}

@Composable
private fun SettingsNote(text: String) {
  Text(text = text, style = DimoFont.body(12f), color = DimoColors.muted)
}
