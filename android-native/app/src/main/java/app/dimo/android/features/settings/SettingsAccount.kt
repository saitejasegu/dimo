package app.dimo.android.features.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.design.ActionButton
import app.dimo.android.design.Avatar
import app.dimo.android.design.Chip
import app.dimo.android.design.DimoColors
import app.dimo.android.store.AppStore
import java.io.BufferedReader
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

@Composable
fun SettingsScreen(
  store: AppStore,
  onAccount: () -> Unit,
  onBack: () -> Unit,
) {
  val state by store.state.collectAsStateWithLifecycle()
  val context = LocalContext.current
  var confirmDeleteHistory by remember { mutableStateOf(false) }

  val exportLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.CreateDocument("text/csv"),
  ) { uri: Uri? ->
    if (uri == null) return@rememberLauncherForActivityResult
    runCatching {
      context.contentResolver.openOutputStream(uri)?.use { out ->
        out.write(store.exportCSV().toByteArray(StandardCharsets.UTF_8))
      }
      store.showToast("Exported CSV")
    }.onFailure { store.showToast("Export failed") }
  }

  val importLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.OpenDocument(),
  ) { uri: Uri? ->
    if (uri == null) return@rememberLauncherForActivityResult
    runCatching {
      val csv = context.contentResolver.openInputStream(uri)?.use { input ->
        BufferedReader(InputStreamReader(input, StandardCharsets.UTF_8)).readText()
      }.orEmpty()
      if (csv.isNotBlank()) store.importCSV(csv) else store.showToast("Empty file")
    }.onFailure { store.showToast("Import failed") }
  }

  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(MaterialTheme.colorScheme.background),
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 8.dp, vertical = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      IconButton(onClick = onBack) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
      }
      Text("Settings", style = MaterialTheme.typography.titleLarge)
    }

    Column(
      modifier = Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp, vertical = 8.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .clip(RoundedCornerShape(16.dp))
          .background(MaterialTheme.colorScheme.surface)
          .clickable(onClick = onAccount)
          .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
      ) {
        Avatar(
          initials = state.profileName
            .split(" ")
            .mapNotNull { it.firstOrNull()?.toString() }
            .take(2)
            .joinToString("")
            .ifBlank { "A" },
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
          Text(
            state.profileName.ifBlank { "Account" },
            fontWeight = FontWeight.SemiBold,
          )
          Text(state.profileEmail, color = DimoColors.mutedLight, style = MaterialTheme.typography.bodyMedium)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
      }

      SettingsCard(title = "Preferences") {
        Text("Appearance", style = MaterialTheme.typography.labelLarge)
        Spacer(Modifier.height(8.dp))
        Row(
          modifier = Modifier.horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          ThemePreference.entries.forEach { theme ->
            Chip(
              label = theme.name.replaceFirstChar { it.uppercase() },
              selected = state.theme == theme,
              onClick = { store.updatePreferences(theme = theme) },
            )
          }
        }
        Spacer(Modifier.height(14.dp))
        Text("Currency", style = MaterialTheme.typography.labelLarge)
        Spacer(Modifier.height(8.dp))
        Row(
          modifier = Modifier.horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          Currency.entries.forEach { currency ->
            Chip(
              label = currency.name,
              selected = state.currency == currency,
              onClick = { store.updatePreferences(currency = currency) },
            )
          }
        }
        Spacer(Modifier.height(14.dp))
        Text("Default stats range", style = MaterialTheme.typography.labelLarge)
        Spacer(Modifier.height(8.dp))
        Row(
          modifier = Modifier.horizontalScroll(rememberScrollState()),
          horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          StatsRange.entries.forEach { range ->
            Chip(
              label = range.wire,
              selected = state.defaultStatsRange == range,
              onClick = { store.updatePreferences(defaultStatsRange = range) },
            )
          }
        }
      }

      SettingsCard(title = "Payment methods") {
        state.paymentMethods.forEach { method ->
          Row(
            modifier = Modifier
              .fillMaxWidth()
              .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
          ) {
            Column(Modifier.weight(1f)) {
              Text(method.name, fontWeight = FontWeight.SemiBold)
              Text(
                buildString {
                  append(method.type.name)
                  if (method.detail.isNotBlank()) {
                    append(" · ")
                    append(method.detail)
                  }
                  if (method.isDefault) append(" · Default")
                  if (method.archived) append(" · Archived")
                },
                style = MaterialTheme.typography.bodyMedium,
                color = DimoColors.mutedLight,
              )
            }
            if (!method.archived && !method.isDefault) {
              TextButton(onClick = { store.setDefaultPaymentMethod(method.id) }) {
                Text("Default")
              }
            }
            TextButton(
              onClick = { store.setPaymentMethodArchived(method.id, !method.archived) },
            ) {
              Text(if (method.archived) "Restore" else "Archive")
            }
          }
        }
      }

      SettingsCard(title = "Transaction data") {
        ActionButton(
          label = "Export CSV",
          onClick = { exportLauncher.launch("dimo-transactions.csv") },
        )
        Spacer(Modifier.height(10.dp))
        ActionButton(
          label = "Import CSV",
          onClick = { importLauncher.launch(arrayOf("text/*", "text/csv", "application/csv")) },
        )
        Spacer(Modifier.height(10.dp))
        TextButton(onClick = { confirmDeleteHistory = true }) {
          Text("Delete history", color = MaterialTheme.colorScheme.error)
        }
      }

      Spacer(Modifier.height(24.dp))
    }
  }

  if (confirmDeleteHistory) {
    AlertDialog(
      onDismissRequest = { confirmDeleteHistory = false },
      title = { Text("Delete history?") },
      text = { Text("This permanently deletes your transaction history.") },
      confirmButton = {
        TextButton(onClick = {
          confirmDeleteHistory = false
          store.deleteHistory()
        }) {
          Text("Delete", color = MaterialTheme.colorScheme.error)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmDeleteHistory = false }) { Text("Cancel") }
      },
    )
  }
}

