package app.dimo.android.data.db

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.DEFAULT_CATEGORY_EMOJI
import app.dimo.android.data.model.DeviceMeta
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LendEntity
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.NotificationSettings
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.PaymentMethodEntity
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.data.model.PreferencesEntity
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StatsRange
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncMeta
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.ThemePreference
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.ViewKey
import app.dimo.android.data.model.WeekStart

/**
 * Room rows for the typed entity tables, mirroring the v6/v7 GRDB schema in
 * `ios-native/Dimo/Data/Database/Records.swift`.
 *
 * iOS stores the logical version as a JSON blob column; Android embeds it as three
 * columns instead, which is equivalent (the local database is private per device)
 * and lets SQLite compare the fields directly.
 */

/** Shared version columns for every typed table. */
data class VersionColumns(
  @ColumnInfo(name = "versionTimestamp") val timestamp: Long,
  @ColumnInfo(name = "versionCounter") val counter: Long,
  @ColumnInfo(name = "versionDeviceId") val deviceId: String,
) {
  fun toLogicalVersion() = LogicalVersion(timestamp, counter, deviceId)

  companion object {
    fun from(version: LogicalVersion) =
      VersionColumns(version.timestamp, version.counter, version.deviceId)
  }
}

@Entity(
  tableName = "categories",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class CategoryRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val name: String,
  val emoji: String?,
  val monthlyBudgetMinor: Long?,
  val tint: String,
  val sortOrder: Int,
  val system: Boolean,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.CATEGORY,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.Category(
      CategoryEntity(
        id = entityId,
        name = name,
        emoji = emoji ?: DEFAULT_CATEGORY_EMOJI,
        monthlyBudgetMinor = monthlyBudgetMinor,
        tint = CategoryTint.fromWire(tint),
        sortOrder = sortOrder,
        system = system,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): CategoryRecord {
      val e = (entity.payload as EntityPayload.Category).value
      return CategoryRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        name = e.name,
        emoji = e.emoji,
        monthlyBudgetMinor = e.monthlyBudgetMinor,
        tint = e.tint.wire,
        sortOrder = e.sortOrder,
        system = e.system,
      )
    }
  }
}

@Entity(
  tableName = "paymentMethods",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class PaymentMethodRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val name: String,
  val type: String,
  val detail: String,
  val archived: Boolean,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.PAYMENT_METHOD,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.PaymentMethod(
      PaymentMethodEntity(
        id = entityId,
        name = name,
        type = PaymentMethodType.fromWire(type),
        detail = detail,
        archived = archived,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): PaymentMethodRecord {
      val e = (entity.payload as EntityPayload.PaymentMethod).value
      return PaymentMethodRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        name = e.name,
        type = e.type.wire,
        detail = e.detail,
        archived = e.archived,
      )
    }
  }
}

@Entity(
  tableName = "transactions",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class TransactionRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val name: String,
  val amountMinor: Long,
  val occurredAt: Long,
  val categoryId: String,
  val paymentMethodId: String?,
  val currency: String?,
  val sourceCurrency: String?,
  val sourceAmountMinor: Long?,
  val exchangeRate: Double?,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.TRANSACTION,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.Transaction(
      TransactionEntity(
        id = entityId,
        name = name,
        amountMinor = amountMinor,
        occurredAt = occurredAt,
        categoryId = categoryId,
        paymentMethodId = paymentMethodId,
        currency = currency,
        sourceCurrency = sourceCurrency,
        sourceAmountMinor = sourceAmountMinor,
        exchangeRate = exchangeRate,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): TransactionRecord {
      val e = (entity.payload as EntityPayload.Transaction).value
      return TransactionRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        name = e.name,
        amountMinor = e.amountMinor,
        occurredAt = e.occurredAt,
        categoryId = e.categoryId,
        paymentMethodId = e.paymentMethodId,
        currency = e.currency,
        sourceCurrency = e.sourceCurrency,
        sourceAmountMinor = e.sourceAmountMinor,
        exchangeRate = e.exchangeRate,
      )
    }
  }
}

