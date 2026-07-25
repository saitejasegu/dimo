package app.dimo.android.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

@Dao
interface CategoryDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: CategoryRecord)

  @Query("SELECT * FROM categories WHERE key = :key")
  suspend fun byKey(key: String): CategoryRecord?

  @Query("SELECT * FROM categories WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<CategoryRecord>

  @Query("SELECT * FROM categories WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<CategoryRecord>>

  @Query("DELETE FROM categories WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface PaymentMethodDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: PaymentMethodRecord)

  @Query("SELECT * FROM paymentMethods WHERE key = :key")
  suspend fun byKey(key: String): PaymentMethodRecord?

  @Query("SELECT * FROM paymentMethods WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<PaymentMethodRecord>

  @Query("SELECT * FROM paymentMethods WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<PaymentMethodRecord>>

  @Query("DELETE FROM paymentMethods WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface TransactionDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: TransactionRecord)

  @Query("SELECT * FROM transactions WHERE key = :key")
  suspend fun byKey(key: String): TransactionRecord?

  @Query("SELECT * FROM transactions WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<TransactionRecord>

  @Query("SELECT * FROM transactions WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<TransactionRecord>>

  @Query("DELETE FROM transactions WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface RecurringDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: RecurringRecord)

  @Query("SELECT * FROM recurring WHERE key = :key")
  suspend fun byKey(key: String): RecurringRecord?

  @Query("SELECT * FROM recurring WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<RecurringRecord>

  @Query("SELECT * FROM recurring WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<RecurringRecord>>

  @Query("DELETE FROM recurring WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface LendDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: LendRecord)

  @Query("SELECT * FROM lends WHERE key = :key")
  suspend fun byKey(key: String): LendRecord?

  @Query("SELECT * FROM lends WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<LendRecord>

  @Query("SELECT * FROM lends WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<LendRecord>>

  @Query("DELETE FROM lends WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface PreferencesDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: PreferencesRecord)

  @Query("SELECT * FROM preferences WHERE key = :key")
  suspend fun byKey(key: String): PreferencesRecord?

  @Query("SELECT * FROM preferences WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<PreferencesRecord>

  @Query("SELECT * FROM preferences WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<PreferencesRecord>>

  @Query("DELETE FROM preferences WHERE key = :key")
  suspend fun deleteByKey(key: String)
}

@Dao
interface OutboxDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: OutboxRecord)

  @Update
  suspend fun update(record: OutboxRecord)

  @Query("SELECT * FROM outbox WHERE key = :key")
  suspend fun byKey(key: String): OutboxRecord?

  @Query("DELETE FROM outbox WHERE key = :key")
  suspend fun deleteByKey(key: String)

  @Query("DELETE FROM outbox WHERE operationId = :operationId")
  suspend fun deleteByOperationId(operationId: String)

  @Query("SELECT * FROM outbox WHERE status = :status ORDER BY createdAt LIMIT :limit")
  suspend fun byStatus(status: String, limit: Int): List<OutboxRecord>

  @Query("SELECT * FROM outbox WHERE status = :status LIMIT 1")
  suspend fun firstWithStatus(status: String): OutboxRecord?

  @Query("SELECT COUNT(*) FROM outbox WHERE status = :status")
  suspend fun countByStatus(status: String): Int

  @Query("SELECT COUNT(*) FROM outbox WHERE status = :status")
  fun observeCountByStatus(status: String): Flow<Int>

  /**
   * Requeue operations a previous build parked permanently, the escape hatch the
   * bootstrapVersion bump uses when a payload bug has been fixed.
   */
  @Query("UPDATE outbox SET status = 'pending', lastError = NULL, attempts = 0 WHERE status = 'blocked'")
  suspend fun requeueBlocked()
}

@Dao
interface SyncMetaDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: SyncMetaRecord)

  @Query("SELECT * FROM syncMeta WHERE workspaceId = :workspaceId")
  suspend fun byWorkspace(workspaceId: String): SyncMetaRecord?

  @Query("SELECT * FROM syncMeta WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<SyncMetaRecord?>
}

@Dao
interface DeviceMetaDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: DeviceMetaRecord)

  @Query("SELECT * FROM deviceMeta WHERE id = :id")
  suspend fun byId(id: String): DeviceMetaRecord?
}
