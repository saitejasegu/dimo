package app.dimo.android.data.model

/**
 * Port of `ios-native/Dimo/Data/Model/Entities.swift`.
 *
 * Android is not an `emailMessage` writer, so that entity type is absent here.
 * See `android-native/README.md` for why it must also stay out of clear/upload.
 */

enum class EntityType(val wire: String) {
  CATEGORY("category"),
  PAYMENT_METHOD("paymentMethod"),
  TRANSACTION("transaction"),
  RECURRING("recurring"),
  LEND("lend"),
  PREFERENCES("preferences");

  companion object {
    fun fromWire(value: String): EntityType? = entries.firstOrNull { it.wire == value }
  }
}

data class LogicalVersion(
  val timestamp: Long,
  val counter: Long,
  val deviceId: String,
) : Comparable<LogicalVersion> {
  override fun compareTo(other: LogicalVersion): Int = compareVersions(this, other)
}

/** Matches the Swift `compareVersions` ordering: timestamp, then counter, then deviceId. */
fun compareVersions(a: LogicalVersion, b: LogicalVersion): Int {
  if (a.timestamp != b.timestamp) return a.timestamp.compareTo(b.timestamp)
  if (a.counter != b.counter) return a.counter.compareTo(b.counter)
  return a.deviceId.compareTo(b.deviceId)
}

const val WORKSPACE_ID = "global"
const val DEFAULT_CATEGORY_EMOJI = "🙂"
const val BOOTSTRAP_VERSION = 4

/**
 * Private local tombstone retention (days). Keep aligned with the Convex
 * TOMBSTONE_RETENTION_DAYS default — not user-visible or synced.
 */
const val TOMBSTONE_RETENTION_DAYS = 90

fun entityKey(type: EntityType, id: String): String = "$WORKSPACE_ID:${type.wire}:$id"

enum class CategoryTint(val wire: String) {
  GREEN("green"),
  NEUTRAL("neutral");

  companion object {
    fun fromWire(value: String?): CategoryTint =
      entries.firstOrNull { it.wire == value } ?: NEUTRAL
  }
}

enum class PaymentMethodType(val wire: String) {
  UPI("UPI"),
  CARD("Card"),
  WALLET("Wallet"),
  CASH("Cash"),
  BANK("Bank");

  companion object {
    fun fromWire(value: String?): PaymentMethodType =
      entries.firstOrNull { it.wire == value } ?: CASH
  }
}

enum class RecurringFrequency(val wire: String) {
  MONTHLY("monthly"),
  YEARLY("yearly");

  companion object {
    fun fromWire(value: String?): RecurringFrequency =
      entries.firstOrNull { it.wire == value } ?: MONTHLY
  }
}

enum class Currency(val wire: String) {
  INR("INR"),
  USD("USD"),
  EUR("EUR");

  companion object {
    fun fromWire(value: String?): Currency = entries.firstOrNull { it.wire == value } ?: INR
  }
}

enum class WeekStart(val wire: String) {
  MON("Mon"),
  SUN("Sun");

  companion object {
    fun fromWire(value: String?): WeekStart = entries.firstOrNull { it.wire == value } ?: MON
  }
}

enum class ThemePreference(val wire: String) {
  SYSTEM("system"),
  LIGHT("light"),
  DARK("dark");

  companion object {
    fun fromWire(value: String?): ThemePreference =
      entries.firstOrNull { it.wire == value } ?: LIGHT
  }
}

enum class StatsRange(val wire: String) {
  ONE_WEEK("1W"),
  MONTH("M"),
  THREE_MONTHS("3M"),
  SIX_MONTHS("6M"),
  ONE_YEAR("1Y"),
  TWO_YEARS("2Y");

  companion object {
    fun fromWire(value: String?): StatsRange = entries.firstOrNull { it.wire == value } ?: ONE_YEAR
  }
}

enum class ViewKey(val wire: String) {
  HOME("home"),
  TX("tx"),
  STATS("stats"),
  RECURRING("recurring"),
  BUDGETS("budgets"),
  LENDING("lending"),
  SETTINGS("settings"),
  ACCOUNT("account");

  companion object {
    fun fromWire(value: String?): ViewKey = entries.firstOrNull { it.wire == value } ?: HOME
  }
}

data class NotificationSettings(
  val bills: Boolean,
  val budget: Boolean,
  val weekly: Boolean,
  val large: Boolean,
)

// MARK: - Persisted entities

data class CategoryEntity(
  val id: String,
  val name: String,
  val emoji: String,
  val monthlyBudgetMinor: Long?,
  val tint: CategoryTint,
  val sortOrder: Int,
  val system: Boolean,
)

data class PaymentMethodEntity(
  val id: String,
  val name: String,
  val type: PaymentMethodType,
  val detail: String,
  val archived: Boolean,
)

data class TransactionEntity(
  val id: String,
  val name: String,
  val amountMinor: Long,
  val occurredAt: Long,
  val categoryId: String,
  val paymentMethodId: String?,
  /**
   * Denomination of [amountMinor] — the account default at write time. New writers
   * always set it so a later preferences change cannot reinterpret historical
   * amounts. Absent only on legacy rows.
   */
  val currency: String? = null,
  /** Original currency when entered in a non-default currency. Absent = [currency]. */
  val sourceCurrency: String? = null,
  /** Original amount in [sourceCurrency] minor units (kept for display/edit). */
  val sourceAmountMinor: Long? = null,
  /** Rate used to convert [sourceCurrency] to [currency] (major-unit ratio). */
  val exchangeRate: Double? = null,
)

