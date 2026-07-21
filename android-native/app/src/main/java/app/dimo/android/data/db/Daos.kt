package app.dimo.android.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface EntityDao {
  @Query("SELECT * FROM entities WHERE workspaceId = :workspaceId")
  fun observeAll(workspaceId: String): Flow<List<EntityRecord>>

  @Query("SELECT * FROM entities WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<EntityRecord>

  @Query("SELECT * FROM entities WHERE `key` = :key LIMIT 1")
  suspend fun get(key: String): EntityRecord?

  @Query(
    "SELECT * FROM entities WHERE workspaceId = :workspaceId AND entityType = :type AND deleted = 0",
  )
  suspend fun activeByType(workspaceId: String, type: String): List<EntityRecord>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: EntityRecord)

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsertAll(records: List<EntityRecord>)

  @Query("DELETE FROM entities WHERE `key` = :key")
  suspend fun deleteByKey(key: String)

  @Query(
    "SELECT * FROM entities WHERE workspaceId = :workspaceId AND deleted = 1",
  )
  suspend fun deleted(workspaceId: String): List<EntityRecord>
}

@Dao
interface OutboxDao {
  @Query("SELECT * FROM outbox WHERE status = 'pending' ORDER BY createdAt ASC LIMIT :limit")
  suspend fun pending(limit: Int): List<OutboxRecord>

  @Query("SELECT * FROM outbox WHERE status = 'blocked' LIMIT 1")
  suspend fun blocked(): OutboxRecord?

  @Query("SELECT COUNT(*) FROM outbox WHERE status = 'pending'")
  suspend fun pendingCount(): Int

  @Query("SELECT COUNT(*) FROM outbox WHERE status = 'blocked'")
  suspend fun blockedCount(): Int

  @Query("SELECT COUNT(*) FROM outbox WHERE status = 'pending'")
  fun observePendingCount(): Flow<Int>

  @Query("SELECT COUNT(*) FROM outbox WHERE status = 'blocked'")
  fun observeBlockedCount(): Flow<Int>

  @Query("SELECT * FROM outbox WHERE `key` = :key LIMIT 1")
  suspend fun getByKey(key: String): OutboxRecord?

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: OutboxRecord)

  @Query("DELETE FROM outbox WHERE `key` = :key")
  suspend fun deleteByKey(key: String)

  @Query("DELETE FROM outbox WHERE operationId IN (:ids)")
  suspend fun deleteByOperationIds(ids: List<String>)
}

@Dao
interface SyncMetaDao {
  @Query("SELECT * FROM sync_meta WHERE workspaceId = :workspaceId LIMIT 1")
  suspend fun get(workspaceId: String): SyncMetaRecord?

  @Query("SELECT * FROM sync_meta WHERE workspaceId = :workspaceId LIMIT 1")
  fun observe(workspaceId: String): Flow<SyncMetaRecord?>

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: SyncMetaRecord)
}

@Dao
interface DeviceMetaDao {
  @Query("SELECT * FROM device_meta WHERE id = :id LIMIT 1")
  suspend fun get(id: String): DeviceMetaRecord?

  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: DeviceMetaRecord)
}
