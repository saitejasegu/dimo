package app.dimo.android.data

import androidx.room.withTransaction
import app.dimo.android.data.db.CategoryRecord
import app.dimo.android.data.db.DeviceMetaRecord
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.db.LendRecord
import app.dimo.android.data.db.OutboxRecord
import app.dimo.android.data.db.PaymentMethodRecord
import app.dimo.android.data.db.PreferencesRecord
import app.dimo.android.data.db.RecurringRecord
import app.dimo.android.data.db.SyncMetaRecord
import app.dimo.android.data.db.TransactionRecord
import app.dimo.android.data.model.BOOTSTRAP_VERSION
import app.dimo.android.data.model.DeviceMeta
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncMeta
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.TOMBSTONE_RETENTION_DAYS
import app.dimo.android.data.model.WORKSPACE_ID
import app.dimo.android.data.model.entityKey
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

/**
 * Port of `ios-native/Dimo/Data/Repository.swift` (core-parity subset).
 *
 * The invariants this file exists to preserve:
 *  - every entity write and its outbox row commit in one transaction;
 *  - a later edit to the same key replaces the pending operation (outbox PK is the key);
 *  - local versions are generated from a device clock that has already observed
 *    remote versions, so last-write-wins converges;
 *  - bootstrap seeds are written at logical version zero with no outbox row, so a
 *    pull always beats a fresh client's defaults.
 */
class Repository(private val db: DimoDatabase) {
  private val writeListeners = ConcurrentHashMap<UUID, () -> Unit>()

  /** Monotonic clock injection point; tests substitute a fixed clock. */
  var now: () -> Long = { System.currentTimeMillis() }

  /** Operation-id factory; tests substitute a deterministic sequence. */
  var newOperationId: () -> String = { UUID.randomUUID().toString().lowercase() }

  /** Device-id factory, used only when `deviceMeta` is first created. */
  var newDeviceId: () -> String = { UUID.randomUUID().toString().lowercase() }

  fun onLocalWrite(listener: () -> Unit): UUID {
    val id = UUID.randomUUID()
    writeListeners[id] = listener
    return id
  }

  fun removeLocalWriteListener(id: UUID) {
    writeListeners.remove(id)
  }

  private fun notifyWrite() {
    writeListeners.values.forEach { it() }
  }

  // MARK: - Bootstrap

  suspend fun initializeLocalDatabase() {
    db.withTransaction {
      ensureDevice()
      val device = db.deviceMeta().byId(DEVICE_ROW_ID)!!
      if (device.bootstrapVersion < BOOTSTRAP_VERSION) {
        // Cash + preferences only — new accounts start with no seeded categories.
        val cashKey = entityKey(EntityType.PAYMENT_METHOD, SeedData.CASH_PAYMENT_METHOD.id)
        if (fetchOne(cashKey) == null) {
          putLocalOnly(EntityPayload.PaymentMethod(SeedData.CASH_PAYMENT_METHOD))
        }
        val prefsKey = entityKey(EntityType.PREFERENCES, SeedData.DEFAULT_PREFERENCES.id)
        if (fetchOne(prefsKey) == null) {
          putLocalOnly(EntityPayload.Preferences(SeedData.DEFAULT_PREFERENCES))
        }
        // Requeue operations a previous build permanently blocked so they retry
        // through the corrected encoding.
        db.outbox().requeueBlocked()
        db.deviceMeta().upsert(device.copy(bootstrapVersion = BOOTSTRAP_VERSION))
      }
      if (db.syncMeta().byWorkspace(WORKSPACE_ID) == null) {
        db.syncMeta().upsert(
          SyncMetaRecord.from(
            SyncMeta(
              workspaceId = WORKSPACE_ID,
              lastPulledRevision = 0,
              lastSyncedAt = null,
              error = null,
              syncing = false,
            ),
          ),
        )
      }
    }
    notifyWrite()
  }

  /**
   * After pull, queue cash / preferences that still have no server revision so
   * empty workspaces get those defaults without inventing categories.
   */
  suspend fun enqueueUnsyncedDefaults() {
    var enqueued = false
    db.withTransaction {
      val defaults = listOf(
        EntityPayload.PaymentMethod(SeedData.CASH_PAYMENT_METHOD),
        EntityPayload.Preferences(SeedData.DEFAULT_PREFERENCES),
      )
      for (seed in defaults) {
        val key = entityKey(seed.entityType, seed.id)
        val stored = fetchOne(key) ?: continue
        if (stored.deleted || stored.serverRevision != 0L) continue
        if (db.outbox().byKey(key) != null) continue
        putInTransaction(stored.payload)
        enqueued = true
      }
    }
    if (enqueued) notifyWrite()
  }

