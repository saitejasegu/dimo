package app.dimo.android.sync

import app.dimo.android.auth.WorkOSSession
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.domain.RateTable
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Network boundary for sync. Kept behind an interface so [SyncCoordinator] can be
 * exercised in unit tests without a Convex deployment.
 */
interface SyncTransport {
  suspend fun currentRevision(workspaceId: String): Long

  suspend fun pull(
    entityType: EntityType,
    workspaceId: String,
    afterRevision: Long,
    limit: Int,
  ): PullResult

  suspend fun push(
    entityType: EntityType,
    workspaceId: String,
    operations: List<SyncOperation>,
  ): PushResult

  suspend fun ensureWorkspaceProfile(workspaceId: String, name: String?, email: String?)

  suspend fun clearWorkspace(
    workspaceId: String,
    entityTypes: List<EntityType>,
    limit: Int,
  ): ClearResult

  suspend fun latestExchangeRates(): RateTable?

  fun revisions(workspaceId: String): Flow<Long>
}

/** Port of `ConvexSyncTransport` in `ios-native/Dimo/Sync/SyncCoordinator.swift`. */
class ConvexSyncTransport(
  private val client: ConvexClientWithAuth<WorkOSSession>,
) : SyncTransport {

  override suspend fun currentRevision(workspaceId: String): Long =
    firstValue("syncTyped:currentRevision", ConvexAPI.revisionArgs(workspaceId))
      .primitiveLong()

  override suspend fun pull(
    entityType: EntityType,
    workspaceId: String,
    afterRevision: Long,
    limit: Int,
  ): PullResult {
    val json = firstValue(
      ConvexAPI.pullPath(entityType),
      ConvexAPI.pullArgs(workspaceId, afterRevision, limit),
    ) as? JsonObject ?: return PullResult(emptyList(), afterRevision, false)

    val entities = (json["entities"] as? JsonArray).orEmpty().mapNotNull { element ->
      val row = (element as? JsonObject)?.toKotlinMap() ?: return@mapNotNull null
      ConvexAPI.storedEntityFrom(entityType, row)
    }
    return PullResult(
      entities = entities,
      latestRevision = json["latestRevision"].primitiveLong(),
      hasMore = (json["hasMore"] as? JsonPrimitive)?.booleanOrNull ?: false,
    )
  }

  override suspend fun push(
    entityType: EntityType,
    workspaceId: String,
    operations: List<SyncOperation>,
  ): PushResult {
    val json = withTimeout(TIMEOUT_MS) {
      client.mutation<JsonObject>(
        ConvexAPI.pushPath(entityType),
        ConvexAPI.pushArgs(workspaceId, operations),
      )
    }
    val acks = (json["acknowledgements"] as? JsonArray).orEmpty().mapNotNull { element ->
      ((element as? JsonObject)?.get("operationId") as? JsonPrimitive)?.content
    }
    return PushResult(acks)
  }

  override suspend fun ensureWorkspaceProfile(
    workspaceId: String,
    name: String?,
    email: String?,
  ) {
    withTimeout(TIMEOUT_MS) {
      client.mutation<JsonObject>(
        "syncTyped:ensureWorkspaceProfile",
        ConvexAPI.profileArgs(workspaceId, name, email),
      )
    }
  }

  override suspend fun clearWorkspace(
    workspaceId: String,
    entityTypes: List<EntityType>,
    limit: Int,
  ): ClearResult {
    val json = withTimeout(TIMEOUT_MS) {
      client.mutation<JsonObject>(
        "syncTyped:clearWorkspace",
        ConvexAPI.clearArgs(workspaceId, entityTypes, limit),
      )
    }
    return ClearResult(hasMore = (json["hasMore"] as? JsonPrimitive)?.booleanOrNull ?: false)
  }

  override suspend fun latestExchangeRates(): RateTable? {
    val json = firstValue("exchangeRates:latest", emptyMap()) as? JsonObject ?: return null
    val rates = (json["rates"] as? JsonObject)?.mapNotNull { (code, value) ->
      val rate = (value as? JsonPrimitive)?.doubleOrNull ?: return@mapNotNull null
      code to rate
    }?.toMap() ?: return null
    return RateTable(
      date = (json["date"] as? JsonPrimitive)?.content ?: "",
      base = (json["base"] as? JsonPrimitive)?.content ?: "EUR",
      rates = rates,
    )
  }

  override fun revisions(workspaceId: String): Flow<Long> =
    client.subscribe<JsonElement>(
      "syncTyped:currentRevision",
      ConvexAPI.revisionArgs(workspaceId),
    ).map { result -> result.getOrNull().primitiveLong() }

  private suspend fun firstValue(name: String, args: Map<String, Any?>): JsonElement? =
    withTimeout(TIMEOUT_MS) {
      client.subscribe<JsonElement>(name, args).first().getOrThrow()
    }

  private companion object {
    const val TIMEOUT_MS = 45_000L
  }
}

private fun JsonArray?.orEmpty(): List<JsonElement> = this ?: emptyList()

private fun JsonElement?.primitiveLong(): Long {
  val primitive = this as? JsonPrimitive ?: return 0L
  return primitive.longOrNull ?: primitive.doubleOrNull?.toLong() ?: 0L
}

/** Flattens a pulled row so [ConvexAPI.storedEntityFrom] can read plain Kotlin values. */
internal fun JsonObject.toKotlinMap(): Map<String, Any?> = mapValues { (_, value) ->
  value.toKotlinValue()
}

private fun JsonElement.toKotlinValue(): Any? = when (this) {
  is JsonNull -> null
  is JsonPrimitive -> when {
    isString -> content
    else -> booleanOrNull ?: longOrNull ?: doubleOrNull ?: content
  }

  is JsonObject -> toKotlinMap()
  is JsonArray -> map { it.toKotlinValue() }
}
