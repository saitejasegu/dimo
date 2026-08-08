package app.dimo.android.domain

import androidx.test.core.app.ApplicationProvider
import app.dimo.android.notifications.ExpenseReminderScheduler
import java.util.Calendar
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class ExpenseReminderStoreTests {
  private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()
  private lateinit var userId: String

  @Before
  fun setUp() {
    userId = "expense-reminder-test-${UUID.randomUUID()}"
  }

  @After
  fun tearDown() {
    ExpenseReminderStore.clear(context, userId)
  }

  @Test
  fun settingsRoundTripInSharedPreferences() {
    val saved = ExpenseReminderSettings(enabled = true, hour = 9, minute = 15)
    ExpenseReminderStore.save(context, saved, userId)
    assertEquals(saved, ExpenseReminderStore.load(context, userId))
  }

  @Test
  fun nextTriggerMillisRollsToTomorrowWhenTimeHasPassed() {
    val calendar = Calendar.getInstance().apply {
      set(Calendar.YEAR, 2026)
      set(Calendar.MONTH, Calendar.AUGUST)
      set(Calendar.DAY_OF_MONTH, 8)
      set(Calendar.HOUR_OF_DAY, 21)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    val trigger = ExpenseReminderScheduler.nextTriggerMillis(
      hour = 20,
      minute = 0,
      nowMillis = calendar.timeInMillis,
    )
    val result = Calendar.getInstance().apply { timeInMillis = trigger }
    assertEquals(9, result.get(Calendar.DAY_OF_MONTH))
    assertEquals(20, result.get(Calendar.HOUR_OF_DAY))
    assertEquals(0, result.get(Calendar.MINUTE))
  }
}

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class OnboardingStoreTests {
  private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

  @Before
  fun setUp() {
    OnboardingStore.resetForTesting(context)
  }

  @After
  fun tearDown() {
    OnboardingStore.resetForTesting(context)
  }

  @Test
  fun hasCompletedFlipsOnMark() {
    assertFalse(OnboardingStore.hasCompleted(context))
    OnboardingStore.markCompleted(context)
    assertTrue(OnboardingStore.hasCompleted(context))
  }

  @Test
  fun staleVersionReshowsOnboarding() {
    OnboardingStore.setCompletedVersionForTesting(
      context,
      OnboardingStore.CURRENT_VERSION - 1,
    )
    assertFalse(OnboardingStore.hasCompleted(context))

    OnboardingStore.setCompletedVersionForTesting(
      context,
      OnboardingStore.CURRENT_VERSION + 1,
    )
    assertTrue(OnboardingStore.hasCompleted(context))
  }

  @Test
  fun pendingReminderOptInIsSingleShot() {
    assertFalse(OnboardingStore.consumePendingReminderOptIn(context))

    OnboardingStore.setPendingReminderOptIn(context)
    assertTrue(OnboardingStore.consumePendingReminderOptIn(context))
    assertFalse(OnboardingStore.consumePendingReminderOptIn(context))
  }
}
