package app.dimo.android.notifications

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import app.dimo.android.R
import app.dimo.android.app.MainActivity
import app.dimo.android.domain.ExpenseReminderCopy
import app.dimo.android.domain.ExpenseReminderSettings
import app.dimo.android.domain.ExpenseReminderStore

/**
 * Fires the daily expense reminder notification and reschedules the next day.
 */
class ExpenseReminderReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    when (intent?.action) {
      ACTION_RESCHEDULE -> {
        for (userId in ExpenseReminderStore.savedUserIds(context)) {
          val settings = ExpenseReminderStore.load(context, userId)
          if (settings.enabled) {
            ExpenseReminderScheduler.apply(context, settings, pendingPurchaseCount = 0)
          }
        }
      }

      ACTION_FIRE -> {
        val pending = intent.getIntExtra(ExpenseReminderCopy.USER_INFO_PENDING_PURCHASES_KEY, 0)
        showNotification(context, pending)
        val hour = intent.getIntExtra(EXTRA_HOUR, 20)
        val minute = intent.getIntExtra(EXTRA_MINUTE, 0)
        ExpenseReminderScheduler.apply(
          context = context,
          settings = ExpenseReminderSettings(enabled = true, hour = hour, minute = minute),
          pendingPurchaseCount = pending,
        )
      }
    }
  }

  private fun showNotification(context: Context, pendingPurchaseCount: Int) {
    ExpenseReminderScheduler.ensureChannel(context)
    if (ExpenseReminderScheduler.authorizationStatus(context) !=
      ExpenseReminderAuthorization.Authorized
    ) {
      return
    }

    val contentIntent = Intent(context, MainActivity::class.java).apply {
      flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
      putExtra(ExpenseReminderCopy.USER_INFO_TYPE_KEY, ExpenseReminderCopy.USER_INFO_TYPE_VALUE)
      putExtra(ExpenseReminderCopy.USER_INFO_PENDING_PURCHASES_KEY, pendingPurchaseCount)
    }
    val pendingIntent = PendingIntent.getActivity(
      context,
      7103,
      contentIntent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    val notification = NotificationCompat.Builder(context, ExpenseReminderCopy.CHANNEL_ID)
      .setSmallIcon(R.drawable.ic_notification)
      .setContentTitle(ExpenseReminderCopy.title(pendingPurchaseCount))
      .setContentText(ExpenseReminderCopy.body(pendingPurchaseCount))
      .setStyle(
        NotificationCompat.BigTextStyle()
          .bigText(ExpenseReminderCopy.body(pendingPurchaseCount)),
      )
      .setContentIntent(pendingIntent)
      .setAutoCancel(true)
      .setPriority(NotificationCompat.PRIORITY_DEFAULT)
      .build()

    runCatching {
      NotificationManagerCompat.from(context).notify(
        ExpenseReminderCopy.NOTIFICATION_IDENTIFIER.hashCode(),
        notification,
      )
    }
  }

  companion object {
    const val ACTION_FIRE = "app.dimo.android.action.EXPENSE_REMINDER_FIRE"
    const val ACTION_RESCHEDULE = "app.dimo.android.action.EXPENSE_REMINDER_RESCHEDULE"
    const val EXTRA_HOUR = "dimo.reminder.hour"
    const val EXTRA_MINUTE = "dimo.reminder.minute"
  }
}
