package app.dimo.android.domain

import android.content.Context
import org.json.JSONObject

/**
 * Device-local daily expense reminder. Not synced — local notifications are
 * per-device, same as last-used payment method metadata.
 *
 * Port of `ios-native/Dimo/Domain/ExpenseReminder.swift`.
 */
data class ExpenseReminderSettings(
  val enabled: Boolean,
  /** Local-clock hour in 0...23. */
  val hour: Int,
  /** Local-clock minute in 0...59. */
  val minute: Int,
) {
  val clamped: ExpenseReminderSettings
    get() = ExpenseReminderSettings(
      enabled = enabled,
      hour = hour.coerceIn(0, 23),
      minute = minute.coerceIn(0, 59),
    )

  companion object {
    val DEFAULT = ExpenseReminderSettings(enabled = false, hour = 20, minute = 0)
  }
}

object ExpenseReminderCopy {
  const val NOTIFICATION_IDENTIFIER = "dimo.expense-reminder.daily"
  const val USER_INFO_TYPE_KEY = "dimo.reminder.type"
  const val USER_INFO_TYPE_VALUE = "expense"
  const val USER_INFO_PENDING_PURCHASES_KEY = "dimo.reminder.pendingPurchases"
  const val CHANNEL_ID = "dimo.expense-reminders"

  fun title(pendingPurchaseCount: Int): String =
    if (pendingPurchaseCount > 0) {
      "Expenses and reviews waiting"
    } else {
      "Log today's expenses"
    }

  fun body(pendingPurchaseCount: Int): String {
    val base = "Take a moment to add anything you spent today."
    if (pendingPurchaseCount <= 0) return base
    val noun = if (pendingPurchaseCount == 1) "purchase" else "purchases"
    return "$base You also have $pendingPurchaseCount $noun waiting for review."
  }
}

object ExpenseReminderStore {
  private const val PREFS = "dimo_device_prefs"
  private const val KEY_PREFIX = "dimo.expenseReminder.settings."

  fun load(context: Context, userId: String): ExpenseReminderSettings {
    val raw = prefs(context).getString(KEY_PREFIX + userId, null) ?: return ExpenseReminderSettings.DEFAULT
    return runCatching {
      val json = JSONObject(raw)
      ExpenseReminderSettings(
        enabled = json.optBoolean("enabled", false),
        hour = json.optInt("hour", 20),
        minute = json.optInt("minute", 0),
      ).clamped
    }.getOrDefault(ExpenseReminderSettings.DEFAULT)
  }

  fun save(context: Context, settings: ExpenseReminderSettings, userId: String) {
    val value = settings.clamped
    val json = JSONObject()
      .put("enabled", value.enabled)
      .put("hour", value.hour)
      .put("minute", value.minute)
    prefs(context).edit().putString(KEY_PREFIX + userId, json.toString()).apply()
  }

  fun clear(context: Context, userId: String) {
    prefs(context).edit().remove(KEY_PREFIX + userId).apply()
  }

  /** User IDs with saved reminder settings — used to reschedule after reboot. */
  fun savedUserIds(context: Context): List<String> =
    prefs(context).all.keys
      .mapNotNull { key ->
        if (key.startsWith(KEY_PREFIX)) key.removePrefix(KEY_PREFIX) else null
      }

  private fun prefs(context: Context) =
    context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
