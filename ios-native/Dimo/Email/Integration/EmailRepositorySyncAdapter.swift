import Foundation

/// Bridges Gmail synchronization to the account-scoped, local-only email
/// tables. The repository supplied here must belong to the signed-in Dimo
/// user; the user identifier passed by the coordinator is used by Gmail's
/// credential layer and is intentionally not persisted with email records.
actor EmailRepositorySyncAdapter: EmailSyncPersistence {
  private let repository: Repository

  init(repository: Repository) {
    self.repository = repository
  }

  func emailAccountsForSync(dimoUserId: String) async throws -> [EmailAccountSnapshot] {
    // Repository databases are already scoped by the WorkOS user identifier.
    // Keeping the argument out of SQLite prevents duplicating account identity
    // in the local-only Gmail schema.
    _ = dimoUserId
    return try repository.emailAccounts()
      .filter { $0.syncState != .disconnected }
      .map { account in
        EmailAccountSnapshot(
          googleSubject: account.id,
          emailAddress: account.emailAddress,
          historyId: account.historyId,
          backfillPageToken: account.backfillPageToken,
          backfillCompletedAt: account.backfillCompletedAt.map(emailDate(milliseconds:))
        )
      }
  }

  func recordEmailSyncAttempt(
    accountSubject: String,
    at date: Date,
    state: GmailSyncState
  ) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      account.lastAttemptAt = emailMilliseconds(date)
      account.syncState = emailRepositorySyncState(state, account: account)
      account.lastError = nil
    }
  }

  func storePendingEmailMessages(_ messages: [EmailMessagePayload]) async throws {
    let pending = messages.map { message in
      PendingEmailMessage(
        accountId: message.accountSubject,
        gmailMessageId: message.gmailMessageId,
        threadId: message.gmailThreadId,
        rfcMessageId: message.rfcMessageId,
        senderName: message.senderName,
        senderAddress: message.senderAddress,
        subject: message.subject,
        snippet: message.snippet,
        internalDate: emailMilliseconds(message.internalDate),
        normalizedBodyText: message.normalizedBody
      )
    }
    _ = try repository.insertPendingEmailMessages(pending)
  }

  func advanceEmailBackfill(
    accountSubject: String,
    nextPageToken: String?,
    completedAt: Date?,
    historyId: String?
  ) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      account.backfillPageToken = nextPageToken
      account.backfillCompletedAt = completedAt.map(emailMilliseconds)
      if let historyId {
        account.historyId = historyId
      }
      account.syncState = nextPageToken == nil ? .syncing : .backfilling
    }
  }

  func advanceEmailHistory(accountSubject: String, historyId: String) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      account.historyId = historyId
    }
  }

  func resetEmailBackfill(accountSubject: String) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      account.historyId = nil
      account.backfillPageToken = nil
      account.backfillCompletedAt = nil
      account.syncState = .backfilling
      account.lastError = nil
    }
  }

  func finishEmailSync(
    accountSubject: String,
    at date: Date,
    state: GmailSyncState,
    error: String?
  ) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      account.syncState = emailRepositorySyncState(state, account: account)
      account.lastError = state == .needsReconnect
        ? error ?? "Gmail access expired or was revoked. Please connect again."
        : error
      if state == .idle, error == nil {
        account.lastSuccessfulSyncAt = emailMilliseconds(date)
      }
    }
  }

  func abandonEmailSync(accountSubject: String) async throws {
    try repository.updateEmailAccount(id: accountSubject) { account in
      guard account.syncState == .syncing || account.syncState == .backfilling else { return }
      account.syncState = .idle
      account.lastError = nil
    }
  }
}

private func emailRepositorySyncState(
  _ state: GmailSyncState,
  account: EmailAccountRecordModel
) -> EmailAccountSyncState {
  switch state {
  case .idle:
    return .idle
  case .backfilling:
    return .backfilling
  case .syncing:
    return account.backfillPageToken == nil ? .syncing : .backfilling
  case .rateLimited:
    return .rateLimited
  case .offline:
    return .offline
  case .needsReconnect, .failed:
    return .failed
  }
}

private func emailMilliseconds(_ date: Date) -> Int {
  Int(date.timeIntervalSince1970 * 1_000)
}

private func emailDate(milliseconds: Int) -> Date {
  Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
}
