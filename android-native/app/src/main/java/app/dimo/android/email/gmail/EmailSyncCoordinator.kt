package app.dimo.android.email.gmail

import app.dimo.android.data.model.EmailSyncWindow
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield
import kotlin.coroutines.coroutineContext

/**
 * Port of `ios-native/Dimo/Email/Gmail/EmailSyncCoordinator.swift`.
 *
 * Synchronizes mailbox pages round-robin so one large inbox cannot starve the
 * others. A failing mailbox is dropped from the current run without preventing
 * the remaining accounts from progressing.
 */
enum class GmailSyncState(val wire: String) {
  IDLE("idle"),
  BACKFILLING("backfilling"),
  SYNCING("syncing"),
  RATE_LIMITED("rateLimited"),
  OFFLINE("offline"),
  NEEDS_RECONNECT("needsReconnect"),
  FAILED("failed"),
}

data class EmailAccountSnapshot(
  val googleSubject: String,
  val emailAddress: String,
  val historyId: String? = null,
  val backfillPageToken: String? = null,
  val backfillCompletedAt: Long? = null,
)

data class EmailMessagePayload(
  val accountSubject: String,
  val gmailMessageId: String,
  val gmailThreadId: String,
  val rfcMessageId: String?,
  val senderName: String?,
  val senderAddress: String,
  val subject: String,
  val snippet: String,
  val internalDate: Long,
  val normalizedBody: String,
)

/**
 * Persistence boundary for account-scoped, local-only email tables.
 * Implementations must not create Dimo entities or outbox operations here.
 */
interface EmailSyncPersistence {
  suspend fun emailAccountsForSync(dimoUserId: String): List<EmailAccountSnapshot>
  suspend fun recordEmailSyncAttempt(accountSubject: String, at: Long, state: GmailSyncState)
  suspend fun storePendingEmailMessages(messages: List<EmailMessagePayload>)
  suspend fun advanceEmailBackfill(
    accountSubject: String,
    nextPageToken: String?,
    completedAt: Long?,
    historyId: String?,
  )

  suspend fun advanceEmailHistory(accountSubject: String, historyId: String)
  suspend fun resetEmailBackfill(accountSubject: String)
  suspend fun finishEmailSync(
    accountSubject: String,
    at: Long,
    state: GmailSyncState,
    error: String?,
  )

  /** Clears an interrupted syncing/backfilling state without claiming success. */
  suspend fun abandonEmailSync(accountSubject: String)
}

