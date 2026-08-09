package app.dimo.android.data

import androidx.room.withTransaction
import app.dimo.android.data.db.DimoDatabase
import app.dimo.android.data.db.EmailAccountRecord
import app.dimo.android.data.db.EmailAnalysisRetryRecord
import app.dimo.android.data.db.EmailAnalysisSettingsRecord
import app.dimo.android.data.db.EmailMessageRecord
import app.dimo.android.data.model.Currency
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EmailAnalysisProvider
import app.dimo.android.data.model.EmailAnalysisRetryState
import app.dimo.android.data.model.EmailAnalysisSettings
import app.dimo.android.data.model.EmailLocalSuggestionFilter
import app.dimo.android.data.model.EmailMessageClassification
import app.dimo.android.data.model.EmailMessageEntity
import app.dimo.android.data.model.EmailMessageRecordModel
import app.dimo.android.data.model.EmailMessageSummaryModel
import app.dimo.android.data.model.EmailRepositoryException
import app.dimo.android.data.model.EmailRepositoryException.Kind
import app.dimo.android.data.model.EmailSuggestionState
import app.dimo.android.data.model.EntityPayload
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.PendingEmailMessage
import app.dimo.android.data.model.PersistedEmailAnalysis
import app.dimo.android.data.model.RecurringEntity
import app.dimo.android.data.model.StoredEntity
import app.dimo.android.data.model.TransactionEntity
import app.dimo.android.data.model.entityKey
import app.dimo.android.domain.EmailPurchaseGroupingSelector
import app.dimo.android.domain.EmailSuggestionSelectors
import java.math.BigDecimal
import java.math.RoundingMode
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Device-local email data, the Kotlin port of the `Repository` email extension in
 * `ios-native/Dimo/Data/Repository.swift`.
 *
 * Split out of [Repository] because it is a self-contained surface, but it shares
 * that class's transaction and outbox rules through [EntityWriter]: any change that
 * must also reach Convex goes through the same `putInTransaction` path, so an
 * email review and the transaction it creates commit together or not at all.
 */
