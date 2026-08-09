package app.dimo.android.features.email

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailSyncWindow
import app.dimo.android.data.model.OpenRouterAccessMode
import app.dimo.android.data.model.OpenRouterPrivacyMode
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PillDropdown
import app.dimo.android.design.SheetContainer
import app.dimo.android.design.StatusBadge
import app.dimo.android.design.StatusBadgeTone
import app.dimo.android.email.openrouter.OpenRouterModel

/**
 * Port of `EmailAccountsSheet.swift` plus `OpenRouterModelPicker.swift`.
 *
 * Combines Gmail account management, the sync window, and OpenRouter provider setup.
 * The content is shared by the full Settings destination and this sheet wrapper.
 */
@Composable
fun EmailSettingsSheet(
  store: EmailFeatureStore,
  gmailConfigured: Boolean,
  onClose: () -> Unit,
) {
  SheetContainer(title = "Email settings", onClose = onClose) {
    EmailSettingsContent(
      store = store,
      gmailConfigured = gmailConfigured,
      onDone = onClose,
      modifier = Modifier
        .heightIn(max = 640.dp)
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 20.dp)
        .padding(bottom = 28.dp),
    )
  }
}

/** Email settings body shared by the full Settings destination and legacy sheet callers. */
@Composable
fun EmailSettingsContent(
  store: EmailFeatureStore,
  gmailConfigured: Boolean,
  modifier: Modifier = Modifier,
  onDone: (() -> Unit)? = null,
) {
  var disconnectCandidate by remember { mutableStateOf<EmailUIAccount?>(null) }
  var confirmReanalyse by remember { mutableStateOf(false) }
  var showModelPicker by remember { mutableStateOf(false) }

  LaunchedEffect(store.openRouterConnectionState, store.openRouterModels.size) {
    if (store.openRouterConnectionState is OpenRouterUIConnectionState.Connected &&
      store.openRouterModels.isEmpty()
    ) {
      store.refreshOpenRouterModels()
    }
  }

  Column(
    verticalArrangement = Arrangement.spacedBy(22.dp),
    modifier = modifier.fillMaxWidth(),
  ) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
      EmailSectionHeader(
        title = "Gmail accounts",
        detail = "Read-only · latest ${store.syncWindow.title}",
      )

      EmailSettingsCard {
        Row(
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
          ) {
            Text(
              "Sync email from",
              style = DimoFont.body(13f, FontWeight.SemiBold),
              color = DimoColors.ink,
            )
            Text(
              "Choose how far back Dimo reads Gmail on this Android device. Analyzed " +
                "suggestions still sync through Dimo for restore.",
              style = DimoFont.body(11f),
              color = DimoColors.muted,
            )
          }
          if (store.isUpdatingSyncWindow) {
            CircularProgressIndicator(
              strokeWidth = 2.dp,
              color = DimoColors.green,
              modifier = Modifier.size(18.dp),
            )
          } else {
            PillDropdown(
              options = EmailSyncWindow.entries.toList(),
              selected = store.syncWindow,
              label = { it.title },
              onSelect = store::selectSyncWindow,
            )
          }
        }
      }

      if (store.accounts.isEmpty()) {
        EmailSettingsCard {
          Text(
            "No Gmail accounts connected.",
            style = DimoFont.body(13f),
            color = DimoColors.muted,
            textAlign = TextAlign.Center,
            modifier = Modifier
              .fillMaxWidth()
              .padding(vertical = 14.dp),
          )
        }
      } else {
        store.accounts.forEach { account ->
          AccountRow(
            account = account,
            onRefresh = { store.refreshAccount(account.id) },
            onReconnect = { store.reconnectAccount(account.id) },
            onDisconnect = { disconnectCandidate = account },
          )
        }
      }
      ActionButton(
        title = "Connect another Gmail account",
        onClick = store::connectAccount,
        variant = ActionButtonVariant.Secondary,
        enabled = gmailConfigured,
      )
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
      EmailSectionHeader(
        title = "Email analyzer",
        detail = if (store.selectedProvider == null) "Not configured" else store.activeAnalyzerTitle,
      )

      if (store.selectedProvider == null) {
        EmailSettingsCard {
          Row(
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
          ) {
            Icon(
              imageVector = Icons.Filled.Warning,
              contentDescription = null,
              tint = DimoColors.muted,
              modifier = Modifier.size(16.dp),
            )
            Text(
              "Email analysis is not configured. Connect OpenRouter with a valid key and " +
                "choose a model. Fetched emails wait on this Android device until analyzed; " +
                "analyzed suggestions then sync through Dimo for restore.",
              style = DimoFont.body(12f),
              color = DimoColors.body,
              modifier = Modifier.weight(1f),
            )
          }
        }
      }

      OpenRouterCard(
        store = store,
        onChooseModel = { showModelPicker = true },
      )

      EmailSettingsCard {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text(
            "Reanalyse email suggestions",
            style = DimoFont.body(13f, FontWeight.SemiBold),
            color = DimoColors.ink,
          )
          Text(
            "Resets every eligible unreviewed email, updates the UI, then reruns OpenRouter " +
              "analysis.",
            style = DimoFont.body(11f),
            color = DimoColors.muted,
          )
          ActionButton(
            title = if (store.isReanalyzing) "Reanalysing emails…" else "Reanalyse all emails",
            onClick = { confirmReanalyse = true },
            enabled = !store.isReanalyzing && store.accounts.isNotEmpty() && store.isOpenRouterReady,
          )
        }
      }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
      EmailSectionHeader(title = "Privacy")
      EmailSettingsCard {
        Row(
          verticalAlignment = Alignment.Top,
          horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
          Icon(
            imageVector = Icons.Filled.Lock,
            contentDescription = null,
            tint = DimoColors.body,
            modifier = Modifier.size(17.dp),
          )
          Text(
            privacyDescription(store),
            style = DimoFont.body(12f),
            color = DimoColors.body,
            modifier = Modifier.weight(1f),
          )
        }
      }
    }

    if (onDone != null) {
      ActionButton(title = "Done", onClick = onDone)
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
  onRefresh: () -> Unit,
  onReconnect: () -> Unit,
  onDisconnect: () -> Unit,
) {
  val needsAttention = account.syncState == EmailUIAccountSyncState.FAILED ||
    account.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT

  Column(
    verticalArrangement = Arrangement.spacedBy(12.dp),
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp))
      .padding(15.dp),
  ) {
    Row(
      verticalAlignment = Alignment.Top,
      horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      Box(
        modifier = Modifier
          .size(36.dp)
          .clip(RoundedCornerShape(11.dp))
          .background(DimoColors.greenSoft),
        contentAlignment = Alignment.Center,
      ) {
        Icon(
          imageVector = Icons.Filled.Email,
          contentDescription = null,
          tint = DimoColors.green,
          modifier = Modifier.size(17.dp),
        )
      }
      Column(
        modifier = Modifier.weight(1f),
        verticalArrangement = Arrangement.spacedBy(3.dp),
      ) {
        Text(
          account.emailAddress,
          style = DimoFont.body(14f, FontWeight.SemiBold),
          color = DimoColors.ink,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
        )
        Text(
          account.statusDetail ?: if (account.initialScanComplete) {
            "Ready to refresh"
          } else {
            "Seven-day scan not complete"
          },
          style = DimoFont.body(11f),
          color = if (needsAttention) DimoColors.danger else DimoColors.muted,
        )
      }
      if (account.syncState == EmailUIAccountSyncState.SYNCING) {
        CircularProgressIndicator(
          strokeWidth = 2.dp,
          color = DimoColors.green,
          modifier = Modifier.size(16.dp),
        )
      } else {
        StatusBadge(
          label = account.syncState.title,
          tone = if (needsAttention) StatusBadgeTone.Muted else StatusBadgeTone.Green,
        )
      }
    }

    account.lastError?.takeIf { it.isNotBlank() }?.let { error ->
      Text(error, style = DimoFont.body(11f), color = DimoColors.danger)
    }

    Box(Modifier.fillMaxWidth().height(1.dp).background(DimoColors.lineSoft))

    when {
      account.syncState == EmailUIAccountSyncState.NEEDS_RECONNECT -> Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        CompactTextAction("Reconnect Gmail", DimoColors.green, onReconnect)
        Spacer(Modifier.weight(1f))
        CompactTextAction("Disconnect", DimoColors.danger, onDisconnect)
      }

      account.syncState != EmailUIAccountSyncState.DISCONNECTED -> Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        CompactTextAction("Refresh", DimoColors.green, onRefresh)
        Spacer(Modifier.weight(1f))
        CompactTextAction("Disconnect", DimoColors.danger, onDisconnect)
      }

      else -> Text(
        "Reconnect from Connect Gmail to resume sync.",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
      )
    }
  }
}