  // MARK: - Writes

  suspend fun saveEntity(payload: EntityPayload) {
    db.withTransaction { putInTransaction(payload) }
    notifyWrite()
  }

  suspend fun saveEntities(payloads: List<EntityPayload>) {
    if (payloads.isEmpty()) return
    db.withTransaction { payloads.forEach { putInTransaction(it) } }
    notifyWrite()
  }

  suspend fun removeEntity(entityType: EntityType, id: String) {
    val key = entityKey(entityType, id)
    var removed = false
    db.withTransaction {
      val current = fetchOne(key) ?: return@withTransaction
      if (current.deleted) return@withTransaction
      putInTransaction(current.payload, deleted = true)
      removed = true
    }
    if (removed) notifyWrite()
  }

  /**
   * Tombstones every active entity of a type in one transaction and emits a single
   * write notification, avoiding a listener storm for bulk deletes.
   */
  suspend fun removeActiveEntities(entityType: EntityType): Int {
    var removedCount = 0
    db.withTransaction {
      for (stored in fetchAll(entityType)) {
        if (stored.deleted) continue
        putInTransaction(stored.payload, deleted = true)
        removedCount += 1
      }
    }
    if (removedCount > 0) notifyWrite()
    return removedCount
  }

  suspend fun setLastPaymentMethod(id: String?) {
    db.withTransaction {
      ensureDevice()
      val device = db.deviceMeta().byId(DEVICE_ROW_ID) ?: return@withTransaction
      db.deviceMeta().upsert(device.copy(lastPaymentMethodId = id))
    }
  }

  // MARK: - Backfills

  /**
   * Gives legacy recurring and transaction rows an explicit denomination and
   * enqueues the versioned repair so every client converges on the same payload.
   */
  suspend fun backfillRecurringCurrencies(): Int {
    var updated = 0
    db.withTransaction {
      val prefsKey = entityKey(EntityType.PREFERENCES, "preferences")
      val prefsRow = fetchOne(prefsKey)
      val accountCurrency =
        if (prefsRow != null && !prefsRow.deleted && prefsRow.payload is EntityPayload.Preferences) {
          (prefsRow.payload as EntityPayload.Preferences).value.currency.wire
        } else {
          SeedData.DEFAULT_PREFERENCES.currency.wire
        }

      for (type in listOf(EntityType.RECURRING, EntityType.TRANSACTION)) {
        for (stored in fetchAll(type)) {
          if (stored.deleted) continue
          when (val payload = stored.payload) {
            is EntityPayload.Recurring -> {
              if (!payload.value.currency.isNullOrBlank()) continue
              putInTransaction(
                EntityPayload.Recurring(payload.value.copy(currency = accountCurrency)),
              )
              updated += 1
            }

            is EntityPayload.Transaction -> {
              if (!payload.value.currency.isNullOrBlank()) continue
              putInTransaction(
                EntityPayload.Transaction(payload.value.copy(currency = accountCurrency)),
              )
              updated += 1
            }

            else -> Unit
          }
        }
      }
    }
    if (updated > 0) notifyWrite()
    return updated
  }

  /** Repairs rows written before payment method became required. */
  suspend fun backfillMissingPaymentMethodIds(): Int {
    var updated = 0
    db.withTransaction {
      val fallback = defaultPaymentMethodIdInTransaction()
      for (type in listOf(EntityType.TRANSACTION, EntityType.RECURRING)) {
        for (stored in fetchAll(type)) {
          if (stored.deleted) continue
          when (val payload = stored.payload) {
            is EntityPayload.Transaction -> {
              if (!payload.value.paymentMethodId.isNullOrBlank()) continue
              putInTransaction(
                EntityPayload.Transaction(payload.value.copy(paymentMethodId = fallback)),
              )
              updated += 1
            }

            is EntityPayload.Recurring -> {
              if (!payload.value.paymentMethodId.isNullOrBlank()) continue
              putInTransaction(
                EntityPayload.Recurring(payload.value.copy(paymentMethodId = fallback)),
              )
              updated += 1
            }

            else -> Unit
          }
        }
      }
    }
    if (updated > 0) notifyWrite()
    return updated
  }

  private suspend fun defaultPaymentMethodIdInTransaction(): String {
    val prefs = fetchOne(entityKey(EntityType.PREFERENCES, "preferences"))?.payload
    val preferred = (prefs as? EntityPayload.Preferences)?.value?.defaultPaymentMethodId
    if (!preferred.isNullOrBlank()) return preferred
    return SeedData.CASH_PAYMENT_METHOD.id
  }

