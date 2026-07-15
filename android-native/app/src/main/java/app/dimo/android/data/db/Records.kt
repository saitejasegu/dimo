package app.dimo.android.data.db

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
  tableName = "entities",
  indices = [
    Index(value = ["workspaceId", "entityType"]),
    Index(value = ["workspaceId", "serverRevision"]),
  ],
)
data class EntityRecord(
  @PrimaryKey val key: String,
  val workspaceId: String,
  val entityType: String,
  val entityId: String,
  val versionJson: String,
  val payloadJson: String,
  val deleted: Boolean,
  val serverRevision: Long,
)

@Entity(
  tableName = "outbox",
  indices = [
    Index(value = ["status"]),
    Index(value = ["createdAt"]),
    Index(value = ["operationId"], unique = true),
  ],
)
data class OutboxRecord(
  @PrimaryKey val key: String,
  val operationId: String,
  val workspaceId: String,
  val entityType: String,
  val entityId: String,
  val versionJson: String,
  val payloadJson: String,
  val deleted: Boolean,
  val status: String,
  val attempts: Int,
  val lastError: String?,
  val createdAt: Long,
)

@Entity(tableName = "sync_meta")
data class SyncMetaRecord(
  @PrimaryKey val workspaceId: String,
  val lastPulledRevision: Long,
  val lastSyncedAt: Long?,
  val error: String?,
  val syncing: Boolean,
)

@Entity(tableName = "device_meta")
data class DeviceMetaRecord(
  @PrimaryKey val id: String,
  val deviceId: String,
  val clockTimestamp: Long,
  val clockCounter: Int,
  val bootstrapVersion: Int,
  val lastPaymentMethodId: String?,
)
