package app.dimo.android.store

import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.domain.DateHelpers
import app.dimo.android.domain.LendFlow
import app.dimo.android.sync.LendUser
import java.time.Instant
import java.time.LocalDate

/** Overlay sheets, matching iOS `OverlayKey` in MainTabShell. */
enum class OverlayKey {
  Add,
  Recurring,
  Category,
  Lend,
}

data class ExpenseDraft(
  val name: String = "",
  val amount: String = "",
  val category: String = "",
  val paymentMethodId: String? = null,
  val date: Instant = Instant.now(),
)

data class RecurringDraft(
  val editingId: String? = null,
  val name: String = "",
  val amount: String = "",
  val currency: String? = null,
  val category: String = "Bills",
  val paymentMethodId: String? = null,
  val frequency: RecurringFrequency = RecurringFrequency.MONTHLY,
  val anchorDate: String = DateHelpers.localDateKey(LocalDate.now(DateHelpers.zone())),
  val paused: Boolean = false,
)

data class CategoryDraft(
  val editingId: String? = null,
  val name: String = "",
  val emoji: String = "🙂",
  val limitText: String = "",
  val tint: CategoryTint = CategoryTint.NEUTRAL,
)

data class LendDraft(
  val editingId: String? = null,
  /**
   * "I gave" or "I got"; whether that's a loan or a repayment follows from the
   * balance when saving.
   */
  val flow: LendFlow = LendFlow.GAVE,
  /** Opened from a person's page, so the person can't be changed. */
  val contactLocked: Boolean = false,
  val contactName: String = "",
  val contactId: String? = null,
  val amount: String = "",
  val date: Instant = Instant.now(),
  val comment: String = "",
  /** A Dimo account picked by email; saving the entry invites them. */
  val invite: LendDraftInvite? = null,
)

/**
 * The Dimo account a new lend's contact was found as, and the contactId
 * generated for them so the entry is shared once they accept.
 */
data class LendDraftInvite(val user: LendUser, val contactId: String)
