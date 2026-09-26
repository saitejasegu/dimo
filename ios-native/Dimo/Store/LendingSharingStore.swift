import Foundation
import Observation

/// Which sharing sheet is open. Presented from the tab shell so a deep link can
/// open it before the Lending tab has ever been visited.
enum LedgerSharingSheet: Identifiable, Equatable {
  /// Invite someone to share a ledger, optionally for an existing contact.
  case invite(contactId: String?, contactName: String)
  /// Join a ledger with a code, optionally prefilled from a link or an
  /// email-addressed invite.
  case join(code: String)

  var id: String {
    switch self {
    case .invite(let contactId, let contactName): return "invite-\(contactId ?? contactName)"
    case .join(let code): return "join-\(code)"
    }
  }
}

/// Server-side state for ledgers shared with other Dimo accounts: invites in
/// both directions and connections. Entries themselves arrive through normal
/// sync because the server mirrors them into this account's `lends`.
@Observable
@MainActor
final class LendingSharingStore {
  private(set) var connections: [LendConnectionSummary] = []
  private(set) var incomingInvites: [IncomingLendInvite] = []
  private(set) var outgoingInvites: [OutgoingLendInvite] = []
  /// Verified sign-in email the server knows for this account, if any.
  private(set) var verifiedEmail: String?
  /// False when the server cannot look up verified emails (no WorkOS API key),
  /// in which case invites can only be shared as a link or code.
  private(set) var emailInvitesAvailable = true
  var sheet: LedgerSharingSheet?

  private var transport: LendingSharingTransport?
  private var didRefreshEmail = false
  /// Pulls fresh lends after the ledger changed on the server.
  var onLedgerChanged: (() -> Void)?

  var isOnline: Bool { transport != nil }

  func attach(_ transport: LendingSharingTransport?) {
    self.transport = transport
    if transport == nil {
      connections = []
      incomingInvites = []
      outgoingInvites = []
      didRefreshEmail = false
    }
  }

  /// Active connection whose shared contactId is `contactId`.
  func activeConnection(contactId: String) -> LendConnectionSummary? {
    connections.first { $0.contactId == contactId && $0.isActive }
  }

  /// A pending invite already sent for this local contact.
  func pendingInvite(contactId: String) -> OutgoingLendInvite? {
    let now = Date().timeIntervalSince1970 * 1000
    return outgoingInvites.first { $0.contactId == contactId && $0.expiresAt > now }
  }

  var liveIncomingInvites: [IncomingLendInvite] {
    let now = Date().timeIntervalSince1970 * 1000
    return incomingInvites.filter { $0.expiresAt > now }
  }

  /// Reloads invites and connections, and records the verified email once per
  /// session so email-addressed invites can reach this account.
  func refresh() async {
    guard let transport else { return }
    if !didRefreshEmail {
      didRefreshEmail = true
      if let result = try? await transport.refreshVerifiedEmail() {
        emailInvitesAvailable = result.available
        verifiedEmail = result.email
      } else {
        didRefreshEmail = false
      }
    }
    async let connections = transport.connections()
    async let incoming = transport.incomingInvites()
    async let outgoing = transport.outgoingInvites()
    if let value = try? await connections { self.connections = value }
    if let value = try? await incoming { self.incomingInvites = value }
    if let value = try? await outgoing { self.outgoingInvites = value }
  }

  func createInvite(contactId: String?, contactName: String, email: String?) async throws -> LendInviteCode {
    let transport = try requireTransport()
    let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
    let invite = try await transport.createInvite(
      contactId: contactId,
      contactName: contactName.trimmingCharacters(in: .whitespacesAndNewlines),
      email: (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
    )
    await refresh()
    return invite
  }

  func preview(code: String) async throws -> LendInvitePreview? {
    try await requireTransport().preview(code: LendInviteLinks.normalize(code))
  }

  func accept(
    code: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice
  ) async throws -> AcceptedLendInvite {
    let accepted = try await requireTransport().accept(
      code: LendInviteLinks.normalize(code),
      contactId: contactId,
      contactName: contactName,
      history: history
    )
    await refresh()
    onLedgerChanged?()
    return accepted
  }

  func decline(code: String) async throws {
    try await requireTransport().decline(code: code)
    await refresh()
  }

  func cancel(code: String) async throws {
    try await requireTransport().cancel(code: code)
    await refresh()
  }

  func stopSharing(contactId: String) async throws {
    guard let connection = activeConnection(contactId: contactId) else { return }
    try await requireTransport().revoke(connectionId: connection.connectionId)
    await refresh()
  }

  private func requireTransport() throws -> LendingSharingTransport {
    guard let transport else { throw LendingSharingError.offline }
    return transport
  }
}

enum LendingSharingError: LocalizedError {
  case offline

  var errorDescription: String? {
    switch self {
    case .offline: return "Shared ledgers need an online Dimo sync session."
    }
  }
}
