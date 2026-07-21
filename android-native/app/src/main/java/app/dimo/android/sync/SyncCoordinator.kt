package app.dimo.android.sync

import app.dimo.android.data.Repository
import app.dimo.android.data.model.CLEAR_PAGE_SIZE
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.OUTBOX_PAGE_SIZE
import app.dimo.android.data.model.OutboxStatus
import app.dimo.android.data.model.PULL_PAGE_SIZE
import app.dimo.android.data.model.SyncOperation
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlin.math.min
import kotlin.random.Random

class SyncCoordinator(
  private val repository: Repository,
  private val client: ConvexClientWithAuth<*>,
  private val networkMonitor: NetworkMonitor,
  private val scope: CoroutineScope,
  private val profileName: () -> String?,
  private val profileEmail: () -> String?,
) {
  private val mutex = Mutex()
  private var requested = false
  private var fullReplace = false
  private var retryAttempt = 0
  private var debounceJob: Job? = null
  private var revisionJob: Job? = null
  private var writeJob: Job? = null
  private var loopJob: Job? = null

  fun start() {
    networkMonitor.onOnline = { request() }
    networkMonitor.start()
    writeJob = scope.launch {
      repository.localWrites.collectLatest { schedule() }
    }
    revisionJob = scope.launch(Dispatchers.IO) {
      client.subscribe<JsonElement>("sync:currentRevision", ConvexAPI.revisionArgs())
        .collect { result ->
          result.onSuccess { value ->
            val revision = ConvexAPI.parseRevision(value)
            val pulled = repository.syncMeta().lastPulledRevision
            if (revision > pulled) request()
          }
        }
    }
    request()
  }

  fun stop() {
    debounceJob?.cancel()
    revisionJob?.cancel()
    writeJob?.cancel()
    loopJob?.cancel()
    networkMonitor.stop()
  }

  fun schedule() {
    debounceJob?.cancel()
    debounceJob = scope.launch {
      delay(250)
      request()
    }
  }

  fun request() {
    requested = true
    if (loopJob?.isActive == true) return
    loopJob = scope.launch(Dispatchers.IO) { runLoop() }
  }

  fun requestFullSync() {
    fullReplace = true
    request()
  }

  fun sceneBecameActive() {
    request()
  }

  suspend fun clearRemoteAll() {
    clearRemote(EntityType.entries)
  }

  private suspend fun runLoop() {
    while (requested) {
      if (!mutex.tryLock()) return
      try {
        requested = false
        val replace = fullReplace
        fullReplace = false
        try {
          if (!networkMonitor.online.value) {
            val meta = repository.syncMeta()
            repository.updateSyncMeta(meta.copy(syncing = false, error = "Offline"))
            continue
          }
          repository.updateSyncMeta(repository.syncMeta().copy(syncing = true, error = null))
          ensureProfile()
          if (replace) {
            clearRemote(EntityType.entries)
            repository.updateSyncMeta(repository.syncMeta().copy(lastPulledRevision = 0))
            repository.enqueueFullUpload(EntityType.entries)
            pushAll()
            pullAll()
          } else {
            pullAll()
            repository.enqueueUnsyncedDefaults()
            pushAll()
            pullAll()
          }
          retryAttempt = 0
          repository.purgeExpiredTombstones()
          val blocked = repository.blockedOutbox()
          val meta = repository.syncMeta()
          if (blocked != null) {
            repository.updateSyncMeta(meta.copy(syncing = false, error = blocked.lastError))
          } else {
            repository.updateSyncMeta(
              meta.copy(syncing = false, error = null, lastSyncedAt = System.currentTimeMillis()),
            )
          }
        } catch (e: Exception) {
          if (replace) fullReplace = true
          val meta = repository.syncMeta()
          repository.updateSyncMeta(meta.copy(syncing = false, error = e.message))
          scheduleRetry()
        }
      } finally {
        mutex.unlock()
      }
    }
  }

  private suspend fun scheduleRetry() {
    val base = min(300_000.0, 1000.0 * Math.pow(2.0, retryAttempt.toDouble()))
    retryAttempt++
    val delayMs = (base * (0.75 + Random.nextDouble(0.0, 0.5))).toLong()
    delay(delayMs)
    request()
  }

  private suspend fun ensureProfile() {
    client.mutation<JsonElement>(
      "sync:ensureWorkspaceProfile",
      ConvexAPI.profileArgs(profileName(), profileEmail()),
    )
  }

  private suspend fun pullAll() {
    var cursor = repository.syncMeta().lastPulledRevision
    while (true) {
      val page = oneShotQuery("sync:pull", ConvexAPI.pullArgs(cursor, PULL_PAGE_SIZE))
      val parsed = ConvexAPI.parsePull(page)
      val nextCursor = if (parsed.entities.isEmpty()) {
        parsed.latestRevision
      } else {
        maxOf(parsed.entities.maxOf { it.serverRevision }, parsed.latestRevision)
      }
      repository.mergeRemotePage(parsed.entities, nextCursor)
      cursor = nextCursor
      if (!parsed.hasMore) break
    }
  }

  private suspend fun pushAll() {
    while (true) {
      val ops = repository.pendingOutbox(OUTBOX_PAGE_SIZE)
      if (ops.isEmpty()) break
      pushBatch(ops)
    }
  }

  private suspend fun pushBatch(ops: List<SyncOperation>) {
    try {
      val raw = client.mutation<JsonElement>("sync:push", ConvexAPI.pushArgs(ops))
      val acks = ConvexAPI.parsePushAcks(raw)
      repository.acknowledgeOperations(acks)
    } catch (e: Exception) {
      val message = e.message.orEmpty()
      if (!ConvexAPI.isPermanentSyncError(message)) {
        for (op in ops) {
          repository.updateOutbox(op.copy(attempts = op.attempts + 1, lastError = message))
        }
        throw e
      }
      if (ops.size > 1) {
        val mid = maxOf(1, ops.size / 2)
        pushBatch(ops.take(mid))
        pushBatch(ops.drop(mid))
      } else {
        val op = ops.first()
        repository.updateOutbox(
          op.copy(status = OutboxStatus.blocked, lastError = message, attempts = op.attempts + 1),
        )
      }
    }
  }

  private suspend fun clearRemote(types: List<EntityType>) {
    var hasMore = true
    while (hasMore) {
      val raw = client.mutation<JsonElement>(
        "sync:clearWorkspace",
        ConvexAPI.clearArgs(types, CLEAR_PAGE_SIZE),
      )
      hasMore = ConvexAPI.parseClear(raw).second
    }
  }

  private suspend fun oneShotQuery(name: String, args: Map<String, Any?>): JsonElement =
    withContext(Dispatchers.IO) {
      val result = client.subscribe<JsonElement>(name, args).first()
      result.getOrThrow()
    }
}
