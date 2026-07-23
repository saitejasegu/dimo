import Foundation
import GRDB

// MARK: - Version codec (shared)

enum VersionCodec {
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

  static func encode(_ version: LogicalVersion) throws -> Data {
    try encoder.encode(version)
  }

  static func decode(_ data: Data) throws -> LogicalVersion {
    try decoder.decode(LogicalVersion.self, from: data)
  }
}

/// One-time migration helper: decode legacy BLOB payloads before the entities
/// table is dropped. Not used on the hot path after v6.
enum PayloadCodec {
  static let encoder = VersionCodec.encoder
  static let decoder = VersionCodec.decoder

  static func encode(_ payload: EntityPayload) throws -> Data {
    switch payload {
    case .category(let value): return try encoder.encode(value)
    case .paymentMethod(let value): return try encoder.encode(value)
    case .transaction(let value): return try encoder.encode(value)
    case .recurring(let value): return try encoder.encode(value)
    case .lend(let value): return try encoder.encode(value)
    case .emailMessage(let value): return try encoder.encode(value)
    case .preferences(let value): return try encoder.encode(value)
    }
  }

  static func decode(entityType: EntityType, data: Data) throws -> EntityPayload {
    switch entityType {
    case .category: return .category(try decoder.decode(CategoryEntity.self, from: data))
    case .paymentMethod: return .paymentMethod(try decoder.decode(PaymentMethodEntity.self, from: data))
    case .transaction: return .transaction(try decoder.decode(TransactionEntity.self, from: data))
    case .recurring: return .recurring(try decoder.decode(RecurringEntity.self, from: data))
    case .lend: return .lend(try decoder.decode(LendEntity.self, from: data))
    case .emailMessage: return .emailMessage(try decoder.decode(EmailMessageEntity.self, from: data))
    case .preferences: return .preferences(try decoder.decode(PreferencesEntity.self, from: data))
    }
  }
}

// MARK: - Typed GRDB records

protocol TypedEntityRecord: Codable, FetchableRecord, PersistableRecord {
  var key: String { get set }
  var workspaceId: String { get set }
  var entityId: String { get set }
  var version: Data { get set }
  var deleted: Bool { get set }
  var serverRevision: Int { get set }
  func toStoredEntity() throws -> StoredEntity
  static func from(_ entity: StoredEntity) throws -> Self
  static var entityType: EntityType { get }
}

struct CategoryRecord: TypedEntityRecord {
  static let databaseTableName = "categories"
  static let entityType: EntityType = .category
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var name: String
  var emoji: String?
  var monthlyBudgetMinor: Int?
  var tint: String
  var sortOrder: Int
  var system: Bool

