package app.dimo.android.features.email

import app.dimo.android.data.model.EmailAccountSyncState
import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailSuggestionState
import app.dimo.android.data.model.PaymentMethodOption
import app.dimo.android.data.model.PaymentMethodType
import app.dimo.android.email.integration.EmailFeatureController
import java.math.BigDecimal
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Covers the derivations that drive the Email tab badge, the filter chips and the
 * mapping from persisted state to what the UI shows.
 */
class EmailFeatureStoreTests {
  private fun store() = EmailFeatureStore(scope = TestScope())

  private fun suggestion(
    id: String,
    kind: EmailUISuggestionKind,
    status: EmailUISuggestionStatus,
  ) = EmailUISuggestion(
    id = id,
    accountId = "account",
    accountEmail = "user@example.com",
    kind = kind,
    status = status,
    sender = "Cafe",
    subject = "Receipt",
    snippet = "receipt",
    receivedAt = 1_700_000_000_000,
    analyzer = EmailUIAnalyzer.OPEN_ROUTER,
  )

  private fun message(id: String, state: EmailUIMessageAnalysisState) = EmailUIMessage(
    id = id,
    accountEmail = "user@example.com",
    sender = "Cafe",
    subject = "Receipt",
    snippet = "receipt",
    receivedAt = 1_700_000_000_000,
    analysisState = state,
  )

  @Test
  fun `pending purchase count drives the tab badge and ignores refunds`() {
    val store = store()
    store.publishSuggestions(
      listOf(
        suggestion("a", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.PENDING_PURCHASE),
        suggestion("b", EmailUISuggestionKind.DEBIT, EmailUISuggestionStatus.PENDING_PURCHASE),
        suggestion("c", EmailUISuggestionKind.REFUND, EmailUISuggestionStatus.PENDING_REFUND),
        suggestion("d", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.ADDED),
      ),
    )
    assertEquals(2, store.pendingPurchaseCount)
  }

  @Test
  fun `filters partition suggestions and messages into separate lists`() {
    val store = store()
    store.publishSuggestions(
      listOf(
        suggestion("a", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.PENDING_PURCHASE),
        suggestion("c", EmailUISuggestionKind.REFUND, EmailUISuggestionStatus.PENDING_REFUND),
        suggestion("d", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.DISMISSED),
      ),
    )
    store.publishAllEmails(
      listOf(
        message("m1", EmailUIMessageAnalysisState.PENDING),
        message("m2", EmailUIMessageAnalysisState.FAILED),
      ),
    )

    store.setFilter(EmailSuggestionFilter.PURCHASES)
    assertEquals(listOf("a"), store.filteredSuggestions.map { it.id })
    // Suggestion tabs must not also render raw message rows.
    assertTrue(store.filteredEmails.isEmpty())

    store.setFilter(EmailSuggestionFilter.REFUNDS)
    assertEquals(listOf("c"), store.filteredSuggestions.map { it.id })

    store.setFilter(EmailSuggestionFilter.REVIEWED)
    assertEquals(listOf("d"), store.filteredSuggestions.map { it.id })

    store.setFilter(EmailSuggestionFilter.ERRORS)
    assertEquals(listOf("m2"), store.filteredEmails.map { it.id })
    assertTrue(store.filteredSuggestions.isEmpty())

    store.setFilter(EmailSuggestionFilter.ALL)
    assertEquals(listOf("m1", "m2"), store.filteredEmails.map { it.id })
  }

  @Test
  fun `analysis error count tracks failed messages`() {
    val store = store()
    assertTrue(!store.hasFailedAnalyses)
    store.publishAllEmails(
      listOf(
        message("m1", EmailUIMessageAnalysisState.PENDING),
        message("m2", EmailUIMessageAnalysisState.FAILED),
      ),
    )
    assertEquals(1, store.analysisErrorCount)
    assertTrue(store.hasFailedAnalyses)
  }