@Composable
private fun OpenRouterCard(
  store: EmailFeatureStore,
  onChooseModel: () -> Unit,
) {
  EmailSettingsCard {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
      Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Box(
          modifier = Modifier
            .size(40.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(
              if (store.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
                DimoColors.greenSoft
              } else {
                DimoColors.canvasDeep
              },
            ),
          contentAlignment = Alignment.Center,
        ) {
          Icon(
            imageVector = if (store.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
              Icons.Filled.CheckCircle
            } else {
              Icons.Filled.Cloud
            },
            contentDescription = null,
            tint = if (store.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER) {
              DimoColors.green
            } else {
              DimoColors.muted
            },
            modifier = Modifier.size(19.dp),
          )
        }
        Column(
          modifier = Modifier.weight(1f),
          verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
          Text(
            "OpenRouter",
            style = DimoFont.body(14f, FontWeight.SemiBold),
            color = DimoColors.ink,
          )
          Text(
            if (store.openRouterAccessMode == OpenRouterAccessMode.FREE_SHARED) {
              "Free models via Dimo · no personal key · suggestions sync through Dimo"
            } else {
              "Bring your own key · Analysis via OpenRouter · suggestions sync through Dimo"
            },
            style = DimoFont.body(11f),
            color = DimoColors.muted,
          )
        }
        OpenRouterStatus(store)
      }

      OpenRouterAccessPicker(
        selected = store.openRouterAccessMode,
        onSelect = store::selectOpenRouterAccessMode,
      )

      when (store.openRouterAccessMode) {
        OpenRouterAccessMode.FREE_SHARED -> FreeOpenRouterBody(store, onChooseModel)
        OpenRouterAccessMode.BRING_YOUR_OWN_KEY -> ByokOpenRouterBody(store, onChooseModel)
      }
    }
  }
}