  func toStoredEntity() throws -> StoredEntity {
    StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .category,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .category(CategoryEntity(
        id: entityId,
        name: name,
        emoji: emoji ?? defaultCategoryEmoji,
        monthlyBudgetMinor: monthlyBudgetMinor,
        tint: CategoryTint(rawValue: tint) ?? .neutral,
        sortOrder: sortOrder,
        system: system
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> CategoryRecord {
    guard case .category(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a category"))
    }
    return CategoryRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      name: e.name,
      emoji: e.emoji,
      monthlyBudgetMinor: e.monthlyBudgetMinor,
      tint: e.tint.rawValue,
      sortOrder: e.sortOrder,
      system: e.system
    )
  }
}

struct PaymentMethodRecord: TypedEntityRecord {
  static let databaseTableName = "paymentMethods"
  static let entityType: EntityType = .paymentMethod
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var name: String
  var type: String
  var detail: String
  var archived: Bool

  func toStoredEntity() throws -> StoredEntity {
    StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .paymentMethod,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .paymentMethod(PaymentMethodEntity(
        id: entityId,
        name: name,
        type: PaymentMethodType(rawValue: type) ?? .Cash,
        detail: detail,
        archived: archived
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> PaymentMethodRecord {
    guard case .paymentMethod(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a paymentMethod"))
    }
    return PaymentMethodRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      name: e.name,
      type: e.type.rawValue,
      detail: e.detail,
      archived: e.archived
    )
  }
}

struct TransactionRecord: TypedEntityRecord {
  static let databaseTableName = "transactions"
  static let entityType: EntityType = .transaction
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var name: String
  var amountMinor: Int
  var occurredAt: Int
  var categoryId: String
  var paymentMethodId: String?
  var currency: String?
  var sourceCurrency: String?
  var sourceAmountMinor: Int?
  var exchangeRate: Double?

  func toStoredEntity() throws -> StoredEntity {
    StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .transaction,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .transaction(TransactionEntity(
        id: entityId,
        name: name,
        amountMinor: amountMinor,
        occurredAt: occurredAt,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        currency: currency,
        sourceCurrency: sourceCurrency,
        sourceAmountMinor: sourceAmountMinor,
        exchangeRate: exchangeRate
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> TransactionRecord {
    guard case .transaction(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a transaction"))
    }
    return TransactionRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      name: e.name,
      amountMinor: e.amountMinor,
      occurredAt: e.occurredAt,
      categoryId: e.categoryId,
      paymentMethodId: e.paymentMethodId,
      currency: e.currency,
      sourceCurrency: e.sourceCurrency,
      sourceAmountMinor: e.sourceAmountMinor,
      exchangeRate: e.exchangeRate
    )
  }
}

struct RecurringRecord: TypedEntityRecord {
  static let databaseTableName = "recurring"
  static let entityType: EntityType = .recurring
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var name: String
  var amountMinor: Int
  var categoryId: String
  var paymentMethodId: String?
  var frequency: String
  var anchorDate: String
  var paused: Bool
  var currency: String?

  func toStoredEntity() throws -> StoredEntity {
    StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .recurring,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .recurring(RecurringEntity(
        id: entityId,
        name: name,
        amountMinor: amountMinor,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        frequency: RecurringFrequency(rawValue: frequency) ?? .monthly,
        anchorDate: anchorDate,
        paused: paused,
        currency: currency
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> RecurringRecord {
    guard case .recurring(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a recurring"))
    }
    return RecurringRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      name: e.name,
      amountMinor: e.amountMinor,
      categoryId: e.categoryId,
      paymentMethodId: e.paymentMethodId,
      frequency: e.frequency.rawValue,
      anchorDate: e.anchorDate,
      paused: e.paused,
      currency: e.currency
    )
  }
}

struct LendRecord: TypedEntityRecord {
  static let databaseTableName = "lends"
  static let entityType: EntityType = .lend
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var contactName: String
  var contactId: String?
  var amountMinor: Int
  var occurredAt: Int
  var comment: String
  var kind: String?

  func toStoredEntity() throws -> StoredEntity {
    let resolvedContactId: String = {
      let trimmed = contactId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? contactName : trimmed
    }()
    return StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .lend,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .lend(LendEntity(
        id: entityId,
        contactName: contactName,
        contactId: resolvedContactId,
        amountMinor: amountMinor,
        occurredAt: occurredAt,
        comment: comment,
        kind: kind.flatMap(LendKind.init(rawValue:))
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> LendRecord {
    guard case .lend(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not a lend"))
    }
    return LendRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      contactName: e.contactName,
      contactId: e.contactId,
      amountMinor: e.amountMinor,
      occurredAt: e.occurredAt,
      comment: e.comment,
      kind: e.kind?.rawValue
    )
  }
}

struct SyncedEmailMessageRecord: TypedEntityRecord {
  static let databaseTableName = "syncedEmailMessages"
  static let entityType: EntityType = .emailMessage
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var accountId: String
  var accountEmail: String
  var gmailMessageId: String
  var threadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Int
  var normalizedBodyText: String?
  var analyzerType: String?
  var modelVersion: String?
  var promptVersion: Int?
  var classification: String?
  var merchant: String?
  var amount: String?
  var currency: String?
  var occurredAt: Int?
  var categoryId: String?
  var paymentMethodId: String?
  var paymentLastFour: String?
  var reference: String?
  var state: String
  var linkedTransactionId: String?
  var analyzedAt: Int?
  var reviewedAt: Int?
  var createdAt: Int
  var updatedAt: Int

  func toStoredEntity() throws -> StoredEntity {
    StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .emailMessage,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .emailMessage(EmailMessageEntity(
        id: entityId,
        accountId: accountId,
        accountEmail: accountEmail,
        gmailMessageId: gmailMessageId,
        threadId: threadId,
        rfcMessageId: rfcMessageId,
        senderName: senderName,
        senderAddress: senderAddress,
        subject: subject,
        snippet: snippet,
        internalDate: internalDate,
        normalizedBodyText: normalizedBodyText,
        analyzerType: analyzerType,
        modelVersion: modelVersion,
        promptVersion: promptVersion,
        classification: classification,
        merchant: merchant,
        amount: amount,
        currency: currency,
        occurredAt: occurredAt,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        paymentLastFour: paymentLastFour,
        reference: reference,
        state: state,
        linkedTransactionId: linkedTransactionId,
        analyzedAt: analyzedAt,
        reviewedAt: reviewedAt,
        createdAt: createdAt,
        updatedAt: updatedAt
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> SyncedEmailMessageRecord {
    guard case .emailMessage(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not an emailMessage"))
    }
    return SyncedEmailMessageRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      accountId: e.accountId,
      accountEmail: e.accountEmail,
      gmailMessageId: e.gmailMessageId,
      threadId: e.threadId,
      rfcMessageId: e.rfcMessageId,
      senderName: e.senderName,
      senderAddress: e.senderAddress,
      subject: e.subject,
      snippet: e.snippet,
      internalDate: e.internalDate,
      normalizedBodyText: e.normalizedBodyText,
      analyzerType: e.analyzerType,
      modelVersion: e.modelVersion,
      promptVersion: e.promptVersion,
      classification: e.classification,
      merchant: e.merchant,
      amount: e.amount,
      currency: e.currency,
      occurredAt: e.occurredAt,
      categoryId: e.categoryId,
      paymentMethodId: e.paymentMethodId,
      paymentLastFour: e.paymentLastFour,
      reference: e.reference,
      state: e.state,
      linkedTransactionId: e.linkedTransactionId,
      analyzedAt: e.analyzedAt,
      reviewedAt: e.reviewedAt,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt
    )
  }
}

struct PreferencesRecord: TypedEntityRecord {
  static let databaseTableName = "preferences"
  static let entityType: EntityType = .preferences
  var key: String
  var workspaceId: String
  var entityId: String
  var version: Data
  var deleted: Bool
  var serverRevision: Int
  var profileName: String
  var profileEmail: String
  var currency: String
  var weekStart: String
  var theme: String?
  var navGlassOpacity: Int?
  var defaultView: String
  var defaultStatsRange: String?
  var notificationsJSON: Data
  var defaultPaymentMethodId: String

  func toStoredEntity() throws -> StoredEntity {
    let notifications = try VersionCodec.decoder.decode(
      NotificationSettings.self,
      from: notificationsJSON
    )
    return StoredEntity(
      key: key,
      workspaceId: workspaceId,
      entityType: .preferences,
      entityId: entityId,
      version: try VersionCodec.decode(version),
      payload: .preferences(PreferencesEntity(
        id: "preferences",
        profileName: profileName,
        profileEmail: profileEmail,
        currency: Currency(rawValue: currency) ?? .INR,
        weekStart: WeekStart(rawValue: weekStart) ?? .Mon,
        theme: theme.flatMap(ThemePreference.init(rawValue:)) ?? .light,
        navGlassOpacity: navGlassOpacity ?? 40,
        defaultView: ViewKey(rawValue: defaultView) ?? .home,
        defaultStatsRange: defaultStatsRange.flatMap(StatsRange.init(rawValue:)) ?? .oneYear,
        notifications: notifications,
        defaultPaymentMethodId: defaultPaymentMethodId
      )),
      deleted: deleted,
      serverRevision: serverRevision
    )
  }

  static func from(_ entity: StoredEntity) throws -> PreferencesRecord {
    guard case .preferences(let e) = entity.payload else {
      throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not preferences"))
    }
    return PreferencesRecord(
      key: entity.key,
      workspaceId: entity.workspaceId,
      entityId: entity.entityId,
      version: try VersionCodec.encode(entity.version),
      deleted: entity.deleted,
      serverRevision: entity.serverRevision,
      profileName: e.profileName,
      profileEmail: e.profileEmail,
      currency: e.currency.rawValue,
      weekStart: e.weekStart.rawValue,
      theme: e.theme.rawValue,
      navGlassOpacity: e.navGlassOpacity,
      defaultView: e.defaultView.rawValue,
      defaultStatsRange: e.defaultStatsRange.rawValue,
      notificationsJSON: try VersionCodec.encoder.encode(e.notifications),
      defaultPaymentMethodId: e.defaultPaymentMethodId
    )
  }
}

// MARK: - Typed entity store (EntityRecord replacement)

enum TypedEntityStore {
  static func tableName(for type: EntityType) -> String {
    switch type {
    case .category: return CategoryRecord.databaseTableName
    case .paymentMethod: return PaymentMethodRecord.databaseTableName
    case .transaction: return TransactionRecord.databaseTableName
    case .recurring: return RecurringRecord.databaseTableName
    case .lend: return LendRecord.databaseTableName
    case .emailMessage: return SyncedEmailMessageRecord.databaseTableName
    case .preferences: return PreferencesRecord.databaseTableName
    }
  }

  static func save(_ entity: StoredEntity, db: Database) throws {
    switch entity.entityType {
    case .category: try CategoryRecord.from(entity).save(db)
    case .paymentMethod: try PaymentMethodRecord.from(entity).save(db)
    case .transaction: try TransactionRecord.from(entity).save(db)
    case .recurring: try RecurringRecord.from(entity).save(db)
    case .lend: try LendRecord.from(entity).save(db)
    case .emailMessage: try SyncedEmailMessageRecord.from(entity).save(db)
    case .preferences: try PreferencesRecord.from(entity).save(db)
    }
  }

  static func fetchOne(db: Database, key: String) throws -> StoredEntity? {
    if let row = try CategoryRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try PaymentMethodRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try TransactionRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try RecurringRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try LendRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try SyncedEmailMessageRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    if let row = try PreferencesRecord.fetchOne(db, key: key) { return try row.toStoredEntity() }
    return nil
  }

  static func fetchOne(db: Database, type: EntityType, key: String) throws -> StoredEntity? {
    switch type {
    case .category: return try CategoryRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .paymentMethod: return try PaymentMethodRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .transaction: return try TransactionRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .recurring: return try RecurringRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .lend: return try LendRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .emailMessage: return try SyncedEmailMessageRecord.fetchOne(db, key: key)?.toStoredEntity()
    case .preferences: return try PreferencesRecord.fetchOne(db, key: key)?.toStoredEntity()
    }
  }

  static func deleteOne(db: Database, type: EntityType, key: String) throws {
    switch type {
    case .category: _ = try CategoryRecord.deleteOne(db, key: key)
    case .paymentMethod: _ = try PaymentMethodRecord.deleteOne(db, key: key)
    case .transaction: _ = try TransactionRecord.deleteOne(db, key: key)
    case .recurring: _ = try RecurringRecord.deleteOne(db, key: key)
    case .lend: _ = try LendRecord.deleteOne(db, key: key)
    case .emailMessage: _ = try SyncedEmailMessageRecord.deleteOne(db, key: key)
    case .preferences: _ = try PreferencesRecord.deleteOne(db, key: key)
    }
  }

  static func fetchAll(db: Database, type: EntityType, workspaceId: String) throws -> [StoredEntity] {
    switch type {
    case .category:
      return try CategoryRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .paymentMethod:
      return try PaymentMethodRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .transaction:
      return try TransactionRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .recurring:
      return try RecurringRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .lend:
      return try LendRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .emailMessage:
      return try SyncedEmailMessageRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    case .preferences:
      return try PreferencesRecord
        .filter(Column("workspaceId") == workspaceId)
        .fetchAll(db)
        .map { try $0.toStoredEntity() }
    }
  }

  static func fetchAll(db: Database, workspaceId: String) throws -> [StoredEntity] {
    var rows: [StoredEntity] = []
    for type in EntityType.allCases {
      rows.append(contentsOf: try fetchAll(db: db, type: type, workspaceId: workspaceId))
    }
    return rows
  }
}

/// Dirty-key outbox — no payload snapshot. Push reads the typed row.
struct OutboxRecord: Codable, FetchableRecord, PersistableRecord {
  static let databaseTableName = "outbox"

  var key: String
  var operationId: String
  var workspaceId: String
  var entityType: String
  var entityId: String
  var status: String
  var attempts: Int
  var lastError: String?
  var createdAt: Int

  func toSyncOperation(payload: EntityPayload, version: LogicalVersion, deleted: Bool) -> SyncOperation {
    SyncOperation(
      operationId: operationId,
      key: key,
      workspaceId: workspaceId,
      entityType: EntityType(rawValue: entityType) ?? .transaction,
      entityId: entityId,
      version: version,
      payload: payload,
      deleted: deleted,
      status: OutboxStatus(rawValue: status) ?? .pending,
      attempts: attempts,
      lastError: lastError,
      createdAt: createdAt
    )
  }

  static func fromDirty(_ op: SyncOperation) -> OutboxRecord {
    OutboxRecord(
      key: op.key,
      operationId: op.operationId,
      workspaceId: op.workspaceId,
      entityType: op.entityType.rawValue,
      entityId: op.entityId,
      status: op.status.rawValue,
      attempts: op.attempts,
      lastError: op.lastError,
      createdAt: op.createdAt
    )
  }

  static func from(_ op: SyncOperation) -> OutboxRecord {
    fromDirty(op)
  }

  func toSyncOperation() throws -> SyncOperation {
    // Payload/version filled by Repository when hydrating from typed store.
    SyncOperation(
      operationId: operationId,
      key: key,
      workspaceId: workspaceId,
      entityType: EntityType(rawValue: entityType) ?? .transaction,
      entityId: entityId,
      version: LogicalVersion(timestamp: 0, counter: 0, deviceId: ""),
      payload: .transaction(TransactionEntity(
        id: entityId,
        name: "",
        amountMinor: 1,
        occurredAt: 0,
        categoryId: "",
        paymentMethodId: nil
      )),
      deleted: false,
      status: OutboxStatus(rawValue: status) ?? .pending,
      attempts: attempts,
      lastError: lastError,
      createdAt: createdAt
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
  /// JSON-encoded `[EntityType.rawValue: Int]` per-type pull cursors.
  var pulledRevisionsJSON: Data?

  func toSyncMeta() -> SyncMeta {
    SyncMeta(
      workspaceId: workspaceId,
      lastPulledRevision: lastPulledRevision,
      lastSyncedAt: lastSyncedAt,
      error: error,
      syncing: syncing,
      pulledRevisions: Self.decodePulled(pulledRevisionsJSON)
    )
  }

  static func from(_ meta: SyncMeta) -> SyncMetaRecord {
    SyncMetaRecord(
      workspaceId: meta.workspaceId,
      lastPulledRevision: meta.lastPulledRevision,
      lastSyncedAt: meta.lastSyncedAt,
      error: meta.error,
      syncing: meta.syncing,
      pulledRevisionsJSON: try? VersionCodec.encoder.encode(meta.pulledRevisions.mapKeys(\.rawValue))
    )
  }

  private static func decodePulled(_ data: Data?) -> [EntityType: Int] {
    guard let data,
          let raw = try? VersionCodec.decoder.decode([String: Int].self, from: data)
    else { return [:] }
    var result: [EntityType: Int] = [:]
    for (key, value) in raw {
      if let type = EntityType(rawValue: key) { result[type] = value }
    }
    return result
  }
}

private extension Dictionary where Key == EntityType, Value == Int {
  func mapKeys(_ transform: (EntityType) -> String) -> [String: Int] {
    var result: [String: Int] = [:]
    for (key, value) in self { result[transform(key)] = value }
    return result
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

/// Compatibility alias used during the Repository migration.
typealias EntityRecord = TypedEntityStoreCompat

enum TypedEntityStoreCompat {
  static func fetchOne(_ db: Database, key: String) throws -> StoredEntityWrapper? {
    guard let entity = try TypedEntityStore.fetchOne(db: db, key: key) else { return nil }
    return StoredEntityWrapper(entity: entity)
  }

  static func from(_ entity: StoredEntity) throws -> StoredEntityWriter {
    StoredEntityWriter(entity: entity)
  }

  static func deleteOne(_ db: Database, key: String) throws -> Bool {
    // Probe type from key: "global:type:id"
    let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3, let type = EntityType(rawValue: parts[1]) else { return false }
    try TypedEntityStore.deleteOne(db: db, type: type, key: key)
    return true
  }
}

struct StoredEntityWrapper {
  let entity: StoredEntity
  var deleted: Bool { entity.deleted }
  var key: String { entity.key }
  var serverRevision: Int { entity.serverRevision }
  var entityType: String { entity.entityType.rawValue }
  var entityId: String { entity.entityId }
  var workspaceId: String { entity.workspaceId }

  func toStoredEntity() throws -> StoredEntity { entity }
}

struct StoredEntityWriter {
  let entity: StoredEntity
  func save(_ db: Database) throws {
    try TypedEntityStore.save(entity, db: db)
  }
}