  // MARK: - Sync plumbing

  /**
   * Applies a pulled page. Remote versions are observed into the device clock
   * first so later local writes sort after them, then last-write-wins decides
   * whether the remote row replaces the local one.
   */
  suspend fun mergeRemotePage(
    remoteEntities: List<StoredEntity>,
    entityType: EntityType,
    cursor: Long,
  ) {
    db.withTransaction {
      for (remote in remoteEntities) {
        observeRemoteVersion(remote.version)
        val local = fetchOne(remote.key)
        val shouldApply = local == null || remote.version >= local.version
        if (!shouldApply) continue
        saveRecord(remote)
        // A pulled row supersedes anything still queued for the same key.
        db.outbox().deleteByKey(remote.key)
      }
      val meta = db.syncMeta().byWorkspace(WORKSPACE_ID)?.toSyncMeta()
      if (meta != null) {
        val pulled = meta.pulledRevisions.toMutableMap()
        pulled[entityType] = cursor
        db.syncMeta().upsert(
          SyncMetaRecord.from(
            meta.copy(
              pulledRevisions = pulled,
              lastPulledRevision = maxOf(meta.lastPulledRevision, cursor),
            ),
          ),
        )
      }
    }
    notifyWrite()
  }

  suspend fun acknowledgeOperations(operationIds: List<String>) {
    if (operationIds.isEmpty()) return
    db.withTransaction {
      operationIds.forEach { db.outbox().deleteByOperationId(it) }
    }
  }

  /**
   * Re-versions and re-queues everything for an explicit full upload.
   *
   * `emailMessage` is deliberately absent from [EntityType]: Android holds no
   * email rows, so including that type would upload nothing while the paired
   * `clearWorkspace` wiped the user's iOS email data.
   */
  suspend fun enqueueFullUpload(entityTypes: List<EntityType> = EntityType.entries) {
    db.withTransaction {
      val allowed = entityTypes.toSet()
      val createdAt = now()
      for (type in EntityType.entries) {
        if (type !in allowed) continue
        for (entity in fetchAll(type)) {
          val version = nextVersion()
          val payload = PayloadSanitizer.sanitize(entity.payload, now())
          saveRecord(
            entity.copy(version = version, payload = payload, serverRevision = 0),
          )
          db.outbox().upsert(
            OutboxRecord.from(
              SyncOperation(
                operationId = newOperationId(),
                key = entity.key,
                workspaceId = WORKSPACE_ID,
                entityType = type,
                entityId = entity.entityId,
                version = version,
                payload = payload,
                deleted = entity.deleted,
                status = OutboxStatus.PENDING,
                attempts = 0,
                lastError = null,
                createdAt = createdAt,
              ),
            ),
          )
        }
      }
    }
    notifyWrite()
  }

  /**
   * Hard-deletes local tombstones past the private retention window. Rows that
   * still have an unacked outbox operation are skipped.
   */
  suspend fun purgeExpiredTombstones(nowMillis: Long = now()): Int {
    val cutoff = nowMillis - TOMBSTONE_RETENTION_DAYS * 24L * 60L * 60L * 1000L
    var count = 0
    db.withTransaction {
      for (type in EntityType.entries) {
        for (entity in fetchAll(type)) {
          if (!entity.deleted) continue
          if (entity.version.timestamp >= cutoff) continue
          if (db.outbox().byKey(entity.key) != null) continue
          deleteRecord(type, entity.key)
          count += 1
        }
      }
    }
    return count
  }

  suspend fun pendingOutbox(limit: Int = 50): List<SyncOperation> {
    val rows = db.outbox().byStatus(OutboxStatus.PENDING.wire, limit)
    return hydrate(rows)
  }

  suspend fun blockedOutbox(): SyncOperation? {
    val row = db.outbox().firstWithStatus(OutboxStatus.BLOCKED.wire) ?: return null
    return hydrate(listOf(row)).firstOrNull()
  }

  private suspend fun hydrate(rows: List<OutboxRecord>): List<SyncOperation> {
    val ops = mutableListOf<SyncOperation>()
    for (row in rows) {
      val type = EntityType.fromWire(row.entityType) ?: continue
      val stored = fetchOne(row.key) ?: continue
      ops.add(row.toSyncOperation(stored.payload, stored.version, stored.deleted))
    }
    return ops
  }

  suspend fun outboxCounts(): Pair<Int, Int> = Pair(
    db.outbox().countByStatus(OutboxStatus.PENDING.wire),
    db.outbox().countByStatus(OutboxStatus.BLOCKED.wire),
  )

  suspend fun updateOutbox(operation: SyncOperation) {
    db.outbox().upsert(OutboxRecord.from(operation))
  }

