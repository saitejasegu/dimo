import Combine
import ConvexMobile
import Foundation

protocol SyncTransport: Sendable {
  func currentRevision(workspaceId: String) async throws -> Double
  func pull(workspaceId: String, afterRevision: Double, limit: Double) async throws -> PullResultDTO
  func push(workspaceId: String, operations: [SyncOperation]) async throws -> PushResultDTO
  func ensureWorkspaceProfile(workspaceId: String, name: String?, email: String?) async throws
  func clearWorkspace(workspaceId: String, entityTypes: [String], limit: Double) async throws -> ClearResultDTO
  func subscribeRevision(workspaceId: String, onChange: @escaping (Double) -> Void) -> AnyCancellable
}

actor SyncCoordinator {
  private let repository: Repository
  private let transport: SyncTransport
  private let network: NetworkMonitor

  private var running: Task<Void, Never>?
  private var requested = false
  private var fullReplace = false
  private var retryAttempt = 0
  private var debounceTask: Task<Void, Never>?
  private var retryTask: Task<Void, Never>?
  private var revisionSub: AnyCancellable?
  private var writeListener: UUID?
  private var profileName: String?
  private var profileEmail: String?

  init(repository: Repository, transport: SyncTransport, network: NetworkMonitor = NetworkMonitor()) {
    self.repository = repository
    self.transport = transport
    self.network = network
  }

  func setProfile(name: String?, email: String?) {
    let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
    profileName = (trimmedName?.isEmpty == false) ? trimmedName : nil
    profileEmail = (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
  }

  func start() {
    writeListener = repository.onLocalWrite { [weak self] in
      Task { await self?.schedule() }
    }
    network.start { [weak self] in
      Task { await self?.request() }
    }
    revisionSub = transport.subscribeRevision(workspaceId: workspaceID) { [weak self] revision in
      Task { await self?.remoteRevisionChanged(revision) }
    }
    Task { request() }
  }

  func stop() {
    if let writeListener { repository.removeLocalWriteListener(writeListener) }
    writeListener = nil
    revisionSub?.cancel()
    revisionSub = nil
    network.stop()
    debounceTask?.cancel()
    retryTask?.cancel()
    running?.cancel()
  }

  func schedule() {
    debounceTask?.cancel()
    debounceTask = Task {
      try? await Task.sleep(nanoseconds: 250_000_000)
      request()
    }
  }

  func request() {
    requested = true
    guard running == nil else { return }
    running = Task {
      await runLoop()
      running = nil
      if requested {
        request()
      }
    }
  }

  func requestFullSync() {
    fullReplace = true
    request()
  }

  /// The revision subscription re-emits on reconnects and re-auth; only kick a
  /// sync when the server is actually ahead of what we have pulled, otherwise
  /// the coordinator loops forever and the UI reads as permanently "Syncing".
  private func remoteRevisionChanged(_ revision: Double) {
    let pulled = ((try? repository.syncMeta()) ?? nil)?.lastPulledRevision ?? 0
    guard Int(revision) > pulled else { return }
    request()
  }

  func clearCloudWorkspace() async throws {
    let types = EntityType.allCases.map(\.rawValue)
    while true {
      let result = try await transport.clearWorkspace(
        workspaceId: workspaceID,
        entityTypes: types,
        limit: 100
      )
      if !result.hasMore { return }
    }
  }

  private func runLoop() async {
    while requested {
      requested = false
      let replace = fullReplace
      fullReplace = false
      guard network.isOnline else {
        try? repository.updateSyncMeta {
          $0.syncing = false
          $0.error = "Offline"
        }
        return
      }
      try? repository.updateSyncMeta {
        $0.syncing = true
        $0.error = nil
      }
      do {
        // Backfill workspace name/email for existing rows on every authenticated sync.
        // WorkOS JWTs omit these claims, so pass the session user profile explicitly.
        try await transport.ensureWorkspaceProfile(
          workspaceId: workspaceID,
          name: profileName,
          email: profileEmail
        )
        if replace {
          try await clearRemote(entityTypes: EntityType.allCases.map(\.rawValue))
          try repository.updateSyncMeta { $0.lastPulledRevision = 0 }
          try repository.enqueueFullUpload(entityTypes: Array(EntityType.allCases))
          try await pushAll()
          try await pullAll()
        } else {
          try await pullAll()
          // Upload bootstrap defaults only if pull left them unsynced (empty
          // workspace). Avoids fresh null-budget seeds overwriting cloud budgets.
          try repository.enqueueUnsyncedDefaults()
          try await pushAll()
          try await pullAll()
        }
        retryAttempt = 0
        retryTask?.cancel()
        let blocked = try repository.blockedOutbox()
        try repository.updateSyncMeta {
          $0.syncing = false
          $0.error = blocked?.lastError
          if blocked == nil {
            $0.lastSyncedAt = Int(Date().timeIntervalSince1970 * 1000)
          }
        }
      } catch {
        if replace { fullReplace = true }
        try? repository.updateSyncMeta {
          $0.syncing = false
          $0.error = error.localizedDescription
        }
        scheduleRetry()
        return
      }
    }
  }

  private func clearRemote(entityTypes: [String]) async throws {
    while true {
      let result = try await transport.clearWorkspace(
        workspaceId: workspaceID,
        entityTypes: entityTypes,
        limit: 100
      )
      if !result.hasMore { return }
    }
  }

  private func pullAll() async throws {
    var cursor = try repository.syncMeta()?.lastPulledRevision ?? 0
    while true {
      let page = try await transport.pull(
        workspaceId: workspaceID,
        afterRevision: Double(cursor),
        limit: 100
      )
      let rows = try page.entities.map { try $0.toStoredEntity() }
      let pageCursor = rows.isEmpty
        ? Int(page.latestRevision)
        : (rows.map(\.serverRevision).max() ?? Int(page.latestRevision))
      try repository.mergeRemotePage(rows, cursor: pageCursor)
      cursor = pageCursor
      if !page.hasMore { break }
    }
  }

  private func pushAll() async throws {
    while true {
      let operations = try repository.pendingOutbox(limit: 50)
      if operations.isEmpty { return }
      try await pushBatch(operations)
    }
  }

  private func pushBatch(_ operations: [SyncOperation]) async throws {
    do {
      let result = try await transport.push(workspaceId: workspaceID, operations: operations)
      try repository.acknowledgeOperations(result.acknowledgements.map(\.operationId))
    } catch {
      let message = error.localizedDescription
      if !isPermanentSyncError(message) {
        for operation in operations {
          var updated = operation
          updated.attempts += 1
          updated.lastError = message
          try repository.updateOutbox(updated)
        }
        throw error
      }
      if operations.count > 1 {
        let mid = max(1, operations.count / 2)
        try await pushBatch(Array(operations.prefix(mid)))
        try await pushBatch(Array(operations.suffix(from: mid)))
        return
      }
      var operation = operations[0]
      operation.attempts += 1
      operation.lastError = message
      operation.status = .blocked
      try repository.updateOutbox(operation)
    }
  }

  private func scheduleRetry() {
    retryTask?.cancel()
    let base = min(300_000.0, 1000.0 * pow(2.0, Double(retryAttempt)))
    retryAttempt += 1
    let delay = base * (0.75 + Double.random(in: 0...0.5))
    retryTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
      request()
    }
  }
}

