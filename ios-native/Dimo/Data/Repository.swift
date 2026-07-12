import Foundation
import GRDB

final class Repository: @unchecked Sendable {
  private let db: DatabaseQueue
  private let lock = NSLock()
  private var listeners: [UUID: () -> Void] = [:]

  init(db: DatabaseQueue) {
    self.db = db
  }

  @discardableResult
  func onLocalWrite(_ listener: @escaping () -> Void) -> UUID {
    let id = UUID()
    lock.lock(); listeners[id] = listener; lock.unlock()
    return id
  }

  func removeLocalWriteListener(_ id: UUID) {
    lock.lock(); listeners[id] = nil; lock.unlock()
  }

  private func notifyWrite() {
    lock.lock(); let values = Array(listeners.values); lock.unlock()
    for listener in values { listener() }
  }

  func initializeLocalDatabase() throws {
    try db.write { db in
      _ = try ensureDevice(db)
      let device = try DeviceMetaRecord.fetchOne(db, key: "device")!
      if device.bootstrapVersion < bootstrapVersion {
        for category in SeedData.defaultCategories {
          let key = entityKey(type: .category, id: category.id)
          if let existing = try EntityRecord.fetchOne(db, key: key) {
            if existing.deleted { continue }
            let payload = try existing.toStoredEntity().payload
            if case .category(let cat) = payload, cat.emoji.isEmpty {
              try putInTransaction(db, entityType: .category, payload: .category({
                var updated = cat
                updated.emoji = category.emoji
                return updated
              }()))
            }
          } else {
            try putInTransaction(db, entityType: .category, payload: .category(category))
          }
        }
        let cashKey = entityKey(type: .paymentMethod, id: SeedData.cashPaymentMethod.id)
        if try EntityRecord.fetchOne(db, key: cashKey) == nil {
          try putInTransaction(db, entityType: .paymentMethod, payload: .paymentMethod(SeedData.cashPaymentMethod))
        }
        let prefsKey = entityKey(type: .preferences, id: SeedData.defaultPreferences.id)
        if try EntityRecord.fetchOne(db, key: prefsKey) == nil {
          try putInTransaction(db, entityType: .preferences, payload: .preferences(SeedData.defaultPreferences))
        }
        var updated = device
        updated.bootstrapVersion = bootstrapVersion
        try updated.update(db)
      }
      if try SyncMetaRecord.fetchOne(db, key: workspaceID) == nil {
        try SyncMetaRecord.from(
          SyncMeta(
            workspaceId: workspaceID,
            lastPulledRevision: 0,
            lastSyncedAt: nil,
            error: nil,
            syncing: false
          )
        ).insert(db)
      }
    }
    notifyWrite()
  }

  func saveEntity(entityType: EntityType, payload: EntityPayload) throws {
    try db.write { db in
      try putInTransaction(db, entityType: entityType, payload: payload)
    }
    notifyWrite()
  }

  func saveEntities(_ entities: [(EntityType, EntityPayload)]) throws {
    try db.write { db in
      for (type, payload) in entities {
        try putInTransaction(db, entityType: type, payload: payload)
      }
    }
    notifyWrite()
  }

  func removeEntity(entityType: EntityType, id: String) throws {
    let key = entityKey(type: entityType, id: id)
    try db.write { db in
      guard let current = try EntityRecord.fetchOne(db, key: key), !current.deleted else { return }
      let stored = try current.toStoredEntity()
      try putInTransaction(db, entityType: entityType, payload: stored.payload, deleted: true)
    }
    notifyWrite()
  }

  /// Tombstones every active entity of a type in one database transaction and
  /// emits a single write notification, avoiding a listener storm for bulk deletes.
  @discardableResult
  func removeActiveEntities(entityType: EntityType) throws -> Int {
    var removedCount = 0
    try db.write { db in
      let records = try EntityRecord
        .filter(Column("workspaceId") == workspaceID && Column("entityType") == entityType.rawValue)
        .fetchAll(db)
      for record in records {
        let stored = try record.toStoredEntity()
        guard !stored.deleted else { continue }
        try putInTransaction(db, entityType: entityType, payload: stored.payload, deleted: true)
        removedCount += 1
      }
    }
    if removedCount > 0 { notifyWrite() }
    return removedCount
  }

