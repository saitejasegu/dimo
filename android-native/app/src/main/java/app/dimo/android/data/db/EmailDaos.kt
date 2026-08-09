package app.dimo.android.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface EmailAccountDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: EmailAccountRecord)

  @Query("SELECT * FROM emailAccounts WHERE id = :id")
  suspend fun byId(id: String): EmailAccountRecord?

  @Query("SELECT * FROM emailAccounts ORDER BY emailAddress")
  suspend fun all(): List<EmailAccountRecord>

  @Query("SELECT * FROM emailAccounts ORDER BY emailAddress")
  fun observeAll(): Flow<List<EmailAccountRecord>>

  @Query("DELETE FROM emailAccounts WHERE id = :id")
  suspend fun deleteById(id: String)

  @Query("DELETE FROM emailAccounts")
  suspend fun deleteAll()
}

@Dao
interface EmailMessageDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: EmailMessageRecord)

  @Query("SELECT * FROM emailMessages WHERE `key` = :key")
  suspend fun byKey(key: String): EmailMessageRecord?

  @Query("SELECT * FROM emailMessages WHERE `key` IN (:keys)")
  suspend fun byKeys(keys: List<String>): List<EmailMessageRecord>

  @Query("SELECT * FROM emailMessages WHERE linkedTransactionId = :transactionId")
  suspend fun byLinkedTransaction(transactionId: String): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE linkedTransactionId = :transactionId AND state = :state",
  )
  suspend fun byLinkedTransactionAndState(
    transactionId: String,
    state: String,
  ): List<EmailMessageRecord>

  @Query("SELECT * FROM emailMessages WHERE purchaseGroupId = :groupId")
  suspend fun byPurchaseGroup(groupId: String): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state IN (:states) " +
      "ORDER BY internalDate DESC LIMIT :limit",
  )
  suspend fun byStates(states: List<String>, limit: Int): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state IN (:states) " +
      "ORDER BY internalDate DESC LIMIT :limit",
  )
  fun observeByStates(states: List<String>, limit: Int): Flow<List<EmailMessageRecord>>

  /** Group members the paged feed clipped, so a grouped pair is never shown half-visible. */
  @Query(
    "SELECT * FROM emailMessages WHERE state IN (:states) AND purchaseGroupId IN (:groupIds)",
  )
  suspend fun byStatesAndGroups(
    states: List<String>,
    groupIds: List<String>,
  ): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state = :state AND normalizedBodyText IS NOT NULL " +
      "ORDER BY internalDate DESC LIMIT :limit",
  )
  suspend fun pendingAnalysis(state: String, limit: Int): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state = :state AND normalizedBodyText IS NOT NULL " +
      "AND accountId = :accountId ORDER BY internalDate DESC LIMIT :limit",
  )
  suspend fun pendingAnalysisForAccount(
    state: String,
    accountId: String,
    limit: Int,
  ): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state = :state AND linkedTransactionId IS NOT NULL",
  )
  suspend fun reviewedWithTransaction(state: String): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state = :state AND purchaseGroupId IS NULL " +
      "ORDER BY internalDate ASC, `key` ASC",
  )
  suspend fun ungroupedInState(state: String): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE state = :state AND accountId = :accountId " +
      "ORDER BY internalDate DESC",
  )
  suspend fun inStateForAccount(state: String, accountId: String): List<EmailMessageRecord>

  @Query("SELECT * FROM emailMessages WHERE normalizedBodyText IS NOT NULL AND reviewedAt IS NULL")
  suspend fun unreviewedWithBody(): List<EmailMessageRecord>

  @Query(
    "SELECT * FROM emailMessages WHERE internalDate < :cutoff AND state != :expiredState " +
      "AND linkedTransactionId IS NULL AND state NOT IN (:retainedStates)",
  )
  suspend fun expirable(
    cutoff: Long,
    expiredState: String,
    retainedStates: List<String>,
  ): List<EmailMessageRecord>

  @Query(
    "DELETE FROM emailMessages WHERE internalDate < :cutoff AND linkedTransactionId IS NULL " +
      "AND state NOT IN (:retainedStates)",
  )
  suspend fun purgeOlderThan(cutoff: Long, retainedStates: List<String>): Int

  @Query(
    "UPDATE emailMessages SET normalizedBodyText = NULL, updatedAt = :now " +
      "WHERE state NOT IN (:bodyRetainedStates) AND normalizedBodyText IS NOT NULL",
  )
  suspend fun purgeBodies(bodyRetainedStates: List<String>, now: Long): Int

  @Query(
    "SELECT `key`, accountId, senderName, senderAddress, subject, snippet, internalDate, " +
      "analyzerType, modelVersion, classification, state, analyzedAt, reviewedAt " +
      "FROM emailMessages ORDER BY internalDate DESC LIMIT 1000",
  )
  suspend fun summaries(): List<EmailMessageSummaryRecord>

  @Query(
    "SELECT `key`, accountId, senderName, senderAddress, subject, snippet, internalDate, " +
      "analyzerType, modelVersion, classification, state, analyzedAt, reviewedAt " +
      "FROM emailMessages ORDER BY internalDate DESC LIMIT 1000",
  )
  fun observeSummaries(): Flow<List<EmailMessageSummaryRecord>>

  @Query("DELETE FROM emailMessages WHERE `key` = :key")
  suspend fun deleteByKey(key: String)

  @Query("DELETE FROM emailMessages WHERE accountId = :accountId")
  suspend fun deleteByAccount(accountId: String)

  @Query("DELETE FROM emailMessages")
  suspend fun deleteAll()
}

@Dao
interface EmailAnalysisSettingsDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: EmailAnalysisSettingsRecord)

  @Query("SELECT * FROM emailAnalysisSettings WHERE id = :id")
  suspend fun byId(id: String): EmailAnalysisSettingsRecord?

  @Query("SELECT * FROM emailAnalysisSettings WHERE id = :id")
  fun observeById(id: String): Flow<EmailAnalysisSettingsRecord?>
}

@Dao
interface EmailAnalysisRetryDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: EmailAnalysisRetryRecord)

  @Query("SELECT * FROM emailAnalysisRetry WHERE id = :id")
  suspend fun byId(id: String): EmailAnalysisRetryRecord?

  @Query("DELETE FROM emailAnalysisRetry WHERE id = :id")
  suspend fun deleteById(id: String)
}

@Dao
interface SyncedEmailMessageDao {
  @Insert(onConflict = OnConflictStrategy.REPLACE)
  suspend fun upsert(record: SyncedEmailMessageRecord)

  @Query("SELECT * FROM syncedEmailMessages WHERE `key` = :key")
  suspend fun byKey(key: String): SyncedEmailMessageRecord?

  @Query("SELECT * FROM syncedEmailMessages WHERE workspaceId = :workspaceId")
  suspend fun all(workspaceId: String): List<SyncedEmailMessageRecord>

  @Query("SELECT * FROM syncedEmailMessages WHERE workspaceId = :workspaceId")
  fun observe(workspaceId: String): Flow<List<SyncedEmailMessageRecord>>

  @Query("DELETE FROM syncedEmailMessages WHERE `key` = :key")
  suspend fun deleteByKey(key: String)
}
