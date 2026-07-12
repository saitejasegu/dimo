import Foundation
import GRDB

enum PayloadCodec {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }()

  static func encode(_ payload: EntityPayload) throws -> Data {
    switch payload {
    case .category(let value): return try encoder.encode(value)
    case .paymentMethod(let value): return try encoder.encode(value)
    case .transaction(let value): return try encoder.encode(value)
    case .recurring(let value): return try encoder.encode(value)
    case .preferences(let value): return try encoder.encode(value)
    }
  }

  static func decode(entityType: EntityType, data: Data) throws -> EntityPayload {
    switch entityType {
    case .category: return .category(try decoder.decode(CategoryEntity.self, from: data))
    case .paymentMethod: return .paymentMethod(try decoder.decode(PaymentMethodEntity.self, from: data))
    case .transaction: return .transaction(try decoder.decode(TransactionEntity.self, from: data))
    case .recurring: return .recurring(try decoder.decode(RecurringEntity.self, from: data))
    case .preferences: return .preferences(try decoder.decode(PreferencesEntity.self, from: data))
    }
  }

  static func encodeVersion(_ version: LogicalVersion) throws -> Data {
    try encoder.encode(version)
  }

  static func decodeVersion(_ data: Data) throws -> LogicalVersion {
    try decoder.decode(LogicalVersion.self, from: data)
  }
}

struct EntityRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "entities"

  var key: String
  var workspaceId: String
  var entityType: String
  var entityId: String
  var version: Data
  var payload: Data
  var deleted: Bool
  var serverRevision: Int

  func toStoredEntity() throws -> StoredEntity {
    let type = EntityType(rawValue: entityType) ?? .transaction
    return StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: type,
      entityId: entityId,
      version: try PayloadCodec.decodeVersion(version),
      payload: try PayloadCodec.decode(entityType: type, data: payload),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> EntityRecord {
    EntityRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityType: entity.entityType.rawValue,
      entityId: entity.entityId,
      version: try PayloadCodec.encodeVersion(entity.version),
      payload: try PayloadCodec.encode(entity.payload),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision
    )
  }
}

struct OutboxRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "outbox"

  var key: String
  var operationId: String
  var workspaceId: String
  var entityType: String
  var entityId: String
  var version: Data
  var payload: Data
  var deleted: Bool
  var status: String
  var attempts: Int
  var lastError: String?
  var createdAt: Int

  func toSyncOperation() throws -> SyncOperation {
    let type = EntityType(rawValue: entityType) ?? .transaction
    return SyncOperation(
      operationId: operationId,
      key: key,
      workspaceId: workspaceId,
      entityType: type,
      entityId: entityId,
      version: try PayloadCodec.decodeVersion(version),
      payload: try PayloadCodec.decode(entityType: type, data: payload),
      deleted: deleted,
      status: OutboxStatus(rawValue: status) ?? .pending,
      attempts: attempts,
      lastError: lastError,
      createdAt: createdAt
    )
  }

  static func from(_ op: SyncOperation) throws -> OutboxRecord {
    OutboxRecord(
      key: op.key,
      operationId: op.operationId,
      workspaceId: op.workspaceId,
      entityType: op.entityType.rawValue,
      entityId: op.entityId,
      version: try PayloadCodec.encodeVersion(op.version),
      payload: try PayloadCodec.encode(op.payload),
      deleted: op.deleted,
      status: op.status.rawValue,
      attempts: op.attempts,
      lastError: op.lastError,
      createdAt: op.createdAt
    )
  }
}

struct SyncMetaRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "syncMeta"

  var workspaceId: String
  var lastPulledRevision: Int
  var lastSyncedAt: Int?
  var error: String?
  var syncing: Bool

  func toSyncMeta() -> SyncMeta {
    SyncMeta(
      workspaceId: workspaceId,
      lastPulledRevision: lastPulledRevision,
      lastSyncedAt: lastSyncedAt,
      error: error,
      syncing: syncing
    )
  }

  static func from(_ meta: SyncMeta) -> SyncMetaRecord {
    SyncMetaRecord(
      workspaceId: meta.workspaceId,
      lastPulledRevision: meta.lastPulledRevision,
      lastSyncedAt: meta.lastSyncedAt,
      error: meta.error,
      syncing: meta.syncing
    )
  }
}

struct DeviceMetaRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "deviceMeta"

  var id: String
  var deviceId: String
  var clockTimestamp: Int
  var clockCounter: Int
  var bootstrapVersion: Int
  var lastPaymentMethodId: String?

  func toDeviceMeta() -> DeviceMeta {
    DeviceMeta(
      id: id,
      deviceId: deviceId,
      clockTimestamp: clockTimestamp,
      clockCounter: clockCounter,
      bootstrapVersion: bootstrapVersion,
      lastPaymentMethodId: lastPaymentMethodId
    )
  }

  static func from(_ meta: DeviceMeta) -> DeviceMetaRecord {
    DeviceMetaRecord(
      id: meta.id,
      deviceId: meta.deviceId,
      clockTimestamp: meta.clockTimestamp,
      clockCounter: meta.clockCounter,
      bootstrapVersion: meta.bootstrapVersion,
      lastPaymentMethodId: meta.lastPaymentMethodId
    )
  }
}