  @Test
  fun `reviewing a purchase opens the purchase draft, a refund opens the refund review`() {
    val store = store()
    val purchase =
      suggestion("a", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.PENDING_PURCHASE)
        .copy(merchant = "Cafe", amount = BigDecimal("512.48"))
    store.review(purchase)
    assertEquals("512.48", store.purchaseReview?.amount)
    assertNull(store.refundReview)

    store.purchaseReview = null
    store.review(suggestion("c", EmailUISuggestionKind.REFUND, EmailUISuggestionStatus.PENDING_REFUND))
    assertEquals("c", store.refundReview?.suggestionId)
    assertNull(store.purchaseReview)
  }

  @Test
  fun `a grouped suggestion acts on every source message`() {
    val grouped =
      suggestion("a", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.PENDING_PURCHASE)
        .copy(sourceMessageIds = listOf("a", "b"))
    assertEquals(listOf("a", "b"), grouped.actionMessageIds)
    // A lone suggestion still acts on itself.
    val lone = suggestion("z", EmailUISuggestionKind.PURCHASE, EmailUISuggestionStatus.ADDED)
    assertEquals(listOf("z"), lone.actionMessageIds)
  }

  @Test
  fun `queued and failed rows produce no reviewable suggestion`() {
    assertNull(EmailFeatureController.uiStatus(EmailSuggestionState.PENDING_ANALYSIS))
    assertNull(EmailFeatureController.uiStatus(EmailSuggestionState.ANALYSIS_FAILED))
    assertEquals(
      EmailUISuggestionStatus.PENDING_PURCHASE,
      EmailFeatureController.uiStatus(EmailSuggestionState.PENDING_PURCHASE),
    )
  }

  @Test
  fun `backfilling and syncing both read as syncing`() {
    assertEquals(
      EmailUIAccountSyncState.SYNCING,
      EmailFeatureController.uiSyncState(EmailAccountSyncState.BACKFILLING),
    )
    assertEquals(
      EmailUIAccountSyncState.SYNCING,
      EmailFeatureController.uiSyncState(EmailAccountSyncState.SYNCING),
    )
    assertEquals(
      EmailUIAccountSyncState.NEEDS_RECONNECT,
      EmailFeatureController.uiSyncState(EmailAccountSyncState.NEEDS_RECONNECT),
    )
  }

  @Test
  fun `minor units round to two decimals and reject non-positive amounts`() {
    assertEquals(51_248L, EmailFeatureController.minorUnits(BigDecimal("512.48")))
    assertEquals(51_200L, EmailFeatureController.minorUnits(BigDecimal("512")))
    // Extra precision is rounded rather than rejected — the amount came from a
    // user-editable field by this point.
    assertEquals(1_235L, EmailFeatureController.minorUnits(BigDecimal("12.345")))
    assertNull(EmailFeatureController.minorUnits(BigDecimal("0")))
    assertNull(EmailFeatureController.minorUnits(BigDecimal("-5")))
  }

  @Test
  fun `payment method resolution falls back to the active default`() {
    val methods = listOf(
      PaymentMethodOption("archived", "Old", PaymentMethodType.CARD, "", false, archived = true),
      PaymentMethodOption("default", "Cash", PaymentMethodType.CASH, "", true, archived = false),
      PaymentMethodOption("other", "UPI", PaymentMethodType.UPI, "", false, archived = false),
    )
    assertEquals("other", EmailFeatureController.resolvedPaymentMethodId("other", methods))
    // An unknown or archived-only request degrades to the active default.
    assertEquals("default", EmailFeatureController.resolvedPaymentMethodId("missing", methods))
    assertEquals("default", EmailFeatureController.resolvedPaymentMethodId(null, methods))
  }

  @Test
  fun `provenance names the model without its vendor prefix`() {
    assertEquals(
      "OpenRouter · gpt-oss-20b:free",
      EmailUIAnalyzer.OPEN_ROUTER.provenanceTitle("openai/gpt-oss-20b:free"),
    )
    assertEquals("OpenRouter", EmailUIAnalyzer.OPEN_ROUTER.provenanceTitle(null))
  }

  @Test
  fun `classification maps to the UI kind one for one`() {
    assertEquals(
      EmailUISuggestionKind.DEBIT,
      EmailFeatureController.uiKind(EmailMessageClassification.DEBIT),
    )
    assertEquals(
      EmailUISuggestionKind.IRRELEVANT,
      EmailFeatureController.uiKind(EmailMessageClassification.IRRELEVANT),
    )
  }
}
