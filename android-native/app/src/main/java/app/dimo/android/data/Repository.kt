package app.dimo.android.data

import app.dimo.android.data.db.AppDatabase
import app.dimo.android.data.db.DeviceMetaRecord
import app.dimo.android.data.db.EntityRecord
import app.dimo.android.data.db.OutboxRecord
import app.dimo.android.data.db.SyncMetaRecord
import app.dimo.android.data.model.BOOTSTRAP_VERSION
import app.dimo.android.data.model.DEVICE_META_ID
import app.dimo.android.data.model.DeviceMeta
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.OUTBOX_PAGE_SIZE
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.SeedData
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncMeta
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.TOMBSTONE_RETENTION_DAYS
import app.dimo.android.data.model.WORKSPACE_ID
import app.dimo.android.data.model.compareVersions
import app.dimo.android.data.model.entityKey
import app.dimo.android.data.model.DAY_MS
import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.map
import java.util.UUID
import kotlin.math.max

data class RemoteEntity(
  val workspaceId: String,
  val entityType: EntityType,
  val entityId: String,
  val version: LogicalVersion,
  val payload: EntityPayload,
  val deleted: Boolean,
  val serverRevision: Long,
)

class Repository(private val db: AppDatabase) {
  private val writeListeners = MutableSharedFlow<Unit>(extraBufferCapacity = 64)
  val localWrites = writeListeners.asSharedFlow()

  fun observeEntities(): Flow<List<StoredEntity>> =
    db.entities().observeAll(WORKSPACE_ID).map { rows -> rows.map { it.toStored() } }

  fun observeSyncMeta(): Flow<SyncMeta> =
    db.syncMeta().observe(WORKSPACE_ID).map { it?.toDomain() ?: SyncMeta() }

  fun observePendingCount(): Flow<Int> = db.outbox().observePendingCount()
  fun observeBlockedCount(): Flow<Int> = db.outbox().observeBlockedCount()

  suspend fun initializeLocalDatabase() {
    val device = ensureDeviceMeta()
    if (device.bootstrapVersion < BOOTSTRAP_VERSION) {
      if (db.entities().get(entityKey(EntityType.PaymentMethod, SeedData.cash.id)) == null) {
        putLocalOnly(EntityType.PaymentMethod, SeedData.cash, deleted = false)
      }
      if (db.entities().get(entityKey(EntityType.Preferences, SeedData.defaultPreferences.id)) == null) {
        putLocalOnly(EntityType.Preferences, SeedData.defaultPreferences, deleted = false)
      }
      val current = requireDevice()
      db.deviceMeta().upsert(
        current.copy(bootstrapVersion = BOOTSTRAP_VERSION).toRecord(),
      )
    }
    if (db.syncMeta().get(WORKSPACE_ID) == null) {
      db.syncMeta().upsert(SyncMeta().toRecord())
    }
  }

  suspend fun saveEntity(type: EntityType, payload: EntityPayload, deleted: Boolean = false) {
    db.withTransaction {
      putInTransaction(type, payload, deleted)
    }
    notifyWrite()
  }

  suspend fun saveEntities(items: List<Triple<EntityType, EntityPayload, Boolean>>) {
    db.withTransaction {
      for ((type, payload, deleted) in items) {
        putInTransaction(type, payload, deleted)
      }
    }
    notifyWrite()
  }

  suspend fun removeEntity(type: EntityType, id: String) {
    val key = entityKey(type, id)
    val existing = db.entities().get(key) ?: return
    if (existing.deleted) return
    val payload = PayloadCodec.decodePayload(type, existing.payloadJson)
    saveEntity(type, payload, deleted = true)
  }

  suspend fun removeActiveEntities(type: EntityType): Int {
    val active = db.entities().activeByType(WORKSPACE_ID, type.wire)
    if (active.isEmpty()) return 0
    db.withTransaction {
      for (row in active) {
        val payload = PayloadCodec.decodePayload(type, row.payloadJson)
        putInTransaction(type, payload, deleted = true)
      }
    }
    notifyWrite()
    return active.size
  }

  suspend fun setLastPaymentMethod(id: String?) {
    val device = requireDevice()
    db.deviceMeta().upsert(device.copy(lastPaymentMethodId = id).toRecord())
  }

  suspend fun deviceMeta(): DeviceMeta = requireDevice()

  suspend fun syncMeta(): SyncMeta = db.syncMeta().get(WORKSPACE_ID)?.toDomain() ?: SyncMeta()

  suspend fun updateSyncMeta(meta: SyncMeta) {
    db.syncMeta().upsert(meta.toRecord())
  }

  suspend fun activeEntities(type: EntityType): List<StoredEntity> =
    db.entities().activeByType(WORKSPACE_ID, type.wire).map { it.toStored() }

  suspend fun allEntities(): List<StoredEntity> =
    db.entities().all(WORKSPACE_ID).map { it.toStored() }

