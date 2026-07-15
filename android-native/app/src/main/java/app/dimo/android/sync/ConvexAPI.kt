package app.dimo.android.sync

import app.dimo.android.data.PayloadCodec
import app.dimo.android.data.RemoteEntity
import app.dimo.android.data.model.EntityType
import app.dimo.android.data.model.LogicalVersion
import app.dimo.android.data.model.SyncOperation
import app.dimo.android.data.model.WORKSPACE_ID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.roundToInt
import kotlin.math.roundToLong

object ConvexAPI {
  private val permanentPatterns = listOf(
    "ArgumentValidationError",
    "Payload does not match",
    "Entity ID mismatch",
    "Workspace mismatch",
    "Unsupported workspace",
    "Invalid logical version",
    "Invalid minor-unit amount",
    "Invalid recurring anchor date",
    "A push may contain at most 50",
  )

  fun isPermanentSyncError(message: String): Boolean =
    permanentPatterns.any { message.contains(it) }

  fun pushArgs(operations: List<SyncOperation>): Map<String, Any?> = mapOf(
    "workspaceId" to WORKSPACE_ID,
    "operations" to operations.map {
      PayloadCodec.toWireMap(
        type = it.entityType,
        payload = it.payload,
        version = it.version,
        deleted = it.deleted,
        operationId = it.operationId,
        entityId = it.entityId,
      )
    },
  )

  fun pullArgs(afterRevision: Long, limit: Int): Map<String, Any?> = mapOf(
    "workspaceId" to WORKSPACE_ID,
    "afterRevision" to afterRevision.toDouble(),
    "limit" to limit.toDouble(),
  )

  fun profileArgs(name: String?, email: String?): Map<String, Any?> = buildMap {
    put("workspaceId", WORKSPACE_ID)
    if (name != null) put("name", name)
    if (email != null) put("email", email)
  }

  fun clearArgs(types: List<EntityType>, limit: Int): Map<String, Any?> = mapOf(
    "workspaceId" to WORKSPACE_ID,
    "entityTypes" to types.map { it.wire },
    "limit" to limit.toDouble(),
  )

  fun revisionArgs(): Map<String, Any?> = mapOf("workspaceId" to WORKSPACE_ID)

  fun parsePull(raw: Any?): PullResult {
    val obj = asJsonObject(raw)
    val entities = obj["entities"]?.jsonArray?.map { el ->
      val e = el.jsonObject
      val type = EntityType.fromWire(e.string("entityType"))
      val versionObj = e["version"]!!.jsonObject
      RemoteEntity(
        workspaceId = e.string("workspaceId"),
        entityType = type,
        entityId = e.string("entityId"),
        version = LogicalVersion(
          timestamp = versionObj.long("timestamp"),
          counter = versionObj.int("counter"),
          deviceId = versionObj.string("deviceId"),
        ),
        payload = PayloadCodec.decodePayload(type, e["payload"]!!.toString()),
        deleted = e.boolean("deleted"),
        serverRevision = e.long("serverRevision"),
      )
    }.orEmpty()
    return PullResult(
      entities = entities,
      latestRevision = obj.long("latestRevision"),
      hasMore = obj.boolean("hasMore"),
    )
  }

  fun parsePushAcks(raw: Any?): List<String> {
    val obj = asJsonObject(raw)
    return obj["acknowledgements"]?.jsonArray?.mapNotNull {
      it.jsonObject["operationId"]?.jsonPrimitive?.contentOrNull
    }.orEmpty()
  }

  fun parseClear(raw: Any?): Pair<Int, Boolean> {
    val obj = asJsonObject(raw)
    return obj.int("deleted") to obj.boolean("hasMore")
  }

  fun parseRevision(raw: Any?): Long = when (raw) {
    is Number -> raw.toLong()
    is String -> raw.toDoubleOrNull()?.toLong() ?: 0L
    else -> asJsonObject(raw).longOrNull("revision")
      ?: Json.parseToJsonElement(raw.toString()).jsonPrimitive.doubleOrNull?.toLong()
      ?: 0L
  }

  private fun asJsonObject(raw: Any?): JsonObject {
    if (raw is JsonObject) return raw
    val text = when (raw) {
      null -> "{}"
      is String -> raw
      else -> raw.toString()
    }
    return Json.parseToJsonElement(text).jsonObject
  }

  private fun JsonObject.string(key: String) = this[key]!!.jsonPrimitive.content
  private fun JsonObject.boolean(key: String) = this[key]?.jsonPrimitive?.booleanOrNull ?: false
  private fun JsonObject.int(key: String) = this[key]?.jsonPrimitive?.doubleOrNull?.roundToInt() ?: 0
  private fun JsonObject.long(key: String) = this[key]?.jsonPrimitive?.doubleOrNull?.roundToLong() ?: 0L
  private fun JsonObject.longOrNull(key: String) = this[key]?.jsonPrimitive?.doubleOrNull?.roundToLong()
}

data class PullResult(
  val entities: List<RemoteEntity>,
  val latestRevision: Long,
  val hasMore: Boolean,
)