  func setLastPaymentMethod(_ id: String?) throws {
    try db.write { db in
      _ = try ensureDevice(db)
      guard var device = try DeviceMetaRecord.fetchOne(db, key: "device") else { return }
      device.lastPaymentMethodId = id
      try device.update(db)
    }
  }

  func mergeRemotePage(_ remoteEntities: [StoredEntity], cursor: Int) throws {
    try db.write { db in
      for remote in remoteEntities {
        try observeRemoteVersion(db, remote.version)
        let local = try EntityRecord.fetchOne(db, key: remote.key)
        let shouldApply: Bool
        if let local {
          let localEntity = try local.toStoredEntity()
          shouldApply = compareVersions(remote.version, localEntity.version) >= 0
        } else {
          shouldApply = true
        }
        if shouldApply {
          try EntityRecord.from(remote).save(db)
          if let pending = try OutboxRecord.fetchOne(db, key: remote.key) {
            let pendingOp = try pending.toSyncOperation()
            if compareVersions(remote.version, pendingOp.version) >= 0 {
              try pending.delete(db)
            }
          }
        }
      }
      if var meta = try SyncMetaRecord.fetchOne(db, key: workspaceID) {
        meta.lastPulledRevision = cursor
        try meta.update(db)
      }
    }
  }

  func acknowledgeOperations(_ operationIds: [String]) throws {
    try db.write { db in
      for operationId in operationIds {
        if let row = try OutboxRecord
          .filter(Column("operationId") == operationId)
          .fetchOne(db) {
          try row.delete(db)
        }
      }
    }
  }

  func enqueueFullUpload() throws {
    try db.write { db in
      let entities = try EntityRecord
        .filter(Column("workspaceId") == workspaceID)
        .fetchAll(db)
      let now = Int(Date().timeIntervalSince1970 * 1000)
      for record in entities {
        let entity = try record.toStoredEntity()
        let version = try nextVersion(db)
        let payload = PayloadSanitizer.sanitize(entityType: entity.entityType, payload: entity.payload)
        var next = entity
        next.version = version
        next.payload = payload
        next.serverRevision = 0
        let operation = SyncOperation(
          operationId: UUID().uuidString.lowercased(),
          key: entity.key,
          workspaceId: workspaceID,
          entityType: entity.entityType,
          entityId: entity.entityId,
          version: version,
          payload: payload,
          deleted: entity.deleted,
          status: .pending,
          attempts: 0,
          lastError: nil,
          createdAt: now
        )
        try EntityRecord.from(next).save(db)
        try OutboxRecord.from(operation).save(db)
      }
    }
    notifyWrite()
  }

  func activeEntities(type: EntityType) throws -> [StoredEntity] {
    try db.read { db in
      try EntityRecord
        .filter(Column("workspaceId") == workspaceID && Column("entityType") == type.rawValue)
        .fetchAll(db)
        .compactMap { record in
          let entity = try record.toStoredEntity()
          return entity.deleted ? nil : entity
        }
    }
  }

  func allEntities() throws -> [StoredEntity] {
    try db.read { db in
      try EntityRecord
        .filter(Column("workspaceId") == workspaceID)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    }
  }

  func pendingOutbox(limit: Int = 50) throws -> [SyncOperation] {
    try db.read { db in
      try OutboxRecord
        .filter(Column("status") == OutboxStatus.pending.rawValue)
        .order(Column("createdAt"))
        .limit(limit)
        .fetchAll(db)
        .map { try $0.toSyncOperation() }
    }
  }

  func blockedOutbox() throws -> SyncOperation? {
    try db.read { db in
      try OutboxRecord
        .filter(Column("status") == OutboxStatus.blocked.rawValue)
        .fetchOne(db)
        .map { try $0.toSyncOperation() }
    }
  }

  func outboxCounts() throws -> (pending: Int, blocked: Int) {
    try db.read { db in
      let pending = try OutboxRecord.filter(Column("status") == OutboxStatus.pending.rawValue).fetchCount(db)
      let blocked = try OutboxRecord.filter(Column("status") == OutboxStatus.blocked.rawValue).fetchCount(db)
      return (pending, blocked)
    }
  }

  func syncMeta() throws -> SyncMeta? {
    try db.read { db in
      try SyncMetaRecord.fetchOne(db, key: workspaceID)?.toSyncMeta()
    }
  }

