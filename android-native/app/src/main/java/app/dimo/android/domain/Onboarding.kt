package app.dimo.android.domain

import android.content.Context

/**
 * One page of the first-run walkthrough.
 * Port of `ios-native/Dimo/Domain/Onboarding.swift` (Email page omitted on Android).
 */
data class OnboardingPage(
  /** Stable key mapped to a Material icon in the UI layer. */
  val iconKey: String,
  val title: String,
  val body: String,
)

object OnboardingCopy {
  /**
   * Feature pages, in order. The notification priming page is not here — it
   * carries its own actions and is rendered separately.
   */
  val pages: List<OnboardingPage> = listOf(
    OnboardingPage(
      iconKey = "wallet",
      title = "Welcome to Dimo",
      body = "A calm, local-first ledger. Everything is saved on your phone first, " +
        "works offline, and syncs to web and iOS when you're back online.",
    ),
    OnboardingPage(
      iconKey = "home",
      title = "Log spending in seconds",
      body = "Add an expense from anywhere with the keypad, see it grouped by day, " +
        "and keep upcoming bills in view.",
    ),
    OnboardingPage(
      iconKey = "chart",
      title = "See where it goes",
      body = "Monthly trends, top categories, and top merchants — tap any bar to " +
        "drill into the month behind it.",
    ),
    OnboardingPage(
      iconKey = "budget",
      title = "Stay inside your budget",
      body = "Set a monthly limit per category and watch the bars fill. Dimo can " +
        "suggest starting budgets from your history.",
    ),
    OnboardingPage(
      iconKey = "people",
      title = "Track money you lend",
      body = "Two-way balances per contact for money lent and borrowed, with " +
        "settlements you can share.",
    ),
  )

  val remindersPage = OnboardingPage(
    iconKey = "bell",
    title = "Never lose a day",
    body = "A gentle nudge each evening to log what you spent. You can change the " +
      "time or turn it off in Settings.",
  )

  val allPages: List<OnboardingPage> = pages + remindersPage
}

/**
 * Device-local first-run state. Deliberately not scoped by userId and not
 * cleared on sign-out — onboarding runs before a user exists, and signing out
 * should not replay the tour.
 */
object OnboardingStore {
  /** Bump to re-show a revised walkthrough to everyone. */
  const val CURRENT_VERSION = 1

  private const val PREFS = "dimo_device_prefs"
  private const val COMPLETED_VERSION_KEY = "dimo.onboarding.completedVersion"
  private const val PENDING_REMINDER_KEY = "dimo.onboarding.pendingReminderOptIn"

  fun hasCompleted(context: Context): Boolean =
    prefs(context).getInt(COMPLETED_VERSION_KEY, 0) >= CURRENT_VERSION

  fun markCompleted(context: Context) {
    prefs(context).edit().putInt(COMPLETED_VERSION_KEY, CURRENT_VERSION).apply()
  }

  /**
   * Set only when the user granted notification permission during onboarding.
   * The daily reminder itself is userId-scoped, so it can only be enabled once
   * a session exists — [consumePendingReminderOptIn] bridges the two.
   */
  fun setPendingReminderOptIn(context: Context) {
    prefs(context).edit().putBoolean(PENDING_REMINDER_KEY, true).apply()
  }

  /** Reads and clears in one shot so the opt-in applies to exactly one sign-in. */
  fun consumePendingReminderOptIn(context: Context): Boolean {
    val prefs = prefs(context)
    if (!prefs.getBoolean(PENDING_REMINDER_KEY, false)) return false
    prefs.edit().remove(PENDING_REMINDER_KEY).apply()
    return true
  }

  /** Test hook — resets both keys. */
  fun resetForTesting(context: Context) {
    prefs(context).edit()
      .remove(COMPLETED_VERSION_KEY)
      .remove(PENDING_REMINDER_KEY)
      .apply()
  }

  /** Exposed for tests that need to write a stale completed version. */
  fun setCompletedVersionForTesting(context: Context, version: Int) {
    prefs(context).edit().putInt(COMPLETED_VERSION_KEY, version).apply()
  }

  private fun prefs(context: Context) =
    context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
