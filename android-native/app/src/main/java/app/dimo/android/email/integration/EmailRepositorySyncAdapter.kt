package app.dimo.android.email.integration

import app.dimo.android.data.EmailRepository
import app.dimo.android.data.model.EmailAccountRecordModel
import app.dimo.android.data.model.EmailAccountSyncState
import app.dimo.android.data.model.PendingEmailMessage
import app.dimo.android.email.gmail.EmailAccountSnapshot
import app.dimo.android.email.gmail.EmailMessagePayload
import app.dimo.android.email.gmail.EmailSyncPersistence
import app.dimo.android.email.gmail.GmailSyncState

/**
 * Port of `ios-native/Dimo/Email/Integration/EmailRepositorySyncAdapter.swift`.
 *
 * Bridges Gmail synchronization to the account-scoped, local-only email tables.
 * The repository supplied here must belong to the signed-in Dimo user; the user
 * identifier passed by the coordinator is used by Gmail's credential layer and is
 * intentionally not persisted with email records.
 */
class EmailRepositorySyncAdapter(
  private val repository: EmailRepository,
) : EmailSyncPersistence {

  override suspend fun emailAccountsForSync(dimoUserId: String): List<EmailAccountSnapshot> =
    // Repository databases are already scoped by the WorkOS user identifier.
    // Keeping the argument out of SQLite prevents duplicating account identity in
    // the local-only Gmail schema.
    repository.accounts()
      // Skip disconnected stubs and accounts waiting for an in-place Gmail reauth.
      .filter {
        it.syncState != EmailAccountSyncState.DISCONNECTED &&
          it.syncState != EmailAccountSyncState.NEEDS_RECONNECT
      }
      .map { account ->
        EmailAccountSnapshot(
          googleSubject = account.id,
          emailAddress = account.emailAddress,
          historyId = account.historyId,
          backfillPageToken = account.backfillPageToken,
          backfillCompletedAt = account.backfillCompletedAt,
        )
      }

  override suspend fun recordEmailSyncAttempt(
    accountSubject: String,
    at: Long,
    state: GmailSyncState,
  ) {
    repository.updateAccount(accountSubject) { account ->
      account.copy(
        lastAttemptAt = at,
        syncState = repositorySyncState(state, account),
        lastError = null,
      )
    }
  }

  override suspend fun storePendingEmailMessages(messages: List<EmailMessagePayload>) {
    repository.insertPendingMessages(
      messages.map { message ->
        PendingEmailMessage(
          accountId = message.accountSubject,
          gmailMessageId = message.gmailMessageId,
          threadId = message.gmailThreadId,
          rfcMessageId = message.rfcMessageId,
          senderName = message.senderName,
          senderAddress = message.senderAddress,
          subject = message.subject,
          snippet = message.snippet,
          internalDate = message.internalDate,
          normalizedBodyText = message.normalizedBody,
        )
      },
    )
  }

  override suspend fun advanceEmailBackfill(
    accountSubject: String,
    nextPageToken: String?,
    completedAt: Long?,
    historyId: String?,
  ) {
    repository.updateAccount(accountSubject) { account ->
      account.copy(
        backfillPageToken = nextPageToken,
        backfillCompletedAt = completedAt,
        historyId = historyId ?: account.historyId,
        syncState = if (nextPageToken == null) {
          EmailAccountSyncState.SYNCING
        } else {
          EmailAccountSyncState.BACKFILLING
        },
      )
    }
  }

  override suspend fun advanceEmailHistory(accountSubject: String, historyId: String) {
    repository.updateAccount(accountSubject) { it.copy(historyId = historyId) }
  }

  override suspend fun resetEmailBackfill(accountSubject: String) {
    repository.updateAccount(accountSubject) { account ->
      account.copy(
        historyId = null,
        backfillPageToken = null,
        backfillCompletedAt = null,
        syncState = EmailAccountSyncState.BACKFILLING,
        lastError = null,
      )
    }
  }

  override suspend fun finishEmailSync(
    accountSubject: String,
    at: Long,
    state: GmailSyncState,
    error: String?,
  ) {
    repository.updateAccount(accountSubject) { account ->
      account.copy(
        syncState = repositorySyncState(state, account),
        lastError = if (state == GmailSyncState.NEEDS_RECONNECT) {
          error ?: "Gmail access expired or was revoked. Reconnect this account to continue."
        } else {
          error
        },
        lastSuccessfulSyncAt = if (state == GmailSyncState.IDLE && error == null) {
          at
        } else {
          account.lastSuccessfulSyncAt
        },
      )
    }
  }

  override suspend fun abandonEmailSync(accountSubject: String) {
    repository.updateAccount(accountSubject) { account ->
      // Only an interrupted in-flight state is cleared; a failure or reconnect
      // prompt recorded by this run must survive.
      if (account.syncState == EmailAccountSyncState.SYNCING ||
        account.syncState == EmailAccountSyncState.BACKFILLING
      ) {
        account.copy(syncState = EmailAccountSyncState.IDLE, lastError = null)
      } else {
        account
      }
    }
  }
}

/**
 * Maps the coordinator's transient state onto the persisted one. `syncing` stays
 * `backfilling` while a page token remains, so the UI does not claim the initial
 * scan finished early.
 */
fun repositorySyncState(
  state: GmailSyncState,
  account: EmailAccountRecordModel,
): EmailAccountSyncState = when (state) {
  GmailSyncState.IDLE -> EmailAccountSyncState.IDLE
  GmailSyncState.BACKFILLING -> EmailAccountSyncState.BACKFILLING
  GmailSyncState.SYNCING -> if (account.backfillPageToken == null) {
    EmailAccountSyncState.SYNCING
  } else {
    EmailAccountSyncState.BACKFILLING
  }

  GmailSyncState.RATE_LIMITED -> EmailAccountSyncState.RATE_LIMITED
  GmailSyncState.OFFLINE -> EmailAccountSyncState.OFFLINE
  GmailSyncState.NEEDS_RECONNECT -> EmailAccountSyncState.NEEDS_RECONNECT
  GmailSyncState.FAILED -> EmailAccountSyncState.FAILED
}
