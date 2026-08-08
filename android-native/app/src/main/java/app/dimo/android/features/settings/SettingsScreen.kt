package app.dimo.android.features.settings

import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.design.ActionButton
import app.dimo.android.design.ActionButtonVariant
import app.dimo.android.design.AvatarView
import app.dimo.android.design.DimoColors
import app.dimo.android.design.DimoFont
import app.dimo.android.design.PillDropdown
import app.dimo.android.domain.Formatting
import app.dimo.android.domain.StatsConstants
import app.dimo.android.domain.TransactionCSV
import app.dimo.android.features.common.ConfirmDialog
import app.dimo.android.features.common.DimoCard
import app.dimo.android.features.common.DimoDivider
import app.dimo.android.features.common.ScreenHeader
import app.dimo.android.features.common.SectionTitle
import app.dimo.android.features.common.SettingsToggleRow
import app.dimo.android.features.common.SyncErrorBanner
import app.dimo.android.features.common.cardSurface
import app.dimo.android.notifications.ExpenseReminderAuthorization
import app.dimo.android.notifications.ExpenseReminderScheduler
import app.dimo.android.store.AppStore
import java.io.File
import java.util.Locale
import kotlinx.coroutines.launch

/**
 * Preferences, reminders, payment methods and transaction data. Port of
 * `ios-native/Dimo/Features/Settings/SettingsAccount.swift` minus the Email
 * section, which Android does not ship.
 *
 * CSV import/export use Activity Result launchers instead of iOS document
 * pickers; export shares through the app's FileProvider.
 */