  func updateSyncMeta(_ update: (inout SyncMeta) -> Void) throws {
    try db.write { db in
      var meta = try SyncMetaRecord.fetchOne(db, key: workspaceID)?.toSyncMeta()
        ?? SyncMeta(workspaceId: workspaceID, lastPulledRevision: 0, lastSyncedAt: nil, error: nil, syncing: false)
      update(&meta)
      try SyncMetaRecord.from(meta).save(db)
    }
  }

  func updateOutbox(_ operation: SyncOperation) throws {
    try db.write { db in
      try OutboxRecord.from(operation).save(db)
    }
  }

  func deviceMeta() throws -> DeviceMeta? {
    try db.read { db in
      try DeviceMetaRecord.fetchOne(db, key: "device")?.toDeviceMeta()
    }
  }

  func observeEntities(onChange: @escaping ([StoredEntity]) -> Void) -> DatabaseCancellable {
    ValueObservation
      .tracking { db in
        try EntityRecord
          .filter(Column("workspaceId") == workspaceID)
          .fetchAll(db)
          .map { try $0.toStoredEntity() }
      }
      .start(in: db, scheduling: .async(onQueue: .main)) { error in
        print("observeEntities error: \(error)")
      } onChange: { entities in
        onChange(entities)
      }
  }

  func observeSyncMeta(onChange: @escaping (SyncMeta?) -> Void) -> DatabaseCancellable {
    ValueObservation
      .tracking { db in
        try SyncMetaRecord.fetchOne(db, key: workspaceID)?.toSyncMeta()
      }
      .start(in: db, scheduling: .async(onQueue: .main)) { _ in
      } onChange: { meta in
        onChange(meta)
      }
  }

  // MARK: - Private

  private func putInTransaction(
    _ db: Database,
    entityType: EntityType,
    payload: EntityPayload,
    deleted: Bool = false
  ) throws {
    let version = try nextVersion(db)
    let clean = PayloadSanitizer.sanitize(entityType: entityType, payload: payload)
    let id = clean.id
    let key = entityKey(type: entityType, id: id)
    let entity = StoredEntity(
      key: key,
      workspaceId: workspaceID,
      entityType: entityType,
      entityId: id,
      version: version,
      payload: clean,
      deleted: deleted,
      serverRevision: 0
    )
    let operation = SyncOperation(
      operationId: UUID().uuidString.lowercased(),
      key: key,
      workspaceId: workspaceID,
      entityType: entityType,
      entityId: id,
      version: version,
      payload: clean,
      deleted: deleted,
      status: .pending,
      attempts: 0,
      lastError: nil,
      createdAt: Int(Date().timeIntervalSince1970 * 1000)
    )
    try EntityRecord.from(entity).save(db)
    try OutboxRecord.from(operation).save(db)
  }

  @discardableResult
  private func ensureDevice(_ db: Database) throws -> DeviceMetaRecord {
    if let current = try DeviceMetaRecord.fetchOne(db, key: "device") {
      return current
    }
    let created = DeviceMetaRecord(
      id: "device",
      deviceId: UUID().uuidString.lowercased(),
      clockTimestamp: 0,
      clockCounter: 0,
      bootstrapVersion: 0,
      lastPaymentMethodId: nil
    )
    try created.insert(db)
    return created
  }

  private func nextVersion(_ db: Database) throws -> LogicalVersion {
    var device = try ensureDevice(db)
    let now = Int(Date().timeIntervalSince1970 * 1000)
    let timestamp = max(now, device.clockTimestamp)
    let counter = timestamp == device.clockTimestamp ? device.clockCounter + 1 : 0
    device.clockTimestamp = timestamp
    device.clockCounter = counter
    try device.update(db)
    return LogicalVersion(timestamp: timestamp, counter: counter, deviceId: device.deviceId)
  }

  private func observeRemoteVersion(_ db: Database, _ version: LogicalVersion) throws {
    var device = try ensureDevice(db)
    if version.timestamp > device.clockTimestamp {
      device.clockTimestamp = version.timestamp
      device.clockCounter = version.counter
      try device.update(db)
    } else if version.timestamp == device.clockTimestamp, version.counter > device.clockCounter {
      device.clockCounter = version.counter
      try device.update(db)
    }
  }
}
