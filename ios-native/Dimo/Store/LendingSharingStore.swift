import Foundation
import Observation

/// Which sharing sheet is open. Presented from the tab shell.
enum LedgerSharingSheet: Identifiable, Equatable {
  /// Accept or decline an invite someone sent.
  case accept(IncomingLendInvite)

  var id: String {
    switch self {
    case .accept(let invite): return "accept-\(invite.inviteId)"
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
  /// in which case nobody can be found to share with.
  private(set) var sharingAvailable = true
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
    outgoingInvites.first { $0.contactId == contactId }
  }

  /// Reloads invites and connections, and records the verified email once per
  /// session so other people can find this account.
  func refresh() async {
    guard let transport else { return }
    if !didRefreshEmail {
      didRefreshEmail = true
      if let result = try? await transport.refreshVerifiedEmail() {
        sharingAvailable = result.available
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

  func findUser(email: String) async throws -> LendUser? {
    try await requireTransport().findUser(
      email: email.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  /// Invites `user`; entries with `contactId` are shared once they accept.
  func sendInvite(to user: LendUser, contactId: String, contactName: String) async throws {
    let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
    try await requireTransport().sendInvite(
      userId: user.userId,
      contactId: contactId,
      contactName: name.isEmpty ? user.name : name
    )
    await refresh()
  }

  func accept(
    _ invite: IncomingLendInvite,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice
  ) async throws {
    _ = try await requireTransport().accept(
      inviteId: invite.inviteId,
      contactId: contactId,
      contactName: contactName,
      history: history
    )
    await refresh()
    onLedgerChanged?()
  }

  func decline(_ invite: IncomingLendInvite) async throws {
    try await requireTransport().decline(inviteId: invite.inviteId)
    await refresh()
  }

  func cancel(_ invite: OutgoingLendInvite) async throws {
    try await requireTransport().cancel(inviteId: invite.inviteId)
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
