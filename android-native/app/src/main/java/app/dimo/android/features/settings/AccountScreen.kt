package app.dimo.android.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.FieldLabel
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionTitle
import app.dimo.android.features.common.cardSurface
import app.dimo.android.store.AppStore
import java.text.DateFormat
import java.util.Date

/**
 * Read-only WorkOS profile, cloud sync status and session actions. Port of
 * `AccountScreen` in `ios-native/Dimo/Features/Settings/SettingsAccount.swift`.
 *
 * Sign-out and account deletion belong to `SessionController`, so they arrive as
 * lambdas from `RootView` through `MainTabShell`.
 */
@Composable
fun AccountScreen(
  store: AppStore,
  onBack: () -> Unit,
  onSignOut: () -> Unit,
  onDeleteAccount: () -> Unit,
  modifier: Modifier = Modifier,
) {
  var confirmSignOut by remember { mutableStateOf(false) }
  var confirmDelete by remember { mutableStateOf(false) }

  val meta = store.syncMeta
  val syncing = meta?.syncing == true
  val error = meta?.error.orEmpty()
  val offline = error == "Offline"
  val statusLabel = when {
    syncing -> "Syncing"
    offline -> "Offline"
    error.isNotEmpty() || store.blockedCount > 0 -> "Error"
    store.pendingCount > 0 -> "Pending"
    else -> "Synced"
  }
  val blockedSuffix = if (store.blockedCount > 0) " · ${store.blockedCount} blocked" else ""
  val lastSync = meta?.lastSyncedAt?.let { at ->
    DateFormat
      .getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
      .format(Date(at))
  } ?: "Not synced yet"

  Column(
    modifier = modifier
      .fillMaxSize()
      .background(DimoColors.canvas)
      .verticalScroll(rememberScrollState())
      .padding(horizontal = 20.dp)
      .padding(top = 12.dp, bottom = 40.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    ScreenHeader(title = "Account", onBack = onBack, modifier = Modifier.statusBarsPadding())

    DimoCard {
      Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
      ) {
        AvatarView(
          name = store.profileName,
          photoUrl = store.profilePhotoUrl,
          size = 60.dp,
          radius = 18.dp,
          fontSize = 26f,
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
          Text(
            text = store.profileName.ifEmpty { "Your account" },
            style = DimoFont.display(17f, FontWeight.SemiBold),
            color = DimoColors.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
          )
          Text(
            text = "Managed by your sign-in provider",
            style = DimoFont.body(12f),
            color = DimoColors.muted,
          )
        }
      }
      ReadOnlyField(label = "Full name", value = store.profileName)
      ReadOnlyField(label = "Email", value = store.profileEmail)
    }

    DimoCard(verticalSpacing = 6.dp) {
      SectionTitle("Cloud sync", modifier = Modifier.fillMaxWidth())
      Text(
        text = "$statusLabel · ${store.pendingCount} pending$blockedSuffix",
        style = DimoFont.body(12f),
        color = DimoColors.muted,
      )
      Text(
        text = "Last successful sync: $lastSync",
        style = DimoFont.body(11f),
        color = DimoColors.faint,
      )
      ActionButton(
        title = if (syncing) "Syncing…" else "Sync now",
        onClick = { store.syncNow() },
        modifier = Modifier.padding(top = 6.dp),
      )
      ActionButton(
        title = "Sync now (full replace)",
        onClick = { store.requestFullSync() },
        variant = ActionButtonVariant.Danger,
      )
      if (error.isNotEmpty()) {
        Text(
          text = error,
          style = DimoFont.body(12f),
          color = DimoColors.danger,
          textAlign = TextAlign.Center,
          modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp)
            .cardSurface(8.dp, DimoColors.dangerSoft, DimoColors.dangerLine)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        )
      }
    }

    DimoCard(verticalSpacing = 10.dp) {
      ActionButton(title = "Sign out", onClick = { confirmSignOut = true })
      ActionButton(
        title = "Delete account",
        onClick = { confirmDelete = true },
        variant = ActionButtonVariant.Danger,
      )
      Text(
        text = "Delete account permanently removes your data from this device and the cloud.",
        style = DimoFont.body(11f),
        color = DimoColors.faint,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
      )
    }
  }

  if (confirmSignOut) {
    ConfirmDialog(
      title = "Sign out?",
      message = "Local Dimo data on this device is removed. Synced data stays in the cloud.",
      confirmLabel = "Sign out",
      onConfirm = onSignOut,
      onDismiss = { confirmSignOut = false },
    )
  }

  if (confirmDelete) {
    ConfirmDialog(
      title = "Delete account and cloud data?",
      message = "This permanently removes every Dimo record from this device and the cloud. " +
        "You need to be online.",
      confirmLabel = "Delete account",
      onConfirm = onDeleteAccount,
      onDismiss = { confirmDelete = false },
    )
  }
}

@Composable
private fun ReadOnlyField(label: String, value: String) {
  Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
    FieldLabel(label)
    Text(
      text = value.ifEmpty { "—" },
      style = DimoFont.body(16f),
      color = DimoColors.body,
      maxLines = 1,
      overflow = TextOverflow.Ellipsis,
      modifier = Modifier
        .fillMaxWidth()
        .cardSurface(12.dp, DimoColors.canvas)
        .padding(horizontal = 14.dp, vertical = 11.dp),
    )
  }
}