  suspend fun pendingOutbox(limit: Int = OUTBOX_PAGE_SIZE): List<SyncOperation> =
    db.outbox().pending(limit).map { it.toDomain() }

  suspend fun blockedOutbox(): SyncOperation? = db.outbox().blocked()?.toDomain()

  suspend fun outboxCounts(): Pair<Int, Int> =
    db.outbox().pendingCount() to db.outbox().blockedCount()

  suspend fun updateOutbox(op: SyncOperation) {
    db.outbox().upsert(op.toRecord())
  }

  suspend fun acknowledgeOperations(ids: List<String>) {
    if (ids.isEmpty()) return
    db.outbox().deleteByOperationIds(ids)
  }

  suspend fun enqueueUnsyncedDefaults() {
    val defaults = listOf(
      EntityType.PaymentMethod to SeedData.cash.id,
      EntityType.Preferences to SeedData.defaultPreferences.id,
    )
    var changed = false
    db.withTransaction {
      for ((type, id) in defaults) {
        val key = entityKey(type, id)
        val entity = db.entities().get(key) ?: continue
        if (entity.deleted || entity.serverRevision != 0L) continue
        if (db.outbox().getByKey(key) != null) continue
        val payload = PayloadCodec.decodePayload(type, entity.payloadJson)
        putInTransaction(type, payload, deleted = false)
        changed = true
      }
    }
    if (changed) notifyWrite()
  }

  suspend fun enqueueFullUpload(types: Collection<EntityType> = EntityType.entries) {
    db.withTransaction {
      for (type in types) {
        val rows = db.entities().all(WORKSPACE_ID).filter { it.entityType == type.wire }
        for (row in rows) {
          val payload = PayloadCodec.decodePayload(type, row.payloadJson)
          putInTransaction(type, payload, deleted = row.deleted)
        }
      }
    }
    notifyWrite()
  }

  suspend fun mergeRemotePage(remotes: List<RemoteEntity>, cursor: Long) {
    db.withTransaction {
      for (remote in remotes) {
        observeRemoteVersion(remote.version)
        val key = entityKey(remote.entityType, remote.entityId)
        val local = db.entities().get(key)
        val apply = local == null ||
          compareVersions(remote.version, PayloadCodec.decodeVersion(local.versionJson)) >= 0
        if (apply) {
          val clean = PayloadSanitizer.sanitize(remote.entityType, remote.payload)
          db.entities().upsert(
            EntityRecord(
              key = key,
              workspaceId = WORKSPACE_ID,
              entityType = remote.entityType.wire,
              entityId = remote.entityId,
              versionJson = PayloadCodec.encodeVersion(remote.version),
              payloadJson = PayloadCodec.encodePayload(clean),
              deleted = remote.deleted,
              serverRevision = remote.serverRevision,
            ),
          )
          val pending = db.outbox().getByKey(key)
          if (pending != null) {
            val pendingVersion = PayloadCodec.decodeVersion(pending.versionJson)
            if (compareVersions(remote.version, pendingVersion) >= 0) {
              db.outbox().deleteByKey(key)
            }
          }
        }
      }
      val meta = syncMeta()
      db.syncMeta().upsert(meta.copy(lastPulledRevision = cursor).toRecord())
    }
  }

  /**
   * Hard-delete local tombstones past the private retention window.
   * Skips rows that still have an unacked outbox operation.
   */
  suspend fun purgeExpiredTombstones(now: Long = System.currentTimeMillis()): Int {
    val cutoff = now - TOMBSTONE_RETENTION_DAYS * DAY_MS
    var purged = 0
    db.withTransaction {
      for (row in db.entities().deleted(WORKSPACE_ID)) {
        val version = PayloadCodec.decodeVersion(row.versionJson)
        if (version.timestamp >= cutoff) continue
        if (db.outbox().getByKey(row.key) != null) continue
        db.entities().deleteByKey(row.key)
        purged += 1
      }
    }
    return purged
  }

  private suspend fun putInTransaction(
    type: EntityType,
    payload: EntityPayload,
    deleted: Boolean,
  ) {
    val version = nextVersion()
    val clean = PayloadSanitizer.sanitize(type, payload)
    val key = entityKey(type, clean.id)
    db.entities().upsert(
      EntityRecord(
        key = key,
        workspaceId = WORKSPACE_ID,
        entityType = type.wire,
        entityId = clean.id,
        versionJson = PayloadCodec.encodeVersion(version),
        payloadJson = PayloadCodec.encodePayload(clean),
        deleted = deleted,
        serverRevision = 0,
      ),
    )
    db.outbox().upsert(
      OutboxRecord(
        key = key,
        operationId = UUID.randomUUID().toString().lowercase(),
        workspaceId = WORKSPACE_ID,
        entityType = type.wire,
        entityId = clean.id,
        versionJson = PayloadCodec.encodeVersion(version),
        payloadJson = PayloadCodec.encodePayload(clean),
        deleted = deleted,
        status = OutboxStatus.pending.name,
        attempts = 0,
        lastError = null,
        createdAt = System.currentTimeMillis(),
      ),
    )
  }

