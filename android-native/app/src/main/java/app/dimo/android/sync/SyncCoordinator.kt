package app.dimo.android.sync

import app.dimo.android.data.Repository
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.WORKSPACE_ID
import app.dimo.android.domain.RateTable
import java.util.UUID
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Port of the `SyncCoordinator` actor in
 * `ios-native/Dimo/Sync/SyncCoordinator.swift`.
 *
 * The canonical cycle is: ensure workspace profile → pull all → backfills →
 * enqueue untouched bootstrap defaults → push pending → pull again. A Kotlin
 * `Mutex` plus the `requested` re-entry flag reproduces the Swift actor's
 * single-flight behaviour.
 */
class SyncCoordinator(
  private val repository: Repository,
  private val transport: SyncTransport,
  private val network: NetworkMonitorLike,
  private val scope: CoroutineScope,
) {
  /** Minimal surface so tests can drive connectivity without Android. */
  interface NetworkMonitorLike {
    val isOnline: Boolean
    fun start(onReconnect: () -> Unit)
    fun stop()
  }

  private val mutex = Mutex()

  @Volatile
  private var requested = false

  @Volatile
  private var fullReplace = false

  private var running: Job? = null
  private var debounceJob: Job? = null
  private var retryJob: Job? = null
  private var revisionJob: Job? = null
  private var writeListener: UUID? = null
  private var retryAttempt = 0

  private var profileName: String? = null
  private var profileEmail: String? = null

  fun setProfile(name: String?, email: String?) {
    profileName = name?.trim()?.takeIf { it.isNotEmpty() }
    profileEmail = email?.trim()?.takeIf { it.isNotEmpty() }
  }

  fun start() {
    scope.launch {
      // Recover from an interrupted sync (a kill mid-flight leaves syncing=true
      // and disables "Sync now" in settings).
      runCatching {
        repository.updateSyncMeta { meta ->
          if (meta.syncing) {
            meta.copy(syncing = false, error = meta.error ?: "Sync interrupted")
          } else {
            meta
          }
        }
      }

      writeListener = repository.onLocalWrite { schedule() }
      network.start { request() }

      revisionJob = scope.launch {
        transport.revisions(WORKSPACE_ID).collectLatest { revision ->
          remoteRevisionChanged(revision)
        }
      }
      request()
    }
  }

  fun stop() {
    writeListener?.let { repository.removeLocalWriteListener(it) }
    writeListener = null
    revisionJob?.cancel()
    revisionJob = null
    network.stop()
    debounceJob?.cancel()
    retryJob?.cancel()
    running?.cancel()
  }

  /** Coalesces bursts of local writes into one sync. */
  fun schedule() {
    debounceJob?.cancel()
    debounceJob = scope.launch {
      delay(DEBOUNCE_MS)
      request()
    }
  }

  fun request(cancelInFlight: Boolean = false) {
    if (cancelInFlight) {
      running?.cancel()
      running = null
      retryJob?.cancel()
    }
    requested = true
    if (running?.isActive == true) return
    running = scope.launch {
      runLoop()
      running = null
      if (requested) request()
    }
  }

  fun requestFullSync() {
    fullReplace = true
    request(cancelInFlight = true)
  }

  /** Latest ECB rates from Convex (Frankfurter is server-only, once per day). */
  suspend fun latestExchangeRates(): RateTable? = transport.latestExchangeRates()

  /**
   * Deletes cloud rows for the types Android owns.
   *
   * `emailMessage` is absent from [EntityType] on Android on purpose: this client
   * holds no email rows, so clearing that type would destroy the user's iOS email
   * suggestions with nothing to re-upload in their place.
   */
  suspend fun clearCloudWorkspace() {
    while (true) {
      val result = transport.clearWorkspace(WORKSPACE_ID, EntityType.entries, CLEAR_PAGE)
      if (!result.hasMore) return
    }
  }

  private suspend fun remoteRevisionChanged(revision: Long) {
    // The subscription re-emits on reconnect and re-auth; only kick a sync when
    // the server is genuinely ahead, otherwise the UI reads as forever "Syncing".
    val pulled = runCatching { repository.syncMeta()?.lastPulledRevision }.getOrNull() ?: 0L
    if (revision > pulled) request()
  }

  private suspend fun runLoop() = mutex.withLock {
    while (requested) {
      requested = false
      val replace = fullReplace
      fullReplace = false

      if (!network.isOnline) {
        runCatching {
          repository.updateSyncMeta { it.copy(syncing = false, error = "Offline") }
        }
        return@withLock
      }

      runCatching { repository.updateSyncMeta { it.copy(syncing = true, error = null) } }

      try {
        // Backfill workspace name/email on every authenticated sync: WorkOS JWTs
        // omit those claims, so the profile is passed explicitly.
        transport.ensureWorkspaceProfile(WORKSPACE_ID, profileName, profileEmail)

        if (replace) {
          repository.backfillRecurringCurrencies()
          repository.backfillMissingPaymentMethodIds()
          clearRemote()
          repository.updateSyncMeta {
            it.copy(lastPulledRevision = 0, pulledRevisions = emptyMap())
          }
          repository.enqueueFullUpload()
          pushAll()
          pullAll()
        } else {
          pullAll()
          repository.backfillRecurringCurrencies()
          repository.backfillMissingPaymentMethodIds()
          // Upload bootstrap defaults only if the pull left them unsynced (an
          // empty workspace). Avoids fresh null-budget seeds overwriting cloud data.
          repository.enqueueUnsyncedDefaults()
          pushAll()
          pullAll()
        }

        retryAttempt = 0
        retryJob?.cancel()
        repository.purgeExpiredTombstones()
        val blocked = repository.blockedOutbox()
        repository.updateSyncMeta { meta ->
          meta.copy(
            syncing = false,
            error = blocked?.lastError,
            lastSyncedAt = if (blocked == null) System.currentTimeMillis() else meta.lastSyncedAt,
          )
        }
      } catch (cancellation: CancellationException) {
        runCatching { repository.updateSyncMeta { it.copy(syncing = false) } }
        throw cancellation
      } catch (error: Throwable) {
        if (replace) fullReplace = true
        runCatching {
          repository.updateSyncMeta {
            it.copy(syncing = false, error = error.message ?: error.toString())
          }
        }
        scheduleRetry()
        return@withLock
      }
    }
  }

  private suspend fun clearRemote() {
    while (true) {
      val result = transport.clearWorkspace(WORKSPACE_ID, EntityType.entries, CLEAR_PAGE)
      if (!result.hasMore) return
    }
  }

  private suspend fun pullAll() {
    for (entityType in EntityType.entries) {
      pullType(entityType)
    }
  }

  private suspend fun pullType(entityType: EntityType) {
    val meta = repository.syncMeta()
    var cursor = meta?.pulledRevisions?.get(entityType) ?: meta?.lastPulledRevision ?: 0L
    while (true) {
      val page = transport.pull(entityType, WORKSPACE_ID, cursor, PULL_PAGE)
      val pageCursor = if (page.entities.isEmpty()) {
        page.latestRevision
      } else {
        page.entities.maxOf { it.serverRevision }
      }
      repository.mergeRemotePage(page.entities, entityType, pageCursor)
      cursor = pageCursor
      if (!page.hasMore) break
    }
  }

  private suspend fun pushAll() {
    while (true) {
      val pending = repository.pendingOutbox(limit = PENDING_SCAN)
      if (pending.isEmpty()) return
      var pushed = false
      for ((entityType, ops) in pending.groupBy { it.entityType }) {
        var index = 0
        while (index < ops.size) {
          val batch = ops.subList(index, min(index + MAX_BATCH, ops.size))
          pushBatch(entityType, batch)
          pushed = true
          index += MAX_BATCH
        }
      }
      if (!pushed) return
    }
  }

  /**
   * Pushes one batch, isolating a permanently bad operation by bisection.
   *
   * Retryable failures bump `attempts` and rethrow so the caller's backoff runs;
   * only a payload Convex will never accept gets parked as `blocked`.
   */
  private suspend fun pushBatch(entityType: EntityType, operations: List<SyncOperation>) {
    try {
      val result = transport.push(entityType, WORKSPACE_ID, operations)
      repository.acknowledgeOperations(result.acknowledgedOperationIds)
    } catch (cancellation: CancellationException) {
      throw cancellation
    } catch (error: Throwable) {
      val message = error.message ?: error.toString()
      if (!isPermanentSyncError(message)) {
        for (operation in operations) {
          repository.updateOutbox(
            operation.copy(attempts = operation.attempts + 1, lastError = message),
          )
        }
        throw error
      }
      if (operations.size > 1) {
        val mid = maxOf(1, operations.size / 2)
        pushBatch(entityType, operations.subList(0, mid))
        pushBatch(entityType, operations.subList(mid, operations.size))
        return
      }
      val operation = operations[0]
      repository.updateOutbox(
        operation.copy(
          attempts = operation.attempts + 1,
          lastError = message,
          status = OutboxStatus.BLOCKED,
        ),
      )
    }
  }

  private fun scheduleRetry() {
    retryJob?.cancel()
    val base = min(MAX_BACKOFF_MS, 1000.0 * 2.0.pow(retryAttempt))
    retryAttempt += 1
    val delayMs = base * (0.75 + Random.nextDouble() * 0.5)
    retryJob = scope.launch {
      delay(delayMs.toLong())
      request()
    }
  }

  private companion object {
    const val DEBOUNCE_MS = 250L
    const val MAX_BACKOFF_MS = 300_000.0
    const val MAX_BATCH = 50
    const val PULL_PAGE = 100
    const val CLEAR_PAGE = 100
    const val PENDING_SCAN = 500
  }
}
