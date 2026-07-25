package app.dimo.android.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.RecurringFrequency
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.TOMBSTONE_RETENTION_DAYS
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.WORKSPACE_ID
import app.dimo.android.data.model.entityKey
import app.dimo.android.data.db.TransactionRecord
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Ports of `RepositoryBootstrapTests` in `ios-native/DimoTests/DomainTests.swift`,
 * plus the sync-boundary cases `AGENTS.md` requires for sync changes.
 *
 * Runs on the JVM against an in-memory Room database via Robolectric.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class RepositoryTests {
  private lateinit var db: DimoDatabase
  private lateinit var repo: Repository

  @Before
  fun setUp() {
    db = Room
      .inMemoryDatabaseBuilder(
        ApplicationProvider.getApplicationContext(),
        DimoDatabase::class.java,
      )
      .allowMainThreadQueries()
      .build()
    repo = Repository(db)
  }

  @After
  fun tearDown() {
    db.close()
  }

  @Test
  fun bootstrapSeedsDefaultsOnce() = runTest {
    repo.initializeLocalDatabase()
    val first = repo.allEntities()
    assertEquals(2, first.count { !it.deleted })
    // Seeds are written at logical version zero with no outbox row, so a pull wins.
    assertEquals(0, repo.pendingOutbox(limit = 100).size)
    assertEquals(0, repo.activeEntities(EntityType.CATEGORY).size)

    repo.initializeLocalDatabase()
    val second = repo.allEntities()
    assertEquals(2, second.count { !it.deleted })
    assertTrue(
      repo.activeEntities(EntityType.PAYMENT_METHOD)
        .any { it.entityId == SeedData.CASH_PAYMENT_METHOD.id },
    )
    assertEquals(
      listOf(LogicalVersion(0, 0, first.first().version.deviceId)),
      first.map { it.version }.distinct(),
    )
  }

  @Test
  fun enqueueUnsyncedDefaultsOnlyWhenNeverPulled() = runTest {
    repo.initializeLocalDatabase()
    assertEquals(0, repo.pendingOutbox(limit = 100).size)

    repo.enqueueUnsyncedDefaults()
    assertEquals(2, repo.pendingOutbox(limit = 100).size)

    // Simulate the cash seed having been accepted by the server, then clear the queue.
    val cashKey = entityKey(EntityType.PAYMENT_METHOD, SeedData.CASH_PAYMENT_METHOD.id)
    val cash = db.paymentMethods().byKey(cashKey)!!
    db.paymentMethods().upsert(cash.copy(serverRevision = 10))
    db.outbox().deleteByKey(cashKey)
    db.outbox().deleteByKey(entityKey(EntityType.PREFERENCES, "preferences"))

    repo.enqueueUnsyncedDefaults()
    val pending = repo.pendingOutbox(limit = 100)
    assertFalse(pending.any { it.entityId == SeedData.CASH_PAYMENT_METHOD.id })
    assertEquals(1, pending.size)
  }

  @Test
  fun purgeExpiredTombstones() = runTest {
    repo.initializeLocalDatabase()

    val now = 1_753_142_400_000L
    val msPerDay = 24L * 60L * 60L * 1000L
    val expiredTs = now - (TOMBSTONE_RETENTION_DAYS + 2) * msPerDay
    val freshTs = now - 5 * msPerDay

    val expiredKey = entityKey(EntityType.TRANSACTION, "transaction-expired")
    db.transactions().upsert(
      TransactionRecord.from(
        StoredEntity(
          key = expiredKey,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.TRANSACTION,
          entityId = "transaction-expired",
          version = LogicalVersion(expiredTs, 0, "test"),
          payload = EntityPayload.Transaction(
            TransactionEntity(
              id = "transaction-expired",
              name = "Old",
              amountMinor = 100,
              occurredAt = expiredTs,
              categoryId = "c1",
              paymentMethodId = SeedData.CASH_PAYMENT_METHOD.id,
            ),
          ),
          deleted = true,
          serverRevision = 1,
        ),
      ),
    )
    val freshKey = entityKey(EntityType.TRANSACTION, "transaction-fresh")
    db.transactions().upsert(
      TransactionRecord.from(
        StoredEntity(
          key = freshKey,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.TRANSACTION,
          entityId = "transaction-fresh",
          version = LogicalVersion(freshTs, 0, "test"),
          payload = EntityPayload.Transaction(
            TransactionEntity(
              id = "transaction-fresh",
              name = "Fresh",
              amountMinor = 200,
              occurredAt = freshTs,
              categoryId = "c1",
              paymentMethodId = SeedData.CASH_PAYMENT_METHOD.id,
            ),
          ),
          deleted = true,
          serverRevision = 1,
        ),
      ),
    )

    assertEquals(1, repo.purgeExpiredTombstones(nowMillis = now))
    assertNull(db.transactions().byKey(expiredKey))
    assertNotNull(db.transactions().byKey(freshKey))
  }

  @Test
  fun expiredTombstoneSurvivesWhileItStillHasAPendingOperation() = runTest {
    repo.initializeLocalDatabase()
    val now = 1_753_142_400_000L
    val expiredTs = now - (TOMBSTONE_RETENTION_DAYS + 2) * 24L * 60L * 60L * 1000L

    val category = CategoryEntity(
      id = "category-pending",
      name = "Pending",
      emoji = "✨",
      monthlyBudgetMinor = null,
      tint = CategoryTint.NEUTRAL,
      sortOrder = 1,
      system = false,
    )
    repo.saveEntity(EntityPayload.Category(category))
    val key = entityKey(EntityType.CATEGORY, category.id)
    val row = db.categories().byKey(key)!!
    db.categories().upsert(
      row.copy(
        deleted = true,
        version = row.version.copy(timestamp = expiredTs),
      ),
    )

    // The outbox row is still there, so the tombstone must not be hard-deleted.
    assertEquals(0, repo.purgeExpiredTombstones(nowMillis = now))
    assertNotNull(db.categories().byKey(key))
  }

  @Test
  fun outboxReplaceOnResave() = runTest {
    repo.initializeLocalDatabase()
    val pendingBefore = repo.pendingOutbox(limit = 100).size

    val category = CategoryEntity(
      id = "category-custom",
      name = "Custom",
      emoji = "✨",
      monthlyBudgetMinor = null,
      tint = CategoryTint.NEUTRAL,
      sortOrder = 10,
      system = false,
    )
    repo.saveEntity(EntityPayload.Category(category))
    repo.saveEntity(EntityPayload.Category(category.copy(name = "Custom 2")))

    val pending = repo.pendingOutbox(limit = 200)
    val customOps = pending.filter { it.entityId == "category-custom" }
    assertEquals(1, customOps.size)
    assertEquals("Custom 2", (customOps[0].payload as EntityPayload.Category).value.name)
    assertEquals(pendingBefore + 1, pending.size)
  }

  @Test
  fun offlineWriteThenPullKeepsTheNewerLocalEdit() = runTest {
    repo.initializeLocalDatabase()
    val category = CategoryEntity(
      id = "category-conflict",
      name = "Local",
      emoji = "✨",
      monthlyBudgetMinor = null,
      tint = CategoryTint.NEUTRAL,
      sortOrder = 1,
      system = false,
    )
    repo.saveEntity(EntityPayload.Category(category))
    val key = entityKey(EntityType.CATEGORY, category.id)
    val localVersion = db.categories().byKey(key)!!.version.toLogicalVersion()

    // An older remote row must lose and must not clear the pending operation.
    repo.mergeRemotePage(
      listOf(
        StoredEntity(
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.CATEGORY,
          entityId = category.id,
          version = LogicalVersion(localVersion.timestamp - 1_000, 0, "remote"),
          payload = EntityPayload.Category(category.copy(name = "Remote")),
          deleted = false,
          serverRevision = 7,
        ),
      ),
      EntityType.CATEGORY,
      cursor = 7,
    )

    assertEquals("Local", db.categories().byKey(key)!!.name)
    assertEquals(1, repo.pendingOutbox(limit = 100).count { it.entityId == category.id })
  }

  @Test
  fun newerRemoteVersionWinsAndDropsThePendingOperation() = runTest {
    repo.initializeLocalDatabase()
    val category = CategoryEntity(
      id = "category-conflict",
      name = "Local",
      emoji = "✨",
      monthlyBudgetMinor = null,
      tint = CategoryTint.NEUTRAL,
      sortOrder = 1,
      system = false,
    )
    repo.saveEntity(EntityPayload.Category(category))
    val key = entityKey(EntityType.CATEGORY, category.id)
    val localVersion = db.categories().byKey(key)!!.version.toLogicalVersion()

    repo.mergeRemotePage(
      listOf(
        StoredEntity(
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.CATEGORY,
          entityId = category.id,
          version = LogicalVersion(localVersion.timestamp + 1_000, 0, "remote"),
          payload = EntityPayload.Category(category.copy(name = "Remote")),
          deleted = false,
          serverRevision = 9,
        ),
      ),
      EntityType.CATEGORY,
      cursor = 9,
    )

    assertEquals("Remote", db.categories().byKey(key)!!.name)
    assertEquals(0, repo.pendingOutbox(limit = 100).count { it.entityId == category.id })

    // The pulled cursor is recorded per type and lifts the global watermark.
    val meta = repo.syncMeta()!!
    assertEquals(9L, meta.pulledRevisions[EntityType.CATEGORY])
    assertEquals(9L, meta.lastPulledRevision)
  }

  @Test
  fun localVersionsSortAfterObservedRemoteVersions() = runTest {
    repo.initializeLocalDatabase()
    val key = entityKey(EntityType.CATEGORY, "category-clock")
    val farFuture = System.currentTimeMillis() + 5_000_000

    repo.mergeRemotePage(
      listOf(
        StoredEntity(
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.CATEGORY,
          entityId = "category-clock",
          version = LogicalVersion(farFuture, 3, "remote"),
          payload = EntityPayload.Category(
            CategoryEntity("category-clock", "Remote", "✨", null, CategoryTint.NEUTRAL, 1, false),
          ),
          deleted = false,
          serverRevision = 4,
        ),
      ),
      EntityType.CATEGORY,
      cursor = 4,
    )

    repo.saveEntity(
      EntityPayload.Category(
        CategoryEntity("category-clock", "Local", "✨", null, CategoryTint.NEUTRAL, 1, false),
      ),
    )

    val next = db.categories().byKey(key)!!.version.toLogicalVersion()
    assertTrue(next > LogicalVersion(farFuture, 3, "remote"))
  }

  @Test
  fun tombstonePropagatesFromRemote() = runTest {
    repo.initializeLocalDatabase()
    val category = CategoryEntity(
      id = "category-tombstone",
      name = "Doomed",
      emoji = "✨",
      monthlyBudgetMinor = null,
      tint = CategoryTint.NEUTRAL,
      sortOrder = 1,
      system = false,
    )
    repo.saveEntity(EntityPayload.Category(category))
    val key = entityKey(EntityType.CATEGORY, category.id)
    val localVersion = db.categories().byKey(key)!!.version.toLogicalVersion()

    repo.mergeRemotePage(
      listOf(
        StoredEntity(
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.CATEGORY,
          entityId = category.id,
          version = LogicalVersion(localVersion.timestamp + 1_000, 0, "remote"),
          payload = EntityPayload.Category(category),
          deleted = true,
          serverRevision = 11,
        ),
      ),
      EntityType.CATEGORY,
      cursor = 11,
    )

    assertTrue(db.categories().byKey(key)!!.deleted)
    assertEquals(0, repo.activeEntities(EntityType.CATEGORY).size)
  }

  @Test
  fun blockedOperationIsReportedAndRequeuedByBootstrapBump() = runTest {
    repo.initializeLocalDatabase()
    repo.saveEntity(
      EntityPayload.Category(
        CategoryEntity("category-blocked", "Bad", "✨", null, CategoryTint.NEUTRAL, 1, false),
      ),
    )
    val op = repo.pendingOutbox(limit = 10).first { it.entityId == "category-blocked" }
    repo.updateOutbox(
      op.copy(status = OutboxStatus.BLOCKED, attempts = 1, lastError = "ArgumentValidationError"),
    )

    assertEquals("ArgumentValidationError", repo.blockedOutbox()?.lastError)
    val (pending, blocked) = repo.outboxCounts()
    assertEquals(1, blocked)
    assertFalse(pending > 0 && repo.pendingOutbox(limit = 10).any { it.entityId == "category-blocked" })

    // Reset the bootstrap gate the way a shipped payload fix would.
    val device = db.deviceMeta().byId("device")!!
    db.deviceMeta().upsert(device.copy(bootstrapVersion = 0))
    repo.initializeLocalDatabase()

    assertNull(repo.blockedOutbox())
    assertTrue(repo.pendingOutbox(limit = 10).any { it.entityId == "category-blocked" })
  }

  @Test
  fun fullUploadReVersionsEveryRowAndExcludesNothingLocal() = runTest {
    repo.initializeLocalDatabase()
    repo.saveEntity(
      EntityPayload.Category(
        CategoryEntity("category-a", "A", "✨", null, CategoryTint.NEUTRAL, 1, false),
      ),
    )
    // Pretend everything has been acked and is server-known.
    repo.acknowledgeOperations(repo.pendingOutbox(limit = 100).map { it.operationId })
    assertEquals(0, repo.pendingOutbox(limit = 100).size)

    repo.enqueueFullUpload()

    val pending = repo.pendingOutbox(limit = 100)
    // Cash + preferences seeds + the category.
    assertEquals(3, pending.size)
    assertTrue(pending.all { it.version.timestamp > 0 })
    assertEquals(
      setOf(EntityType.CATEGORY, EntityType.PAYMENT_METHOD, EntityType.PREFERENCES),
      pending.map { it.entityType }.toSet(),
    )
  }

  @Test
  fun backfillsLegacyRecurringAndTransactionCurrencyFromPreferences() = runTest {
    repo.initializeLocalDatabase()
    repo.updateSyncMeta { it }

    // Move the account to USD so the backfill has something distinctive to stamp.
    val prefs = repo.activeEntities(EntityType.PREFERENCES).first().payload
    val prefsValue = (prefs as EntityPayload.Preferences).value
    repo.saveEntity(EntityPayload.Preferences(prefsValue.copy(currency = Currency.USD)))

    val recurringKey = entityKey(EntityType.RECURRING, "rec-legacy")
    db.recurring().upsert(
      app.dimo.android.data.db.RecurringRecord.from(
        StoredEntity(
          key = recurringKey,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.RECURRING,
          entityId = "rec-legacy",
          version = LogicalVersion(1_000, 0, "legacy"),
          payload = EntityPayload.Recurring(
            RecurringEntity(
              id = "rec-legacy",
              name = "Rent",
              amountMinor = 50_000,
              categoryId = "c1",
              paymentMethodId = SeedData.CASH_PAYMENT_METHOD.id,
              frequency = RecurringFrequency.MONTHLY,
              anchorDate = "2026-01-01",
              paused = false,
              currency = null,
            ),
          ),
          deleted = false,
          serverRevision = 3,
        ),
      ),
    )

    assertEquals(1, repo.backfillRecurringCurrencies())
    val updated = db.recurring().byKey(recurringKey)!!.toStoredEntity().payload
    assertEquals("USD", (updated as EntityPayload.Recurring).value.currency)
    // The repair is versioned and queued so other clients converge.
    assertTrue(repo.pendingOutbox(limit = 100).any { it.entityId == "rec-legacy" })

    // Idempotent second run.
    assertEquals(0, repo.backfillRecurringCurrencies())
  }

  @Test
  fun backfillsMissingPaymentMethodIds() = runTest {
    repo.initializeLocalDatabase()

    val key = entityKey(EntityType.TRANSACTION, "tx-legacy")
    db.transactions().upsert(
      TransactionRecord.from(
        StoredEntity(
          key = key,
          workspaceId = WORKSPACE_ID,
          entityType = EntityType.TRANSACTION,
          entityId = "tx-legacy",
          version = LogicalVersion(1_000, 0, "legacy"),
          payload = EntityPayload.Transaction(
            TransactionEntity(
              id = "tx-legacy",
              name = "Old",
              amountMinor = 100,
              occurredAt = 1_000,
              categoryId = "c1",
              paymentMethodId = null,
              currency = "INR",
            ),
          ),
          deleted = false,
          serverRevision = 2,
        ),
      ),
    )

    assertEquals(1, repo.backfillMissingPaymentMethodIds())
    val updated = db.transactions().byKey(key)!!.toStoredEntity().payload
    assertEquals(
      SeedData.CASH_PAYMENT_METHOD.id,
      (updated as EntityPayload.Transaction).value.paymentMethodId,
    )
    assertEquals(0, repo.backfillMissingPaymentMethodIds())
  }

  @Test
  fun deleteTombstonesRatherThanHardDeleting() = runTest {
    repo.initializeLocalDatabase()
    repo.saveEntity(
      EntityPayload.Category(
        CategoryEntity("category-del", "Gone", "✨", null, CategoryTint.NEUTRAL, 1, false),
      ),
    )
    repo.removeEntity(EntityType.CATEGORY, "category-del")

    val key = entityKey(EntityType.CATEGORY, "category-del")
    val row = db.categories().byKey(key)
    assertNotNull(row)
    assertTrue(row!!.deleted)
    // The tombstone is queued for upload so other clients learn about the delete.
    val op: SyncOperation? = repo.pendingOutbox(limit = 100).firstOrNull { it.entityId == "category-del" }
    assertNotNull(op)
    assertTrue(op!!.deleted)
  }

  @Test
  fun removeActiveEntitiesTombstonesEveryRowOfAType() = runTest {
    repo.initializeLocalDatabase()
    repeat(3) { index ->
      repo.saveEntity(
        EntityPayload.Transaction(
          TransactionEntity(
            id = "tx-$index",
            name = "T$index",
            amountMinor = 100,
            occurredAt = 1_000L + index,
            categoryId = "c1",
            paymentMethodId = SeedData.CASH_PAYMENT_METHOD.id,
            currency = "INR",
          ),
        ),
      )
    }
    assertEquals(3, repo.removeActiveEntities(EntityType.TRANSACTION))
    assertEquals(0, repo.activeEntities(EntityType.TRANSACTION).size)
    assertEquals(0, repo.removeActiveEntities(EntityType.TRANSACTION))
  }
}
