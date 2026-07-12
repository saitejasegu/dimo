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
      try? FileManager.default.removeItem(at: file)
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path + "-wal"))
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path + "-shm"))
    }
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
    return migrator
  }
}