@Composable
fun SettingsScreen(
  store: AppStore,
  onBack: () -> Unit,
  onOpenAccount: () -> Unit,
  onApplyTheme: (ThemePreference) -> Unit,
  modifier: Modifier = Modifier,
) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  var confirmDeleteHistory by remember { mutableStateOf(false) }

  val importLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.OpenDocument(),
  ) { uri ->
    if (uri == null) return@rememberLauncherForActivityResult
    scope.launch {
      try {
        val text = context.contentResolver.openInputStream(uri)?.use { stream ->
          stream.readBytes().toString(Charsets.UTF_8)
        } ?: throw IllegalStateException("Could not read that file.")
        store.importCSV(text)
      } catch (error: Throwable) {
        store.showToast(error.message ?: "Could not import that file")
      }
    }
  }

  fun shareCsv(text: String, fileName: String) {
    try {
      val dir = File(context.cacheDir, "exports").apply { mkdirs() }
      val file = File(dir, fileName)
      file.writeText(text)
      val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
      val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/csv"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      }
      context.startActivity(Intent.createChooser(intent, "Export transactions"))
    } catch (error: Throwable) {
      store.showToast(error.message ?: "Could not export")
    }
  }

  LazyColumn(
    modifier = modifier.fillMaxSize().background(DimoColors.canvas),
    contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 40.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    item {
      ScreenHeader(title = "Settings", onBack = onBack, modifier = Modifier.statusBarsPadding())
    }

    item {
      AccountCard(
        name = store.profileName,
        email = store.profileEmail,
        photoUrl = store.profilePhotoUrl,
        onClick = onOpenAccount,
      )
    }

    store.syncMeta?.error?.let { error ->
      if (error != "Offline") item { SyncErrorBanner(message = error) }
    }

    item {
      DimoCard(verticalSpacing = 14.dp) {
        SectionTitle("Preferences")

        PreferenceRow(label = "Theme") {
          PillDropdown(
            options = listOf(ThemePreference.SYSTEM, ThemePreference.LIGHT, ThemePreference.DARK),
            selected = store.theme,
            label = { it.wire.replaceFirstChar { char -> char.uppercase() } },
            onSelect = { value ->
              store.updatePreferences { it.copy(theme = value) }
              onApplyTheme(value)
            },
          )
        }

        PreferenceRow(label = "Default stats range") {
          PillDropdown(
            options = StatsConstants.ranges,
            selected = store.defaultStatsRange,
            label = { StatsConstants.rangeLabel[it] ?: it.wire },
            onSelect = { value ->
              store.updatePreferences { it.copy(defaultStatsRange = value) }
              store.statsRange = value
            },
          )
        }

        PreferenceRow(label = "Currency") {
          PillDropdown(
            options = Currency.entries.toList(),
            selected = store.currency,
            label = { "${Formatting.currencySymbol(it)} ${it.wire}" },
            onSelect = { value -> store.updatePreferences { it.copy(currency = value) } },
          )
        }
      }
    }

    item {
      RemindersCard(store = store)
    }

    item { PaymentMethodsCard(store = store) }

    item {
      DimoCard(verticalSpacing = 10.dp) {
        SectionTitle("Transaction data")
        Text(
          text = "Export all expenses as CSV, or import from Dimo's template.",
          style = DimoFont.body(12f),
          color = DimoColors.muted,
        )
        ActionButton(
          title = "Import transactions",
          onClick = { importLauncher.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain")) },
          variant = ActionButtonVariant.Accent,
        )
        ActionButton(
          title = if (store.transactions.isEmpty()) {
            "No transactions to export"
          } else {
            "Export transactions"
          },
          onClick = { shareCsv(store.exportCSV(), "dimo-transactions.csv") },
          enabled = store.transactions.isNotEmpty(),
        )
        ActionButton(
          title = "Export CSV template",
          onClick = { shareCsv(TransactionCSV.template, "dimo-template.csv") },
        )
        DimoDivider(modifier = Modifier.padding(vertical = 6.dp))
        ActionButton(
          title = when {
            store.deletingHistory -> "Deleting history…"
            store.transactions.isEmpty() -> "No history to delete"
            else -> "Delete history"
          },
          onClick = { confirmDeleteHistory = true },
          variant = ActionButtonVariant.Danger,
          enabled = store.transactions.isNotEmpty() && !store.deletingHistory,
        )
      }
    }
  }

  if (confirmDeleteHistory) {
    ConfirmDialog(
      title = "Delete history?",
      message = "This permanently deletes your transaction history. This cannot be undone.",
      confirmLabel = "Delete",
      onConfirm = { store.deleteHistory() },
      onDismiss = { confirmDeleteHistory = false },
    )
  }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RemindersCard(store: AppStore) {
  val context = LocalContext.current
  var showTimePicker by remember { mutableStateOf(false) }
  val reminder = store.expenseReminder

  val permissionLauncher = rememberLauncherForActivityResult(
    ActivityResultContracts.RequestPermission(),
  ) { granted ->
    store.refreshExpenseReminderAuthorization()
    if (granted) {
      store.updateExpenseReminder { it.copy(enabled = true) }
    } else {
      store.updateExpenseReminder { it.copy(enabled = false) }
    }
  }

  fun setReminderEnabled(enabled: Boolean) {
    if (!enabled) {
      store.updateExpenseReminder { it.copy(enabled = false) }
      return
    }
    store.refreshExpenseReminderAuthorization()
    when (store.expenseReminderAuthorization) {
      ExpenseReminderAuthorization.Authorized ->
        store.updateExpenseReminder { it.copy(enabled = true) }
      ExpenseReminderAuthorization.NotDetermined -> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
          !ExpenseReminderScheduler.hasRuntimePermission(context)
        ) {
          permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
          store.updateExpenseReminder { it.copy(enabled = true) }
        }
      }
      ExpenseReminderAuthorization.Denied ->
        store.updateExpenseReminder { it.copy(enabled = true) }
    }
  }

  DimoCard(verticalSpacing = 6.dp) {
    SectionTitle("Reminders")

    SettingsToggleRow(
      label = "Daily expense reminder",
      caption = "Remind me to log expenses each day.",
      checked = reminder.enabled,
      onCheckedChange = { setReminderEnabled(it) },
    )

    if (reminder.enabled) {
      Row(
        modifier = Modifier
          .fillMaxWidth()
          .clickable { showTimePicker = true }
          .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
      ) {
        Text(
          text = "Reminder time",
          style = DimoFont.body(15f, FontWeight.Medium),
          color = DimoColors.ink,
          modifier = Modifier.weight(1f),
        )
        Text(
          text = formatReminderTime(reminder.hour, reminder.minute),
          style = DimoFont.body(15f, FontWeight.Medium),
          color = DimoColors.green,
        )
      }

      if (store.expenseReminderAuthorization == ExpenseReminderAuthorization.Denied) {
        Text(
          text = "Notifications are off. Open Settings to allow reminders.",
          style = DimoFont.body(12f, FontWeight.Medium),
          color = DimoColors.warn,
          modifier = Modifier
            .fillMaxWidth()
            .clickable {
              context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                  putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                },
              )
            }
            .padding(vertical = 6.dp),
        )
      }
    }

    DimoDivider(modifier = Modifier.padding(vertical = 8.dp))
    Text(
      text = "These preferences sync across your devices. Delivery is not scheduled yet.",
      style = DimoFont.body(12f),
      color = DimoColors.muted,
    )
    NotificationToggles(store = store)
  }

  if (showTimePicker) {
    val timeState = rememberTimePickerState(
      initialHour = reminder.hour,
      initialMinute = reminder.minute,
      is24Hour = false,
    )
    AlertDialog(
      onDismissRequest = { showTimePicker = false },
      containerColor = DimoColors.surface,
      title = {
        Text(
          text = "Reminder time",
          style = DimoFont.display(18f, FontWeight.SemiBold),
          color = DimoColors.ink,
        )
      },
      text = {
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
          TimePicker(state = timeState)
        }
      },
      confirmButton = {
        TextButton(
          onClick = {
            showTimePicker = false
            store.updateExpenseReminder {
              it.copy(hour = timeState.hour, minute = timeState.minute)
            }
          },
        ) {
          Text(
            text = "Done",
            style = DimoFont.body(15f, FontWeight.SemiBold),
            color = DimoColors.green,
          )
        }
      },
      dismissButton = {
        TextButton(onClick = { showTimePicker = false }) {
          Text(text = "Cancel", style = DimoFont.body(15f), color = DimoColors.muted)
        }
      },
    )
  }
}