final class ConvexSyncTransport: SyncTransport, @unchecked Sendable {
  private let client: ConvexClientWithAuth<WorkOSSession>

  init(client: ConvexClientWithAuth<WorkOSSession>) {
    self.client = client
  }

  func currentRevision(workspaceId: String) async throws -> Double {
    try await firstValue(
      client.subscribe(
        to: "sync:currentRevision",
        with: ["workspaceId": workspaceId]
      )
    )
  }

  func pull(workspaceId: String, afterRevision: Double, limit: Double) async throws -> PullResultDTO {
    try await firstValue(
      client.subscribe(
        to: "sync:pull",
        with: [
          "workspaceId": workspaceId,
          "afterRevision": afterRevision,
          "limit": limit,
        ]
      )
    )
  }

  func push(workspaceId: String, operations: [SyncOperation]) async throws -> PushResultDTO {
    let encoded: [ConvexEncodable?] = operations.map { op -> ConvexEncodable? in
      wireOperation(op) as [String: ConvexEncodable?]
    }
    return try await client.mutation(
      "sync:push",
      with: [
        "workspaceId": workspaceId,
        "operations": encoded,
      ]
    )
  }

  func ensureWorkspaceProfile(workspaceId: String, name: String?, email: String?) async throws {
    struct EnsureResult: Decodable {
      var created: Bool
      var updated: Bool
      var name: String?
      var email: String?
    }
    var args: [String: ConvexEncodable?] = ["workspaceId": workspaceId]
    if let name { args["name"] = name }
    if let email { args["email"] = email }
    let _: EnsureResult = try await client.mutation(
      "sync:ensureWorkspaceProfile",
      with: args
    )
  }

