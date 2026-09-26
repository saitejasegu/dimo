package app.dimo.android.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.Lend
import app.dimo.android.data.model.LendActor
import app.dimo.android.data.model.LendEntity
import app.dimo.android.data.model.LendKind
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.domain.LendFlow
import app.dimo.android.domain.LendPeople
import app.dimo.android.domain.LendSelectors
import app.dimo.android.sync.ConvexAPI
import app.dimo.android.sync.LendUser
import app.dimo.android.sync.OutgoingLendInvite
import app.dimo.android.sync.isPermanentSyncError
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Port of `ios-native/DimoTests/LendSharingTests.swift`. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class LendSharingTests {
  private lateinit var db: DimoDatabase
  private lateinit var repo: Repository

  @Before
  fun setUp() {
    db = Room
      .inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), DimoDatabase::class.java)
      .allowMainThreadQueries()
      .build()
    repo = Repository(db)
  }

  @After
  fun tearDown() {
    db.close()
  }

  @Test
  fun lendingPermissionErrorsAreBlockedNotRetried() {
    assertTrue(isPermanentSyncError("Uncaught Error: Not a member of this lending connection"))
    assertTrue(isPermanentSyncError("Unknown lending connection"))
    assertTrue(isPermanentSyncError("Lend id collides with an unshared entry"))
  }

  @Test
  fun foundUserDecodesWithOptionalContactId() {
    val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
    val found = json.decodeFromString(
      LendUser.serializer(),
      """{"userId":"u1","name":"Bob","email":"bob@example.com","relation":"connected","contactId":"dimo:c1"}""",
    )
    assertEquals("dimo:c1", found.contactId)
    val fresh = json.decodeFromString(
      LendUser.serializer(),
      """{"userId":"u1","name":"Bob","email":"bob@example.com","relation":"none"}""",
    )
    assertNull(fresh.contactId)
  }

  @Test
  fun wireDecodesSharingMetadataAndEncodesOnlyCurrency() {
    val stored = ConvexAPI.storedEntityFrom(
      EntityType.LEND,
      mapOf(
        "workspaceId" to "global",
        "entityId" to "lend-1",
        "version" to mapOf("timestamp" to 1L, "counter" to 0L, "deviceId" to "d"),
        "deleted" to false,
        "serverRevision" to 3L,
        "contactName" to "Alice",
        "contactId" to "dimo:conn1",
        "amountMinor" to 50_000L,
        "occurredAt" to 100L,
        "comment" to "",
        "kind" to "borrowed",
        "currency" to "USD",
        "connectionId" to "conn1",
        "createdBy" to "contact",
        "lastEditedBy" to "me",
      ),
    )
    val lend = (stored.payload as EntityPayload.Lend).value
    assertEquals(LendKind.BORROWED, lend.kind)
    assertEquals("USD", lend.currency)
    assertEquals("conn1", lend.connectionId)
    assertEquals(LendActor.CONTACT, lend.createdBy)
    assertEquals(LendActor.ME, lend.lastEditedBy)

    val wire = ConvexAPI.wireTypedOperation(
      SyncOperation(
        operationId = "op",
        key = stored.key,
        workspaceId = "global",
        entityType = EntityType.LEND,
        entityId = "lend-1",
        version = LogicalVersion(1, 0, "d"),
        payload = stored.payload,
        deleted = false,
        status = OutboxStatus.PENDING,
        attempts = 0,
        lastError = null,
        createdAt = 0,
      ),
    )
    assertEquals("USD", wire["currency"])
    assertFalse(wire.containsKey("connectionId"))
    assertFalse(wire.containsKey("createdBy"))
  }

  @Test
  fun sharingColumnsPersistLocally() = runTest {
    repo.saveEntity(
      EntityPayload.Lend(
        LendEntity(
          id = "lend-1",
          contactName = "Alice",
          contactId = "dimo:conn1",
          amountMinor = 50_000,
          occurredAt = 100,
          comment = "",
          kind = LendKind.BORROWED,
          currency = "EUR",
          connectionId = "conn1",
          createdBy = LendActor.CONTACT,
          lastEditedBy = LendActor.ME,
        ),
      ),
    )
    val lend = (repo.activeEntities(EntityType.LEND).single().payload as EntityPayload.Lend).value
    assertEquals("EUR", lend.currency)
    assertEquals("conn1", lend.connectionId)
    assertEquals(LendActor.CONTACT, lend.createdBy)
    assertEquals(LendActor.ME, lend.lastEditedBy)
  }

  @Test
  fun summaryUsesNewestCurrencyAndFlagsSharedLedgers() {
    fun lend(id: String, contactId: String, currency: String?, occurredAt: Long) = Lend(
      id = id,
      contactName = "Alice",
      contactId = contactId,
      amount = 10.0,
      comment = "",
      time = "",
      day = "",
      amountMinor = 1_000,
      occurredAt = occurredAt,
      kind = LendKind.LENT,
      currency = currency,
    )
    val summaries = LendSelectors.contactSummaries(
      listOf(
        lend("old", "dimo:conn1", "INR", 1),
        lend("new", "dimo:conn1", "USD", 2),
        lend("private", "cn-bob", null, 3),
      ),
    )
    val shared = summaries.first { it.contactId == "dimo:conn1" }
    assertEquals("USD", shared.currency)
    assertTrue(shared.isShared)
    assertFalse(summaries.first { it.contactId == "cn-bob" }.isShared)
  }

  @Test
  fun kindFollowsFlowAndBalance() {
    // Gave: pays down what you owe, else lends.
    assertEquals(LendKind.RETURNED, LendSelectors.kindFor(LendFlow.GAVE, 50.0, -100.0))
    assertEquals(LendKind.RETURNED, LendSelectors.kindFor(LendFlow.GAVE, 100.0, -100.0))
    assertEquals(LendKind.LENT, LendSelectors.kindFor(LendFlow.GAVE, 150.0, -100.0))
    assertEquals(LendKind.LENT, LendSelectors.kindFor(LendFlow.GAVE, 50.0, 0.0))
    // Got: collects what they owe, else borrows.
    assertEquals(LendKind.REPAID, LendSelectors.kindFor(LendFlow.GOT, 100.0, 100.0))
    assertEquals(LendKind.BORROWED, LendSelectors.kindFor(LendFlow.GOT, 150.0, 100.0))
    assertEquals(LendKind.BORROWED, LendSelectors.kindFor(LendFlow.GOT, 10.0, -5.0))
    assertEquals(LendFlow.GOT, LendFlow.of(LendKind.REPAID))
    assertEquals(LendFlow.GAVE, LendFlow.of(LendKind.RETURNED))
  }

  @Test
  fun peopleSplitIncludesSettledAndInvitedOnly() {
    fun lend(id: String, contactId: String, kind: LendKind, amount: Double, occurredAt: Long) = Lend(
      id = id,
      contactName = contactId,
      contactId = contactId,
      amount = amount,
      comment = "",
      time = "",
      day = "",
      amountMinor = (amount * 100).toLong(),
      occurredAt = occurredAt,
      kind = kind,
    )
    val lends = listOf(
      lend("a1", "small", LendKind.LENT, 10.0, 1),
      lend("b1", "big", LendKind.BORROWED, 90.0, 2),
      lend("c1", "done", LendKind.LENT, 20.0, 3),
      lend("c2", "done", LendKind.REPAID, 20.0, 4),
    )
    val invites = listOf(
      OutgoingLendInvite(inviteId = "i1", contactName = "New", contactId = "fresh", createdAt = 5.0),
      OutgoingLendInvite(inviteId = "i2", contactName = "Small", contactId = "small", createdAt = 6.0),
    )
    val people = LendPeople.split(LendSelectors.allContactSummaries(lends), invites)
    assertEquals(listOf("big", "small"), people.active.map { it.contactId })
    assertEquals(-90.0, people.active.first().balance, 0.0001)
    assertEquals(listOf("fresh", "done"), people.settled.map { it.contactId })
    assertEquals(0, people.settled.first().entryCount)
  }
}