  private suspend fun putLocalOnly(type: EntityType, payload: EntityPayload, deleted: Boolean) {
    val device = requireDevice()
    val version = LogicalVersion(0, 0, device.deviceId)
    val clean = PayloadSanitizer.sanitize(type, payload)
    val key = entityKey(type, clean.id)
    db.entities().upsert(
      EntityRecord(
        key = key,
        workspaceId = WORKSPACE_ID,
        entityType = type.wire,
        entityId = clean.id,
        versionJson = PayloadCodec.encodeVersion(version),
        payloadJson = PayloadCodec.encodePayload(clean),
        deleted = deleted,
        serverRevision = 0,
      ),
    )
  }

  private suspend fun nextVersion(): LogicalVersion {
    val device = requireDevice()
    val now = System.currentTimeMillis()
    val timestamp = max(now, device.clockTimestamp)
    val counter = if (timestamp == device.clockTimestamp) device.clockCounter + 1 else 0
    val updated = device.copy(clockTimestamp = timestamp, clockCounter = counter)
    db.deviceMeta().upsert(updated.toRecord())
    return LogicalVersion(timestamp, counter, device.deviceId)
  }

  private suspend fun observeRemoteVersion(remote: LogicalVersion) {
    val device = requireDevice()
    val updated = when {
      remote.timestamp > device.clockTimestamp ->
        device.copy(clockTimestamp = remote.timestamp, clockCounter = remote.counter)
      remote.timestamp == device.clockTimestamp && remote.counter > device.clockCounter ->
        device.copy(clockCounter = remote.counter)
      else -> device
    }
    if (updated != device) db.deviceMeta().upsert(updated.toRecord())
  }

  private suspend fun ensureDeviceMeta(): DeviceMeta {
    val existing = db.deviceMeta().get(DEVICE_META_ID)
    if (existing != null) return existing.toDomain()
    val created = DeviceMeta(deviceId = UUID.randomUUID().toString().lowercase())
    db.deviceMeta().upsert(created.toRecord())
    return created
  }

  private suspend fun requireDevice(): DeviceMeta = ensureDeviceMeta()

  private fun notifyWrite() {
    writeListeners.tryEmit(Unit)
  }

  private fun EntityRecord.toStored(): StoredEntity {
    val type = EntityType.fromWire(entityType)
    return StoredEntity(
      key = key,
      workspaceId = workspaceId,
      entityType = type,
      entityId = entityId,
      version = PayloadCodec.decodeVersion(versionJson),
      payload = PayloadCodec.decodePayload(type, payloadJson),
      deleted = deleted,
      serverRevision = serverRevision,
    )
  }

  private fun OutboxRecord.toDomain(): SyncOperation {
    val type = EntityType.fromWire(entityType)
    return SyncOperation(
      operationId = operationId,
      key = key,
      workspaceId = workspaceId,
      entityType = type,
      entityId = entityId,
      version = PayloadCodec.decodeVersion(versionJson),
      payload = PayloadCodec.decodePayload(type, payloadJson),
      deleted = deleted,
      status = OutboxStatus.valueOf(status),
      attempts = attempts,
      lastError = lastError,
      createdAt = createdAt,
    )
  }

  private fun SyncOperation.toRecord(): OutboxRecord = OutboxRecord(
    key = key,
    operationId = operationId,
    workspaceId = workspaceId,
    entityType = entityType.wire,
    entityId = entityId,
    versionJson = PayloadCodec.encodeVersion(version),
    payloadJson = PayloadCodec.encodePayload(payload),
    deleted = deleted,
    status = status.name,
    attempts = attempts,
    lastError = lastError,
    createdAt = createdAt,
  )

  private fun SyncMetaRecord.toDomain() = SyncMeta(
    workspaceId = workspaceId,
    lastPulledRevision = lastPulledRevision,
    lastSyncedAt = lastSyncedAt,
    error = error,
    syncing = syncing,
  )

  private fun SyncMeta.toRecord() = SyncMetaRecord(
    workspaceId = workspaceId,
    lastPulledRevision = lastPulledRevision,
    lastSyncedAt = lastSyncedAt,
    error = error,
    syncing = syncing,
  )

  private fun DeviceMetaRecord.toDomain() = DeviceMeta(
    id = id,
    deviceId = deviceId,
    clockTimestamp = clockTimestamp,
    clockCounter = clockCounter,
    bootstrapVersion = bootstrapVersion,
    lastPaymentMethodId = lastPaymentMethodId,
  )

  private fun DeviceMeta.toRecord() = DeviceMetaRecord(
    id = id,
    deviceId = deviceId,
    clockTimestamp = clockTimestamp,
    clockCounter = clockCounter,
    bootstrapVersion = bootstrapVersion,
    lastPaymentMethodId = lastPaymentMethodId,
  )
}