  suspend fun syncMeta(): SyncMeta? = db.syncMeta().byWorkspace(WORKSPACE_ID)?.toSyncMeta()

  suspend fun updateSyncMeta(update: (SyncMeta) -> SyncMeta) {
    db.withTransaction {
      val current = db.syncMeta().byWorkspace(WORKSPACE_ID)?.toSyncMeta()
        ?: SyncMeta(
          workspaceId = WORKSPACE_ID,
          lastPulledRevision = 0,
          lastSyncedAt = null,
          error = null,
          syncing = false,
        )
      db.syncMeta().upsert(SyncMetaRecord.from(update(current)))
    }
  }

  suspend fun deviceMeta(): DeviceMeta? = db.deviceMeta().byId(DEVICE_ROW_ID)?.toDeviceMeta()

  // MARK: - Reads

  suspend fun activeEntities(type: EntityType): List<StoredEntity> =
    fetchAll(type).filter { !it.deleted }

  suspend fun allEntities(): List<StoredEntity> =
    EntityType.entries.flatMap { fetchAll(it) }

  /**
   * Room Flow observation, the replacement for GRDB `ValueObservation`.
   *
   * `combine` only has typed overloads up to five flows, so the six typed tables
   * are combined in two groups and then merged.
   */
  fun observeEntities(): Flow<List<StoredEntity>> {
    val groupA: Flow<List<StoredEntity>> = combine(
      db.categories().observe(WORKSPACE_ID),
      db.paymentMethods().observe(WORKSPACE_ID),
      db.transactions().observe(WORKSPACE_ID),
    ) { categories, paymentMethods, transactions ->
      categories.map { it.toStoredEntity() } +
        paymentMethods.map { it.toStoredEntity() } +
        transactions.map { it.toStoredEntity() }
    }
    val groupB: Flow<List<StoredEntity>> = combine(
      db.recurring().observe(WORKSPACE_ID),
      db.lends().observe(WORKSPACE_ID),
      db.preferences().observe(WORKSPACE_ID),
    ) { recurring, lends, preferences ->
      recurring.map { it.toStoredEntity() } +
        lends.map { it.toStoredEntity() } +
        preferences.map { it.toStoredEntity() }
    }
    return combine(groupA, groupB) { a, b -> a + b }
  }

  fun observeSyncMeta(): Flow<SyncMeta?> =
    db.syncMeta().observe(WORKSPACE_ID).map { it?.toSyncMeta() }

  fun observePendingCount(): Flow<Int> =
    db.outbox().observeCountByStatus(OutboxStatus.PENDING.wire)

  fun observeBlockedCount(): Flow<Int> =
    db.outbox().observeCountByStatus(OutboxStatus.BLOCKED.wire)

  // MARK: - Private

  /**
   * Writes an entity for offline UI without enqueueing sync. Uses a zero logical
   * version so any cloud row wins on the first pull.
   */
  private suspend fun putLocalOnly(payload: EntityPayload, deleted: Boolean = false) {
    ensureDevice()
    val device = db.deviceMeta().byId(DEVICE_ROW_ID)!!
    val clean = PayloadSanitizer.sanitize(payload, now())
    saveRecord(
      StoredEntity(
        key = entityKey(clean.entityType, clean.id),
        workspaceId = WORKSPACE_ID,
        entityType = clean.entityType,
        entityId = clean.id,
        version = LogicalVersion(timestamp = 0, counter = 0, deviceId = device.deviceId),
        payload = clean,
        deleted = deleted,
        serverRevision = 0,
      ),
    )
  }

  /** Entity row and outbox row, written together inside the caller's transaction. */
  private suspend fun putInTransaction(payload: EntityPayload, deleted: Boolean = false) {
    val version = nextVersion()
    val clean = PayloadSanitizer.sanitize(payload, now())
    val key = entityKey(clean.entityType, clean.id)
    saveRecord(
      StoredEntity(
        key = key,
        workspaceId = WORKSPACE_ID,
        entityType = clean.entityType,
        entityId = clean.id,
        version = version,
        payload = clean,
        deleted = deleted,
        serverRevision = 0,
      ),
    )
    db.outbox().upsert(
      OutboxRecord.from(
        SyncOperation(
          operationId = newOperationId(),
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = clean.entityType,
          entityId = clean.id,
          version = version,
          payload = clean,
          deleted = deleted,
          status = OutboxStatus.PENDING,
          attempts = 0,
          lastError = null,
          createdAt = now(),
        ),
      ),
    )
  }

