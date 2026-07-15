package app.dimo.android.store

import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.ThemePreference

data class UiCategory(
  val id: String,
  val name: String,
  val emoji: String,
  val monthlyBudget: Double?,
  val tint: CategoryTint,
  val sortOrder: Int,
  val system: Boolean,
)

data class UiPaymentMethod(
  val id: String,
  val name: String,
  val type: PaymentMethodType,
  val detail: String,
  val archived: Boolean,
  val isDefault: Boolean,
)

data class UiTransaction(
  val id: String,
  val name: String,
  val amount: Double,
  val occurredAt: Long,
  val categoryId: String,
  val category: String,
  val emoji: String,
  val tint: String,
  val paymentMethodId: String?,
  val paymentMethod: String?,
)

data class UiRecurring(
  val id: String,
  val name: String,
  val amount: Double,
  val categoryId: String,
  val category: String,
  val emoji: String,
  val paymentMethodId: String?,
  val paymentMethod: String?,
  val frequency: RecurringFrequency,
  val anchorDate: String,
  val paused: Boolean,
  val dueLabel: String,
)

data class UiLend(
  val id: String,
  val contactName: String,
  val contactId: String,
  val amount: Double,
  val occurredAt: Long,
  val comment: String,
  val kind: LendKind,
)

data class ExpenseDraft(
  val id: String? = null,
  val name: String = "",
  val amount: String = "",
  val category: String = "",
  val paymentMethodId: String? = null,
  val occurredAt: Long = System.currentTimeMillis(),
  val makeRecurring: Boolean = false,
  val frequency: RecurringFrequency = RecurringFrequency.monthly,
  val includeHistorical: Boolean = false,
)

data class RecurringDraft(
  val id: String? = null,
  val name: String = "",
  val amount: String = "",
  val category: String = "",
  val paymentMethodId: String? = null,
  val frequency: RecurringFrequency = RecurringFrequency.monthly,
  val anchorDate: String = "",
  val includeHistorical: Boolean = true,
)

data class CategoryDraft(
  val id: String? = null,
  val name: String = "",
  val emoji: String = "🙂",
  val monthlyBudget: String = "",
  val tint: CategoryTint = CategoryTint.green,
)

data class LendDraft(
  val id: String? = null,
  val contactName: String = "",
  val contactId: String = "",
  val amount: String = "",
  val comment: String = "",
  val kind: LendKind = LendKind.lent,
  val occurredAt: Long = System.currentTimeMillis(),
)

enum class OverlayKey { add, recurring, category, lend }

enum class AppTab { home, stats, budgets, lending }
