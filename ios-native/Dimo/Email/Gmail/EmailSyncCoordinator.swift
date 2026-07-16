import Foundation

enum GmailSyncState: String, Codable, Sendable {
  case idle
  case backfilling
  case syncing
  case rateLimited
  case offline
  case needsReconnect
  case failed
}

struct EmailAccountSnapshot: Hashable, Sendable {
  var googleSubject: String
  var emailAddress: String
  var historyId: String?
  var backfillPageToken: String?
  var backfillCompletedAt: Date?
}

struct EmailMessagePayload: Hashable, Sendable {
  var accountSubject: String
  var gmailMessageId: String
  var gmailThreadId: String
  var rfcMessageId: String?
  var senderName: String?
  var senderAddress: String
  var subject: String
  var snippet: String
  var internalDate: Date
  var normalizedBody: String
}

/// Persistence boundary for account-scoped, local-only email tables.
/// Implementations must not create Dimo entities or outbox operations here.
protocol EmailSyncPersistence: Sendable {
  func emailAccountsForSync(dimoUserId: String) async throws -> [EmailAccountSnapshot]
  func recordEmailSyncAttempt(
    accountSubject: String,
    at date: Date,
    state: GmailSyncState
  ) async throws
  func storePendingEmailMessages(_ messages: [EmailMessagePayload]) async throws
  func advanceEmailBackfill(
    accountSubject: String,
    nextPageToken: String?,
    completedAt: Date?,
    historyId: String?
  ) async throws
  func advanceEmailHistory(accountSubject: String, historyId: String) async throws
  func resetEmailBackfill(accountSubject: String) async throws
  func finishEmailSync(
    accountSubject: String,
    at date: Date,
    state: GmailSyncState,
    error: String?
  ) async throws
  /// Clears an interrupted syncing/backfilling state without claiming success.
  func abandonEmailSync(accountSubject: String) async throws
}

