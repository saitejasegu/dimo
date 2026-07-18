import Foundation
import GRDB

enum AppDatabase {
  private static let lock = NSLock()
  private static var queue: DatabaseQueue?
  private static var activeUserId: String?

  static var shared: DatabaseQueue {
    lock.lock(); defer { lock.unlock() }
    if let queue { return queue }
    let q = try! openUnconfigured()
    queue = q
    return q
  }

  @discardableResult
  static func activate(userId: String) throws -> DatabaseQueue {
    lock.lock(); defer { lock.unlock() }
    if activeUserId == userId, let queue { return queue }
    try queue?.close()
    let q = try open(userId: userId)
    queue = q
    activeUserId = userId
    return q
  }

  static func close() throws {
    lock.lock(); defer { lock.unlock() }
    try queue?.close()
    queue = nil
    activeUserId = nil
  }

  static func deleteAllLocalDatabases() throws {
    try close()
    let dir = try applicationSupportDirectory()
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
    for file in files where file.lastPathComponent.hasPrefix("dimo-") && file.pathExtension == "sqlite" {
      try removeIfPresent(file)
      try removeIfPresent(URL(fileURLWithPath: file.path + "-wal"))
      try removeIfPresent(URL(fileURLWithPath: file.path + "-shm"))
      try removeIfPresent(URL(fileURLWithPath: file.path + "-journal"))
    }
  }

  private static func removeIfPresent(_ url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.removeItem(at: url)
  }

  private static func openUnconfigured() throws -> DatabaseQueue {
    try open(fileName: "dimo-unconfigured.sqlite")
  }

  private static func open(userId: String) throws -> DatabaseQueue {
    let safe = userId
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    return try open(fileName: "dimo-\(safe).sqlite")
  }

  private static func open(fileName: String) throws -> DatabaseQueue {
    let dir = try applicationSupportDirectory()
    let url = dir.appendingPathComponent(fileName)
    var config = Configuration()
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
    let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
    try migrator.migrate(dbQueue)
    return dbQueue
  }

  private static func applicationSupportDirectory() throws -> URL {
    let url = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("Dimo", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
    var excludedURL = url
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try excludedURL.setResourceValues(resourceValues)
    return url
  }

  private static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1") { db in
      try db.create(table: "entities") { t in
        t.column("key", .text).primaryKey()
        t.column("workspaceId", .text).notNull()
        t.column("entityType", .text).notNull()
        t.column("entityId", .text).notNull()
        t.column("version", .blob).notNull()
        t.column("payload", .blob).notNull()
        t.column("deleted", .boolean).notNull().defaults(to: false)
        t.column("serverRevision", .integer).notNull().defaults(to: 0)
      }
      try db.create(
        index: "entities_workspace_type",
        on: "entities",
        columns: ["workspaceId", "entityType"]
      )
      try db.create(
        index: "entities_workspace_revision",
        on: "entities",
        columns: ["workspaceId", "serverRevision"]
      )

      try db.create(table: "outbox") { t in
        t.column("key", .text).primaryKey()
        t.column("operationId", .text).notNull().unique()
        t.column("workspaceId", .text).notNull()
        t.column("entityType", .text).notNull()
        t.column("entityId", .text).notNull()
        t.column("version", .blob).notNull()
        t.column("payload", .blob).notNull()
        t.column("deleted", .boolean).notNull().defaults(to: false)
        t.column("status", .text).notNull()
        t.column("attempts", .integer).notNull().defaults(to: 0)
        t.column("lastError", .text)
        t.column("createdAt", .integer).notNull()
      }
      try db.create(index: "outbox_status", on: "outbox", columns: ["status"])
      try db.create(index: "outbox_createdAt", on: "outbox", columns: ["createdAt"])

      try db.create(table: "syncMeta") { t in
        t.column("workspaceId", .text).primaryKey()
        t.column("lastPulledRevision", .integer).notNull().defaults(to: 0)
        t.column("lastSyncedAt", .integer)
        t.column("error", .text)
        t.column("syncing", .boolean).notNull().defaults(to: false)
      }

      try db.create(table: "deviceMeta") { t in
        t.column("id", .text).primaryKey()
        t.column("deviceId", .text).notNull()
        t.column("clockTimestamp", .integer).notNull().defaults(to: 0)
        t.column("clockCounter", .integer).notNull().defaults(to: 0)
        t.column("bootstrapVersion", .integer).notNull().defaults(to: 0)
        t.column("lastPaymentMethodId", .text)
      }
    }