  func clearWorkspace(workspaceId: String, entityTypes: [String], limit: Double) async throws -> ClearResultDTO {
    let encodedTypes: [ConvexEncodable?] = entityTypes.map { $0 as ConvexEncodable? }
    return try await client.mutation(
      "sync:clearWorkspace",
      with: [
        "workspaceId": workspaceId,
        "entityTypes": encodedTypes,
        "limit": limit,
      ]
    )
  }

  func subscribeRevision(workspaceId: String, onChange: @escaping (Double) -> Void) -> AnyCancellable {
    client.subscribe(to: "sync:currentRevision", with: ["workspaceId": workspaceId])
      .removeDuplicates()
      .sink(
        receiveCompletion: { _ in },
        receiveValue: { (value: Double) in onChange(value) }
      )
  }

  private func wireOperation(_ op: SyncOperation) -> [String: ConvexEncodable?] {
    [
      "operationId": op.operationId,
      "workspaceId": op.workspaceId,
      "entityType": op.entityType.rawValue,
      "entityId": op.entityId,
      "version": [
        "timestamp": Double(op.version.timestamp),
        "counter": Double(op.version.counter),
        "deviceId": op.version.deviceId,
      ] as [String: ConvexEncodable?],
      "payload": wirePayload(op.payload),
      "deleted": op.deleted,
    ]
  }

  private func wirePayload(_ payload: EntityPayload) -> [String: ConvexEncodable?] {
    switch payload {
    case .category(let e):
      return [
        "id": e.id,
        "name": e.name,
        "emoji": e.emoji,
        "monthlyBudgetMinor": e.monthlyBudgetMinor.map { Double($0) },
        "tint": e.tint.rawValue,
        "sortOrder": Double(e.sortOrder),
        "system": e.system,
      ]
    case .paymentMethod(let e):
      return [
        "id": e.id,
        "name": e.name,
        "type": e.type.rawValue,
        "detail": e.detail,
        "archived": e.archived,
      ]
    case .transaction(let e):
      return [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "occurredAt": Double(e.occurredAt),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId,
      ]
    case .recurring(let e):
      return [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId,
        "frequency": e.frequency.rawValue,
        "anchorDate": e.anchorDate,
        "paused": e.paused,
      ]
    case .lend(let e):
      return [
        "id": e.id,
        "contactName": e.contactName,
        "contactId": e.contactId,
        "amountMinor": Double(e.amountMinor),
        "occurredAt": Double(e.occurredAt),
        "comment": e.comment,
        "kind": (e.kind ?? .lent).rawValue,
      ]
    case .preferences(let e):
      return [
        "id": e.id,
        "profileName": e.profileName,
        "profileEmail": e.profileEmail,
        "currency": e.currency.rawValue,
        "weekStart": e.weekStart.rawValue,
        "theme": e.theme.rawValue,
        "navGlassOpacity": Double(e.navGlassOpacity),
        "defaultView": e.defaultView.rawValue,
        "defaultStatsRange": e.defaultStatsRange.rawValue,
        "notifications": [
          "bills": e.notifications.bills,
          "budget": e.notifications.budget,
          "weekly": e.notifications.weekly,
          "large": e.notifications.large,
        ] as [String: ConvexEncodable?],
        "defaultPaymentMethodId": e.defaultPaymentMethodId,
      ]
    }
  }

  private func firstValue<T: Decodable>(_ publisher: AnyPublisher<T, ClientError>) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      var cancellable: AnyCancellable?
      cancellable = publisher.first().sink(
        receiveCompletion: { completion in
          if case .failure(let error) = completion {
            continuation.resume(throwing: error)
          }
          cancellable?.cancel()
        },
        receiveValue: { value in
          continuation.resume(returning: value)
          cancellable?.cancel()
        }
      )
    }
  }
}