@Entity(
  tableName = "recurring",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class RecurringRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val name: String,
  val amountMinor: Long,
  val categoryId: String,
  val paymentMethodId: String?,
  val frequency: String,
  val anchorDate: String,
  val paused: Boolean,
  val currency: String?,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.RECURRING,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.Recurring(
      RecurringEntity(
        id = entityId,
        name = name,
        amountMinor = amountMinor,
        categoryId = categoryId,
        paymentMethodId = paymentMethodId,
        frequency = RecurringFrequency.fromWire(frequency),
        anchorDate = anchorDate,
        paused = paused,
        currency = currency,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): RecurringRecord {
      val e = (entity.payload as EntityPayload.Recurring).value
      return RecurringRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        name = e.name,
        amountMinor = e.amountMinor,
        categoryId = e.categoryId,
        paymentMethodId = e.paymentMethodId,
        frequency = e.frequency.wire,
        anchorDate = e.anchorDate,
        paused = e.paused,
        currency = e.currency,
      )
    }
  }
}

@Entity(
  tableName = "lends",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class LendRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val contactName: String,
  val contactId: String?,
  val amountMinor: Long,
  val occurredAt: Long,
  val comment: String,
  val kind: String?,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.LEND,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.Lend(
      LendEntity(
        id = entityId,
        contactName = contactName,
        // Legacy rows may omit contactId; fall back to the display name.
        contactId = contactId?.takeIf { it.isNotBlank() } ?: contactName,
        amountMinor = amountMinor,
        occurredAt = occurredAt,
        comment = comment,
        kind = LendKind.fromWire(kind),
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): LendRecord {
      val e = (entity.payload as EntityPayload.Lend).value
      return LendRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        contactName = e.contactName,
        contactId = e.contactId,
        amountMinor = e.amountMinor,
        occurredAt = e.occurredAt,
        comment = e.comment,
        kind = e.kind?.wire,
      )
    }
  }
}

@Entity(
  tableName = "preferences",
  indices = [
    Index("workspaceId", "entityId"),
    Index("workspaceId", "serverRevision"),
  ],
)
data class PreferencesRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityId: String,
  @Embedded val version: VersionColumns,
  val deleted: Boolean,
  val serverRevision: Long,
  val profileName: String,
  val profileEmail: String,
  val currency: String,
  val weekStart: String,
  val theme: String?,
  val navGlassOpacity: Int?,
  val defaultView: String,
  val defaultStatsRange: String?,
  @Embedded(prefix = "notif_") val notifications: NotificationColumns,
  val defaultPaymentMethodId: String,
) {
  fun toStoredEntity() = StoredEntity(
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.PREFERENCES,
    entityId = entityId,
    version = version.toLogicalVersion(),
    payload = EntityPayload.Preferences(
      PreferencesEntity(
        id = entityId,
        profileName = profileName,
        profileEmail = profileEmail,
        currency = Currency.fromWire(currency),
        weekStart = WeekStart.fromWire(weekStart),
        theme = ThemePreference.fromWire(theme),
        navGlassOpacity = navGlassOpacity ?: 40,
        defaultView = ViewKey.fromWire(defaultView),
        defaultStatsRange = StatsRange.fromWire(defaultStatsRange),
        notifications = notifications.toSettings(),
        defaultPaymentMethodId = defaultPaymentMethodId,
      ),
    ),
    deleted = deleted,
    serverRevision = serverRevision,
  )

  companion object {
    fun from(entity: StoredEntity): PreferencesRecord {
      val e = (entity.payload as EntityPayload.Preferences).value
      return PreferencesRecord(
        key = entity.key,
        workspaceId = entity.workspaceId,
        entityId = entity.entityId,
        version = VersionColumns.from(entity.version),
        deleted = entity.deleted,
        serverRevision = entity.serverRevision,
        profileName = e.profileName,
        profileEmail = e.profileEmail,
        currency = e.currency.wire,
        weekStart = e.weekStart.wire,
        theme = e.theme.wire,
        navGlassOpacity = e.navGlassOpacity,
        defaultView = e.defaultView.wire,
        defaultStatsRange = e.defaultStatsRange.wire,
        notifications = NotificationColumns.from(e.notifications),
        defaultPaymentMethodId = e.defaultPaymentMethodId,
      )
    }
  }
}

data class NotificationColumns(
  val bills: Boolean,
  val budget: Boolean,
  val weekly: Boolean,
  val large: Boolean,
) {
  fun toSettings() = NotificationSettings(bills, budget, weekly, large)

  companion object {
    fun from(settings: NotificationSettings) =
      NotificationColumns(settings.bills, settings.budget, settings.weekly, settings.large)
  }
}

/**
 * Dirty-key outbox. The primary key is the entity key, so a later edit to the
 * same entity replaces the pending operation instead of queueing a second one.
 * Payload and version are read back from the typed row at push time.
 */