    // Working Gmail fetch/analysis tables. Reviewed suggestions are also
    // dual-written into the synced `emailMessage` entity/outbox path. These
    // local tables live in the account-scoped database and are removed with
    // it on sign-out.
    migrator.registerMigration("v2-email-local") { db in
      try db.create(table: "emailAccounts") { t in
        // Google's OpenID `sub` claim is stable even when the address changes.
        t.column("id", .text).primaryKey()
        t.column("emailAddress", .text).notNull()
        t.column("historyId", .text)
        t.column("backfillPageToken", .text)
        t.column("backfillCompletedAt", .integer)
        t.column("lastAttemptAt", .integer)
        t.column("lastSuccessfulSyncAt", .integer)
        t.column("syncState", .text).notNull()
        t.column("lastError", .text)
        t.column("createdAt", .integer).notNull()
        t.column("updatedAt", .integer).notNull()
      }
      try db.create(index: "email_accounts_address", on: "emailAccounts", columns: ["emailAddress"])

      try db.create(table: "emailMessages") { t in
        t.column("key", .text).primaryKey()
        t.column("accountId", .text)
          .notNull()
          .references("emailAccounts", column: "id", onDelete: .cascade)
        t.column("gmailMessageId", .text).notNull()
        t.column("threadId", .text).notNull()
        t.column("rfcMessageId", .text)
        t.column("senderName", .text)
        t.column("senderAddress", .text).notNull()
        t.column("subject", .text).notNull()
        t.column("snippet", .text).notNull()
        t.column("internalDate", .integer).notNull()
        t.column("normalizedBodyText", .text)
        t.column("analyzerType", .text)
        t.column("modelVersion", .text)
        t.column("promptVersion", .integer)
        t.column("classification", .text)
        t.column("merchant", .text)
        // Keep a canonical decimal string. Converting email amounts to a
        // binary floating-point column would make exact refund checks unsafe.
        t.column("amount", .text)
        t.column("currency", .text)
        t.column("occurredAt", .integer)
        t.column("categoryId", .text)
        t.column("paymentMethodId", .text)
        t.column("paymentLastFour", .text)
        t.column("reference", .text)
        t.column("state", .text).notNull()
        t.column("linkedTransactionId", .text)
        t.column("analyzedAt", .integer)
        t.column("reviewedAt", .integer)
        t.column("createdAt", .integer).notNull()
        t.column("updatedAt", .integer).notNull()
        t.uniqueKey(["accountId", "gmailMessageId"])
      }
      try db.create(
        index: "email_messages_account_date",
        on: "emailMessages",
        columns: ["accountId", "internalDate"]
      )
      try db.create(
        index: "email_messages_state_date",
        on: "emailMessages",
        columns: ["state", "internalDate"]
      )
      try db.create(
        index: "email_messages_analysis_queue",
        on: "emailMessages",
        columns: ["analyzerType", "state", "internalDate"]
      )
    }
    migrator.registerMigration("v3-email-analysis-providers") { db in
      try db.alter(table: "emailMessages") { t in
        t.add(column: "analysisProviderOverride", .text)
      }
      try db.create(table: "emailAnalysisSettings") { t in
        t.column("id", .text).primaryKey()
        t.column("selectedProvider", .text)
        t.column("openRouterModelID", .text)
        t.column("openRouterPrivacyMode", .text).notNull().defaults(to: "zdrOnly")
        t.column("nonZDRConsentVersion", .integer)
        t.column("updatedAt", .integer).notNull()
      }
      try db.create(table: "emailAnalysisRetry") { t in
        t.column("id", .text).primaryKey()
        t.column("attempt", .integer).notNull().defaults(to: 0)
        t.column("notBefore", .integer)
        t.column("reason", .text)
        t.column("lastHTTPStatus", .integer)
        t.column("updatedAt", .integer).notNull()
      }
    }
    migrator.registerMigration("v4-email-sync-window") { db in
      try db.alter(table: "emailAnalysisSettings") { t in
        t.add(column: "syncWindow", .text)
          .notNull()
          .defaults(to: EmailSyncWindow.defaultValue.rawValue)
      }
    }
    migrator.registerMigration("v5-email-gemma-model-variant") { db in
      try db.alter(table: "emailAnalysisSettings") { t in
        t.add(column: "gemmaModelVariant", .text)
          .notNull()
          .defaults(to: EmailGemmaModelVariant.defaultValue.rawValue)
      }
    }
    return migrator
  }
}