data class RecurringEntity(
  val id: String,
  val name: String,
  val amountMinor: Long,
  val categoryId: String,
  val paymentMethodId: String?,
  val frequency: RecurringFrequency,
  val anchorDate: String,
  val paused: Boolean,
  /** Currency the amount is denominated in. Absent only on legacy rows. */
  val currency: String? = null,
)

enum class LendKind(val wire: String) {
  /** The user gave the contact money. */
  LENT("lent"),
  /** The contact gave it back. */
  REPAID("repaid"),
  /** The user took money from the contact. */
  BORROWED("borrowed"),
  /** The user paid the contact back. */
  RETURNED("returned");

  /** Money flowed towards the user rather than away from them. */
  val isIncoming: Boolean
    get() = when (this) {
      REPAID, BORROWED -> true
      LENT, RETURNED -> false
    }

  companion object {
    fun fromWire(value: String?): LendKind? = entries.firstOrNull { it.wire == value }
  }
}

data class LendEntity(
  val id: String,
  val contactName: String,
  /**
   * Address-book identifier of the picked contact, so same-named contacts stay
   * distinct. Legacy rows may omit this; decoding falls back to the name.
   */
  val contactId: String,
  val amountMinor: Long,
  val occurredAt: Long,
  val comment: String,
  /** Optional so rows saved before repayments existed still decode; null means lent. */
  val kind: LendKind?,
)

data class PreferencesEntity(
  val id: String,
  val profileName: String,
  val profileEmail: String,
  val currency: Currency,
  val weekStart: WeekStart,
  val theme: ThemePreference,
  val navGlassOpacity: Int,
  val defaultView: ViewKey,
  val defaultStatsRange: StatsRange,
  val notifications: NotificationSettings,
  val defaultPaymentMethodId: String,
)

sealed interface EntityPayload {
  val id: String
  val entityType: EntityType

  data class Category(val value: CategoryEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.CATEGORY
  }

  data class PaymentMethod(val value: PaymentMethodEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.PAYMENT_METHOD
  }

  data class Transaction(val value: TransactionEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.TRANSACTION
  }

  data class Recurring(val value: RecurringEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.RECURRING
  }

  data class Lend(val value: LendEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.LEND
  }

  data class Preferences(val value: PreferencesEntity) : EntityPayload {
    override val id get() = value.id
    override val entityType get() = EntityType.PREFERENCES
  }
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

enum class OutboxStatus(val wire: String) {
  PENDING("pending"),
  BLOCKED("blocked");

  companion object {
    fun fromWire(value: String?): OutboxStatus =
      entries.firstOrNull { it.wire == value } ?: PENDING
  }
}

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
  val workspaceId: String,
  val lastPulledRevision: Long,
  val lastSyncedAt: Long?,
  val error: String?,
  val syncing: Boolean,
  val pulledRevisions: Map<EntityType, Long> = emptyMap(),
)

data class DeviceMeta(
  val id: String,
  val deviceId: String,
  val clockTimestamp: Long,
  val clockCounter: Long,
  val bootstrapVersion: Int,
  val lastPaymentMethodId: String?,
)

// MARK: - UI models (ports of the display structs in Entities.swift)

data class PaymentMethodOption(
  val id: String,
  val name: String,
  val type: PaymentMethodType,
  val detail: String,
  val isDefault: Boolean,
  val archived: Boolean,
) {
  val label: String
    get() = if (type == PaymentMethodType.CASH) {
      name
    } else {
      listOf(type.wire, name, detail).filter { it.isNotEmpty() }.joinToString(" · ")
    }
}

data class Transaction(
  val id: String,
  val name: String,
  val category: String,
  val time: String,
  val day: String,
  val amount: Double,
  val paymentMethod: String? = null,
  val green: Boolean? = null,
  val emoji: String? = null,
  val amountMinor: Long? = null,
  val occurredAt: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  /** Denomination of [amountMinor] / display [amount] when not converted for totals. */
  val currency: String? = null,
  /** Original currency when entered in a non-default currency (else null). */
  val sourceCurrency: String? = null,
  /** Original amount in [sourceCurrency] major units, shown alongside [amount]. */
  val sourceAmount: Double? = null,
)

data class Recurring(
  val id: String,
  val name: String,
  val category: String,
  val due: String,
  val amount: Double,
  val paused: Boolean,
  val urgent: Boolean? = null,
  val green: Boolean? = null,
  val emoji: String? = null,
  val amountMinor: Long? = null,
  val categoryId: String? = null,
  val paymentMethodId: String? = null,
  val anchorDate: String? = null,
  val frequency: RecurringFrequency? = null,
  /** Currency the amount is denominated in. null = account default currency. */
  val currency: String? = null,
)

data class Lend(
  val id: String,
  val contactName: String,
  val contactId: String,
  val amount: Double,
  val comment: String,
  val time: String,
  val day: String,
  val amountMinor: Long,
  val occurredAt: Long,
  val kind: LendKind,
) {
  /**
   * Positive for money that left the user's pocket (lent out, or paid back to
   * someone they borrowed from), negative for money that came in.
   */
  val signedAmount: Double get() = if (kind.isIncoming) -amount else amount

  /** Money came towards the user, so the row reads as a credit. */
  val isIncoming: Boolean get() = kind.isIncoming
}

/** Category display name to optional monthly limit in major units. */
typealias CategoryLimits = Map<String, Double?>