@Composable
private fun FreeOpenRouterBody(store: EmailFeatureStore, onChooseModel: () -> Unit) {
  when (val state = store.openRouterConnectionState) {
    is OpenRouterUIConnectionState.Failed -> {
      SettingsNote(state.message, color = DimoColors.danger)
      SettingsNote("Free models need an online Dimo session. No OpenRouter key is stored on this Android device.")
      ActionButton(
        title = "Retry free models",
        onClick = store::retryOpenRouterConnection,
        variant = ActionButtonVariant.Accent,
      )
    }

    OpenRouterUIConnectionState.Disconnected -> {
      SettingsNote(
        "Connect to Dimo sync to load free OpenRouter models. Selected email text is sent " +
          "through Dimo's servers to OpenRouter for analysis.",
      )
      ActionButton(
        title = "Load free models",
        onClick = store::retryOpenRouterConnection,
        variant = ActionButtonVariant.Accent,
      )
    }

    OpenRouterUIConnectionState.Validating -> ProgressStatus("Loading free OpenRouter models…")
    is OpenRouterUIConnectionState.Connected -> OpenRouterConnectedControls(
      store = store,
      showRemoveKey = false,
      onChooseModel = onChooseModel,
    )
  }
}

@Composable
private fun ByokOpenRouterBody(store: EmailFeatureStore, onChooseModel: () -> Unit) {
  when (val state = store.openRouterConnectionState) {
    is OpenRouterUIConnectionState.Failed -> {
      SettingsNote(state.message, color = DimoColors.danger)
      ActionButton(
        title = "Retry OpenRouter",
        onClick = store::retryOpenRouterConnection,
        variant = ActionButtonVariant.Accent,
      )
      OpenRouterKeyField(store)
      SettingsNote(
        "Retry uses the key already saved on this Android device. Enter a different key only " +
          "if you want to replace it.",
      )
      ActionButton(
        title = "Validate and save key",
        onClick = store::saveOpenRouterKey,
        enabled = store.openRouterApiKeyInput.isNotBlank(),
      )
    }

    OpenRouterUIConnectionState.Disconnected -> {
      OpenRouterKeyField(store)
      SettingsNote(
        "Use a dedicated, revocable OpenRouter key with a spending limit. The key stays in " +
          "this Android device's encrypted storage. Analysis goes from this Android device " +
          "to OpenRouter; analyzed suggestions sync through Dimo.",
      )
      ActionButton(
        title = "Validate and save key",
        onClick = store::saveOpenRouterKey,
        variant = ActionButtonVariant.Accent,
        enabled = store.openRouterApiKeyInput.isNotBlank(),
      )
    }

    OpenRouterUIConnectionState.Validating -> ProgressStatus("Validating key and loading models…")
    is OpenRouterUIConnectionState.Connected -> OpenRouterConnectedControls(
      store = store,
      showRemoveKey = true,
      onChooseModel = onChooseModel,
    )
  }
}

