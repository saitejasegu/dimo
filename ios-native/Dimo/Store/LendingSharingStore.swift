import Foundation
import Observation

/// Server-side state for lending shared with other Dimo accounts: invites in
/// both directions and connections. Entries themselves arrive through normal
/// sync because the server mirrors them into this account's `lends`.
@Observable
@MainActor
final class LendingSharingStore {
  private(set) var connections: [LendConnectionSummary] = []
  private(set) var incomingInvites: [IncomingLendInvite] = []
  private(set) var outgoingInvites: [OutgoingLendInvite] = []

  private var transport: (any LendingSharingAPI)?
  private var generation = 0
  private var persist: ((LendingSharingSnapshot) -> Void)?

  /// Hydrated before local entries become visible. The cache belongs to the
  /// account database, so sign-out deletes it together with the ledger.
  func restore(_ snapshot: LendingSharingSnapshot?, persist: @escaping (LendingSharingSnapshot) -> Void) {
    connections = snapshot?.connections ?? []
    incomingInvites = snapshot?.incomingInvites ?? []
    outgoingInvites = snapshot?.outgoingInvites ?? []
    self.persist = persist
  }

  private func saveSnapshot() {
    persist?(LendingSharingSnapshot(
      connections: connections, incomingInvites: incomingInvites, outgoingInvites: outgoingInvites
    ))
  }
  private var publishedPhoto: String??
  /// Pulls fresh lends after sharing changed on the server.
  var onLedgerChanged: (() -> Void)?
  /// This account's sign-in photo, published so people it shares with see it.
  var profilePhotoUrl: (() -> String?)?

  var isOnline: Bool { transport != nil }

  func attach(_ transport: (any LendingSharingAPI)?) {
    generation += 1
    self.transport = transport
    if transport == nil {
      connections = []
      incomingInvites = []
      outgoingInvites = []
      publishedPhoto = nil
      persist = nil
    }
  }

  /// Active connection whose shared contactId is `contactId`.
  func activeConnection(contactId: String) -> LendConnectionSummary? {
    connections.first { $0.contactId == contactId && $0.isActive }
  }

  /// Was shared with this contact, and one side stopped.
  func stoppedConnection(contactId: String) -> LendConnectionSummary? {
    connections.first { $0.contactId == contactId && !$0.isActive }
  }

  /// A pending invite already sent for this local contact.
  func pendingInvite(contactId: String) -> OutgoingLendInvite? {
    outgoingInvites.first { $0.contactId == contactId }
  }

  /// Profile photo for a shared or invited contact, if they have one.
  func photoUrl(contactId: String) -> String? {
    connections.first { $0.contactId == contactId }?.photoUrl
      ?? outgoingInvites.first { $0.contactId == contactId }?.inviteePhotoUrl
  }

  /// Each result reaches the UI as soon as it arrives. In particular, neither
  /// the photo mutation nor a slow connection query holds up outgoing invites.
  func refresh() async {
    guard let transport else { return }
    generation += 1
    let current = generation
    async let connections: Void = refreshConnections(transport, generation: current)
    async let incoming: Void = refreshIncoming(transport, generation: current)
    async let outgoing: Void = refreshOutgoing(transport, generation: current)
    async let photo: Void = publishPhoto(transport, generation: current)
    _ = await (connections, incoming, outgoing, photo)
  }

  private func refreshConnections(_ transport: any LendingSharingAPI, generation: Int) async {
    guard let value = try? await transport.connections(), self.generation == generation,
      !Task.isCancelled else { return }
    connections = value
    saveSnapshot()
  }

  private func refreshIncoming(_ transport: any LendingSharingAPI, generation: Int) async {
    guard let value = try? await transport.incomingInvites(), self.generation == generation,
      !Task.isCancelled else { return }
    incomingInvites = value
    saveSnapshot()
  }

  private func refreshOutgoing(_ transport: any LendingSharingAPI, generation: Int) async {
    guard let value = try? await transport.outgoingInvites(), self.generation == generation,
      !Task.isCancelled else { return }
    outgoingInvites = value
    saveSnapshot()
  }

  private func publishPhoto(_ transport: any LendingSharingAPI, generation: Int) async {
    let photo = profilePhotoUrl?()
    guard publishedPhoto != .some(photo) else { return }
    if (try? await transport.setProfilePhoto(photo)) != nil,
      self.generation == generation, !Task.isCancelled {
      publishedPhoto = .some(photo)
    }
  }

  /// Dimo accounts (never this one) matching a name or email.
  func searchUsers(_ query: String) async throws -> [LendUser] {
    try await requireTransport().searchUsers(
      query: query.trimmingCharacters(in: .whitespacesAndNewlines)
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

  /// Accepts, keeping both sides' history; `mergeWith` joins a contact you
  /// already track into the shared one.
  func accept(_ invite: IncomingLendInvite, mergeWith contactId: String?) async throws {
    _ = try await requireTransport().accept(
      inviteId: invite.inviteId,
      contactId: contactId,
      contactName: invite.inviterName,
      history: .both
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

  /// Invites the other person to share a stopped connection again.
  func shareAgain(contactId: String) async throws {
    guard let connection = stoppedConnection(contactId: contactId) else { return }
    try await requireTransport().reshare(connectionId: connection.connectionId)
    await refresh()
  }

  private func requireTransport() throws -> any LendingSharingAPI {
    guard let transport else { throw LendingSharingError.offline }
    return transport
  }
}

enum LendingSharingError: LocalizedError {
  case offline

  var errorDescription: String? {
    switch self {
    case .offline: return "Sharing needs an online Dimo sync session."
    }
  }
}