class EmailSyncCoordinator(
  private val api: GmailAPIClient,
  private val persistence: EmailSyncPersistence,
  private val scope: CoroutineScope,
) {
  private sealed interface Work {
    val account: EmailAccountSnapshot

    data class Backfill(
      override val account: EmailAccountSnapshot,
      val pageToken: String?,
    ) : Work

    data class Incremental(
      override val account: EmailAccountSnapshot,
      val startHistoryId: String,
      val pageToken: String?,
    ) : Work
  }

  private val refreshLock = Mutex()
  private val scheduledRetries = ConcurrentHashMap<String, Job>()

  @Volatile
  private var stopRequested = false

  @Volatile
  private var refreshInProgress = false

  suspend fun refresh(
    dimoUserId: String,
    accountSubject: String? = null,
    syncWindow: EmailSyncWindow = EmailSyncWindow.DEFAULT,
    now: Long = System.currentTimeMillis(),
  ) {
    // A second refresh while one is running is a no-op, not a queue: the running
    // pass already covers every account.
    if (!refreshLock.tryLock()) return
    refreshInProgress = true
    try {
      stopRequested = false
      val all = runCatching { persistence.emailAccountsForSync(dimoUserId) }.getOrNull() ?: return
      val accounts = accountSubject?.let { selected ->
        all.filter { it.googleSubject == selected }
      } ?: all
      accounts.forEach { scheduledRetries.remove(it.googleSubject)?.cancel() }

      var work = accounts.map { account ->
        if (account.backfillCompletedAt == null || account.historyId == null) {
          Work.Backfill(account, account.backfillPageToken)
        } else {
          Work.Incremental(account, account.historyId, null)
        }
      }
      for (account in accounts) {
        val state = if (account.backfillCompletedAt == null || account.historyId == null) {
          GmailSyncState.BACKFILLING
        } else {
          GmailSyncState.SYNCING
        }
        runCatching { persistence.recordEmailSyncAttempt(account.googleSubject, now, state) }
      }

      while (work.isNotEmpty() && !stopRequested && coroutineContext.isActive) {
        val nextRound = mutableListOf<Work>()
        for (item in work) {
          if (stopRequested || !coroutineContext.isActive) break
          try {
            processOnePage(item, dimoUserId, syncWindow, now)?.let(nextRound::add)
          } catch (_: GmailAPIException.HistoryCursorExpired) {
            // The cursor is gone; a full re-scan is the only way to catch up.
            runCatching { persistence.resetEmailBackfill(item.account.googleSubject) }
            nextRound.add(
              Work.Backfill(
                item.account.copy(
                  historyId = null,
                  backfillPageToken = null,
                  backfillCompletedAt = null,
                ),
                null,
              ),
            )
          } catch (error: GmailOAuthException.RequiresReconnect) {
            runCatching {
              persistence.finishEmailSync(
                item.account.googleSubject,
                System.currentTimeMillis(),
                GmailSyncState.NEEDS_RECONNECT,
                error.message,
              )
            }
          } catch (error: GmailAPIException.RateLimited) {
            runCatching {
              persistence.finishEmailSync(
                item.account.googleSubject,
                System.currentTimeMillis(),
                GmailSyncState.RATE_LIMITED,
                null,
              )
            }
            scheduleRetry(
              dimoUserId,
              item.account.googleSubject,
              syncWindow,
              error.retryAfterSeconds ?: 60.0,
            )
          } catch (_: CancellationException) {
            abandonInFlightAccounts(accounts)
            throw CancellationException("Gmail refresh cancelled")
          } catch (error: IOException) {
            runCatching {
              persistence.finishEmailSync(
                item.account.googleSubject,
                System.currentTimeMillis(),
                GmailSyncState.OFFLINE,
                "Gmail will refresh when this device is online.",
              )
            }
          } catch (error: Exception) {
            runCatching {
              persistence.finishEmailSync(
                item.account.googleSubject,
                System.currentTimeMillis(),
                GmailSyncState.FAILED,
                error.message ?: "Gmail sync failed.",
              )
            }
          }
        }
        work = nextRound
      }

      if (stopRequested || !coroutineContext.isActive) abandonInFlightAccounts(accounts)
    } finally {
      refreshInProgress = false
      refreshLock.unlock()
    }
  }

  suspend fun stop() {
    stopRequested = true
    scheduledRetries.values.forEach { it.cancel() }
    scheduledRetries.clear()
    while (refreshInProgress) yield()
  }

  // MARK: - Private

  private suspend fun abandonInFlightAccounts(accounts: List<EmailAccountSnapshot>) {
    for (account in accounts) {
      runCatching { persistence.abandonEmailSync(account.googleSubject) }
    }
  }

  private fun scheduleRetry(
    dimoUserId: String,
    accountSubject: String,
    syncWindow: EmailSyncWindow,
    requestedDelaySeconds: Double,
  ) {
    scheduledRetries.remove(accountSubject)?.cancel()
    val delayMs = (requestedDelaySeconds.coerceIn(5.0, 300.0) * 1000).toLong()
    scheduledRetries[accountSubject] = scope.launch {
      delay(delayMs)
      // Wait out any refresh that started in the meantime rather than bouncing
      // off the lock and losing the retry.
      while (refreshInProgress) delay(1_000)
      scheduledRetries.remove(accountSubject)
      refresh(dimoUserId, accountSubject, syncWindow)
    }
  }

  private suspend fun processOnePage(
    work: Work,
    dimoUserId: String,
    syncWindow: EmailSyncWindow,
    now: Long,
  ): Work? = when (work) {
    is Work.Backfill -> {
      var account = work.account
      // Capture the cursor before the scan. Starting incremental history from this
      // point after the scan closes the race with messages that arrive while paged
      // backfill is in progress.
      if (account.historyId == null) {
        val profile = api.profile(account.googleSubject, dimoUserId)
        account = account.copy(historyId = profile.historyId)
        persistence.advanceEmailBackfill(
          accountSubject = account.googleSubject,
          nextPageToken = work.pageToken,
          completedAt = null,
          historyId = profile.historyId,
        )
      }
      val page = api.listMessages(
        subject = account.googleSubject,
        dimoUserId = dimoUserId,
        since = syncWindow.cutoff(now),
        pageToken = work.pageToken,
      )
      fetchAndPersist(page.messages.map { it.id }, account.googleSubject, dimoUserId, syncWindow, now)
      val nextPageToken = page.nextPageToken
      if (nextPageToken != null) {
        persistence.advanceEmailBackfill(
          accountSubject = account.googleSubject,
          nextPageToken = nextPageToken,
          completedAt = null,
          historyId = null,
        )
        Work.Backfill(account, nextPageToken)
      } else {
        val capturedHistoryId = account.historyId ?: throw GmailAPIException.InvalidResponse
        persistence.advanceEmailBackfill(
          accountSubject = account.googleSubject,
          nextPageToken = null,
          completedAt = System.currentTimeMillis(),
          historyId = capturedHistoryId,
        )
        Work.Incremental(account, capturedHistoryId, null)
      }
    }

    is Work.Incremental -> {
      val page = api.listHistory(
        subject = work.account.googleSubject,
        dimoUserId = dimoUserId,
        startHistoryId = work.startHistoryId,
        pageToken = work.pageToken,
      )
      fetchAndPersist(
        page.addedMessageIds,
        work.account.googleSubject,
        dimoUserId,
        syncWindow,
        now,
      )
      val nextPageToken = page.nextPageToken
      if (nextPageToken != null) {
        Work.Incremental(work.account, work.startHistoryId, nextPageToken)
      } else {
        persistence.advanceEmailHistory(work.account.googleSubject, page.latestHistoryId)
        persistence.finishEmailSync(
          work.account.googleSubject,
          System.currentTimeMillis(),
          GmailSyncState.IDLE,
          null,
        )
        null
      }
    }
  }

  private suspend fun fetchAndPersist(
    ids: List<String>,
    accountSubject: String,
    dimoUserId: String,
    syncWindow: EmailSyncWindow,
    now: Long,
  ) {
    if (ids.isEmpty()) return
    val resources = api.getMessages(accountSubject, dimoUserId, ids)
    val messages = mutableListOf<EmailMessagePayload>()
    for (resource in resources) {
      val labels = resource.labelIds.orEmpty().toSet()
      if (labels.contains("SPAM") || labels.contains("TRASH")) continue

      val resolvedBodies = mutableMapOf<String, ByteArray>()
      for (attachmentId in GmailMessageParser.unresolvedBodyAttachmentIds(resource)) {
        // Keep going with whatever inline body Gmail already returned.
        val data = runCatching {
          api.getAttachmentData(accountSubject, dimoUserId, resource.id, attachmentId)
        }.getOrNull() ?: continue
        resolvedBodies[attachmentId] = data
      }

      val parsed = runCatching { GmailMessageParser.parse(resource, resolvedBodies) }.getOrNull()
        ?: continue
      if (!syncWindow.contains(parsed.internalDate, now)) continue
      messages.add(
        EmailMessagePayload(
          accountSubject = accountSubject,
          gmailMessageId = parsed.gmailMessageId,
          gmailThreadId = parsed.gmailThreadId,
          rfcMessageId = parsed.rfcMessageId,
          senderName = parsed.senderName,
          senderAddress = parsed.senderAddress,
          subject = parsed.subject,
          snippet = parsed.snippet,
          internalDate = parsed.internalDate,
          normalizedBody = parsed.normalizedBody,
        ),
      )
    }
    if (messages.isNotEmpty()) persistence.storePendingEmailMessages(messages)
  }
}