class EmailRepository(
  private val db: DimoDatabase,
  private val entities: EntityWriter,
) {
  /** Monotonic clock injection point; tests substitute a fixed clock. */
  var now: () -> Long = { System.currentTimeMillis() }

  // MARK: - Accounts

  suspend fun accounts(): List<EmailAccountRecordModel> =
    db.emailAccounts().all().map { it.toModel() }

  suspend fun account(id: String): EmailAccountRecordModel? =
    db.emailAccounts().byId(id)?.toModel()

  fun observeAccounts(): Flow<List<EmailAccountRecordModel>> =
    db.emailAccounts().observeAll().map { rows -> rows.map { it.toModel() } }

  /**
   * Inserts or replaces local account metadata. The caller is responsible for
   * committing the matching refresh-token vault update before exposing a newly
   * connected account to the UI.
   */
  suspend fun saveAccount(account: EmailAccountRecordModel) {
    val id = account.id.trim()
    val email = account.emailAddress.trim()
    if (id.isEmpty() || !email.contains("@")) throw EmailRepositoryException(Kind.INVALID_ACCOUNT)
    val stamp = now()
    db.withTransaction {
      val current = db.emailAccounts().byId(id)
      val clean = account.copy(
        id = id,
        emailAddress = email,
        createdAt = current?.createdAt ?: account.createdAt.takeIf { it > 0 } ?: stamp,
        updatedAt = stamp,
      )
      db.emailAccounts().upsert(EmailAccountRecord.from(clean))
    }
    entities.notifyWrite()
  }

  /**
   * Mutates cursors and status in one write so cursor advancement cannot be
   * observed separately from its successful-sync timestamp.
   */
  suspend fun updateAccount(
    id: String,
    update: (EmailAccountRecordModel) -> EmailAccountRecordModel,
  ) {
    db.withTransaction {
      val record = db.emailAccounts().byId(id)
        ?: throw EmailRepositoryException(Kind.ACCOUNT_NOT_FOUND)
      val updated = update(record.toModel())
      val normalizedEmail = updated.emailAddress.trim()
      if (updated.id.trim() != id || !normalizedEmail.contains("@")) {
        throw EmailRepositoryException(Kind.INVALID_ACCOUNT)
      }
      db.emailAccounts().upsert(
        EmailAccountRecord.from(
          updated.copy(
            emailAddress = normalizedEmail,
            createdAt = record.createdAt,
            updatedAt = now(),
          ),
        ),
      )
    }
    entities.notifyWrite()
  }

  /**
   * Disconnect cleanup. OAuth credentials are deleted separately by the vault
   * owner; the database never stores them. Cascades to every local `emailMessages`
   * row for the account. Synced `emailMessage` entities are left alone so
   * reconnect can materialize them again.
   */
  suspend fun deleteAccount(id: String): Boolean {
    var deleted = false
    db.withTransaction {
      if (db.emailAccounts().byId(id) == null) return@withTransaction
      db.emailMessages().deleteByAccount(id)
      db.emailAccounts().deleteById(id)
      deleted = true
    }
    if (deleted) entities.notifyWrite()
    return deleted
  }

  /**
   * Copies active synced `emailMessage` entities for an account into the local
   * table. Call after reconnect so Gmail refresh sees reviewed keys and skips
   * re-analysis.
   */
  suspend fun materializeSyncedMessages(accountId: String) {
    db.withTransaction {
      if (db.emailAccounts().byId(accountId) == null) return@withTransaction
      for (stored in entities.fetchAllEmailMessages()) {
        if (stored.deleted) continue
        val entity = (stored.payload as? EntityPayload.EmailMessage)?.value ?: continue
        if (entity.accountId != accountId) continue
        upsertLocalMessage(entity)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Explicit local cleanup used alongside credential deletion. Normal Dimo
   * sign-out deletes the whole account-scoped database instead.
   */
  suspend fun deleteAllEmailData() {
    db.withTransaction {
      db.emailMessages().deleteAll()
      db.emailAccounts().deleteAll()
    }
    entities.notifyWrite()
  }

  // MARK: - Message ingest

  suspend fun insertPendingMessages(messages: List<PendingEmailMessage>): Int {
    if (messages.isEmpty()) return 0
    val stamp = now()
    var inserted = 0
    db.withTransaction {
      for (message in messages) {
        if (message.accountId.isEmpty() ||
          message.gmailMessageId.isEmpty() ||
          message.threadId.isEmpty() ||
          message.internalDate <= 0 ||
          db.emailAccounts().byId(message.accountId) == null
        ) {
          throw EmailRepositoryException(Kind.ACCOUNT_NOT_FOUND)
        }
        // Gmail messages are immutable for this feature. Never overwrite a
        // reviewed row or restore body text when a page is replayed.
        if (db.emailMessages().byKey(message.key) != null) continue
        db.emailMessages().upsert(EmailMessageRecord.pending(message, stamp))
        inserted += 1
      }
    }
    if (inserted > 0) entities.notifyWrite()
    return inserted
  }

  // MARK: - Message reads

  suspend fun message(key: String): EmailMessageRecordModel? =
    db.emailMessages().byKey(key)?.toModel()

  /**
   * Retained source emails for a transaction accepted from one or more grouped
   * suggestions, with the merchant receipt before the bank debit.
   */
  suspend fun messagesForTransaction(transactionId: String): List<EmailMessageRecordModel> =
    db.emailMessages().byLinkedTransaction(transactionId)
      .map { it.toModel() }
      .sortedWith(
        compareBy(
          { if (it.classification == EmailMessageClassification.PURCHASE) 0 else 1 },
          { it.internalDate },
          { it.key },
        ),
      )

  suspend fun messageForTransaction(transactionId: String): EmailMessageRecordModel? =
    messagesForTransaction(transactionId).firstOrNull()

  /**
   * The combined feed excludes queued and irrelevant messages. Those remain
   * available through the analysis queue or are compacted by retention.
   */
  suspend fun suggestions(
    filter: EmailLocalSuggestionFilter? = null,
    limit: Int = 200,
  ): List<EmailMessageRecordModel> {
    val states = suggestionStates(filter)
    val rows = db.emailMessages().byStates(states, maxOf(0, limit))
    return completeGroups(rows, states).map { it.toModel() }
  }

  fun observeSuggestions(
    filter: EmailLocalSuggestionFilter? = null,
    limit: Int = 200,
  ): Flow<List<EmailMessageRecordModel>> {
    val states = suggestionStates(filter)
    return db.emailMessages().observeByStates(states, maxOf(0, limit))
      .map { rows -> completeGroups(rows, states).map { it.toModel() } }
  }

  /**
   * A grouped purchase/debit pair must never appear half-visible, so members the
   * page limit clipped are pulled back in before sorting.
   */
  private suspend fun completeGroups(
    rows: List<EmailMessageRecord>,
    states: List<String>,
  ): List<EmailMessageRecord> {
    val visibleGroupIds = rows.mapNotNull { row ->
      row.purchaseGroupId?.takeIf { it != row.key }
    }.distinct()
    val complete = if (visibleGroupIds.isEmpty()) {
      rows
    } else {
      val existing = rows.map { it.key }.toSet()
      rows + db.emailMessages().byStatesAndGroups(states, visibleGroupIds)
        .filter { it.key !in existing }
    }
    return complete.sortedWith(compareByDescending<EmailMessageRecord> { it.internalDate }
      .thenBy { it.key })
  }

  /**
   * Reviewed purchase/debit sources used only for deterministic late-email
   * matching. This is intentionally not limited by the visible feed page.
   */
  suspend fun reviewedPurchaseSources(): List<EmailMessageRecordModel> =
    db.emailMessages().reviewedWithTransaction(EmailSuggestionState.ADDED.wire)
      .map { it.toModel() }
      .filter {
        it.classification == EmailMessageClassification.PURCHASE ||
          it.classification == EmailMessageClassification.DEBIT
      }

  /**
   * Pass an account ID with a small limit (normally one) while iterating the
   * connected accounts to implement fair, round-robin analysis.
   */
  suspend fun messagesPendingAnalysis(
    accountId: String? = null,
    limit: Int = 25,
  ): List<EmailMessageRecordModel> {
    val state = EmailSuggestionState.PENDING_ANALYSIS.wire
    val capped = maxOf(0, limit)
    val rows = if (accountId == null) {
      db.emailMessages().pendingAnalysis(state, capped)
    } else {
      db.emailMessages().pendingAnalysisForAccount(state, accountId, capped)
    }
    return rows.map { it.toModel() }
  }

  suspend fun messageSummaries(): List<EmailMessageSummaryModel> =
    db.emailMessages().summaries().map { it.toModel() }

  fun observeMessageSummaries(): Flow<List<EmailMessageSummaryModel>> =
    db.emailMessages().observeSummaries().map { rows -> rows.map { it.toModel() } }

  // MARK: - Settings and retry state

  suspend fun analysisSettings(): EmailAnalysisSettings {
    val record = db.emailAnalysisSettings().byId(EmailAnalysisSettings.SINGLETON_ID)
      ?: return EmailAnalysisSettings.defaults(now())
    val settings = record.toModel()
    // Only rewrite when the stored provider is the removed Local Gemma value.
    if (record.selectedProvider == "gemma") saveAnalysisSettings(settings)
    return settings
  }

  fun observeAnalysisSettings(): Flow<EmailAnalysisSettings> =
    db.emailAnalysisSettings().observeById(EmailAnalysisSettings.SINGLETON_ID)
      .map { it?.toModel() ?: EmailAnalysisSettings.defaults(now()) }

  suspend fun saveAnalysisSettings(settings: EmailAnalysisSettings) {
    db.emailAnalysisSettings().upsert(
      EmailAnalysisSettingsRecord.from(settings.copy(updatedAt = now())),
    )
  }

  suspend fun analysisRetryState(): EmailAnalysisRetryState? =
    db.emailAnalysisRetry().byId(EmailAnalysisRetryState.SINGLETON_ID)?.toModel()

  suspend fun saveAnalysisRetryState(state: EmailAnalysisRetryState) {
    db.emailAnalysisRetry().upsert(
      EmailAnalysisRetryRecord.from(state.copy(updatedAt = now())),
    )
  }

  suspend fun clearAnalysisRetryState() {
    db.emailAnalysisRetry().deleteById(EmailAnalysisRetryState.SINGLETON_ID)
  }

  // MARK: - Analysis lifecycle

  suspend fun setAnalysisProviderOverride(messageKey: String, provider: EmailAnalysisProvider?) {
    db.withTransaction {
      val record = requireUnreviewedWithBody(messageKey)
      db.emailMessages().upsert(
        record.copy(analysisProviderOverride = provider?.wire, updatedAt = now()),
      )
    }
    entities.notifyWrite()
  }

  suspend fun retryAnalysis(
    messageKey: String,
    providerOverride: EmailAnalysisProvider? = null,
  ) {
    db.withTransaction {
      var record = requireUnreviewedWithBody(messageKey)
      val stamp = now()
      val groupId = record.purchaseGroupId
      if (groupId != null && groupId != record.key) {
        // Re-analysis invalidates the pairing, so the whole group is ungrouped
        // and the change is pushed for every member.
        for (member in db.emailMessages().byPurchaseGroup(groupId)) {
          val ungrouped = member.copy(purchaseGroupId = null, updatedAt = stamp)
          db.emailMessages().upsert(ungrouped)
          putSyncedMessage(ungrouped)
        }
        record = db.emailMessages().byKey(messageKey)
          ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      }
      db.emailMessages().upsert(
        record.clearedAnalysis(stamp).copy(analysisProviderOverride = providerOverride?.wire),
      )
    }
    entities.notifyWrite()
  }

  /**
   * Returns every unreviewed message with retained content to the ordinary
   * analysis queue. Reviewed rows are intentionally excluded because their bodies
   * have been purged and their Dimo transaction effects must remain unchanged.
   */
  suspend fun resetMessagesForReanalysis(): Int {
    var count = 0
    db.withTransaction {
      val rows = db.emailMessages().unreviewedWithBody()
      val stamp = now()
      for (row in rows) {
        var current = row
        if (current.purchaseGroupId != null && current.purchaseGroupId != current.key) {
          current = current.copy(purchaseGroupId = null, updatedAt = stamp)
          db.emailMessages().upsert(current)
          putSyncedMessage(current)
        }
        db.emailMessages().upsert(
          current.clearedAnalysis(stamp).copy(analysisProviderOverride = null),
        )
      }
      count = rows.size
    }
    if (count > 0) entities.notifyWrite()
    return count
  }

  suspend fun saveAnalysis(messageKey: String, analysis: PersistedEmailAnalysis) {
    val stamp = now()
    db.withTransaction {
      val record = requireUnreviewedWithBody(messageKey)
      if (EmailSuggestionState.fromWire(record.state) != EmailSuggestionState.PENDING_ANALYSIS) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      if (analysis.promptVersion <= 0 ||
        analysis.analyzerType == app.dimo.android.data.model.EmailAnalyzerKind.RULES ||
        analysis.modelVersion.isNullOrEmpty()
      ) {
        throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
      }
      val amount = validateAmount(analysis.amount)
      analysis.occurredAt?.let { occurredAt ->
        if (occurredAt <= 0) throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
        val isSpend = analysis.classification == EmailMessageClassification.PURCHASE ||
          analysis.classification == EmailMessageClassification.DEBIT
        // A spend dated in the future is a parse error, not a real receipt.
        if (isSpend && occurredAt > stamp + FUTURE_TOLERANCE_MS) {
          throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
        }
      }
      validateIdentifiers(analysis.categoryId, analysis.paymentMethodId)

      val state = when (analysis.classification) {
        EmailMessageClassification.PURCHASE, EmailMessageClassification.DEBIT ->
          EmailSuggestionState.PENDING_PURCHASE
        EmailMessageClassification.REFUND -> EmailSuggestionState.PENDING_REFUND
        // Keep the full body so the user can still open and read the email.
        EmailMessageClassification.IRRELEVANT -> EmailSuggestionState.UNACTIONABLE
      }
      val updated = record.copy(
        analyzerType = analysis.analyzerType.wire,
        modelVersion = nonempty(analysis.modelVersion),
        promptVersion = analysis.promptVersion,
        classification = analysis.classification.wire,
        merchant = nonempty(analysis.merchant),
        amount = amount,
        currency = analysis.currency?.wire,
        occurredAt = analysis.occurredAt,
        categoryId = nonempty(analysis.categoryId),
        paymentMethodId = nonempty(analysis.paymentMethodId),
        paymentLastFour = nonempty(analysis.paymentLastFour),
        reference = nonempty(analysis.reference),
        analyzedAt = stamp,
        updatedAt = stamp,
        linkedTransactionId = null,
        analysisProviderOverride = null,
        state = state.wire,
      )
      db.emailMessages().upsert(updated)
      if (analysis.classification == EmailMessageClassification.PURCHASE ||
        analysis.classification == EmailMessageClassification.DEBIT
      ) {
        reconcilePendingPurchaseGroup(updated.key, stamp)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Records an analyzer failure without discarding the retained email body, so a
   * later explicit reanalysis can return the message to the ordinary queue.
   */
  suspend fun markAnalysisFailed(
    messageKey: String,
    analyzer: app.dimo.android.data.model.EmailAnalyzerKind? = null,
    modelVersion: String? = null,
  ) {
    db.withTransaction {
      val record = requireUnreviewedWithBody(messageKey)
      db.emailMessages().upsert(
        record.clearedAnalysis(now()).copy(
          analyzerType = analyzer?.wire,
          modelVersion = nonempty(modelVersion),
          state = EmailSuggestionState.ANALYSIS_FAILED.wire,
          analysisProviderOverride = null,
        ),
      )
    }
    entities.notifyWrite()
  }

  /**
   * Reconciles eligible pending rows that were analyzed before grouping was
   * available, or arrived through sync without a group decision.
   */
  suspend fun reconcilePendingPurchaseGroups(): Int {
    var grouped = 0
    db.withTransaction {
      val candidateKeys = db.emailMessages()
        .ungroupedInState(EmailSuggestionState.PENDING_PURCHASE.wire)
        .map { it.key }
      for (key in candidateKeys) {
        val before = db.emailMessages().byKey(key) ?: continue
        if (before.purchaseGroupId != null) continue
        reconcilePendingPurchaseGroup(key, now())
        if (db.emailMessages().byKey(key)?.purchaseGroupId != null) grouped += 1
      }
    }
    if (grouped > 0) entities.notifyWrite()
    return grouped
  }

  // MARK: - Review actions

  suspend fun dismissSuggestion(messageKey: String) = dismissSuggestions(listOf(messageKey))

  suspend fun dismissSuggestions(messageKeys: List<String>) {
    finishSuggestions(messageKeys, EmailSuggestionState.DISMISSED)
  }

  /**
   * Restores the analyzed result to the review queue. Body text is retained
   * through dismissal and Convex sync so restore does not need to rebuild it.
   */
  suspend fun restoreDismissedSuggestion(messageKey: String) =
    restoreDismissedSuggestions(listOf(messageKey))

  suspend fun restoreDismissedSuggestions(messageKeys: List<String>) {
    val stamp = now()
    db.withTransaction {
      val messages = messagesForAction(messageKeys)
      if (messages.size > 1) validatePurchaseGroup(messages)
      for (message in messages) {
        if (message.state != EmailSuggestionState.DISMISSED.wire) {
          throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
        }
        val classification = EmailMessageClassification.fromWire(message.classification)
          ?: throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
        val restored = when (classification) {
          EmailMessageClassification.PURCHASE, EmailMessageClassification.DEBIT ->
            EmailSuggestionState.PENDING_PURCHASE
          EmailMessageClassification.REFUND -> EmailSuggestionState.PENDING_REFUND
          EmailMessageClassification.IRRELEVANT ->
            throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
        }
        val updated = message.copy(
          state = restored.wire,
          linkedTransactionId = null,
          reviewedAt = null,
          updatedAt = stamp,
        )
        db.emailMessages().upsert(updated)
        putSyncedMessage(updated)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Marks a fetched or analyzed message as locally unusable without discarding the
   * retained body (so the email remains readable in the detail view).
   */
  suspend fun markSuggestionUnactionable(messageKey: String) {
    finishSuggestions(
      listOf(messageKey),
      EmailSuggestionState.UNACTIONABLE,
      allowedStates = setOf(
        EmailSuggestionState.PENDING_ANALYSIS,
        EmailSuggestionState.PENDING_PURCHASE,
        EmailSuggestionState.PENDING_REFUND,
      ),
      retainBody = true,
    )
  }

  /**
   * Creates the normal synced transaction and resolves the local suggestion in one
   * database transaction. No Gmail identifier enters the entity payload. The email
   * stays linked and retains its body on this device so the user can open the
   * source email from the transaction later.
   */
  suspend fun acceptSuggestion(
    messageKey: String,
    transaction: TransactionEntity,
    recurring: RecurringEntity? = null,
  ) = acceptSuggestions(listOf(messageKey), transaction, recurring)

  suspend fun acceptSuggestions(
    messageKeys: List<String>,
    transaction: TransactionEntity,
    recurring: RecurringEntity? = null,
  ) {
    if (transaction.amountMinor <= 0) throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
    db.withTransaction {
      val messages = messagesForAction(messageKeys)
      validatePurchaseGroup(messages)
      for (message in messages) {
        if (message.reviewedAt != null) {
          throw EmailRepositoryException(Kind.SUGGESTION_ALREADY_REVIEWED)
        }
        val isPendingPurchase = message.state == EmailSuggestionState.PENDING_PURCHASE.wire &&
          (
            message.classification == EmailMessageClassification.PURCHASE.wire ||
              message.classification == EmailMessageClassification.DEBIT.wire
            )
        if (!isPendingPurchase) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      validateIdentifiers(
        transaction.categoryId,
        transaction.paymentMethodId,
        requireCategory = true,
      )

      if (recurring != null) {
        if (recurring.amountMinor <= 0 ||
          recurring.categoryId != transaction.categoryId ||
          recurring.paymentMethodId != transaction.paymentMethodId
        ) {
          throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
        }
        validateIdentifiers(
          recurring.categoryId,
          recurring.paymentMethodId,
          requireCategory = true,
        )
        if (entities.fetchOne(entityKey(EntityType.RECURRING, recurring.id)) != null) {
          throw EmailRepositoryException(Kind.DUPLICATE_TRANSACTION)
        }
        entities.put(EntityPayload.Recurring(recurring))
      }

      if (entities.fetchOne(entityKey(EntityType.TRANSACTION, transaction.id)) != null) {
        throw EmailRepositoryException(Kind.DUPLICATE_TRANSACTION)
      }
      entities.put(EntityPayload.Transaction(transaction))
      entities.setLastPaymentMethodInTransaction(transaction.paymentMethodId)

      val stamp = now()
      for (message in messages) {
        val updated = message.copy(
          state = EmailSuggestionState.ADDED.wire,
          linkedTransactionId = transaction.id,
          reviewedAt = stamp,
          updatedAt = stamp,
        )
        db.emailMessages().upsert(updated)
        putSyncedMessage(updated)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Resolves a purchase suggestion against a transaction the user already
   * recorded. The existing transaction is left unchanged; the email row is marked
   * reviewed/linked and dual-written into the synced `emailMessage` entity.
   */
  suspend fun linkSuggestionToTransaction(messageKey: String, transactionId: String) =
    linkSuggestionsToTransaction(listOf(messageKey), transactionId)

  suspend fun linkSuggestionsToTransaction(messageKeys: List<String>, transactionId: String) {
    db.withTransaction {
      val messages = messagesForAction(messageKeys)
      validatePurchaseGroup(messages)
      for (message in messages) {
        if (message.reviewedAt != null) {
          throw EmailRepositoryException(Kind.SUGGESTION_ALREADY_REVIEWED)
        }
        val isPendingPurchase = message.state == EmailSuggestionState.PENDING_PURCHASE.wire &&
          (
            message.classification == EmailMessageClassification.PURCHASE.wire ||
              message.classification == EmailMessageClassification.DEBIT.wire
            )
        if (!isPendingPurchase) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      if (activeEntity(EntityType.TRANSACTION, transactionId) == null) {
        throw EmailRepositoryException(Kind.TRANSACTION_NOT_FOUND)
      }

      val stamp = now()
      for (message in messages) {
        val updated = message.copy(
          state = EmailSuggestionState.ADDED.wire,
          linkedTransactionId = transactionId,
          reviewedAt = stamp,
          updatedAt = stamp,
        )
        db.emailMessages().upsert(updated)
        putSyncedMessage(updated)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Links a late-arriving counterpart only after the user confirms the
   * deterministic match to a reviewed source email.
   */
  suspend fun linkLateSuggestion(messageKey: String, reviewedSourceKey: String) {
    db.withTransaction {
      val pending = db.emailMessages().byKey(messageKey)
        ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      val source = db.emailMessages().byKey(reviewedSourceKey)
        ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      val transactionId = source.linkedTransactionId
      val eligible = pending.state == EmailSuggestionState.PENDING_PURCHASE.wire &&
        pending.reviewedAt == null &&
        pending.linkedTransactionId == null &&
        source.state == EmailSuggestionState.ADDED.wire &&
        source.reviewedAt != null &&
        transactionId != null &&
        EmailPurchaseGroupingSelector.isEligiblePair(pending.toModel(), source.toModel())
      if (!eligible) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      if (activeEntity(EntityType.TRANSACTION, transactionId) == null) {
        throw EmailRepositoryException(Kind.TRANSACTION_NOT_FOUND)
      }

      val stamp = now()
      val groupId = EmailPurchaseGroupingSelector.groupId(pending.key, source.key)
      val updatedSource = source.copy(purchaseGroupId = groupId, updatedAt = stamp)
      val updatedPending = pending.copy(
        purchaseGroupId = groupId,
        state = EmailSuggestionState.ADDED.wire,
        linkedTransactionId = transactionId,
        reviewedAt = stamp,
        updatedAt = stamp,
      )
      db.emailMessages().upsert(updatedSource)
      db.emailMessages().upsert(updatedPending)
      putSyncedMessage(updatedSource)
      putSyncedMessage(updatedPending)
    }
    entities.notifyWrite()
  }

  /**
   * Persists the user's decision that automatically grouped emails are two
   * distinct purchases. Self group IDs prevent future reconciliation.
   */
  suspend fun separateSuggestions(messageKeys: List<String>) {
    db.withTransaction {
      val messages = messagesForAction(messageKeys)
      validatePurchaseGroup(messages)
      val allPending = messages.all {
        it.state == EmailSuggestionState.PENDING_PURCHASE.wire && it.reviewedAt == null
      }
      if (messages.size <= 1 || !allPending) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      val stamp = now()
      for (message in messages) {
        val updated = message.copy(purchaseGroupId = message.key, updatedAt = stamp)
        db.emailMessages().upsert(updated)
        putSyncedMessage(updated)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Keeps a late candidate in the ordinary purchase flow and suppresses any future
   * automatic match for this email.
   */
  suspend fun keepLateSuggestionSeparate(messageKey: String) {
    db.withTransaction {
      val message = db.emailMessages().byKey(messageKey)
        ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      if (message.state != EmailSuggestionState.PENDING_PURCHASE.wire ||
        message.reviewedAt != null
      ) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      val updated = message.copy(purchaseGroupId = message.key, updatedAt = now())
      db.emailMessages().upsert(updated)
      putSyncedMessage(updated)
    }
    entities.notifyWrite()
  }

  /**
   * Applies only an exact, same-currency, full refund within the 120-day matching
   * window. The ordinary transaction tombstone replaces any pending outbox edit
   * for that transaction key.
   */
  suspend fun applyFullRefund(messageKey: String, transactionId: String) {
    db.withTransaction {
      val message = db.emailMessages().byKey(messageKey)
        ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      if (message.reviewedAt != null) {
        throw EmailRepositoryException(Kind.SUGGESTION_ALREADY_REVIEWED)
      }
      if (message.state != EmailSuggestionState.PENDING_REFUND.wire ||
        message.classification != EmailMessageClassification.REFUND.wire
      ) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      val partialSource = listOf(
        message.subject,
        message.snippet,
        message.normalizedBodyText.orEmpty(),
      ).joinToString("\n")
      if (EmailSuggestionSelectors.isExplicitlyPartialRefund(partialSource)) {
        throw EmailRepositoryException(Kind.AMOUNT_MISMATCH)
      }

      val stored = activeEntity(EntityType.TRANSACTION, transactionId)
        ?: throw EmailRepositoryException(Kind.TRANSACTION_NOT_FOUND)
      val transaction = (stored.payload as? EntityPayload.Transaction)?.value
        ?: throw EmailRepositoryException(Kind.TRANSACTION_NOT_FOUND)

      if (message.currency != activeCurrency().wire) {
        throw EmailRepositoryException(Kind.CURRENCY_MISMATCH)
      }
      val refundMinor = message.amount?.let(::exactMinorUnits)
      if (refundMinor == null || refundMinor != transaction.amountMinor) {
        throw EmailRepositoryException(Kind.AMOUNT_MISMATCH)
      }

      val refundDate = message.occurredAt ?: message.internalDate
      if (transaction.occurredAt > refundDate ||
        refundDate - transaction.occurredAt > REFUND_WINDOW_MS
      ) {
        throw EmailRepositoryException(Kind.TRANSACTION_OUTSIDE_REFUND_WINDOW)
      }

      entities.put(EntityPayload.Transaction(transaction), deleted = true)
      val stamp = now()
      val updated = message.copy(
        state = EmailSuggestionState.REFUND_APPLIED.wire,
        linkedTransactionId = transactionId,
        reviewedAt = stamp,
        updatedAt = stamp,
      )
      db.emailMessages().upsert(updated)
      putSyncedMessage(updated)
    }
    entities.notifyWrite()
  }

  // MARK: - Retention

  /**
   * Marks rows outside the rolling window before deletion. Emails linked to an
   * accepted transaction are kept as a permanent reference and never expire.
   */
  suspend fun expireMessages(olderThan: Long): Int {
    var count = 0
    db.withTransaction {
      val rows = db.emailMessages().expirable(
        olderThan,
        EmailSuggestionState.EXPIRED.wire,
        SYNCED_STATES,
      )
      val stamp = now()
      for (row in rows) {
        db.emailMessages().upsert(
          row.copy(
            state = EmailSuggestionState.EXPIRED.wire,
            normalizedBodyText = null,
            reviewedAt = row.reviewedAt ?: stamp,
            updatedAt = stamp,
          ),
        )
      }
      count = rows.size
    }
    return count
  }

  /**
   * Removes compact message metadata after it leaves the caller-provided
   * rolling-window cutoff. No account cursor is affected.
   */
  suspend fun purgeMessages(olderThan: Long): Int =
    db.emailMessages().purgeOlderThan(olderThan, SYNCED_STATES)

  /**
   * Defensive maintenance: drop body text only for expired compact rows.
   * Unactionable and synced reviewed states keep the full body for reading.
   */
  suspend fun purgeReviewedBodies(): Int = db.emailMessages().purgeBodies(
    SYNCED_STATES + listOf(
      EmailSuggestionState.PENDING_ANALYSIS.wire,
      EmailSuggestionState.ANALYSIS_FAILED.wire,
      EmailSuggestionState.UNACTIONABLE.wire,
    ),
    now(),
  )

  // MARK: - Sync projection

  /**
   * Applies one pulled `emailMessage` entity to the device-local table. Called by
   * the sync adapter inside the pull transaction.
   */
  suspend fun projectRemoteMessage(remote: StoredEntity) {
    val entity = (remote.payload as? EntityPayload.EmailMessage)?.value ?: return
    if (remote.deleted) {
      db.emailMessages().deleteByKey(entity.id)
      return
    }
    // While Gmail is disconnected there is no account row; keep the entity in the
    // sync store and materialize only after reconnect.
    val account = db.emailAccounts().byId(entity.accountId) ?: return
    val trimmed = entity.accountEmail.trim()
    if (trimmed.isNotEmpty() && account.emailAddress != trimmed) {
      db.emailAccounts().upsert(account.copy(emailAddress = trimmed, updatedAt = now()))
    }
    upsertLocalMessage(entity)
  }

  /**
   * Dismisses email rows still pointing at a transaction the user deleted
   * elsewhere, so the Email tab cannot link to a tombstoned row.
   */
  suspend fun dismissMessagesLinkedToDeletedTransaction(transactionId: String) {
    val linked = db.emailMessages()
      .byLinkedTransactionAndState(transactionId, EmailSuggestionState.ADDED.wire)
    if (linked.isEmpty()) return
    val stamp = now()
    for (message in linked) {
      val updated = message.copy(
        state = EmailSuggestionState.DISMISSED.wire,
        linkedTransactionId = null,
        reviewedAt = message.reviewedAt ?: stamp,
        updatedAt = stamp,
      )
      db.emailMessages().upsert(updated)
      putSyncedMessage(updated)
    }
  }

  // MARK: - Private

  private suspend fun finishSuggestions(
    messageKeys: List<String>,
    state: EmailSuggestionState,
    allowedStates: Set<EmailSuggestionState> = setOf(
      EmailSuggestionState.PENDING_PURCHASE,
      EmailSuggestionState.PENDING_REFUND,
    ),
    retainBody: Boolean = false,
  ) {
    db.withTransaction {
      val messages = messagesForAction(messageKeys)
      if (messages.size > 1) validatePurchaseGroup(messages)
      val stamp = now()
      val synced = state.wire in SYNCED_STATES
      for (message in messages) {
        if (message.reviewedAt != null) {
          throw EmailRepositoryException(Kind.SUGGESTION_ALREADY_REVIEWED)
        }
        val current = EmailSuggestionState.fromWire(message.state)
        if (current == null || current !in allowedStates) {
          throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
        }
        val updated = message.copy(
          state = state.wire,
          // Keep the full body for synced reviewed/dismissed rows so Convex and
          // Restore retain the complete email text, not only the snippet.
          normalizedBodyText = if (!retainBody && !synced) null else message.normalizedBodyText,
          reviewedAt = stamp,
          updatedAt = stamp,
        )
        db.emailMessages().upsert(updated)
        if (synced) putSyncedMessage(updated)
      }
    }
    entities.notifyWrite()
  }

  /**
   * Resolves the rows an action applies to. Passing one member of a grouped pair
   * expands to the whole group, so a group can never be half-reviewed.
   */
  private suspend fun messagesForAction(messageKeys: List<String>): List<EmailMessageRecord> {
    val keys = messageKeys.distinct()
    if (keys.isEmpty() || keys.size != messageKeys.size) {
      throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
    }
    var messages = keys.map { key ->
      db.emailMessages().byKey(key) ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
    }
    val sharedGroupIds = messages
      .mapNotNull { message -> message.purchaseGroupId?.takeIf { it != message.key } }
      .distinct()
    if (sharedGroupIds.size > 1) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
    val groupId = sharedGroupIds.firstOrNull()
    if (groupId != null) {
      if (messages.any { it.purchaseGroupId != groupId }) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      messages = db.emailMessages().byPurchaseGroup(groupId)
    }
    return messages.sortedBy { it.key }
  }

  private fun validatePurchaseGroup(messages: List<EmailMessageRecord>) {
    if (messages.isEmpty()) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
    if (messages.size == 1) {
      val message = messages[0]
      if (message.purchaseGroupId != null && message.purchaseGroupId != message.key) {
        throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
      }
      return
    }
    val groupIds = messages.mapNotNull { it.purchaseGroupId }.toSet()
    val classifications = messages.mapNotNull { it.classification }.toSet()
    val groupId = groupIds.firstOrNull()
    val valid = messages.size == 2 &&
      classifications == setOf(
        EmailMessageClassification.PURCHASE.wire,
        EmailMessageClassification.DEBIT.wire,
      ) &&
      messages.map { it.accountId }.toSet().size == 1 &&
      groupIds.size == 1 &&
      groupId != null &&
      groupId == EmailPurchaseGroupingSelector.groupId(messages[0].key, messages[1].key) &&
      messages.all { it.purchaseGroupId == groupId && groupId != it.key }
    if (!valid) throw EmailRepositoryException(Kind.INVALID_SUGGESTION_STATE)
  }

  private suspend fun reconcilePendingPurchaseGroup(messageKey: String, stamp: Long) {
    val target = db.emailMessages().byKey(messageKey)
      ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
    val pending = db.emailMessages()
      .inStateForAccount(EmailSuggestionState.PENDING_PURCHASE.wire, target.accountId)
      .map { it.toModel() }
    val pair = EmailPurchaseGroupingSelector.reciprocalPendingPair(messageKey, pending) ?: return
    for (key in pair.messageIds) {
      val message = db.emailMessages().byKey(key)
        ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
      val updated = message.copy(purchaseGroupId = pair.groupId, updatedAt = stamp)
      db.emailMessages().upsert(updated)
      putSyncedMessage(updated)
    }
  }

  private suspend fun requireUnreviewedWithBody(messageKey: String): EmailMessageRecord {
    val record = db.emailMessages().byKey(messageKey)
      ?: throw EmailRepositoryException(Kind.MESSAGE_NOT_FOUND)
    if (record.reviewedAt != null || record.normalizedBodyText == null) {
      throw EmailRepositoryException(Kind.SUGGESTION_ALREADY_REVIEWED)
    }
    return record
  }

  private suspend fun validateIdentifiers(
    categoryId: String?,
    paymentMethodId: String?,
    requireCategory: Boolean = false,
  ) {
    val category = nonempty(categoryId)
    if (requireCategory && category == null) {
      throw EmailRepositoryException(Kind.INVALID_CATEGORY)
    }
    if (category != null && activeEntity(EntityType.CATEGORY, category) == null) {
      throw EmailRepositoryException(Kind.INVALID_CATEGORY)
    }
    val method = nonempty(paymentMethodId)
    if (method != null && activeEntity(EntityType.PAYMENT_METHOD, method) == null) {
      throw EmailRepositoryException(Kind.INVALID_PAYMENT_METHOD)
    }
  }

  private suspend fun activeEntity(type: EntityType, id: String): StoredEntity? =
    entities.fetchOne(entityKey(type, id))?.takeIf { !it.deleted }

  private suspend fun activeCurrency(): Currency {
    val stored = activeEntity(EntityType.PREFERENCES, PREFERENCES_ID) ?: return DEFAULT_CURRENCY
    val preferences = (stored.payload as? EntityPayload.Preferences)?.value
    return preferences?.currency ?: DEFAULT_CURRENCY
  }

  /** Dual-writes a reviewed row into the synced `emailMessage` entity + outbox. */
  private suspend fun putSyncedMessage(message: EmailMessageRecord) {
    if (message.state !in SYNCED_STATES) return
    val accountEmail = db.emailAccounts().byId(message.accountId)?.emailAddress ?: ""
    entities.put(
      EntityPayload.EmailMessage(
        EmailMessageEntity(
          id = message.key,
          accountId = message.accountId,
          accountEmail = accountEmail,
          gmailMessageId = message.gmailMessageId,
          threadId = message.threadId,
          rfcMessageId = message.rfcMessageId,
          senderName = message.senderName,
          senderAddress = message.senderAddress,
          subject = message.subject,
          snippet = message.snippet,
          internalDate = message.internalDate,
          normalizedBodyText = message.normalizedBodyText,
          analyzerType = message.analyzerType,
          modelVersion = message.modelVersion,
          promptVersion = message.promptVersion,
          classification = message.classification,
          merchant = message.merchant,
          amount = message.amount,
          currency = message.currency,
          occurredAt = message.occurredAt,
          categoryId = message.categoryId,
          paymentMethodId = message.paymentMethodId,
          paymentLastFour = message.paymentLastFour,
          reference = message.reference,
          state = message.state,
          purchaseGroupId = message.purchaseGroupId,
          linkedTransactionId = message.linkedTransactionId,
          analyzedAt = message.analyzedAt,
          reviewedAt = message.reviewedAt,
          createdAt = message.createdAt,
          updatedAt = message.updatedAt,
        ),
      ),
    )
  }

  private suspend fun upsertLocalMessage(entity: EmailMessageEntity) {
    val existing = db.emailMessages().byKey(entity.id)
    db.emailMessages().upsert(
      EmailMessageRecord(
        key = entity.id,
        accountId = entity.accountId,
        gmailMessageId = entity.gmailMessageId,
        threadId = entity.threadId,
        rfcMessageId = entity.rfcMessageId,
        senderName = entity.senderName,
        senderAddress = entity.senderAddress,
        subject = entity.subject,
        snippet = entity.snippet,
        internalDate = entity.internalDate,
        // Prefer the synced full body; fall back to a local body when the cloud
        // row predates body sync and still has an empty body field.
        normalizedBodyText = entity.normalizedBodyText ?: existing?.normalizedBodyText,
        analysisProviderOverride = existing?.analysisProviderOverride,
        analyzerType = entity.analyzerType,
        modelVersion = entity.modelVersion,
        promptVersion = entity.promptVersion,
        classification = entity.classification,
        merchant = entity.merchant,
        amount = entity.amount,
        currency = entity.currency,
        occurredAt = entity.occurredAt,
        categoryId = entity.categoryId,
        paymentMethodId = entity.paymentMethodId,
        paymentLastFour = entity.paymentLastFour,
        reference = entity.reference,
        state = entity.state,
        purchaseGroupId = entity.purchaseGroupId,
        linkedTransactionId = entity.linkedTransactionId,
        analyzedAt = entity.analyzedAt,
        reviewedAt = entity.reviewedAt,
        createdAt = entity.createdAt,
        updatedAt = entity.updatedAt,
      ),
    )
  }

  private fun validateAmount(value: String?): String? {
    val trimmed = nonempty(value) ?: return null
    if (exactMinorUnits(trimmed) == null) {
      throw EmailRepositoryException(Kind.INVALID_ANALYSIS)
    }
    return trimmed
  }

  companion object {
    private const val PREFERENCES_ID = "preferences"
    private val DEFAULT_CURRENCY = Currency.INR

    /** A spend timestamp may run at most this far ahead of the clock. */
    private const val FUTURE_TOLERANCE_MS = 5L * 60 * 1000

    /** How long after a purchase a refund email can still match it. */
    private const val REFUND_WINDOW_MS = 120L * 24 * 60 * 60 * 1000

    /** States that exist in Convex; everything else is device-local. */
    val SYNCED_STATES = listOf(
      EmailSuggestionState.ADDED.wire,
      EmailSuggestionState.DISMISSED.wire,
      EmailSuggestionState.REFUND_APPLIED.wire,
      EmailSuggestionState.PENDING_PURCHASE.wire,
      EmailSuggestionState.PENDING_REFUND.wire,
    )

    fun suggestionStates(filter: EmailLocalSuggestionFilter?): List<String> = when (filter) {
      EmailLocalSuggestionFilter.PURCHASES -> listOf(EmailSuggestionState.PENDING_PURCHASE.wire)
      EmailLocalSuggestionFilter.REFUNDS -> listOf(EmailSuggestionState.PENDING_REFUND.wire)
      EmailLocalSuggestionFilter.REVIEWED -> listOf(
        EmailSuggestionState.ADDED.wire,
        EmailSuggestionState.REFUND_APPLIED.wire,
        EmailSuggestionState.DISMISSED.wire,
      )
      null -> listOf(
        EmailSuggestionState.PENDING_PURCHASE.wire,
        EmailSuggestionState.PENDING_REFUND.wire,
        EmailSuggestionState.ADDED.wire,
        EmailSuggestionState.REFUND_APPLIED.wire,
        EmailSuggestionState.DISMISSED.wire,
      )
    }

    private fun nonempty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

    /**
     * Parses canonical base-unit decimal text (`1234.50`) to minor units, rejecting
     * anything that is not an exact non-negative amount with at most two decimals.
     */
    fun exactMinorUnits(value: String): Long? {
      val trimmed = value.trim()
      if (!AMOUNT_TEXT.matches(trimmed)) return null
      val decimal = runCatching { BigDecimal(trimmed) }.getOrNull() ?: return null
      if (decimal.signum() <= 0) return null
      val scaled = runCatching { decimal.movePointRight(2).setScale(0, RoundingMode.UNNECESSARY) }
        .getOrNull() ?: return null
      return runCatching { scaled.longValueExact() }.getOrNull()
    }

    private val AMOUNT_TEXT = Regex("^\\d+(?:\\.\\d{1,2})?$")
  }
}

/** Clears every analyzer-produced field and returns the row to the queue. */
private fun EmailMessageRecord.clearedAnalysis(stamp: Long) = copy(
  analyzerType = null,
  modelVersion = null,
  promptVersion = null,
  classification = null,
  merchant = null,
  amount = null,
  currency = null,
  occurredAt = null,
  categoryId = null,
  paymentMethodId = null,
  paymentLastFour = null,
  reference = null,
  state = EmailSuggestionState.PENDING_ANALYSIS.wire,
  linkedTransactionId = null,
  analyzedAt = null,
  updatedAt = stamp,
)

/**
 * The slice of [Repository] the email surface needs: entity reads plus the
 * transactional entity+outbox write. Keeping it as an interface lets email logic
 * be tested without standing up the whole repository.
 */
interface EntityWriter {
  suspend fun fetchOne(key: String): StoredEntity?
  suspend fun fetchAllEmailMessages(): List<StoredEntity>
  suspend fun put(payload: EntityPayload, deleted: Boolean = false)
  suspend fun setLastPaymentMethodInTransaction(id: String?)
  fun notifyWrite()
}
