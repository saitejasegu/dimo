package app.dimo.android.email.work

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.runBlocking

/**
 * Android replacement for `ios-native/Dimo/Email/Background/EmailBackgroundTasks.swift`.
 *
 * iOS uses `BGTaskScheduler`'s app-refresh and processing tasks. The equivalent
 * here would be WorkManager, which also gives network constraints and backoff for
 * free; it is not a dependency of this module yet, so this uses the same
 * inexact-`AlarmManager` + `BroadcastReceiver` pattern the expense reminder
 * already uses. Inexact alarms are deliberate: this work is opportunistic, and
 * exact alarms would need `SCHEDULE_EXACT_ALARM` for no user benefit.
 *
 * Scheduling policy lives here so a future move to WorkManager only has to
 * replace the two `schedule*` bodies.
 */
object EmailBackgroundWork {
  const val ACTION_REFRESH = "app.dimo.android.action.EMAIL_BACKGROUND_REFRESH"
  const val ACTION_ANALYSIS = "app.dimo.android.action.EMAIL_BACKGROUND_ANALYSIS"

  private const val REFRESH_INTERVAL_MS = 30L * 60 * 1000
  private const val ANALYSIS_INTERVAL_MS = 15L * 60 * 1000
  private const val REQUEST_REFRESH = 8_101
  private const val REQUEST_ANALYSIS = 8_102

  /**
   * The live controller for the signed-in user, set while the Email feature is
   * running. Background work is skipped when it is absent — there is no signed-in
   * account to work on, and waking the whole store from a receiver would be worse
   * than waiting for the next foreground refresh.
   */
  @Volatile
  var provider: EmailBackgroundWorkProviding? = null

  fun schedule(context: Context, requiresAnalysisNetwork: Boolean = false) {
    scheduleRefresh(context)
    scheduleAnalysis(context, requiresAnalysisNetwork)
  }

  fun scheduleRefresh(
    context: Context,
    earliestMillis: Long = System.currentTimeMillis() + REFRESH_INTERVAL_MS,
  ) {
    setAlarm(context, ACTION_REFRESH, REQUEST_REFRESH, earliestMillis)
  }

  /**
   * [requiresNetwork] currently only documents intent: `AlarmManager` cannot
   * express a connectivity constraint, so the worker re-checks and returns a
   * retry instead. WorkManager would enforce it up front.
   */
  fun scheduleAnalysis(
    context: Context,
    requiresNetwork: Boolean = false,
    earliestMillis: Long = System.currentTimeMillis() + ANALYSIS_INTERVAL_MS,
  ) {
    setAlarm(context, ACTION_ANALYSIS, REQUEST_ANALYSIS, earliestMillis)
  }

  fun cancel(context: Context) {
    val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
    alarmManager.cancel(operation(context, ACTION_REFRESH, REQUEST_REFRESH))
    alarmManager.cancel(operation(context, ACTION_ANALYSIS, REQUEST_ANALYSIS))
  }

  private fun setAlarm(context: Context, action: String, requestCode: Int, triggerAt: Long) {
    val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
    val operation = operation(context, action, requestCode)
    alarmManager.cancel(operation)
    // Inexact + allow-while-idle: the system may batch or defer this, which is
    // exactly the behaviour wanted for opportunistic sync.
    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, operation)
  }

  private fun operation(context: Context, action: String, requestCode: Int): PendingIntent =
    PendingIntent.getBroadcast(
      context.applicationContext,
      requestCode,
      Intent(context.applicationContext, EmailBackgroundReceiver::class.java).setAction(action),
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** What the controller exposes to background work. */
interface EmailBackgroundWorkProviding {
  suspend fun performBackgroundRefresh(): Boolean
  suspend fun performBackgroundAnalysis(): Boolean
}

/**
 * Runs one background pass and reschedules the next.
 *
 * A broadcast receiver's process may be killed as soon as `onReceive` returns, so
 * the work runs inside `goAsync()` and is bounded — long Gmail backfills stay in
 * the foreground path.
 */
class EmailBackgroundReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    val action = intent?.action ?: return
    if (action != EmailBackgroundWork.ACTION_REFRESH &&
      action != EmailBackgroundWork.ACTION_ANALYSIS
    ) {
      return
    }
    val provider = EmailBackgroundWork.provider
    val appContext = context.applicationContext
    if (provider == null) {
      // Nothing signed in; keep the cadence so work resumes after the next launch.
      reschedule(appContext, action)
      return
    }

    val result = goAsync()
    Thread {
      try {
        runBlocking {
          when (action) {
            EmailBackgroundWork.ACTION_REFRESH -> provider.performBackgroundRefresh()
            else -> provider.performBackgroundAnalysis()
          }
        }
      } catch (error: Throwable) {
        Log.w(TAG, "Email background work failed for $action", error)
      } finally {
        reschedule(appContext, action)
        result.finish()
      }
    }.start()
  }

  private fun reschedule(context: Context, action: String) {
    if (action == EmailBackgroundWork.ACTION_REFRESH) {
      EmailBackgroundWork.scheduleRefresh(context)
    } else {
      EmailBackgroundWork.scheduleAnalysis(context)
    }
  }

  private companion object {
    const val TAG = "EmailBackgroundWork"
  }
}
