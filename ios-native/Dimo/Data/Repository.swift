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
        // Cash + preferences only — new accounts start with no seeded categories.
        let cashKey = entityKey(type: .paymentMethod, id: SeedData.cashPaymentMethod.id)
        if try EntityRecord.fetchOne(db, key: cashKey) == nil {
          try putLocalOnly(
            db,
            entityType: .paymentMethod,
            payload: .paymentMethod(SeedData.cashPaymentMethod)
          )
        }
        let prefsKey = entityKey(type: .preferences, id: SeedData.defaultPreferences.id)
        if try EntityRecord.fetchOne(db, key: prefsKey) == nil {
          try putLocalOnly(
            db,
            entityType: .preferences,
            payload: .preferences(SeedData.defaultPreferences)
          )
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

  /// After pull, queue cash / preferences that still have no server revision so
  /// empty workspaces get those defaults without inventing categories.
  func enqueueUnsyncedDefaults() throws {
    var enqueued = false
    try db.write { db in
      let defaults: [(EntityType, EntityPayload)] = [
        (.paymentMethod, .paymentMethod(SeedData.cashPaymentMethod)),
        (.preferences, .preferences(SeedData.defaultPreferences)),
      ]
      for (type, seedPayload) in defaults {
        let id = seedPayload.id
        let key = entityKey(type: type, id: id)
        guard let record = try EntityRecord.fetchOne(db, key: key) else { continue }
        let stored = try record.toStoredEntity()
        guard !stored.deleted, stored.serverRevision == 0 else { continue }
        if try OutboxRecord.fetchOne(db, key: key) != nil { continue }
        try putInTransaction(db, entityType: type, payload: stored.payload)
        enqueued = true
      }
    }
    if enqueued { notifyWrite() }
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

  /// Gives legacy recurring and transaction rows an explicit denomination and
  /// enqueues the versioned repair so web and iOS converge on the same payload.
  @discardableResult
  func backfillRecurringCurrencies() throws -> Int {
    var updated = 0
    try db.write { db in
      let preferencesKey = entityKey(type: .preferences, id: "preferences")
      let accountCurrency: String
      if let record = try EntityRecord.fetchOne(db, key: preferencesKey),
         !record.deleted,
         case .preferences(let preferences) = try record.toStoredEntity().payload {
        accountCurrency = preferences.currency.rawValue
      } else {
        accountCurrency = SeedData.defaultPreferences.currency.rawValue
      }

      for entityType in [EntityType.recurring, .transaction] {
        let records = try EntityRecord
          .filter(
            Column("workspaceId") == workspaceID
              && Column("entityType") == entityType.rawValue
          )
          .fetchAll(db)
        for record in records {
          let stored = try record.toStoredEntity()
          guard !stored.deleted else { continue }
          switch stored.payload {
          case .recurring(var recurring):
            let current = recurring.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current?.isEmpty != false else { continue }
            recurring.currency = accountCurrency
            try putInTransaction(db, entityType: .recurring, payload: .recurring(recurring))
            updated += 1
          case .transaction(var transaction):
            let current = transaction.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard current?.isEmpty != false else { continue }
            transaction.currency = accountCurrency
            try putInTransaction(db, entityType: .transaction, payload: .transaction(transaction))
            updated += 1
          default:
            continue
          }
        }
      }
    }
    if updated > 0 { notifyWrite() }
    return updated
  }

  func removeEntity(entityType: EntityType, id: String) throws {
    let key = entityKey(type: entityType, id: id)
    try db.write { db in
      guard let current = try EntityRecord.fetchOne(db, key: key), !current.deleted else { return }
      let stored = try current.toStoredEntity()
      try putInTransaction(db, entityType: entityType, payload: stored.payload, deleted: true)
      if entityType == .transaction {
        try dismissEmailsLinkedToDeletedTransaction(db, transactionId: id)
      }
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
        if entityType == .transaction {
          try dismissEmailsLinkedToDeletedTransaction(db, transactionId: stored.entityId)
        }
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
          if remote.entityType == .emailMessage {
            try projectRemoteEmailMessage(db, remote: remote)
          } else if remote.entityType == .transaction, remote.deleted {
            try dismissEmailsLinkedToDeletedTransaction(db, transactionId: remote.entityId)
          }
        }
      }
      if var meta = try SyncMetaRecord.fetchOne(db, key: workspaceID) {
        meta.lastPulledRevision = cursor
        try meta.update(db)
      }
    }
  }

  /// Uploads local reviewed/restored email rows that are not yet in the entity store.
  func enqueueUnsyncedEmailMessages() throws {
    try db.write { db in
      let messages = try EmailMessageRecord
        .filter(emailSyncedSuggestionStates().contains(Column("state")))
        .fetchAll(db)
      for message in messages {
        let key = entityKey(type: .emailMessage, id: message.key)
        if try EntityRecord.fetchOne(db, key: key) == nil {
          try putSyncedEmailMessage(db, message: message)
        }
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

  func enqueueFullUpload(entityTypes: [EntityType] = Array(EntityType.allCases)) throws {
    let allowed = Set(entityTypes.map(\.rawValue))
    try db.write { db in
      let entities = try EntityRecord
        .filter(Column("workspaceId") == workspaceID)
        .fetchAll(db)
        .filter { allowed.contains($0.entityType) }
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

  /// Hard-delete local tombstones past the private retention window.
  /// Skips rows that still have an unacked outbox operation.
  @discardableResult
  func purgeExpiredTombstones(now: Int = Int(Date().timeIntervalSince1970 * 1000)) throws -> Int {
    let cutoff = now - tombstoneRetentionDays * 24 * 60 * 60 * 1000
    let purged = try db.write { db -> Int in
      let records = try EntityRecord
        .filter(Column("workspaceId") == workspaceID && Column("deleted") == true)
        .fetchAll(db)
      var count = 0
      for record in records {
        let entity = try record.toStoredEntity()
        guard entity.version.timestamp < cutoff else { continue }
        if try OutboxRecord.fetchOne(db, key: entity.key) != nil { continue }
        _ = try EntityRecord.deleteOne(db, key: entity.key)
        count += 1
      }
      return count
    }
    return purged
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

  /// Writes an entity for offline UI without enqueueing sync. Uses a zero
  /// logical version so any cloud row wins on the first pull.
  private func putLocalOnly(
    _ db: Database,
    entityType: EntityType,
    payload: EntityPayload,
    deleted: Bool = false
  ) throws {
    _ = try ensureDevice(db)
    let device = try DeviceMetaRecord.fetchOne(db, key: "device")!
    let clean = PayloadSanitizer.sanitize(entityType: entityType, payload: payload)
    let id = clean.id
    let key = entityKey(type: entityType, id: id)
    let entity = StoredEntity(
      key: key,
      workspaceId: workspaceID,
      entityType: entityType,
      entityId: id,
      version: LogicalVersion(timestamp: 0, counter: 0, deviceId: device.deviceId),
      payload: clean,
      deleted: deleted,
      serverRevision: 0
    )
    try EntityRecord.from(entity).save(db)
  }

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

// MARK: - Device-local email data

extension Repository {
  func emailAccounts() throws -> [EmailAccountRecordModel] {
    try db.read { db in
      try EmailAccountRecord
        .order(Column("emailAddress"))
        .fetchAll(db)
        .map { try $0.toModel() }
    }
  }

  func emailAccount(id: String) throws -> EmailAccountRecordModel? {
    try db.read { db in
      try EmailAccountRecord.fetchOne(db, key: id)?.toModel()
    }
  }

  /// Inserts or replaces local account metadata. The caller is responsible for
  /// committing the matching refresh-token Keychain update before exposing a
  /// newly connected account to the UI.
  func saveEmailAccount(_ account: EmailAccountRecordModel) throws {
    let id = account.id.trimmingCharacters(in: .whitespacesAndNewlines)
    let email = account.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, email.contains("@") else { throw EmailRepositoryError.invalidAccount }
    let now = emailNowMilliseconds()
    try db.write { db in
      var clean = account
      clean.id = id
      clean.emailAddress = email
      clean.updatedAt = now
      if let current = try EmailAccountRecord.fetchOne(db, key: id) {
        clean.createdAt = current.createdAt
      } else if clean.createdAt <= 0 {
        clean.createdAt = now
      }
      try EmailAccountRecord.from(clean).save(db)
    }
  }

  /// Mutates cursors and status in one write so cursor advancement cannot be
  /// observed separately from its successful-sync timestamp.
  func updateEmailAccount(
    id: String,
    _ update: (inout EmailAccountRecordModel) -> Void
  ) throws {
    try db.write { db in
      guard let record = try EmailAccountRecord.fetchOne(db, key: id) else {
        throw EmailRepositoryError.accountNotFound
      }
      var account = try record.toModel()
      update(&account)
      let normalizedId = account.id.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedEmail = account.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
      guard normalizedId == id, normalizedEmail.contains("@") else {
        throw EmailRepositoryError.invalidAccount
      }
      account.emailAddress = normalizedEmail
      account.createdAt = record.createdAt
      account.updatedAt = emailNowMilliseconds()
      try EmailAccountRecord.from(account).update(db)
    }
  }

  /// Disconnect cleanup for SQLite. OAuth credentials are deleted separately
  /// by the Keychain owner; SQLite never stores them. Cascades to every local
  /// emailMessages row for the account. Synced `emailMessage` entities in the
  /// outbox/entity store are left alone so reconnect can materialize them.
  @discardableResult
  func deleteEmailAccount(id: String) throws -> Bool {
    try db.write { db in
      guard let account = try EmailAccountRecord.fetchOne(db, key: id) else { return false }
      try account.delete(db)
      return true
    }
  }

  /// Copies active synced `emailMessage` entities for an account into the local
  /// emailMessages table. Call after reconnect so Gmail refresh sees reviewed
  /// keys and skips re-analysis.
  func materializeSyncedEmailMessages(accountId: String) throws {
    try db.write { db in
      guard try EmailAccountRecord.fetchOne(db, key: accountId) != nil else { return }
      let records = try EntityRecord
        .filter(
          Column("workspaceId") == workspaceID
            && Column("entityType") == EntityType.emailMessage.rawValue
        )
        .fetchAll(db)
      for record in records {
        let stored = try record.toStoredEntity()
        guard !stored.deleted, case .emailMessage(let entity) = stored.payload else { continue }
        guard entity.accountId == accountId else { continue }
        try upsertLocalEmailMessage(db, from: entity, existingOverride: nil)
      }
    }
  }

  /// Explicit local cleanup used alongside credential deletion. Normal Dimo
  /// sign-out deletes the whole account-scoped database instead.
  func deleteAllEmailData() throws {
    try db.write { db in
      try EmailMessageRecord.deleteAll(db)
      try EmailAccountRecord.deleteAll(db)
    }
  }

  @discardableResult
  func insertPendingEmailMessages(_ messages: [PendingEmailMessage]) throws -> Int {
    guard !messages.isEmpty else { return 0 }
    let now = emailNowMilliseconds()
    return try db.write { db in
      var inserted = 0
      for message in messages {
        guard !message.accountId.isEmpty,
              !message.gmailMessageId.isEmpty,
              !message.threadId.isEmpty,
              message.internalDate > 0,
              try EmailAccountRecord.fetchOne(db, key: message.accountId) != nil
        else {
          throw EmailRepositoryError.accountNotFound
        }
        // Gmail messages are immutable for this feature. Never overwrite a
        // reviewed row or restore body text when a page is replayed.
        guard try EmailMessageRecord.fetchOne(db, key: message.key) == nil else { continue }
        try EmailMessageRecord.pending(message, now: now).insert(db)
        inserted += 1
      }
      return inserted
    }
  }

  func emailMessage(key: String) throws -> EmailMessageRecordModel? {
    try db.read { db in
      try EmailMessageRecord.fetchOne(db, key: key)?.toModel()
    }
  }

  /// The retained source email for a transaction the user accepted from an
  /// email suggestion, if it is still stored on this device.
  func emailMessage(linkedTransactionId: String) throws -> EmailMessageRecordModel? {
    try db.read { db in
      try EmailMessageRecord
        .filter(Column("linkedTransactionId") == linkedTransactionId)
        .order(Column("updatedAt").desc)
        .fetchOne(db)?
        .toModel()
    }
  }

  func emailAnalysisSettings() throws -> EmailAnalysisSettings {
    let (settings, shouldRewriteVariant) = try db.read { db -> (EmailAnalysisSettings, Bool) in
      guard let record = try EmailAnalysisSettingsRecord
        .fetchOne(db, key: EmailAnalysisSettings.singletonID)
      else {
        return (.defaults, false)
      }
      let settings = try record.toModel()
      let needsRewrite: Bool
      if let storedVariant = record.gemmaModelVariant {
        needsRewrite = EmailGemmaModelVariant(rawValue: storedVariant) == nil
      } else {
        needsRewrite = false
      }
      return (settings, needsRewrite)
    }
    if shouldRewriteVariant {
      try saveEmailAnalysisSettings(settings)
    }
    return settings
  }

  func saveEmailAnalysisSettings(_ settings: EmailAnalysisSettings) throws {
    var updated = settings
    updated.updatedAt = emailNowMilliseconds()
    try db.write { db in
      try EmailAnalysisSettingsRecord.from(updated).save(db)
    }
  }

  func emailAnalysisRetryState() throws -> EmailAnalysisRetryState? {
    try db.read { db in
      try EmailAnalysisRetryRecord
        .fetchOne(db, key: EmailAnalysisRetryState.singletonID)?
        .toModel()
    }
  }

  func saveEmailAnalysisRetryState(_ state: EmailAnalysisRetryState) throws {
    try db.write { db in
      try EmailAnalysisRetryRecord(
        id: EmailAnalysisRetryState.singletonID,
        attempt: state.attempt,
        notBefore: state.notBefore,
        reason: state.reason,
        lastHTTPStatus: state.lastHTTPStatus,
        updatedAt: emailNowMilliseconds()
      ).save(db)
    }
  }

  func clearEmailAnalysisRetryState() throws {
    try db.write { db in
      _ = try EmailAnalysisRetryRecord.deleteOne(db, key: EmailAnalysisRetryState.singletonID)
    }
  }

  func setEmailAnalysisProviderOverride(
    messageKey: String,
    provider: EmailAnalysisProvider?
  ) throws {
    try db.write { db in
      guard var record = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard record.reviewedAt == nil, record.normalizedBodyText != nil else {
        throw EmailRepositoryError.suggestionAlreadyReviewed
      }
      record.analysisProviderOverride = provider?.rawValue
      record.updatedAt = emailNowMilliseconds()
      try record.update(db)
    }
  }

  func retryEmailAnalysis(
    messageKey: String,
    providerOverride: EmailAnalysisProvider? = nil
  ) throws {
    try db.write { db in
      guard var record = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard record.reviewedAt == nil, record.normalizedBodyText != nil else {
        throw EmailRepositoryError.suggestionAlreadyReviewed
      }
      record.analysisProviderOverride = providerOverride?.rawValue
      record.analyzerType = nil
      record.modelVersion = nil
      record.promptVersion = nil
      record.classification = nil
      record.merchant = nil
      record.amount = nil
      record.currency = nil
      record.occurredAt = nil
      record.categoryId = nil
      record.paymentMethodId = nil
      record.paymentLastFour = nil
      record.reference = nil
      record.state = EmailSuggestionState.pendingAnalysis.rawValue
      record.linkedTransactionId = nil
      record.analyzedAt = nil
      record.updatedAt = emailNowMilliseconds()
      try record.update(db)
    }
  }

  func emailMessageSummaries() throws -> [EmailMessageSummaryModel] {
    try db.read { db in
      try EmailMessageSummaryRecord
        .fetchAll(db, sql: emailMessageSummarySQL)
        .map { try $0.toModel() }
    }
  }

  /// The combined feed excludes queued and irrelevant messages. Those remain
  /// available through the analysis queue or are compacted by retention.
  func emailSuggestions(
    filter: EmailLocalSuggestionFilter? = nil,
    limit: Int = 200
  ) throws -> [EmailMessageRecordModel] {
    try db.read { db in
      let states = emailSuggestionStates(matching: filter)
      return try EmailMessageRecord
        .filter(states.contains(Column("state")))
        .order(Column("internalDate").desc)
        .limit(max(0, limit))
        .fetchAll(db)
        .map { try $0.toModel() }
    }
  }

  /// Pass an account ID with a small limit (normally one) while iterating the
  /// connected accounts to implement fair, round-robin analysis.
  func emailMessagesPendingAnalysis(
    accountId: String? = nil,
    limit: Int = 25
  ) throws -> [EmailMessageRecordModel] {
    try db.read { db in
      var request = EmailMessageRecord
        .filter(
          Column("state") == EmailSuggestionState.pendingAnalysis.rawValue
            && Column("normalizedBodyText") != nil
        )
      if let accountId {
        request = request.filter(Column("accountId") == accountId)
      }
      return try request
        .order(Column("internalDate").desc)
        .limit(max(0, limit))
        .fetchAll(db)
        .map { try $0.toModel() }
    }
  }

  /// Returns every unreviewed message with retained content to the ordinary
  /// analysis queue. Reviewed rows are intentionally excluded because their
  /// bodies have been purged and their Dimo transaction effects must remain
  /// unchanged.
  @discardableResult
  func resetEmailMessagesForReanalysis() throws -> Int {
    try db.write { db in
      let rows = try EmailMessageRecord
        .filter(
          Column("normalizedBodyText") != nil
            && Column("reviewedAt") == nil
        )
        .fetchAll(db)
      let now = emailNowMilliseconds()
      for var row in rows {
        row.analysisProviderOverride = nil
        row.analyzerType = nil
        row.modelVersion = nil
        row.promptVersion = nil
        row.classification = nil
        row.merchant = nil
        row.amount = nil
        row.currency = nil
        row.occurredAt = nil
        row.categoryId = nil
        row.paymentMethodId = nil
        row.paymentLastFour = nil
        row.reference = nil
        row.state = EmailSuggestionState.pendingAnalysis.rawValue
        row.linkedTransactionId = nil
        row.analyzedAt = nil
        row.updatedAt = now
        try row.update(db)
      }
      return rows.count
    }
  }

  func saveEmailAnalysis(messageKey: String, analysis: PersistedEmailAnalysis) throws {
    let now = emailNowMilliseconds()
    try db.write { db in
      guard var record = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard record.reviewedAt == nil, record.normalizedBodyText != nil else {
        throw EmailRepositoryError.suggestionAlreadyReviewed
      }
      let currentState = EmailSuggestionState(rawValue: record.state)
      let isFirstAnalysis = currentState == .pendingAnalysis
      guard isFirstAnalysis else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      guard analysis.promptVersion > 0,
            analysis.analyzerType != .rules,
            !(analysis.modelVersion?.isEmpty ?? true)
      else {
        throw EmailRepositoryError.invalidAnalysis
      }

      let amount = try validateEmailAmount(analysis.amount)
      if let occurredAt = analysis.occurredAt {
        guard occurredAt > 0 else { throw EmailRepositoryError.invalidAnalysis }
        if analysis.classification == .purchase || analysis.classification == .debit {
          guard occurredAt <= now + 5 * 60 * 1000 else {
            throw EmailRepositoryError.invalidAnalysis
          }
        }
      }
      try validateEmailSuggestionIdentifiers(
        db,
        categoryId: analysis.categoryId,
        paymentMethodId: analysis.paymentMethodId
      )

      record.analyzerType = analysis.analyzerType.rawValue
      record.modelVersion = emailNonempty(analysis.modelVersion)
      record.promptVersion = analysis.promptVersion
      record.classification = analysis.classification.rawValue
      record.merchant = emailNonempty(analysis.merchant)
      record.amount = amount
      record.currency = analysis.currency?.rawValue
      record.occurredAt = analysis.occurredAt
      record.categoryId = emailNonempty(analysis.categoryId)
      record.paymentMethodId = emailNonempty(analysis.paymentMethodId)
      record.paymentLastFour = emailNonempty(analysis.paymentLastFour)
      record.reference = emailNonempty(analysis.reference)
      record.analyzedAt = now
      record.updatedAt = now
      record.linkedTransactionId = nil
      record.analysisProviderOverride = nil

      switch analysis.classification {
      case .purchase, .debit:
        record.state = EmailSuggestionState.pendingPurchase.rawValue
      case .refund:
        record.state = EmailSuggestionState.pendingRefund.rawValue
      case .irrelevant:
        // Keep the full body so the user can still open and read the email.
        record.state = EmailSuggestionState.unactionable.rawValue
      }
      try record.update(db)
    }
  }

  /// Records an analyzer failure without discarding the retained email body, so a
  /// later explicit reanalysis can return the message to the ordinary queue.
  func markEmailAnalysisFailed(
    messageKey: String,
    analyzer: EmailAnalyzerKind? = nil,
    modelVersion: String? = nil
  ) throws {
    try db.write { db in
      guard var record = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard record.reviewedAt == nil, record.normalizedBodyText != nil else {
        throw EmailRepositoryError.suggestionAlreadyReviewed
      }

      record.analyzerType = analyzer?.rawValue
      record.modelVersion = emailNonempty(modelVersion)
      record.promptVersion = nil
      record.classification = nil
      record.merchant = nil
      record.amount = nil
      record.currency = nil
      record.occurredAt = nil
      record.categoryId = nil
      record.paymentMethodId = nil
      record.paymentLastFour = nil
      record.reference = nil
      record.state = EmailSuggestionState.analysisFailed.rawValue
      record.linkedTransactionId = nil
      record.analyzedAt = nil
      record.analysisProviderOverride = nil
      record.updatedAt = emailNowMilliseconds()
      try record.update(db)
    }
  }

  func dismissEmailSuggestion(messageKey: String) throws {
    try finishEmailSuggestion(messageKey: messageKey, state: .dismissed)
  }

  /// Restores the analyzed result to the review queue. Body text is retained
  /// through dismissal and Convex sync so restore does not need to rebuild it.
  func restoreDismissedEmailSuggestion(messageKey: String) throws {
    let now = emailNowMilliseconds()
    try db.write { db in
      guard var message = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard message.state == EmailSuggestionState.dismissed.rawValue else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      guard let rawClassification = message.classification,
            let classification = EmailMessageClassification(rawValue: rawClassification)
      else {
        throw EmailRepositoryError.invalidAnalysis
      }
      switch classification {
      case .purchase, .debit:
        message.state = EmailSuggestionState.pendingPurchase.rawValue
      case .refund:
        message.state = EmailSuggestionState.pendingRefund.rawValue
      case .irrelevant:
        throw EmailRepositoryError.invalidSuggestionState
      }
      message.linkedTransactionId = nil
      message.reviewedAt = nil
      message.updatedAt = now
      try message.update(db)
      try putSyncedEmailMessage(db, message: message)
    }
    notifyWrite()
  }

  /// Marks a fetched or analyzed message as locally unusable without discarding
  /// the retained body (so the email remains readable in the detail view).
  func markEmailSuggestionUnactionable(messageKey: String) throws {
    try finishEmailSuggestion(
      messageKey: messageKey,
      state: .unactionable,
      allowedStates: [.pendingAnalysis, .pendingPurchase, .pendingRefund],
      retainBody: true
    )
  }

  /// Marks rows outside the rolling window before deletion. This is useful for
  /// tests and for a UI refresh that wants to stop displaying stale rows before
  /// the compact record purge runs. Emails linked to an accepted transaction
  /// are kept as a permanent reference and never expire with the window.
  @discardableResult
  func expireEmailMessages(olderThan cutoff: Int) throws -> Int {
    try db.write { db in
      let retained = emailSyncedSuggestionStates()
      let rows = try EmailMessageRecord
        .filter(
          Column("internalDate") < cutoff
            && Column("state") != EmailSuggestionState.expired.rawValue
            && Column("linkedTransactionId") == nil
            && !retained.contains(Column("state"))
        )
        .fetchAll(db)
      let now = emailNowMilliseconds()
      for var row in rows {
        row.state = EmailSuggestionState.expired.rawValue
        row.normalizedBodyText = nil
        row.reviewedAt = row.reviewedAt ?? now
        row.updatedAt = now
        try row.update(db)
      }
      return rows.count
    }
  }

  /// Removes compact message metadata after it leaves the caller-provided
  /// rolling-window cutoff. No account cursor is affected. Emails linked to an
  /// accepted transaction survive the window so the user can reference them.
  @discardableResult
  func purgeEmailMessages(olderThan cutoff: Int) throws -> Int {
    try db.write { db in
      let retained = emailSyncedSuggestionStates()
      return try EmailMessageRecord
        .filter(
          Column("internalDate") < cutoff
            && Column("linkedTransactionId") == nil
            && !retained.contains(Column("state"))
        )
        .deleteAll(db)
    }
  }

  /// Defensive maintenance: drop body text only for expired compact rows.
  /// Unactionable and synced reviewed states keep the full body for reading.
  @discardableResult
  func purgeReviewedEmailBodies() throws -> Int {
    try db.write { db in
      let bodyRetainedStates =
        emailSyncedSuggestionStates() + [
          EmailSuggestionState.pendingAnalysis.rawValue,
          EmailSuggestionState.analysisFailed.rawValue,
          EmailSuggestionState.unactionable.rawValue,
        ]
      return try EmailMessageRecord
        .filter(
          !bodyRetainedStates.contains(Column("state"))
            && Column("normalizedBodyText") != nil
        )
        .updateAll(
          db,
          Column("normalizedBodyText").set(to: nil),
          Column("updatedAt").set(to: emailNowMilliseconds())
        )
    }
  }

  /// Creates the normal synced transaction and resolves the local suggestion
  /// in one SQLite transaction. No Gmail identifier enters the entity payload.
  /// The email stays linked and retains its body on this device so the user
  /// can open the source email from the transaction later.
  func acceptEmailSuggestion(
    messageKey: String,
    transaction: TransactionEntity,
    recurring: RecurringEntity? = nil
  ) throws {
    guard transaction.amountMinor > 0 else { throw EmailRepositoryError.invalidAnalysis }
    try db.write { db in
      guard var message = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard message.reviewedAt == nil else { throw EmailRepositoryError.suggestionAlreadyReviewed }
      guard message.state == EmailSuggestionState.pendingPurchase.rawValue,
            message.classification == EmailMessageClassification.purchase.rawValue
              || message.classification == EmailMessageClassification.debit.rawValue
      else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      try validateEmailSuggestionIdentifiers(
        db,
        categoryId: transaction.categoryId,
        paymentMethodId: transaction.paymentMethodId,
        requireCategory: true
      )

      if let recurring {
        guard recurring.amountMinor > 0,
              recurring.categoryId == transaction.categoryId,
              recurring.paymentMethodId == transaction.paymentMethodId else {
          throw EmailRepositoryError.invalidAnalysis
        }
        try validateEmailSuggestionIdentifiers(
          db,
          categoryId: recurring.categoryId,
          paymentMethodId: recurring.paymentMethodId,
          requireCategory: true
        )
        let recurringKey = entityKey(type: .recurring, id: recurring.id)
        guard try EntityRecord.fetchOne(db, key: recurringKey) == nil else {
          throw EmailRepositoryError.duplicateTransaction
        }
        try putInTransaction(db, entityType: .recurring, payload: .recurring(recurring))
      }

      let key = entityKey(type: .transaction, id: transaction.id)
      guard try EntityRecord.fetchOne(db, key: key) == nil else {
        throw EmailRepositoryError.duplicateTransaction
      }
      try putInTransaction(db, entityType: .transaction, payload: .transaction(transaction))

      var device = try ensureDevice(db)
      device.lastPaymentMethodId = transaction.paymentMethodId
      try device.update(db)

      let now = emailNowMilliseconds()
      message.state = EmailSuggestionState.added.rawValue
      message.linkedTransactionId = transaction.id
      message.reviewedAt = now
      message.updatedAt = now
      try message.update(db)
      try putSyncedEmailMessage(db, message: message)
    }
    notifyWrite()
  }

  /// Resolves a purchase suggestion against a transaction the user already
  /// recorded. The existing transaction is left unchanged; the email row is
  /// marked reviewed/linked and dual-written into the synced emailMessage entity.
  func linkEmailSuggestionToTransaction(messageKey: String, transactionId: String) throws {
    try db.write { db in
      guard var message = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard message.reviewedAt == nil else { throw EmailRepositoryError.suggestionAlreadyReviewed }
      guard message.state == EmailSuggestionState.pendingPurchase.rawValue,
            message.classification == EmailMessageClassification.purchase.rawValue
              || message.classification == EmailMessageClassification.debit.rawValue
      else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      guard let record = try EntityRecord.fetchOne(
        db,
        key: entityKey(type: .transaction, id: transactionId)
      ),
        !record.deleted,
        case .transaction = try record.toStoredEntity().payload
      else {
        throw EmailRepositoryError.transactionNotFound
      }

      let now = emailNowMilliseconds()
      message.state = EmailSuggestionState.added.rawValue
      message.linkedTransactionId = transactionId
      message.reviewedAt = now
      message.updatedAt = now
      try message.update(db)
      try putSyncedEmailMessage(db, message: message)
    }
    notifyWrite()
  }

  /// Applies only an exact, same-currency, full refund within the 120-day
  /// matching window. The ordinary transaction tombstone replaces any pending
  /// outbox edit for that transaction key.
  func applyFullEmailRefund(
    messageKey: String,
    transactionId: String
  ) throws {
    try db.write { db in
      guard var message = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard message.reviewedAt == nil else { throw EmailRepositoryError.suggestionAlreadyReviewed }
      guard message.state == EmailSuggestionState.pendingRefund.rawValue,
            message.classification == EmailMessageClassification.refund.rawValue
      else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      let partialSource = [message.subject, message.snippet, message.normalizedBodyText ?? ""]
        .joined(separator: "\n")
      guard !EmailSuggestionSelectors.isExplicitlyPartialRefund(partialSource) else {
        throw EmailRepositoryError.amountMismatch
      }

      let key = entityKey(type: .transaction, id: transactionId)
      guard let transactionRecord = try EntityRecord.fetchOne(db, key: key),
            !transactionRecord.deleted,
            case .transaction(let transaction) = try transactionRecord.toStoredEntity().payload
      else {
        throw EmailRepositoryError.transactionNotFound
      }

      let activeCurrency = try emailActiveCurrency(db)
      guard message.currency == activeCurrency.rawValue else {
        throw EmailRepositoryError.currencyMismatch
      }
      guard let amount = message.amount,
            let refundMinor = emailExactMinorUnits(amount),
            refundMinor == transaction.amountMinor
      else {
        throw EmailRepositoryError.amountMismatch
      }

      let refundDate = message.occurredAt ?? message.internalDate
      let maximumWindow = 120 * 24 * 60 * 60 * 1000
      guard transaction.occurredAt <= refundDate,
            refundDate - transaction.occurredAt <= maximumWindow
      else {
        throw EmailRepositoryError.transactionOutsideRefundWindow
      }

      try putInTransaction(
        db,
        entityType: .transaction,
        payload: .transaction(transaction),
        deleted: true
      )
      let now = emailNowMilliseconds()
      message.state = EmailSuggestionState.refundApplied.rawValue
      message.linkedTransactionId = transactionId
      message.reviewedAt = now
      message.updatedAt = now
      try message.update(db)
      try putSyncedEmailMessage(db, message: message)
    }
    notifyWrite()
  }

  func observeEmailAccounts(
    onChange: @escaping ([EmailAccountRecordModel]) -> Void
  ) -> DatabaseCancellable {
    ValueObservation
      .tracking { db in
        try EmailAccountRecord
          .order(Column("emailAddress"))
          .fetchAll(db)
          .map { try $0.toModel() }
      }
      .start(in: db, scheduling: .async(onQueue: .main)) { error in
        print("observeEmailAccounts error: \(error)")
      } onChange: { accounts in
        onChange(accounts)
      }
  }

  func observeEmailSuggestions(
    filter: EmailLocalSuggestionFilter? = nil,
    limit: Int = 200,
    onChange: @escaping ([EmailMessageRecordModel]) -> Void
  ) -> DatabaseCancellable {
    ValueObservation
      .tracking { db in
        let states = emailSuggestionStates(matching: filter)
        return try EmailMessageRecord
          .filter(states.contains(Column("state")))
          .order(Column("internalDate").desc)
          .limit(max(0, limit))
          .fetchAll(db)
          .map { try $0.toModel() }
      }
      .start(in: db, scheduling: .async(onQueue: .main)) { error in
        print("observeEmailSuggestions error: \(error)")
      } onChange: { messages in
        onChange(messages)
      }
  }

  func observeEmailMessageSummaries(
    onChange: @escaping ([EmailMessageSummaryModel]) -> Void
  ) -> DatabaseCancellable {
    ValueObservation
      .tracking { db in
        try EmailMessageSummaryRecord
          .fetchAll(db, sql: emailMessageSummarySQL)
          .map { try $0.toModel() }
      }
      .start(in: db, scheduling: .async(onQueue: .main)) { error in
        print("observeEmailMessageSummaries error: \(error)")
      } onChange: { messages in
        onChange(messages)
      }
  }

  private func finishEmailSuggestion(
    messageKey: String,
    state: EmailSuggestionState,
    allowedStates: Set<EmailSuggestionState> = [.pendingPurchase, .pendingRefund],
    retainBody: Bool = false
  ) throws {
    try db.write { db in
      guard var message = try EmailMessageRecord.fetchOne(db, key: messageKey) else {
        throw EmailRepositoryError.messageNotFound
      }
      guard message.reviewedAt == nil else { throw EmailRepositoryError.suggestionAlreadyReviewed }
      guard let current = EmailSuggestionState(rawValue: message.state), allowedStates.contains(current) else {
        throw EmailRepositoryError.invalidSuggestionState
      }
      let now = emailNowMilliseconds()
      message.state = state.rawValue
      // Keep the full body for synced reviewed/dismissed rows so Convex and
      // Restore retain the complete email text, not only the snippet. Also keep
      // it when the caller explicitly asks (e.g. unactionable / not-a-transaction).
      if !retainBody, !emailSyncedSuggestionStates().contains(state.rawValue) {
        message.normalizedBodyText = nil
      }
      message.reviewedAt = now
      message.updatedAt = now
      try message.update(db)
      if emailSyncedSuggestionStates().contains(state.rawValue) {
        try putSyncedEmailMessage(db, message: message)
      }
    }
    notifyWrite()
  }

  private func validateEmailSuggestionIdentifiers(
    _ db: Database,
    categoryId: String?,
    paymentMethodId: String?,
    requireCategory: Bool = false
  ) throws {
    if requireCategory, emailNonempty(categoryId) == nil {
      throw EmailRepositoryError.invalidCategory
    }
    if let categoryId = emailNonempty(categoryId) {
      guard try emailActiveEntity(db, type: .category, id: categoryId) != nil else {
        throw EmailRepositoryError.invalidCategory
      }
    }
    if let paymentMethodId = emailNonempty(paymentMethodId) {
      guard try emailActiveEntity(db, type: .paymentMethod, id: paymentMethodId) != nil else {
        throw EmailRepositoryError.invalidPaymentMethod
      }
    }
  }

  private func emailActiveEntity(
    _ db: Database,
    type: EntityType,
    id: String
  ) throws -> StoredEntity? {
    guard let record = try EntityRecord.fetchOne(db, key: entityKey(type: type, id: id)) else {
      return nil
    }
    let entity = try record.toStoredEntity()
    return entity.deleted ? nil : entity
  }

  private func emailActiveCurrency(_ db: Database) throws -> Currency {
    guard let entity = try emailActiveEntity(db, type: .preferences, id: "preferences"),
          case .preferences(let preferences) = entity.payload
    else {
      return SeedData.defaultPreferences.currency
    }
    return preferences.currency
  }

  private func dismissEmailsLinkedToDeletedTransaction(_ db: Database, transactionId: String) throws {
    let linked = try EmailMessageRecord
      .filter(
        Column("linkedTransactionId") == transactionId
          && Column("state") == EmailSuggestionState.added.rawValue
      )
      .fetchAll(db)
    guard !linked.isEmpty else { return }
    let now = emailNowMilliseconds()
    for var message in linked {
      message.state = EmailSuggestionState.dismissed.rawValue
      message.linkedTransactionId = nil
      message.reviewedAt = message.reviewedAt ?? now
      message.updatedAt = now
      try message.update(db)
      try putSyncedEmailMessage(db, message: message)
    }
  }

  private func putSyncedEmailMessage(_ db: Database, message: EmailMessageRecord) throws {
    guard emailSyncedSuggestionStates().contains(message.state) else { return }
    let accountEmail = try EmailAccountRecord.fetchOne(db, key: message.accountId)?.emailAddress
      ?? ""
    let entity = EmailMessageEntity(
      id: message.key,
      accountId: message.accountId,
      accountEmail: accountEmail,
      gmailMessageId: message.gmailMessageId,
      threadId: message.threadId,
      rfcMessageId: message.rfcMessageId,
      senderName: message.senderName,
      senderAddress: message.senderAddress,
      subject: message.subject,
      snippet: message.snippet,
      internalDate: message.internalDate,
      normalizedBodyText: message.normalizedBodyText,
      analyzerType: message.analyzerType,
      modelVersion: message.modelVersion,
      promptVersion: message.promptVersion,
      classification: message.classification,
      merchant: message.merchant,
      amount: message.amount,
      currency: message.currency,
      occurredAt: message.occurredAt,
      categoryId: message.categoryId,
      paymentMethodId: message.paymentMethodId,
      paymentLastFour: message.paymentLastFour,
      reference: message.reference,
      state: message.state,
      linkedTransactionId: message.linkedTransactionId,
      analyzedAt: message.analyzedAt,
      reviewedAt: message.reviewedAt,
      createdAt: message.createdAt,
      updatedAt: message.updatedAt
    )
    try putInTransaction(db, entityType: .emailMessage, payload: .emailMessage(entity))
  }

  private func projectRemoteEmailMessage(_ db: Database, remote: StoredEntity) throws {
    guard case .emailMessage(let entity) = remote.payload else { return }
    if remote.deleted {
      _ = try EmailMessageRecord.deleteOne(db, key: entity.id)
      return
    }
    // While Gmail is disconnected there is no account row; keep the entity in
    // the sync store and materialize only after reconnect.
    guard try EmailAccountRecord.fetchOne(db, key: entity.accountId) != nil else { return }
    let trimmed = entity.accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty, var account = try EmailAccountRecord.fetchOne(db, key: entity.accountId),
       account.emailAddress != trimmed {
      account.emailAddress = trimmed
      account.updatedAt = emailNowMilliseconds()
      try account.update(db)
    }
    try upsertLocalEmailMessage(db, from: entity, existingOverride: nil)
  }

  private func upsertLocalEmailMessage(
    _ db: Database,
    from entity: EmailMessageEntity,
    existingOverride: EmailMessageRecord?
  ) throws {
    let existing = try existingOverride ?? EmailMessageRecord.fetchOne(db, key: entity.id)
    // Prefer the synced full body; fall back to a local body when the cloud
    // row predates body sync and still has an empty body field.
    let body = entity.normalizedBodyText ?? existing?.normalizedBodyText
    let record = EmailMessageRecord(
      key: entity.id,
      accountId: entity.accountId,
      gmailMessageId: entity.gmailMessageId,
      threadId: entity.threadId,
      rfcMessageId: entity.rfcMessageId,
      senderName: entity.senderName,
      senderAddress: entity.senderAddress,
      subject: entity.subject,
      snippet: entity.snippet,
      internalDate: entity.internalDate,
      normalizedBodyText: body,
      analysisProviderOverride: existing?.analysisProviderOverride,
      analyzerType: entity.analyzerType,
      modelVersion: entity.modelVersion,
      promptVersion: entity.promptVersion,
      classification: entity.classification,
      merchant: entity.merchant,
      amount: entity.amount,
      currency: entity.currency,
      occurredAt: entity.occurredAt,
      categoryId: entity.categoryId,
      paymentMethodId: entity.paymentMethodId,
      paymentLastFour: entity.paymentLastFour,
      reference: entity.reference,
      state: entity.state,
      linkedTransactionId: entity.linkedTransactionId,
      analyzedAt: entity.analyzedAt,
      reviewedAt: entity.reviewedAt,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt
    )
    try record.save(db)
  }
}

private func emailSyncedSuggestionStates() -> [String] {
  [
    EmailSuggestionState.added.rawValue,
    EmailSuggestionState.dismissed.rawValue,
    EmailSuggestionState.refundApplied.rawValue,
    EmailSuggestionState.pendingPurchase.rawValue,
    EmailSuggestionState.pendingRefund.rawValue,
  ]
}

private func emailSuggestionStates(matching filter: EmailLocalSuggestionFilter?) -> [String] {
  switch filter {
  case .purchases:
    return [EmailSuggestionState.pendingPurchase.rawValue]
  case .refunds:
    return [EmailSuggestionState.pendingRefund.rawValue]
  case .reviewed:
    return [
      EmailSuggestionState.added.rawValue,
      EmailSuggestionState.refundApplied.rawValue,
      EmailSuggestionState.dismissed.rawValue,
    ]
  case nil:
    return [
      EmailSuggestionState.pendingPurchase.rawValue,
      EmailSuggestionState.pendingRefund.rawValue,
      EmailSuggestionState.added.rawValue,
      EmailSuggestionState.refundApplied.rawValue,
      EmailSuggestionState.dismissed.rawValue,
    ]
  }
}

private let emailMessageSummarySQL = """
  SELECT key, accountId, senderName, senderAddress, subject, snippet,
         internalDate, analyzerType, modelVersion, classification, state,
         analyzedAt, reviewedAt
  FROM emailMessages
  ORDER BY internalDate DESC
  """

private func emailNowMilliseconds() -> Int {
  Int(Date().timeIntervalSince1970 * 1000)
}

private func emailNonempty(_ value: String?) -> String? {
  let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed?.isEmpty == false ? trimmed : nil
}

private func validateEmailAmount(_ value: String?) throws -> String? {
  guard let value = emailNonempty(value) else { return nil }
  guard emailExactMinorUnits(value) != nil else { throw EmailRepositoryError.invalidAnalysis }
  return value
}

private func emailExactMinorUnits(_ value: String) -> Int? {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard trimmed.range(of: #"^\d+(?:\.\d{1,2})?$"#, options: .regularExpression) != nil,
        let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
        decimal > 0
  else {
    return nil
  }
  var scaled = decimal * 100
  var rounded = Decimal()
  NSDecimalRound(&rounded, &scaled, 0, .plain)
  guard scaled == rounded else { return nil }
  let number = NSDecimalNumber(decimal: rounded)
  let maximum = NSDecimalNumber(value: Int.max)
  guard number.compare(maximum) != .orderedDescending else { return nil }
  return number.intValue
}