@Composable
private fun OpenRouterKeyField(store: EmailFeatureStore) {
  OutlinedTextField(
    value = store.openRouterApiKeyInput,
    onValueChange = { store.openRouterApiKeyInput = it },
    singleLine = true,
    placeholder = { Text("sk-or-v1-…", style = DimoFont.body(12f)) },
    textStyle = DimoFont.body(12f),
    visualTransformation = PasswordVisualTransformation(),
    shape = RoundedCornerShape(11.dp),
    colors = TextFieldDefaults.colors(
      focusedContainerColor = DimoColors.canvasDeep,
      unfocusedContainerColor = DimoColors.canvasDeep,
      disabledContainerColor = DimoColors.canvasDeep,
      focusedIndicatorColor = DimoColors.green,
      unfocusedIndicatorColor = DimoColors.line,
    ),
    modifier = Modifier.fillMaxWidth(),
  )
}

@Composable
private fun OpenRouterConnectedControls(
  store: EmailFeatureStore,
  showRemoveKey: Boolean,
  onChooseModel: () -> Unit,
) {
  var confirmNonZDR by remember { mutableStateOf(false) }

  Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
    if (store.selectedProvider == EmailAnalysisProvider.OPEN_ROUTER &&
      openRouterNeedsManualRetry(store.analysisStatusDetail)
    ) {
      SettingsNote(store.analysisStatusDetail, color = DimoColors.danger)
      ActionButton(
        title = "Retry OpenRouter analysis",
        onClick = store::retryOpenRouterAnalysis,
        variant = ActionButtonVariant.Accent,
      )
    }

    Column(
      modifier = Modifier
        .fillMaxWidth()
        .clip(RoundedCornerShape(11.dp))
        .background(DimoColors.canvasDeep)
        .clickable(onClick = onChooseModel)
        .padding(12.dp),
      verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
      Text(
        store.selectedOpenRouterModel?.name ?: "Choose an OpenRouter model",
        style = DimoFont.body(12f, FontWeight.SemiBold),
        color = DimoColors.ink,
      )
      Text(
        store.selectedOpenRouterModelId ?: "Choose a model",
        style = DimoFont.body(9f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }

    if (store.selectedProvider != EmailAnalysisProvider.OPEN_ROUTER &&
      store.selectedOpenRouterModel != null
    ) {
      ActionButton(
        title = "Use OpenRouter",
        onClick = {
          val model = store.selectedOpenRouterModel ?: return@ActionButton
          if (model.hasZDREndpoint) {
            store.selectOpenRouterModel(model.id, allowNonZDR = false)
          } else {
            confirmNonZDR = true
          }
        },
        variant = ActionButtonVariant.Accent,
      )
    }

    SettingsNote(
      if (store.openRouterPrivacyMode == OpenRouterPrivacyMode.ALLOW_NON_ZDR) {
        "Non-ZDR enabled for analysis. Analyzed suggestions still sync through Dimo with their email text."
      } else {
        "Zero-data-retention routes for analysis. Analyzed suggestions still sync through Dimo with their email text."
      },
      color = if (store.openRouterPrivacyMode == OpenRouterPrivacyMode.ALLOW_NON_ZDR) {
        DimoColors.danger
      } else {
        DimoColors.green
      },
    )

    store.selectedOpenRouterModel?.let { model ->
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
      ) {
        Text(
          "Zero-data-retention routes only",
          style = DimoFont.body(11f, FontWeight.Medium),
          color = DimoColors.ink,
          modifier = Modifier.weight(1f),
        )
        Switch(
          checked = store.openRouterPrivacyMode == OpenRouterPrivacyMode.ZDR_ONLY,
          onCheckedChange = { enabled ->
            if (enabled) {
              store.selectOpenRouterModel(model.id, allowNonZDR = false)
            } else {
              confirmNonZDR = true
            }
          },
          enabled = model.hasZDREndpoint,
          colors = SwitchDefaults.colors(
            checkedTrackColor = DimoColors.green,
            checkedThumbColor = DimoColors.onGreen,
          ),
        )
      }
      if (!model.hasZDREndpoint) {
        SettingsNote("Choose a model with a ZDR badge to enable this protection.")
      }
    }

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
      CompactBoxAction(
        title = if (store.isRefreshingOpenRouterModels) "Loading…" else "Refresh models",
        color = DimoColors.green,
        onClick = store::refreshOpenRouterModels,
        modifier = Modifier.weight(1f),
      )
      if (showRemoveKey) {
        CompactBoxAction(
          title = "Remove key",
          color = DimoColors.danger,
          onClick = store::removeOpenRouterKey,
          modifier = Modifier.weight(1f),
        )
      }
    }
  }

  if (confirmNonZDR) {
    AlertDialog(
      onDismissRequest = { confirmNonZDR = false },
      title = { Text("Allow non-ZDR analysis?") },
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
          store.selectedOpenRouterModel?.let { model ->
            store.selectOpenRouterModel(model.id, allowNonZDR = true)
          }
          confirmNonZDR = false
        }) { Text("Allow non-ZDR") }
      },
      dismissButton = {
        TextButton(onClick = { confirmNonZDR = false }) { Text("Cancel") }
      },
      containerColor = DimoColors.surface,
    )
  }
}