@Composable
private fun NotificationToggles(store: AppStore) {
  val settings = store.notifications

  fun update(mutate: (NotificationSettings) -> NotificationSettings) {
    store.updatePreferences { it.copy(notifications = mutate(it.notifications)) }
  }

  SettingsToggleRow(
    label = "Upcoming bills",
    caption = "Remind me before a recurring bill is due.",
    checked = settings.bills,
    onCheckedChange = { next -> update { it.copy(bills = next) } },
  )
  SettingsToggleRow(
    label = "Budget alerts",
    caption = "Tell me when a category is close to its limit.",
    checked = settings.budget,
    onCheckedChange = { next -> update { it.copy(budget = next) } },
  )
  SettingsToggleRow(
    label = "Weekly summary",
    caption = "A recap of what I spent each week.",
    checked = settings.weekly,
    onCheckedChange = { next -> update { it.copy(weekly = next) } },
  )
  SettingsToggleRow(
    label = "Large expenses",
    caption = "Flag unusually large purchases.",
    checked = settings.large,
    onCheckedChange = { next -> update { it.copy(large = next) } },
  )
}

private fun formatReminderTime(hour: Int, minute: Int): String {
  val h12 = when {
    hour == 0 -> 12
    hour > 12 -> hour - 12
    else -> hour
  }
  val amPm = if (hour < 12) "AM" else "PM"
  return String.format(Locale.US, "%d:%02d %s", h12, minute, amPm)
}

@Composable
private fun PreferenceRow(
  label: String,
  trailing: @Composable () -> Unit,
) {
  Row(
    modifier = Modifier.fillMaxWidth(),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(12.dp),
  ) {
    Text(
      text = label,
      style = DimoFont.body(13f, FontWeight.Medium),
      color = DimoColors.ink,
      modifier = Modifier.weight(1f),
    )
    trailing()
  }
}

@Composable
private fun AccountCard(
  name: String,
  email: String,
  photoUrl: String?,
  onClick: () -> Unit,
) {
  Row(
    modifier = Modifier
      .fillMaxWidth()
      .cardSurface(16.dp)
      .clickable(onClick = onClick)
      .padding(16.dp),
    verticalAlignment = Alignment.CenterVertically,
    horizontalArrangement = Arrangement.spacedBy(14.dp),
  ) {
    AvatarView(name = name, photoUrl = photoUrl, size = 52.dp, radius = 16.dp, fontSize = 22f)
    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
      Text(
        text = name.ifEmpty { "Your account" },
        style = DimoFont.display(17f, FontWeight.SemiBold),
        color = DimoColors.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
      Text(
        text = email.ifEmpty { "Manage profile, sync and sign-in" },
        style = DimoFont.body(12f),
        color = DimoColors.muted,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
      )
    }
    Text(text = "›", style = DimoFont.display(20f, FontWeight.Medium), color = DimoColors.muted)
  }
}
