package app.dimo.android.data.model

const val WORKSPACE_ID = "global"
const val DEFAULT_CATEGORY_EMOJI = "🙂"
const val BOOTSTRAP_VERSION = 3
const val CASH_PAYMENT_METHOD_ID = "payment-method-cash"
const val PREFERENCES_ID = "preferences"
const val DEVICE_META_ID = "device"
const val OUTBOX_PAGE_SIZE = 50
const val HOME_PAGE_SIZE = 50
const val PULL_PAGE_SIZE = 100
const val CLEAR_PAGE_SIZE = 100
const val DAY_MS = 86_400_000L
const val LEND_BALANCE_EPSILON = 0.0001
const val NAV_GLASS_OPACITY_MIN = 40
const val NAV_GLASS_OPACITY_MAX = 100

enum class EntityType(val wire: String) {
  Category("category"),
  PaymentMethod("paymentMethod"),
  Transaction("transaction"),
  Recurring("recurring"),
  Lend("lend"),
  Preferences("preferences");

  companion object {
    fun fromWire(value: String): EntityType =
      entries.firstOrNull { it.wire == value }
        ?: throw IllegalArgumentException("Unknown entity type: $value")
  }
}

enum class CategoryTint { green, neutral }

enum class PaymentMethodType { UPI, Card, Wallet, Cash, Bank }

enum class RecurringFrequency { monthly, yearly }

enum class Currency { INR, USD, EUR }

enum class WeekStart { Mon, Sun }

enum class ThemePreference { system, light, dark }

enum class StatsRange {
  OneWeek, Month, ThreeMonths, SixMonths, OneYear, TwoYears;

  val wire: String
    get() = when (this) {
      OneWeek -> "1W"
      Month -> "M"
      ThreeMonths -> "3M"
      SixMonths -> "6M"
      OneYear -> "1Y"
      TwoYears -> "2Y"
    }

  companion object {
    fun fromWire(value: String?): StatsRange = when (value) {
      "1W" -> OneWeek
      "M" -> Month
      "3M" -> ThreeMonths
      "6M" -> SixMonths
      "2Y" -> TwoYears
      else -> OneYear
    }
  }
}

enum class ViewKey {
  home, tx, stats, recurring, budgets, lending, settings, account
}

enum class LendKind { lent, repaid }

enum class OutboxStatus { pending, blocked }

data class LogicalVersion(
  val timestamp: Long,
  val counter: Int,
  val deviceId: String,
) : Comparable<LogicalVersion> {
  override fun compareTo(other: LogicalVersion): Int {
    if (timestamp != other.timestamp) return timestamp.compareTo(other.timestamp)
    if (counter != other.counter) return counter.compareTo(other.counter)
    return deviceId.compareTo(other.deviceId)
  }
}

fun compareVersions(a: LogicalVersion, b: LogicalVersion): Int = a.compareTo(b)

fun entityKey(type: EntityType, id: String): String = "$WORKSPACE_ID:${type.wire}:$id"

data class NotificationsPrefs(
  val bills: Boolean = true,
  val budget: Boolean = true,
  val weekly: Boolean = false,
  val large: Boolean = true,
)

sealed class EntityPayload {
  abstract val id: String

  data class Category(
    override val id: String,
    val name: String,
    val emoji: String,
    val monthlyBudgetMinor: Int?,
    val tint: CategoryTint,
    val sortOrder: Int,
    val system: Boolean,
  ) : EntityPayload()

  data class PaymentMethod(
    override val id: String,
    val name: String,
    val type: PaymentMethodType,
    val detail: String,
    val archived: Boolean,
  ) : EntityPayload()

  data class Transaction(
    override val id: String,
    val name: String,
    val amountMinor: Int,
    val occurredAt: Long,
    val categoryId: String,
    val paymentMethodId: String?,
  ) : EntityPayload()

  data class Recurring(
    override val id: String,
    val name: String,
    val amountMinor: Int,
    val categoryId: String,
    val paymentMethodId: String?,
    val frequency: RecurringFrequency,
    val anchorDate: String,
    val paused: Boolean,
  ) : EntityPayload()

  data class Lend(
    override val id: String,
    val contactName: String,
    val contactId: String,
    val amountMinor: Int,
    val occurredAt: Long,
    val comment: String,
    val kind: LendKind?,
  ) : EntityPayload()

  data class Preferences(
    override val id: String = PREFERENCES_ID,
    val profileName: String,
    val profileEmail: String,
    val currency: Currency,
    val weekStart: WeekStart,
    val theme: ThemePreference,
    val navGlassOpacity: Int,
    val defaultView: ViewKey,
    val defaultStatsRange: StatsRange,
    val notifications: NotificationsPrefs,
    val defaultPaymentMethodId: String,
  ) : EntityPayload()
}

data class StoredEntity(
  val key: String,
  val workspaceId: String,
  val entityType: EntityType,
  val entityId: String,
  val version: LogicalVersion,
  val payload: EntityPayload,
  val deleted: Boolean,
  val serverRevision: Long,
)

data class SyncOperation(
  val operationId: String,
  val key: String,
  val workspaceId: String,
  val entityType: EntityType,
  val entityId: String,
  val version: LogicalVersion,
  val payload: EntityPayload,
  val deleted: Boolean,
  val status: OutboxStatus,
  val attempts: Int,
  val lastError: String?,
  val createdAt: Long,
)

data class SyncMeta(
  val workspaceId: String = WORKSPACE_ID,
  val lastPulledRevision: Long = 0,
  val lastSyncedAt: Long? = null,
  val error: String? = null,
  val syncing: Boolean = false,
)

data class DeviceMeta(
  val id: String = DEVICE_META_ID,
  val deviceId: String,
  val clockTimestamp: Long = 0,
  val clockCounter: Int = 0,
  val bootstrapVersion: Int = 0,
  val lastPaymentMethodId: String? = null,
)