@Entity(
  tableName = "outbox",
  indices = [Index("operationId", unique = true), Index("status"), Index("createdAt")],
)
data class OutboxRecord(
  @PrimaryKey val key: String,
  val operationId: String,
  val workspaceId: String,
  val entityType: String,
  val entityId: String,
  val status: String,
  val attempts: Int,
  val lastError: String?,
  val createdAt: Long,
) {
  fun toSyncOperation(
    payload: EntityPayload,
    version: LogicalVersion,
    deleted: Boolean,
  ) = SyncOperation(
    operationId = operationId,
    key = key,
    workspaceId = workspaceId,
    entityType = EntityType.fromWire(entityType) ?: EntityType.TRANSACTION,
    entityId = entityId,
    version = version,
    payload = payload,
    deleted = deleted,
    status = OutboxStatus.fromWire(status),
    attempts = attempts,
    lastError = lastError,
    createdAt = createdAt,
  )

  companion object {
    fun from(op: SyncOperation) = OutboxRecord(
      key = op.key,
      operationId = op.operationId,
      workspaceId = op.workspaceId,
      entityType = op.entityType.wire,
      entityId = op.entityId,
      status = op.status.wire,
      attempts = op.attempts,
      lastError = op.lastError,
      createdAt = op.createdAt,
    )
  }
}

@Entity(tableName = "syncMeta")
data class SyncMetaRecord(
  @PrimaryKey val workspaceId: String,
  val lastPulledRevision: Long,
  val lastSyncedAt: Long?,
  val error: String?,
  val syncing: Boolean,
  /** Serialized `entityType.wire=revision` pairs, one per line. */
  val pulledRevisions: String?,
) {
  fun toSyncMeta() = SyncMeta(
    workspaceId = workspaceId,
    lastPulledRevision = lastPulledRevision,
    lastSyncedAt = lastSyncedAt,
    error = error,
    syncing = syncing,
    pulledRevisions = decodePulled(pulledRevisions),
  )

  companion object {
    fun from(meta: SyncMeta) = SyncMetaRecord(
      workspaceId = meta.workspaceId,
      lastPulledRevision = meta.lastPulledRevision,
      lastSyncedAt = meta.lastSyncedAt,
      error = meta.error,
      syncing = meta.syncing,
      pulledRevisions = encodePulled(meta.pulledRevisions),
    )

    private fun encodePulled(pulled: Map<EntityType, Long>): String? {
      if (pulled.isEmpty()) return null
      return pulled.entries.joinToString("\n") { "${it.key.wire}=${it.value}" }
    }

    private fun decodePulled(raw: String?): Map<EntityType, Long> {
      if (raw.isNullOrEmpty()) return emptyMap()
      return raw.lineSequence().mapNotNull { line ->
        val parts = line.split("=", limit = 2)
        if (parts.size != 2) return@mapNotNull null
        val type = EntityType.fromWire(parts[0]) ?: return@mapNotNull null
        val revision = parts[1].toLongOrNull() ?: return@mapNotNull null
        type to revision
      }.toMap()
    }
  }
}

@Entity(tableName = "deviceMeta")
data class DeviceMetaRecord(
  @PrimaryKey val id: String,
  val deviceId: String,
  val clockTimestamp: Long,
  val clockCounter: Long,
  val bootstrapVersion: Int,
  val lastPaymentMethodId: String?,
) {
  fun toDeviceMeta() = DeviceMeta(
    id = id,
    deviceId = deviceId,
    clockTimestamp = clockTimestamp,
    clockCounter = clockCounter,
    bootstrapVersion = bootstrapVersion,
    lastPaymentMethodId = lastPaymentMethodId,
  )

  companion object {
    fun from(meta: DeviceMeta) = DeviceMetaRecord(
      id = meta.id,
      deviceId = meta.deviceId,
      clockTimestamp = meta.clockTimestamp,
      clockCounter = meta.clockCounter,
      bootstrapVersion = meta.bootstrapVersion,
      lastPaymentMethodId = meta.lastPaymentMethodId,
    )
  }
}

/** Builds the Room row for any entity type, the analogue of `TypedEntityStore.save`. */
fun storedEntityToRecord(entity: StoredEntity): Any = when (entity.entityType) {
  EntityType.CATEGORY -> CategoryRecord.from(entity)
  EntityType.PAYMENT_METHOD -> PaymentMethodRecord.from(entity)
  EntityType.TRANSACTION -> TransactionRecord.from(entity)
  EntityType.RECURRING -> RecurringRecord.from(entity)
  EntityType.LEND -> LendRecord.from(entity)
  EntityType.PREFERENCES -> PreferencesRecord.from(entity)
}