@Composable
fun AccountScreen(
  store: AppStore,
  onBack: () -> Unit,
  onSignOut: () -> Unit = {},
  onDeleteAccount: () -> Unit = {},
) {
  val state by store.state.collectAsStateWithLifecycle()
  var confirmReplace by remember { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }
  var confirmSignOut by remember { mutableStateOf(false) }

  Column(
    modifier = Modifier
      .fillMaxSize()
      .background(MaterialTheme.colorScheme.background),
  ) {
    Row(
      modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 8.dp, vertical = 8.dp),
      verticalAlignment = Alignment.CenterVertically,
    ) {
      IconButton(onClick = onBack) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
      }
      Text("Account", style = MaterialTheme.typography.titleLarge)
    }

    Column(
      modifier = Modifier
        .fillMaxSize()
        .verticalScroll(rememberScrollState())
        .padding(horizontal = 22.dp, vertical = 8.dp),
      verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
      SettingsCard(title = "Profile") {
        Text(state.profileName.ifBlank { "—" }, fontWeight = FontWeight.SemiBold)
        Text(state.profileEmail, color = DimoColors.mutedLight)
        Spacer(Modifier.height(6.dp))
        Text(
          "Name and email come from your WorkOS profile and are read-only here.",
          style = MaterialTheme.typography.bodyMedium,
          color = DimoColors.mutedLight,
        )
      }

      SettingsCard(title = "Sync") {
        val syncLabel = when {
          state.syncMeta.syncing -> "Syncing…"
          state.pendingCount > 0 -> "${state.pendingCount} pending"
          state.syncMeta.error != null -> state.syncMeta.error!!
          else -> "Up to date"
        }
        Text(syncLabel, color = DimoColors.mutedLight, style = MaterialTheme.typography.bodyMedium)
        if (state.blockedCount > 0) {
          Text(
            "${state.blockedCount} blocked operations",
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium,
          )
        }
        Spacer(Modifier.height(10.dp))
        ActionButton(label = "Sync now", onClick = { store.syncNow() })
        Spacer(Modifier.height(10.dp))
        ActionButton(label = "Full replace from cloud", onClick = { confirmReplace = true })
      }

      SettingsCard(title = "Session") {
        ActionButton(label = "Sign out", onClick = { confirmSignOut = true })
        Spacer(Modifier.height(10.dp))
        TextButton(onClick = { confirmDelete = true }) {
          Text("Delete account", color = MaterialTheme.colorScheme.error)
        }
      }

      Spacer(Modifier.height(24.dp))
    }
  }

  if (confirmReplace) {
    AlertDialog(
      onDismissRequest = { confirmReplace = false },
      title = { Text("Replace local data?") },
      text = {
        Text("This hard-replaces local entities from the cloud and cannot be undone.")
      },
      confirmButton = {
        TextButton(onClick = {
          confirmReplace = false
          store.fullReplaceSync()
          store.showToast("Full sync started")
        }) { Text("Replace") }
      },
      dismissButton = {
        TextButton(onClick = { confirmReplace = false }) { Text("Cancel") }
      },
    )
  }

  if (confirmSignOut) {
    AlertDialog(
      onDismissRequest = { confirmSignOut = false },
      title = { Text("Sign out?") },
      text = { Text("Local data for this account will be removed from this device.") },
      confirmButton = {
        TextButton(onClick = {
          confirmSignOut = false
          onSignOut()
        }) { Text("Sign out") }
      },
      dismissButton = {
        TextButton(onClick = { confirmSignOut = false }) { Text("Cancel") }
      },
    )
  }

  if (confirmDelete) {
    AlertDialog(
      onDismissRequest = { confirmDelete = false },
      title = { Text("Delete account?") },
      text = {
        Text("Deletes all cloud data for this account, then signs out. This cannot be undone.")
      },
      confirmButton = {
        TextButton(onClick = {
          confirmDelete = false
          onDeleteAccount()
        }) {
          Text("Delete", color = MaterialTheme.colorScheme.error)
        }
      },
      dismissButton = {
        TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
      },
    )
  }
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
  Column(
    modifier = Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(MaterialTheme.colorScheme.surface)
      .padding(16.dp),
  ) {
    Text(title, style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(12.dp))
    content()
  }
}
