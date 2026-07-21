import Combine
import ConvexMobile
import Foundation

protocol SyncTransport: Sendable {
  func currentRevision(workspaceId: String) async throws -> Double
  func pull(workspaceId: String, afterRevision: Double, limit: Double) async throws -> PullResultDTO
  func push(workspaceId: String, operations: [SyncOperation]) async throws -> PushResultDTO
  func ensureWorkspaceProfile(workspaceId: String, name: String?, email: String?) async throws
  func clearWorkspace(workspaceId: String, entityTypes: [String], limit: Double) async throws -> ClearResultDTO
  func latestExchangeRates() async throws -> RateTable?
  func subscribeRevision(workspaceId: String, onChange: @escaping (Double) -> Void) -> AnyCancellable
}

actor SyncCoordinator {
  private let repository: Repository
  private let transport: SyncTransport
  private let network: NetworkMonitor

  private var running: Task<Void, Never>?
  private var runGeneration = 0
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
    // Recover from an interrupted sync (kill mid-flight left syncing=true and
    // disabled Sync now in settings).
    try? repository.updateSyncMeta {
      if $0.syncing {
        $0.syncing = false
        if $0.error == nil {
          $0.error = "Sync interrupted"
        }
      }
    }
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

  func request(cancelInFlight: Bool = false) {
    if cancelInFlight {
      runGeneration += 1
      running?.cancel()
      running = nil
      retryTask?.cancel()
    }
    requested = true
    guard running == nil else { return }
    runGeneration += 1
    let generation = runGeneration
    running = Task {
      await runLoop()
      guard generation == runGeneration else { return }
      running = nil
      if requested {
        request()
      }
    }
  }

  func requestFullSync() {
    fullReplace = true
    request(cancelInFlight: true)
  }

  /// Latest ECB rates from Convex (Frankfurter is server-only, once per day).
  func latestExchangeRates() async throws -> RateTable? {
    try await transport.latestExchangeRates()
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
          // Ensure reviewed email rows exist as entities before the full upload.
          try repository.enqueueUnsyncedEmailMessages()
          try repository.backfillRecurringCurrencies()
          try await clearRemote(entityTypes: EntityType.allCases.map(\.rawValue))
          try repository.updateSyncMeta { $0.lastPulledRevision = 0 }
          try repository.enqueueFullUpload(entityTypes: Array(EntityType.allCases))
          try await pushAll()
          try await pullAll()
        } else {
          try await pullAll()
          try repository.backfillRecurringCurrencies()
          // Upload bootstrap defaults only if pull left them unsynced (empty
          // workspace). Avoids fresh null-budget seeds overwriting cloud budgets.
          try repository.enqueueUnsyncedDefaults()
          try repository.enqueueUnsyncedEmailMessages()
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
      } catch is CancellationError {
        try? repository.updateSyncMeta {
          $0.syncing = false
        }
        return
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
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "sync:push",
        with: [
          "workspaceId": workspaceId,
          "operations": encoded,
        ]
      )
    }
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
    let _: EnsureResult = try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "sync:ensureWorkspaceProfile",
        with: args
      )
    }
  }

  func clearWorkspace(workspaceId: String, entityTypes: [String], limit: Double) async throws -> ClearResultDTO {
    let encodedTypes: [ConvexEncodable?] = entityTypes.map { $0 as ConvexEncodable? }
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "sync:clearWorkspace",
        with: [
          "workspaceId": workspaceId,
          "entityTypes": encodedTypes,
          "limit": limit,
        ]
      )
    }
  }

  func latestExchangeRates() async throws -> RateTable? {
    try await firstValue(
      client.subscribe(to: "exchangeRates:latest", with: [:] as [String: ConvexEncodable?])
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
      // Keep optional currency keys omitted (not null) — matches
      // WirePayload.encode and Convex `v.optional(...)` validators.
      var dict: [String: ConvexEncodable?] = [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "occurredAt": Double(e.occurredAt),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId,
      ]
      if let currency = e.currency, !currency.isEmpty {
        dict["currency"] = currency
      }
      if let sourceCurrency = e.sourceCurrency, !sourceCurrency.isEmpty {
        dict["sourceCurrency"] = sourceCurrency
        dict["sourceAmountMinor"] = Double(e.sourceAmountMinor ?? 0)
        if let rate = e.exchangeRate {
          dict["exchangeRate"] = rate
        }
      }
      return dict
    case .recurring(let e):
      var dict: [String: ConvexEncodable?] = [
        "id": e.id,
        "name": e.name,
        "amountMinor": Double(e.amountMinor),
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId,
        "frequency": e.frequency.rawValue,
        "anchorDate": e.anchorDate,
        "paused": e.paused,
      ]
      if let currency = e.currency, !currency.isEmpty {
        dict["currency"] = currency
      }
      return dict
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
    case .emailMessage(let e):
      return [
        "id": e.id,
        "accountId": e.accountId,
        "accountEmail": e.accountEmail,
        "gmailMessageId": e.gmailMessageId,
        "threadId": e.threadId,
        "rfcMessageId": e.rfcMessageId,
        "senderName": e.senderName,
        "senderAddress": e.senderAddress,
        "subject": e.subject,
        "snippet": e.snippet,
        "internalDate": Double(e.internalDate),
        "normalizedBodyText": e.normalizedBodyText,
        "analyzerType": e.analyzerType,
        "modelVersion": e.modelVersion,
        "promptVersion": e.promptVersion.map { Double($0) },
        "classification": e.classification,
        "merchant": e.merchant,
        "amount": e.amount,
        "currency": e.currency,
        "occurredAt": e.occurredAt.map { Double($0) },
        "categoryId": e.categoryId,
        "paymentMethodId": e.paymentMethodId,
        "paymentLastFour": e.paymentLastFour,
        "reference": e.reference,
        "state": e.state,
        "linkedTransactionId": e.linkedTransactionId,
        "analyzedAt": e.analyzedAt.map { Double($0) },
        "reviewedAt": e.reviewedAt.map { Double($0) },
        "createdAt": Double(e.createdAt),
        "updatedAt": Double(e.updatedAt),
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
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      var cancellable: AnyCancellable?
      var settled = false
      cancellable = publisher
        .timeout(
          .seconds(45),
          scheduler: DispatchQueue.global(),
          customError: { ClientError.InternalError(msg: "Convex sync timed out") }
        )
        .first()
        .sink(
          receiveCompletion: { completion in
            guard !settled else { return }
            settled = true
            switch completion {
            case .failure(let error):
              continuation.resume(throwing: error)
            case .finished:
              continuation.resume(
                throwing: ClientError.InternalError(msg: "Convex subscription completed without a value")
              )
            }
            cancellable?.cancel()
          },
          receiveValue: { value in
            guard !settled else { return }
            settled = true
            continuation.resume(returning: value)
            cancellable?.cancel()
          }
        )
    }
  }

  private func withTimeout<T: Sendable>(
    seconds: Double,
    _ work: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await work() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw ClientError.InternalError(msg: "Convex sync timed out")
      }
      defer { group.cancelAll() }
      guard let value = try await group.next() else {
        throw ClientError.InternalError(msg: "Convex sync timed out")
      }
      return value
    }
  }
}