@Composable
private fun OpenRouterStatus(store: EmailFeatureStore) {
  when (val state = store.openRouterConnectionState) {
    is OpenRouterUIConnectionState.Connected -> {
      val credit = state.limitRemaining?.let { remaining ->
        state.creditLimit?.let { limit ->
          "$%.2f left · $%.2f limit".format(remaining, limit)
        } ?: "$%.2f credit left".format(remaining)
      }
      Column(
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(2.dp),
      ) {
        Text(
          state.label.ifBlank { "Connected" },
          style = DimoFont.body(9f, FontWeight.SemiBold),
          color = DimoColors.green,
        )
        credit?.let {
          Text(it, style = DimoFont.body(8f), color = DimoColors.muted)
        }
      }
    }

    is OpenRouterUIConnectionState.Validating ->
      CircularProgressIndicator(
        strokeWidth = 2.dp,
        color = DimoColors.green,
        modifier = Modifier.size(14.dp),
      )

    is OpenRouterUIConnectionState.Failed ->
      Text("Needs attention", style = DimoFont.body(9f), color = DimoColors.danger)

    OpenRouterUIConnectionState.Disconnected ->
      Text("Not connected", style = DimoFont.body(9f), color = DimoColors.muted)
  }
}

@Composable
private fun OpenRouterAccessPicker(
  selected: OpenRouterAccessMode,
  onSelect: (OpenRouterAccessMode) -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .height(34.dp)
      .clip(RoundedCornerShape(10.dp))
      .background(DimoColors.canvasDeep)
      .padding(2.dp),
  ) {
    listOf(
      OpenRouterAccessMode.FREE_SHARED to "Free models",
      OpenRouterAccessMode.BRING_YOUR_OWN_KEY to "Bring your own key",
    ).forEach { (mode, label) ->
      val active = selected == mode
      Box(
        modifier = Modifier
          .weight(1f)
          .height(30.dp)
          .clip(RoundedCornerShape(8.dp))
          .background(if (active) DimoColors.surface else DimoColors.canvasDeep)
          .clickable { onSelect(mode) },
        contentAlignment = Alignment.Center,
      ) {
        Text(
          label,
          style = DimoFont.body(11f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      }
    }
  }
}

@Composable
private fun EmailSectionHeader(title: String, detail: String? = null) {
  Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
      title.uppercase(),
      style = DimoFont.body(12f, FontWeight.Medium),
      color = DimoColors.muted,
    )
    Spacer(Modifier.weight(1f))
    detail?.let {
      Text(it, style = DimoFont.body(10f), color = DimoColors.faint)
    }
  }
}