  private suspend fun ensureDevice(): DeviceMetaRecord {
    val current = db.deviceMeta().byId(DEVICE_ROW_ID)
    if (current != null) return current
    val created = DeviceMetaRecord(
      id = DEVICE_ROW_ID,
      deviceId = newDeviceId(),
      clockTimestamp = 0,
      clockCounter = 0,
      bootstrapVersion = 0,
      lastPaymentMethodId = null,
    )
    db.deviceMeta().upsert(created)
    return created
  }

  /** Hybrid logical clock: never goes backwards, bumps the counter within a tick. */
  private suspend fun nextVersion(): LogicalVersion {
    val device = ensureDevice()
    val timestamp = maxOf(now(), device.clockTimestamp)
    val counter = if (timestamp == device.clockTimestamp) device.clockCounter + 1 else 0
    db.deviceMeta().upsert(device.copy(clockTimestamp = timestamp, clockCounter = counter))
    return LogicalVersion(timestamp = timestamp, counter = counter, deviceId = device.deviceId)
  }

  /** Pulls the device clock forward past any version the server has already seen. */
  private suspend fun observeRemoteVersion(version: LogicalVersion) {
    val device = ensureDevice()
    if (version.timestamp > device.clockTimestamp) {
      db.deviceMeta().upsert(
        device.copy(clockTimestamp = version.timestamp, clockCounter = version.counter),
      )
    } else if (version.timestamp == device.clockTimestamp && version.counter > device.clockCounter) {
      db.deviceMeta().upsert(device.copy(clockCounter = version.counter))
    }
  }

  private suspend fun saveRecord(entity: StoredEntity) {
    when (entity.entityType) {
      EntityType.CATEGORY -> db.categories().upsert(CategoryRecord.from(entity))
      EntityType.PAYMENT_METHOD -> db.paymentMethods().upsert(PaymentMethodRecord.from(entity))
      EntityType.TRANSACTION -> db.transactions().upsert(TransactionRecord.from(entity))
      EntityType.RECURRING -> db.recurring().upsert(RecurringRecord.from(entity))
      EntityType.LEND -> db.lends().upsert(LendRecord.from(entity))
      EntityType.PREFERENCES -> db.preferences().upsert(PreferencesRecord.from(entity))
    }
  }

  private suspend fun deleteRecord(type: EntityType, key: String) {
    when (type) {
      EntityType.CATEGORY -> db.categories().deleteByKey(key)
      EntityType.PAYMENT_METHOD -> db.paymentMethods().deleteByKey(key)
      EntityType.TRANSACTION -> db.transactions().deleteByKey(key)
      EntityType.RECURRING -> db.recurring().deleteByKey(key)
      EntityType.LEND -> db.lends().deleteByKey(key)
      EntityType.PREFERENCES -> db.preferences().deleteByKey(key)
    }
  }

  private suspend fun fetchOne(key: String): StoredEntity? {
    // Keys are "workspace:type:id", so the type is recoverable from the key.
    val parts = key.split(":", limit = 3)
    if (parts.size != 3) return null
    val type = EntityType.fromWire(parts[1]) ?: return null
    return fetchOne(type, key)
  }

  private suspend fun fetchOne(type: EntityType, key: String): StoredEntity? = when (type) {
    EntityType.CATEGORY -> db.categories().byKey(key)?.toStoredEntity()
    EntityType.PAYMENT_METHOD -> db.paymentMethods().byKey(key)?.toStoredEntity()
    EntityType.TRANSACTION -> db.transactions().byKey(key)?.toStoredEntity()
    EntityType.RECURRING -> db.recurring().byKey(key)?.toStoredEntity()
    EntityType.LEND -> db.lends().byKey(key)?.toStoredEntity()
    EntityType.PREFERENCES -> db.preferences().byKey(key)?.toStoredEntity()
  }

  private suspend fun fetchAll(type: EntityType): List<StoredEntity> = when (type) {
    EntityType.CATEGORY -> db.categories().all(WORKSPACE_ID).map { it.toStoredEntity() }
    EntityType.PAYMENT_METHOD -> db.paymentMethods().all(WORKSPACE_ID).map { it.toStoredEntity() }
    EntityType.TRANSACTION -> db.transactions().all(WORKSPACE_ID).map { it.toStoredEntity() }
    EntityType.RECURRING -> db.recurring().all(WORKSPACE_ID).map { it.toStoredEntity() }
    EntityType.LEND -> db.lends().all(WORKSPACE_ID).map { it.toStoredEntity() }
    EntityType.PREFERENCES -> db.preferences().all(WORKSPACE_ID).map { it.toStoredEntity() }
  }

  companion object {
    private const val DEVICE_ROW_ID = "device"
  }
}
