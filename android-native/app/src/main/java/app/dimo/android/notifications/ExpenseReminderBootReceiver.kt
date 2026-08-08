package app.dimo.android.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import app.dimo.android.domain.ExpenseReminderStore

/** Reschedules enabled daily reminders after reboot or app update. */
class ExpenseReminderBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    when (intent?.action) {
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      -> {
        for (userId in ExpenseReminderStore.savedUserIds(context)) {
          val settings = ExpenseReminderStore.load(context, userId)
          if (settings.enabled) {
            ExpenseReminderScheduler.apply(context, settings, pendingPurchaseCount = 0)
          }
        }
      }
    }
  }
}
