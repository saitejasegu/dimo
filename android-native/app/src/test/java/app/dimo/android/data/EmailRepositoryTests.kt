package app.dimo.android.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.model.CategoryEntity
import app.dimo.android.data.model.CategoryTint
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EmailAnalyzerKind
import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailRepositoryException
import app.dimo.android.data.model.EmailSuggestionState
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.PendingEmailMessage
import app.dimo.android.data.model.PersistedEmailAnalysis
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.emailMessageKey
import app.dimo.android.data.model.entityKey
import app.dimo.android.domain.EmailPurchaseGroupingSelector
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Covers the email surface's invariants: the dual write into the synced entity,
 * the review-state gates, purchase grouping, and refund matching limits.
 */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [34])
class EmailRepositoryTests {
  private lateinit var db: DimoDatabase
  private lateinit var repo: Repository
  private lateinit var email: EmailRepository

  private val accountId = "google-subject-1"

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
    email = EmailRepository(db, repo.entityWriter)
  }

  @After
  fun tearDown() {
    db.close()
  }

  private suspend fun seedAccount() {
    email.saveAccount(
      EmailAccountRecordModel(id = accountId, emailAddress = "user@example.com"),
    )
  }

  private suspend fun seedCategory(id: String = "cat-food") {
    repo.saveEntity(
      EntityPayload.Category(
        CategoryEntity(
          id = id,
          name = "Food",
          emoji = "🍔",
          monthlyBudgetMinor = null,
          tint = CategoryTint.NEUTRAL,
          sortOrder = 0,
          system = false,
        ),
      ),
    )
  }

  private fun pending(
    gmailId: String,
    internalDate: Long = 1_700_000_000_000,
    subject: String = "Your order",
    body: String = "You paid Rs.512.48 to Cafe",
  ) = PendingEmailMessage(
    accountId = accountId,
    gmailMessageId = gmailId,
    threadId = "thread-$gmailId",
    senderName = "Cafe",
    senderAddress = "billing@cafe.example",
    subject = subject,
    snippet = "receipt",
    internalDate = internalDate,
    normalizedBodyText = body,
  )

  private fun analysis(
    classification: EmailMessageClassification = EmailMessageClassification.PURCHASE,
    amount: String? = "512.48",
    categoryId: String? = null,
  ) = PersistedEmailAnalysis(
    analyzerType = EmailAnalyzerKind.OPEN_ROUTER,
    modelVersion = "test/model",
    promptVersion = 1,
    classification = classification,
    merchant = "Cafe",
    amount = amount,
    currency = Currency.INR,
    occurredAt = 1_700_000_000_000,
    categoryId = categoryId,
  )

  @Test
  fun `pending insert is idempotent and requires a known account`() = runTest {
    seedAccount()
    assertEquals(1, email.insertPendingMessages(listOf(pending("m1"))))
    // Replaying the same Gmail page must not resurrect or duplicate a row.
    assertEquals(0, email.insertPendingMessages(listOf(pending("m1"))))

    val failure = runCatching {
      email.insertPendingMessages(
        listOf(pending("m2").copy(accountId = "unknown-account")),
      )
    }.exceptionOrNull()
    assertEquals(
      EmailRepositoryException.Kind.ACCOUNT_NOT_FOUND,
      (failure as EmailRepositoryException).kind,
    )
  }

  @Test
  fun `saving analysis moves a purchase to pending review without syncing it`() = runTest {
    seedAccount()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")

    email.saveAnalysis(key, analysis())

    val stored = email.message(key)
    assertEquals(EmailSuggestionState.PENDING_PURCHASE, stored?.state)
    assertEquals("512.48", stored?.amount)
    // pendingPurchase is a synced state, but nothing is dual-written until the
    // user reviews it, so the outbox stays empty here.
    assertNull(repo.pendingOutbox(10).firstOrNull { it.entityType == EntityType.EMAIL_MESSAGE })
  }

  @Test
  fun `analysis is rejected when the amount is not exact minor units`() = runTest {
    seedAccount()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")

    val failure = runCatching {
      email.saveAnalysis(key, analysis(amount = "12.345"))
    }.exceptionOrNull()

    assertEquals(
      EmailRepositoryException.Kind.INVALID_ANALYSIS,
      (failure as EmailRepositoryException).kind,
    )
  }

  @Test
  fun `accepting a suggestion writes the transaction and the synced email together`() = runTest {
    seedAccount()
    seedCategory()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")
    email.saveAnalysis(key, analysis(categoryId = "cat-food"))

    email.acceptSuggestion(
      key,
      TransactionEntity(
        id = "tx-1",
        name = "Cafe",
        amountMinor = 51_248,
        occurredAt = 1_700_000_000_000,
        categoryId = "cat-food",
        paymentMethodId = null,
        currency = "INR",
      ),
    )

    val stored = email.message(key)
    assertEquals(EmailSuggestionState.ADDED, stored?.state)
    assertEquals("tx-1", stored?.linkedTransactionId)
    // Both the transaction and the reviewed email must be queued for Convex.
    val queued = repo.pendingOutbox(10).map { it.entityType }.toSet()
    assertTrue(EntityType.TRANSACTION in queued)
    assertTrue(EntityType.EMAIL_MESSAGE in queued)
    // The body is retained locally so the source email stays readable.
    assertNotNull(stored?.normalizedBodyText)
  }

  @Test
  fun `a reviewed suggestion cannot be accepted twice`() = runTest {
    seedAccount()
    seedCategory()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")
    email.saveAnalysis(key, analysis(categoryId = "cat-food"))
    val transaction = TransactionEntity(
      id = "tx-1",
      name = "Cafe",
      amountMinor = 51_248,
      occurredAt = 1_700_000_000_000,
      categoryId = "cat-food",
      paymentMethodId = null,
      currency = "INR",
    )
    email.acceptSuggestion(key, transaction)

    val failure = runCatching {
      email.acceptSuggestion(key, transaction.copy(id = "tx-2"))
    }.exceptionOrNull()

    assertEquals(
      EmailRepositoryException.Kind.SUGGESTION_ALREADY_REVIEWED,
      (failure as EmailRepositoryException).kind,
    )
  }

  @Test
  fun `a purchase and its bank debit are grouped and reviewed as one`() = runTest {
    seedAccount()
    seedCategory()
    val purchaseKey = emailMessageKey(accountId, "m-purchase")
    val debitKey = emailMessageKey(accountId, "m-debit")
    email.insertPendingMessages(
      listOf(
        pending("m-purchase", internalDate = 1_700_000_000_000),
        // Five minutes later: inside the 15-minute close window.
        pending("m-debit", internalDate = 1_700_000_300_000, subject = "Debit alert"),
      ),
    )
    email.saveAnalysis(purchaseKey, analysis(EmailMessageClassification.PURCHASE))
    email.saveAnalysis(debitKey, analysis(EmailMessageClassification.DEBIT))

    val expectedGroup = EmailPurchaseGroupingSelector.groupId(purchaseKey, debitKey)
    assertEquals(expectedGroup, email.message(purchaseKey)?.purchaseGroupId)
    assertEquals(expectedGroup, email.message(debitKey)?.purchaseGroupId)

    // Reviewing one member resolves the whole group, so one expense is created.
    email.acceptSuggestion(
      purchaseKey,
      TransactionEntity(
        id = "tx-1",
        name = "Cafe",
        amountMinor = 51_248,
        occurredAt = 1_700_000_000_000,
        categoryId = "cat-food",
        paymentMethodId = null,
        currency = "INR",
      ),
    )
    assertEquals(EmailSuggestionState.ADDED, email.message(purchaseKey)?.state)
    assertEquals(EmailSuggestionState.ADDED, email.message(debitKey)?.state)
    assertEquals("tx-1", email.message(debitKey)?.linkedTransactionId)
  }

  @Test
  fun `separating a grouped pair keeps them independently reviewable`() = runTest {
    seedAccount()
    val purchaseKey = emailMessageKey(accountId, "m-purchase")
    val debitKey = emailMessageKey(accountId, "m-debit")
    email.insertPendingMessages(
      listOf(
        pending("m-purchase", internalDate = 1_700_000_000_000),
        pending("m-debit", internalDate = 1_700_000_300_000, subject = "Debit alert"),
      ),
    )
    email.saveAnalysis(purchaseKey, analysis(EmailMessageClassification.PURCHASE))
    email.saveAnalysis(debitKey, analysis(EmailMessageClassification.DEBIT))

    email.separateSuggestions(listOf(purchaseKey, debitKey))

    // A self group id is the marker that stops future re-grouping.
    assertEquals(purchaseKey, email.message(purchaseKey)?.purchaseGroupId)
    assertEquals(debitKey, email.message(debitKey)?.purchaseGroupId)
  }

  @Test
  fun `dismiss then restore returns the suggestion to review`() = runTest {
    seedAccount()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")
    email.saveAnalysis(key, analysis())

    email.dismissSuggestion(key)
    assertEquals(EmailSuggestionState.DISMISSED, email.message(key)?.state)
    // Dismissed rows sync, so the body is kept for Restore on another device.
    assertNotNull(email.message(key)?.normalizedBodyText)

    email.restoreDismissedSuggestion(key)
    assertEquals(EmailSuggestionState.PENDING_PURCHASE, email.message(key)?.state)
    assertNull(email.message(key)?.reviewedAt)
  }

  @Test
  fun `a full refund tombstones the matched transaction`() = runTest {
    seedAccount()
    seedCategory()
    repo.saveEntity(
      EntityPayload.Transaction(
        TransactionEntity(
          id = "tx-1",
          name = "Cafe",
          amountMinor = 51_248,
          occurredAt = 1_700_000_000_000,
          categoryId = "cat-food",
          paymentMethodId = null,
          currency = "INR",
        ),
      ),
    )
    email.insertPendingMessages(
      listOf(
        pending(
          "m-refund",
          internalDate = 1_700_100_000_000,
          subject = "Refund processed",
          body = "We refunded Rs.512.48",
        ),
      ),
    )
    val key = emailMessageKey(accountId, "m-refund")
    email.saveAnalysis(
      key,
      analysis(EmailMessageClassification.REFUND).copy(occurredAt = 1_700_100_000_000),
    )

    email.applyFullRefund(key, "tx-1")

    assertEquals(EmailSuggestionState.REFUND_APPLIED, email.message(key)?.state)
    val transactionKey = entityKey(EntityType.TRANSACTION, "tx-1")
    assertTrue(repo.allEntities().first { it.key == transactionKey }.deleted)
  }

  @Test
  fun `a partial refund email cannot delete a transaction`() = runTest {
    seedAccount()
    seedCategory()
    repo.saveEntity(
      EntityPayload.Transaction(
        TransactionEntity(
          id = "tx-1",
          name = "Cafe",
          amountMinor = 51_248,
          occurredAt = 1_700_000_000_000,
          categoryId = "cat-food",
          paymentMethodId = null,
          currency = "INR",
        ),
      ),
    )
    email.insertPendingMessages(
      listOf(
        pending(
          "m-refund",
          internalDate = 1_700_100_000_000,
          subject = "Partial refund issued",
          body = "We issued a partial refund of Rs.512.48",
        ),
      ),
    )
    val key = emailMessageKey(accountId, "m-refund")
    email.saveAnalysis(
      key,
      analysis(EmailMessageClassification.REFUND).copy(occurredAt = 1_700_100_000_000),
    )

    val failure = runCatching { email.applyFullRefund(key, "tx-1") }.exceptionOrNull()

    assertEquals(
      EmailRepositoryException.Kind.AMOUNT_MISMATCH,
      (failure as EmailRepositoryException).kind,
    )
    val transactionKey = entityKey(EntityType.TRANSACTION, "tx-1")
    assertTrue(!repo.allEntities().first { it.key == transactionKey }.deleted)
  }

  @Test
  fun `retention expires unlinked rows but keeps accepted sources`() = runTest {
    seedAccount()
    seedCategory()
    email.insertPendingMessages(
      listOf(pending("m-old", internalDate = 1_000), pending("m-kept", internalDate = 2_000)),
    )
    val keptKey = emailMessageKey(accountId, "m-kept")
    email.saveAnalysis(keptKey, analysis(categoryId = "cat-food"))
    email.acceptSuggestion(
      keptKey,
      TransactionEntity(
        id = "tx-1",
        name = "Cafe",
        amountMinor = 51_248,
        occurredAt = 1_700_000_000_000,
        categoryId = "cat-food",
        paymentMethodId = null,
        currency = "INR",
      ),
    )

    assertEquals(1, email.expireMessages(olderThan = 10_000))

    assertEquals(
      EmailSuggestionState.EXPIRED,
      email.message(emailMessageKey(accountId, "m-old"))?.state,
    )
    assertEquals(EmailSuggestionState.ADDED, email.message(keptKey)?.state)
  }

  @Test
  fun `disconnecting an account drops its local mail but keeps synced entities`() = runTest {
    seedAccount()
    seedCategory()
    email.insertPendingMessages(listOf(pending("m1")))
    val key = emailMessageKey(accountId, "m1")
    email.saveAnalysis(key, analysis(categoryId = "cat-food"))
    email.dismissSuggestion(key)

    assertTrue(email.deleteAccount(accountId))

    assertNull(email.message(key))
    // The synced entity survives so a reconnect can materialize it again.
    assertNotNull(db.syncedEmailMessages().byKey(entityKey(EntityType.EMAIL_MESSAGE, key)))

    // Reconnecting restores the reviewed row from the synced copy.
    seedAccount()
    email.materializeSyncedMessages(accountId)
    assertEquals(EmailSuggestionState.DISMISSED, email.message(key)?.state)
  }
}
