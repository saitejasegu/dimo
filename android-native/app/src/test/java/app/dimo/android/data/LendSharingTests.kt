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
import app.dimo.android.domain.LendSelectors
import app.dimo.android.sync.ConvexAPI
import app.dimo.android.sync.LendInviteLinks
import app.dimo.android.sync.LendInvitePreview
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
  fun inviteLinksParseEverySupportedForm() {
    assertEquals("ABCDE23456", LendInviteLinks.code("dimo", "invite", "/abcde-23456", null))
    assertEquals("ABCDE23456", LendInviteLinks.code("dimo", "invite", "", "ABCDE23456"))
    assertEquals(
      "ABCDE23456",
      LendInviteLinks.code("https", "dimoapp.xyz", "/invite", "abcde23456"),
    )
    assertNull(LendInviteLinks.code("https", "example.com", "/invite", "ABCDE23456"))
    assertNull(LendInviteLinks.code("dimo", "widget", "/add-expense", null))
    assertNull(LendInviteLinks.code("dimo", "invite", "", null))
  }

  @Test
  fun inviteMessageMatchesIos() {
    val message = LendInviteLinks.message("Alice", "ABCDE23456")
    assertTrue(message.startsWith("Alice wants"))
    assertTrue(message.contains("https://dimoapp.xyz/invite?code=ABCDE23456"))
    assertTrue(message.contains("ABCDE-23456"))
  }

  @Test
  fun lendingPermissionErrorsAreBlockedNotRetried() {
    assertTrue(isPermanentSyncError("Uncaught Error: Not a member of this lending connection"))
    assertTrue(isPermanentSyncError("Unknown lending connection"))
    assertTrue(isPermanentSyncError("Lend id collides with an unshared entry"))
  }

  @Test
  fun previewAcceptability() {
    val now = 1_000_000L
    val pending = LendInvitePreview("A", "pending", (now + 1_000).toDouble(), isOwnInvite = false)
    assertTrue(pending.isAcceptable(now))
    assertFalse(pending.copy(isOwnInvite = true).isAcceptable(now))
    assertFalse(pending.copy(expiresAt = (now - 1).toDouble()).isAcceptable(now))
    assertFalse(pending.copy(status = "accepted").isAcceptable(now))
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
}