/// Synchronizes mailbox pages round-robin. A failing mailbox is removed from the
/// current run without preventing the remaining accounts from progressing.
actor EmailSyncCoordinator {
  private enum Work {
    case backfill(account: EmailAccountSnapshot, pageToken: String?)
    case incremental(
      account: EmailAccountSnapshot,
      startHistoryId: String,
      pageToken: String?
    )

    var account: EmailAccountSnapshot {
      switch self {
      case .backfill(let account, _), .incremental(let account, _, _): return account
      }
    }
  }

  private let api: any GmailAPIClient
  private let persistence: any EmailSyncPersistence
  private let calendar: Calendar
  private var stopRequested = false
  private var refreshInProgress = false
  private var scheduledRetryTasks: [String: Task<Void, Never>] = [:]

  init(
    api: any GmailAPIClient,
    persistence: any EmailSyncPersistence,
    calendar: Calendar = .current
  ) {
    self.api = api
    self.persistence = persistence
    self.calendar = calendar
  }

  func refresh(
    dimoUserId: String,
    accountSubject: String? = nil,
    syncWindow: EmailSyncWindow = .defaultValue,
    now: Date = .now
  ) async {
    guard !refreshInProgress else { return }
    refreshInProgress = true
    defer { refreshInProgress = false }
    stopRequested = false
    let accounts: [EmailAccountSnapshot]
    do {
      let allAccounts = try await persistence.emailAccountsForSync(dimoUserId: dimoUserId)
      accounts = accountSubject.map { selected in
        allAccounts.filter { $0.googleSubject == selected }
      } ?? allAccounts
    } catch {
      return
    }
    for account in accounts {
      scheduledRetryTasks.removeValue(forKey: account.googleSubject)?.cancel()
    }

    var work = accounts.map { account -> Work in
      if account.backfillCompletedAt == nil || account.historyId == nil {
        return .backfill(account: account, pageToken: account.backfillPageToken)
      }
      return .incremental(
        account: account,
        startHistoryId: account.historyId!,
        pageToken: nil
      )
    }
    for account in accounts {
      try? await persistence.recordEmailSyncAttempt(
        accountSubject: account.googleSubject,
        at: now,
        state: account.backfillCompletedAt == nil || account.historyId == nil
          ? .backfilling
          : .syncing
      )
    }

    while !work.isEmpty, !stopRequested, !Task.isCancelled {
      var nextRound: [Work] = []
      for item in work {
        guard !stopRequested, !Task.isCancelled else { break }
        do {
          if let next = try await processOnePage(
            item,
            dimoUserId: dimoUserId,
            syncWindow: syncWindow,
            now: now
          ) {
            nextRound.append(next)
          }
        } catch GmailAPIError.historyCursorExpired {
          try? await persistence.resetEmailBackfill(accountSubject: item.account.googleSubject)
          var resetAccount = item.account
          resetAccount.historyId = nil
          resetAccount.backfillPageToken = nil
          resetAccount.backfillCompletedAt = nil
          nextRound.append(.backfill(account: resetAccount, pageToken: nil))
        } catch GmailOAuthError.requiresReconnect {
          try? await persistence.finishEmailSync(
            accountSubject: item.account.googleSubject,
            at: .now,
            state: .needsReconnect,
            error: GmailOAuthError.requiresReconnect.localizedDescription
          )
        } catch let GmailAPIError.rateLimited(retryAfter) {
          try? await persistence.finishEmailSync(
            accountSubject: item.account.googleSubject,
            at: .now,
            state: .rateLimited,
            error: nil
          )
          scheduleRetry(
            dimoUserId: dimoUserId,
            accountSubject: item.account.googleSubject,
            syncWindow: syncWindow,
            after: retryAfter ?? 60
          )
        } catch let error as URLError where Self.isOffline(error) {
          try? await persistence.finishEmailSync(
            accountSubject: item.account.googleSubject,
            at: .now,
            state: .offline,
            error: "Gmail will refresh when this iPhone is online."
          )
        } catch let error where Self.isCancellation(error) {
          await abandonInFlightAccounts(accounts)
          return
        } catch {
          try? await persistence.finishEmailSync(
            accountSubject: item.account.googleSubject,
            at: .now,
            state: .failed,
            error: error.localizedDescription
          )
        }
      }
      work = nextRound
    }

    if stopRequested || Task.isCancelled {
      await abandonInFlightAccounts(accounts)
    }
  }

  private func abandonInFlightAccounts(_ accounts: [EmailAccountSnapshot]) async {
    for account in accounts {
      try? await persistence.abandonEmailSync(accountSubject: account.googleSubject)
    }
  }

  func stop() async {
    stopRequested = true
    for task in scheduledRetryTasks.values { task.cancel() }
    scheduledRetryTasks.removeAll()
    while refreshInProgress {
      await Task.yield()
    }
  }

  private func scheduleRetry(
    dimoUserId: String,
    accountSubject: String,
    syncWindow: EmailSyncWindow,
    after requestedDelay: TimeInterval
  ) {
    scheduledRetryTasks[accountSubject]?.cancel()
    let delay = min(max(requestedDelay, 5), 300)
    scheduledRetryTasks[accountSubject] = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(Int64(delay * 1_000)))
      } catch {
        return
      }
      await self?.runScheduledRetry(
        dimoUserId: dimoUserId,
        accountSubject: accountSubject,
        syncWindow: syncWindow
      )
    }
  }

  private func runScheduledRetry(
    dimoUserId: String,
    accountSubject: String,
    syncWindow: EmailSyncWindow
  ) async {
    while refreshInProgress {
      do {
        try await Task.sleep(for: .seconds(1))
      } catch {
        return
      }
    }
    guard !Task.isCancelled else { return }
    scheduledRetryTasks[accountSubject] = nil
    await refresh(
      dimoUserId: dimoUserId,
      accountSubject: accountSubject,
      syncWindow: syncWindow
    )
  }

  private static func isOffline(_ error: URLError) -> Bool {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .timedOut,
         .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
      return true
    default:
      return false
    }
  }

  private static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
  }

  private func processOnePage(
    _ work: Work,
    dimoUserId: String,
    syncWindow: EmailSyncWindow,
    now: Date
  ) async throws -> Work? {
    switch work {
    case .backfill(let originalAccount, let pageToken):
      var account = originalAccount
      // Capture the cursor before the scan. Starting incremental history from
      // this point after the scan closes the race with messages that arrive
      // while paged backfill is in progress.
      if account.historyId == nil {
        let profile = try await api.profile(
          subject: account.googleSubject,
          dimoUserId: dimoUserId
        )
        account.historyId = profile.historyId
        try await persistence.advanceEmailBackfill(
          accountSubject: account.googleSubject,
          nextPageToken: pageToken,
          completedAt: nil,
          historyId: profile.historyId
        )
      }
      let since = syncWindow.cutoff(from: now, calendar: calendar)
      let page = try await api.listMessages(
        subject: account.googleSubject,
        dimoUserId: dimoUserId,
        since: since,
        pageToken: pageToken
      )
      try await fetchAndPersist(
        ids: page.messages.map(\.id),
        accountSubject: account.googleSubject,
        dimoUserId: dimoUserId,
        syncWindow: syncWindow,
        now: now
      )
      if let nextPageToken = page.nextPageToken {
        try await persistence.advanceEmailBackfill(
          accountSubject: account.googleSubject,
          nextPageToken: nextPageToken,
          completedAt: nil,
          historyId: nil
        )
        return .backfill(account: account, pageToken: nextPageToken)
      }
      guard let capturedHistoryId = account.historyId else {
        throw GmailAPIError.invalidResponse
      }
      try await persistence.advanceEmailBackfill(
        accountSubject: account.googleSubject,
        nextPageToken: nil,
        completedAt: .now,
        historyId: capturedHistoryId
      )
      return .incremental(
        account: account,
        startHistoryId: capturedHistoryId,
        pageToken: nil
      )

    case .incremental(let account, let startHistoryId, let pageToken):
      let page = try await api.listHistory(
        subject: account.googleSubject,
        dimoUserId: dimoUserId,
        startHistoryId: startHistoryId,
        pageToken: pageToken
      )
      try await fetchAndPersist(
        ids: page.addedMessageIds,
        accountSubject: account.googleSubject,
        dimoUserId: dimoUserId,
        syncWindow: syncWindow,
        now: now
      )
      if let nextPageToken = page.nextPageToken {
        return .incremental(
          account: account,
          startHistoryId: startHistoryId,
          pageToken: nextPageToken
        )
      }
      try await persistence.advanceEmailHistory(
        accountSubject: account.googleSubject,
        historyId: page.latestHistoryId
      )
      try await persistence.finishEmailSync(
        accountSubject: account.googleSubject,
        at: .now,
        state: .idle,
        error: nil
      )
      return nil
    }
  }

  private func fetchAndPersist(
    ids: [String],
    accountSubject: String,
    dimoUserId: String,
    syncWindow: EmailSyncWindow,
    now: Date
  ) async throws {
    guard !ids.isEmpty else { return }
    let resources = try await api.getMessages(
      subject: accountSubject,
      dimoUserId: dimoUserId,
      ids: ids
    )
    var messages: [EmailMessagePayload] = []
    messages.reserveCapacity(resources.count)
    for resource in resources {
      let labels = Set(resource.labelIds ?? [])
      guard labels.isDisjoint(with: Set(["SPAM", "TRASH"])) else { continue }

      var resolvedBodies: [String: Data] = [:]
      for attachmentId in GmailMessageParser.unresolvedBodyAttachmentIds(from: resource) {
        try Task.checkCancellation()
        do {
          resolvedBodies[attachmentId] = try await api.getAttachmentData(
            subject: accountSubject,
            dimoUserId: dimoUserId,
            messageId: resource.id,
            attachmentId: attachmentId
          )
        } catch {
          // Keep going with whatever inline body Gmail already returned.
          continue
        }
      }

      guard let parsed = try? GmailMessageParser.parse(resource, resolvedBodies: resolvedBodies)
      else { continue }
      guard syncWindow.contains(parsed.internalDate, now: now, calendar: calendar) else {
        continue
      }
      messages.append(
        EmailMessagePayload(
          accountSubject: accountSubject,
          gmailMessageId: parsed.gmailMessageId,
          gmailThreadId: parsed.gmailThreadId,
          rfcMessageId: parsed.rfcMessageId,
          senderName: parsed.senderName,
          senderAddress: parsed.senderAddress,
          subject: parsed.subject,
          snippet: parsed.snippet,
          internalDate: parsed.internalDate,
          normalizedBody: parsed.normalizedBody
        )
      )
    }
    if !messages.isEmpty { try await persistence.storePendingEmailMessages(messages) }
  }
}