@Composable
private fun EmailSettingsCard(content: @Composable () -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(DimoColors.surface)
      .border(1.dp, DimoColors.line, RoundedCornerShape(16.dp))
      .padding(15.dp),
  ) {
    content()
  }
}

@Composable
private fun CompactTextAction(title: String, color: androidx.compose.ui.graphics.Color, onClick: () -> Unit) {
  Text(
    title,
    style = DimoFont.body(12f, FontWeight.Medium),
    color = color,
    modifier = Modifier.clickable(onClick = onClick).padding(vertical = 4.dp),
  )
}

@Composable
private fun CompactBoxAction(
  title: String,
  color: androidx.compose.ui.graphics.Color,
  onClick: () -> Unit,
  modifier: Modifier = Modifier,
) {
  Text(
    title,
    style = DimoFont.body(13f, FontWeight.SemiBold),
    color = color,
    textAlign = TextAlign.Center,
    modifier = modifier
      .height(42.dp)
      .clip(RoundedCornerShape(11.dp))
      .background(DimoColors.canvas)
      .border(1.dp, DimoColors.line, RoundedCornerShape(11.dp))
      .clickable(onClick = onClick)
      .padding(vertical = 11.dp),
  )
}

@Composable
private fun ProgressStatus(label: String) {
  Row(
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    CircularProgressIndicator(
      strokeWidth = 2.dp,
      color = DimoColors.green,
      modifier = Modifier.size(14.dp),
    )
    Text(label, style = DimoFont.body(11f), color = DimoColors.muted)
  }
}

@Composable
private fun SettingsNote(
  text: String,
  color: androidx.compose.ui.graphics.Color = DimoColors.muted,
) {
  Text(text = text, style = DimoFont.body(10f), color = color)
}

private fun privacyDescription(store: EmailFeatureStore): String = when (store.selectedProvider) {
  EmailAnalysisProvider.OPEN_ROUTER -> when (store.openRouterAccessMode) {
    OpenRouterAccessMode.FREE_SHARED ->
      "Selected email content is sent from this Android device through Dimo's servers to " +
        "OpenRouter for free-model analysis. Analyzed suggestions, including the full email " +
        "text, then sync through Dimo. No personal OpenRouter key is stored on this Android device."

    OpenRouterAccessMode.BRING_YOUR_OWN_KEY ->
      "Selected email content is sent from this Android device to OpenRouter and the chosen " +
        "model provider for analysis. Analyzed suggestions, including the full email text, " +
        "then sync through Dimo. OpenRouter keys stay in this Android device's encrypted storage."
  }

  null -> "Gmail is contacted directly from this Android device. Credentials stay on-device. " +
    "Email content stays local until you configure OpenRouter; analyzed suggestions later " +
    "sync through Dimo for restore."
}

private fun openRouterNeedsManualRetry(detail: String): Boolean {
  val normalized = detail.lowercase()
  return listOf(
    "unavailable",
    "insufficient",
    "rate limit",
    "waiting to retry",
    "could not be reached",
    "timed out",
    "forbidden",
    "invalid",
    "analysis failed",
  ).any(normalized::contains)
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
