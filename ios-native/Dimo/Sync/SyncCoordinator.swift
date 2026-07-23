import Combine
import ConvexMobile
import Foundation

protocol SyncTransport: Sendable {
  func currentRevision(workspaceId: String) async throws -> Double
  func pull(
    entityType: EntityType,
    workspaceId: String,
    afterRevision: Double,
    limit: Double
  ) async throws -> PullResultDTO
  func push(
    entityType: EntityType,
    workspaceId: String,
    operations: [SyncOperation]
  ) async throws -> PushResultDTO
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
          try repository.updateSyncMeta {
            $0.lastPulledRevision = 0
            $0.pulledRevisions = [:]
          }
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
        _ = try repository.purgeExpiredTombstones()
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
    for entityType in EntityType.allCases {
      try await pullType(entityType)
    }
  }

  private func pullType(_ entityType: EntityType) async throws {
    var meta = try repository.syncMeta()
    var cursor = meta?.pulledRevisions[entityType] ?? meta?.lastPulledRevision ?? 0
    while true {
      let page = try await transport.pull(
        entityType: entityType,
        workspaceId: workspaceID,
        afterRevision: Double(cursor),
        limit: 100
      )
      let rows = try page.entities.map { try $0.toStoredEntity(entityType: entityType) }
      let pageCursor = rows.isEmpty
        ? Int(page.latestRevision)
        : (rows.map(\.serverRevision).max() ?? Int(page.latestRevision))
      try repository.mergeRemotePage(rows, entityType: entityType, cursor: pageCursor)
      cursor = pageCursor
      if !page.hasMore { break }
      meta = try repository.syncMeta()
    }
  }

  private func pushAll() async throws {
    while true {
      let pending = try repository.pendingOutbox(limit: 500)
      if pending.isEmpty { return }
      let grouped = Dictionary(grouping: pending, by: \.entityType)
      var pushed = false
      for (entityType, ops) in grouped {
        var index = 0
        while index < ops.count {
          let batch = Array(ops[index..<min(index + 50, ops.count)])
          try await pushBatch(entityType: entityType, operations: batch)
          pushed = true
          index += 50
        }
      }
      if !pushed { return }
    }
  }

  private func pushBatch(entityType: EntityType, operations: [SyncOperation]) async throws {
    do {
      let result = try await transport.push(
        entityType: entityType,
        workspaceId: workspaceID,
        operations: operations
      )
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
        try await pushBatch(entityType: entityType, operations: Array(operations.prefix(mid)))
        try await pushBatch(entityType: entityType, operations: Array(operations.suffix(from: mid)))
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

  func pull(
    entityType: EntityType,
    workspaceId: String,
    afterRevision: Double,
    limit: Double
  ) async throws -> PullResultDTO {
    try await firstValue(
      client.subscribe(
        to: Self.pullPath(entityType),
        with: [
          "workspaceId": workspaceId,
          "afterRevision": afterRevision,
          "limit": limit,
        ]
      )
    )
  }

  func push(
    entityType: EntityType,
    workspaceId: String,
    operations: [SyncOperation]
  ) async throws -> PushResultDTO {
    let encoded: [ConvexEncodable?] = operations.map { op -> ConvexEncodable? in
      wireTypedOperation(op) as [String: ConvexEncodable?]
    }
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        Self.pushPath(entityType),
        with: [
          "workspaceId": workspaceId,
          "operations": encoded,
        ]
      )
    }
  }

  private static func pullPath(_ type: EntityType) -> String {
    switch type {
    case .category: return "syncTyped:pullCategories"
    case .paymentMethod: return "syncTyped:pullPaymentMethods"
    case .transaction: return "syncTyped:pullTransactions"
    case .recurring: return "syncTyped:pullRecurring"
    case .lend: return "syncTyped:pullLends"
    case .emailMessage: return "syncTyped:pullEmailMessages"
    case .preferences: return "syncTyped:pullPreferences"
    }
  }

  private static func pushPath(_ type: EntityType) -> String {
    switch type {
    case .category: return "syncTyped:pushCategories"
    case .paymentMethod: return "syncTyped:pushPaymentMethods"
    case .transaction: return "syncTyped:pushTransactions"
    case .recurring: return "syncTyped:pushRecurring"
    case .lend: return "syncTyped:pushLends"
    case .emailMessage: return "syncTyped:pushEmailMessages"
    case .preferences: return "syncTyped:pushPreferences"
    }
  }

  func ensureWorkspaceProfile(workspaceId: String, name: String?, email: String?) async throws {
    struct EnsureResult: Decodable {
      var created: Bool
      var updated: Bool
      var name: String?
      var email: String?
    }
    var mutableArgs: [String: ConvexEncodable?] = ["workspaceId": workspaceId]
    if let name { mutableArgs["name"] = name }
    if let email { mutableArgs["email"] = email }
    let args = mutableArgs
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

  private func wireTypedOperation(_ op: SyncOperation) -> [String: ConvexEncodable?] {
    var dict: [String: ConvexEncodable?] = [
      "operationId": op.operationId,
      "workspaceId": op.workspaceId,
      "entityId": op.entityId,
      "version": [
        "timestamp": Double(op.version.timestamp),
        "counter": Double(op.version.counter),
        "deviceId": op.version.deviceId,
      ] as [String: ConvexEncodable?],
      "deleted": op.deleted,
    ]
    switch op.payload {
    case .category(let e):
      dict["name"] = e.name
      dict["emoji"] = e.emoji
      dict["monthlyBudgetMinor"] = e.monthlyBudgetMinor.map { Double($0) }
      dict["tint"] = e.tint.rawValue
      dict["sortOrder"] = Double(e.sortOrder)
      dict["system"] = e.system
    case .paymentMethod(let e):
      dict["name"] = e.name
      dict["type"] = e.type.rawValue
      dict["detail"] = e.detail
      dict["archived"] = e.archived
    case .transaction(let e):
      dict["name"] = e.name
      dict["amountMinor"] = Double(e.amountMinor)
      dict["occurredAt"] = Double(e.occurredAt)
      dict["categoryId"] = e.categoryId
      dict["paymentMethodId"] = e.paymentMethodId
      if let currency = e.currency, !currency.isEmpty { dict["currency"] = currency }
      if let sourceCurrency = e.sourceCurrency, !sourceCurrency.isEmpty {
        dict["sourceCurrency"] = sourceCurrency
        dict["sourceAmountMinor"] = Double(e.sourceAmountMinor ?? 0)
        if let rate = e.exchangeRate { dict["exchangeRate"] = rate }
      }
    case .recurring(let e):
      dict["name"] = e.name
      dict["amountMinor"] = Double(e.amountMinor)
      dict["categoryId"] = e.categoryId
      dict["paymentMethodId"] = e.paymentMethodId
      dict["frequency"] = e.frequency.rawValue
      dict["anchorDate"] = e.anchorDate
      dict["paused"] = e.paused
      if let currency = e.currency, !currency.isEmpty { dict["currency"] = currency }
    case .lend(let e):
      dict["contactName"] = e.contactName
      dict["contactId"] = e.contactId
      dict["amountMinor"] = Double(e.amountMinor)
      dict["occurredAt"] = Double(e.occurredAt)
      dict["comment"] = e.comment
      dict["kind"] = (e.kind ?? .lent).rawValue
    case .emailMessage(let e):
      dict["accountId"] = e.accountId
      dict["accountEmail"] = e.accountEmail
      dict["gmailMessageId"] = e.gmailMessageId
      dict["threadId"] = e.threadId
      dict["rfcMessageId"] = e.rfcMessageId
      dict["senderName"] = e.senderName
      dict["senderAddress"] = e.senderAddress
      dict["subject"] = e.subject
      dict["snippet"] = e.snippet
      dict["internalDate"] = Double(e.internalDate)
      dict["normalizedBodyText"] = e.normalizedBodyText
      dict["analyzerType"] = e.analyzerType
      dict["modelVersion"] = e.modelVersion
      dict["promptVersion"] = e.promptVersion.map { Double($0) }
      dict["classification"] = e.classification
      dict["merchant"] = e.merchant
      dict["amount"] = e.amount
      dict["currency"] = e.currency
      dict["occurredAt"] = e.occurredAt.map { Double($0) }
      dict["categoryId"] = e.categoryId
      dict["paymentMethodId"] = e.paymentMethodId
      dict["paymentLastFour"] = e.paymentLastFour
      dict["reference"] = e.reference
      dict["state"] = e.state
      dict["linkedTransactionId"] = e.linkedTransactionId
      dict["analyzedAt"] = e.analyzedAt.map { Double($0) }
      dict["reviewedAt"] = e.reviewedAt.map { Double($0) }
      dict["createdAt"] = Double(e.createdAt)
      dict["updatedAt"] = Double(e.updatedAt)
    case .preferences(let e):
      dict["profileName"] = e.profileName
      dict["profileEmail"] = e.profileEmail
      dict["currency"] = e.currency.rawValue
      dict["weekStart"] = e.weekStart.rawValue
      dict["theme"] = e.theme.rawValue
      dict["navGlassOpacity"] = Double(e.navGlassOpacity)
      dict["defaultView"] = e.defaultView.rawValue
      dict["defaultStatsRange"] = e.defaultStatsRange.rawValue
      dict["notifications"] = [
        "bills": e.notifications.bills,
        "budget": e.notifications.budget,
        "weekly": e.notifications.weekly,
        "large": e.notifications.large,
      ] as [String: ConvexEncodable?]
      dict["defaultPaymentMethodId"] = e.defaultPaymentMethodId
    }
    return dict
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
