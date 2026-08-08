package app.dimo.android.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.dimo.android.app.MainActivity
import app.dimo.android.domain.ExpenseReminderCopy
import app.dimo.android.domain.ExpenseReminderSettings
import app.dimo.android.store.AppStore
import java.util.Calendar

enum class ExpenseReminderAuthorization {
  NotDetermined,
  Authorized,
  Denied,
}

/** Active signed-in store for notification taps. Cleared on tearDown. */
object ExpenseReminderRouter {
  @Volatile
  var store: AppStore? = null
}

/**
 * Schedules (or cancels) the daily expense reminder via [AlarmManager].
 * Port of `ios-native/Dimo/Notifications/ExpenseReminderScheduler.swift`.
 *
 * Android has no Email suggestions subsystem, so [pendingPurchaseCount] is
 * always treated as zero by callers — kept in the API for copy parity.
 */
object ExpenseReminderScheduler {
  private const val REQUEST_CODE_ALARM = 7101
  private const val REQUEST_CODE_CONTENT = 7102

  fun ensureChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val existing = manager.getNotificationChannel(ExpenseReminderCopy.CHANNEL_ID)
    if (existing != null) return
    manager.createNotificationChannel(
      NotificationChannel(
        ExpenseReminderCopy.CHANNEL_ID,
        "Expense reminders",
        NotificationManager.IMPORTANCE_DEFAULT,
      ).apply {
        description = "Daily nudge to log expenses"
      },
    )
  }

  fun authorizationStatus(context: Context): ExpenseReminderAuthorization {
    if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
      return if (needsRuntimePermission() && !hasRuntimePermission(context)) {
        ExpenseReminderAuthorization.NotDetermined
      } else {
        ExpenseReminderAuthorization.Denied
      }
    }
    if (needsRuntimePermission() && !hasRuntimePermission(context)) {
      return ExpenseReminderAuthorization.NotDetermined
    }
    return ExpenseReminderAuthorization.Authorized
  }

  fun needsRuntimePermission(): Boolean =
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

  fun hasRuntimePermission(context: Context): Boolean {
    if (!needsRuntimePermission()) return true
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
  }

  fun cancel(context: Context) {
    val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
    alarmManager.cancel(alarmPendingIntent(context))
  }

  /**
   * Schedules (or replaces) the daily reminder. Cancels when disabled.
   * Returns whether a reminder is currently scheduled.
   */
  fun apply(
    context: Context,
    settings: ExpenseReminderSettings,
    pendingPurchaseCount: Int = 0,
  ): Boolean {
    val appContext = context.applicationContext
    ensureChannel(appContext)
    cancel(appContext)
    val clamped = settings.clamped
    if (!clamped.enabled) return false
    if (authorizationStatus(appContext) != ExpenseReminderAuthorization.Authorized) return false

    val triggerAt = nextTriggerMillis(clamped.hour, clamped.minute)
    val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return false
    val operation = alarmPendingIntent(
      appContext,
      pendingPurchaseCount = pendingPurchaseCount,
      hour = clamped.hour,
      minute = clamped.minute,
    )
    val showIntent = PendingIntent.getActivity(
      appContext,
      REQUEST_CODE_CONTENT,
      Intent(appContext, MainActivity::class.java),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAt, showIntent), operation)
    return true
  }

  fun nextTriggerMillis(hour: Int, minute: Int, nowMillis: Long = System.currentTimeMillis()): Long {
    val calendar = Calendar.getInstance().apply {
      timeInMillis = nowMillis
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
      set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
      set(Calendar.MINUTE, minute.coerceIn(0, 59))
    }
    if (calendar.timeInMillis <= nowMillis) {
      calendar.add(Calendar.DAY_OF_YEAR, 1)
    }
    return calendar.timeInMillis
  }

  fun handleNotificationTap(context: Context, intent: Intent?): Boolean {
    val type = intent?.getStringExtra(ExpenseReminderCopy.USER_INFO_TYPE_KEY) ?: return false
    if (type != ExpenseReminderCopy.USER_INFO_TYPE_VALUE) return false
    val pending = intent.getIntExtra(ExpenseReminderCopy.USER_INFO_PENDING_PURCHASES_KEY, 0)
    val store = ExpenseReminderRouter.store ?: return true
    // Android has no Email tab — always open Home + add expense.
    store.setView(app.dimo.android.data.model.ViewKey.HOME)
    store.openOverlay(app.dimo.android.store.OverlayKey.Add)
    // pending is unused today but kept so a future Email port can branch.
    @Suppress("UNUSED_VARIABLE")
    val ignored = pending
    return true
  }

  private fun alarmPendingIntent(
    context: Context,
    pendingPurchaseCount: Int = 0,
    hour: Int = 20,
    minute: Int = 0,
  ): PendingIntent {
    val intent = Intent(context, ExpenseReminderReceiver::class.java).apply {
      action = ExpenseReminderReceiver.ACTION_FIRE
      putExtra(ExpenseReminderCopy.USER_INFO_PENDING_PURCHASES_KEY, pendingPurchaseCount)
      putExtra(ExpenseReminderReceiver.EXTRA_HOUR, hour)
      putExtra(ExpenseReminderReceiver.EXTRA_MINUTE, minute)
    }
    return PendingIntent.getBroadcast(
      context,
      REQUEST_CODE_ALARM,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}
