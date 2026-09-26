import ConvexMobile
import Foundation

/// A Dimo account found by name or email.
struct LendUser: Decodable, Sendable, Equatable {
  var userId: String
  var name: String
  var email: String?
  var photoUrl: String?
  /// `none`, `connected`, `invited` or `invitedYou`.
  var relation: String
  /// Your contactId for them: the shared contact when connected, or the
  /// contact a pending invite is for.
  var contactId: String?
}

/// An invite waiting for this account to accept or decline.
struct IncomingLendInvite: Codable, Sendable, Identifiable, Equatable {
  var inviteId: String
  var inviterName: String
  var inviterEmail: String?
  var inviterPhotoUrl: String?
  /// Turns a stopped share back on.
  var reconnect: Bool
  var createdAt: Double

  var id: String { inviteId }
}

/// An invite this account sent that hasn't been accepted yet.
struct OutgoingLendInvite: Codable, Sendable, Identifiable, Equatable {
  var inviteId: String
  var contactName: String
  var contactId: String?
  var inviteeEmail: String?
  var inviteePhotoUrl: String?
  var createdAt: Double

  var id: String { inviteId }
}

struct LendConnectionSummary: Codable, Sendable, Identifiable, Equatable {
  var connectionId: String
  /// `dimo:<connectionId>`, the contactId every shared entry carries.
  var contactId: String
  var contactName: String
  /// `active` or `revoked`.
  var status: String
  var createdAt: Double
  var revokedAt: Double?
  /// The other member's profile photo.
  var photoUrl: String?

  var id: String { connectionId }
  var isActive: Bool { status == "active" }
}

struct SentLendInvite: Decodable, Sendable {
  var inviteId: String
}

struct AcceptedLendInvite: Decodable, Sendable {
  var connectionId: String
  var contactId: String
}

/// Whose past entries are kept when both sides already tracked each other;
/// the other side's duplicates are deleted. Clients always keep both.
enum LendHistoryChoice: String, CaseIterable, Identifiable, Sendable {
  case both
  case inviter
  case accepter

  var id: String { rawValue }
}

protocol LendingSharingAPI: Sendable {
  func searchUsers(query: String) async throws -> [LendUser]
  func reshare(connectionId: String) async throws
  func setProfilePhoto(_ photoUrl: String?) async throws
  func sendInvite(userId: String, contactId: String, contactName: String) async throws
  func accept(inviteId: String, contactId: String?, contactName: String?, history: LendHistoryChoice) async throws -> AcceptedLendInvite
  func decline(inviteId: String) async throws
  func cancel(inviteId: String) async throws
  func revoke(connectionId: String) async throws
  func incomingInvites() async throws -> [IncomingLendInvite]
  func outgoingInvites() async throws -> [OutgoingLendInvite]
  func connections() async throws -> [LendConnectionSummary]
}

/// Authenticated calls for collaborative lending (`convex/lending.ts`).
final class LendingSharingTransport: LendingSharingAPI, @unchecked Sendable {
  private let client: ConvexClientWithAuth<WorkOSSession>

  init(client: ConvexClientWithAuth<WorkOSSession>) {
    self.client = client
  }

  func searchUsers(query: String) async throws -> [LendUser] {
    try await firstValue(
      client.subscribe(to: "lending:searchLendUsers", with: ["query": query])
    )
  }

  func reshare(connectionId: String) async throws {
    let _: SentLendInvite = try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "lending:reshareLendConnection",
        with: ["connectionId": connectionId]
      )
    }
  }

  func setProfilePhoto(_ photoUrl: String?) async throws {
    let args: [String: ConvexEncodable?] = ["photoUrl": photoUrl]
    try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:setProfilePhoto", with: args)
    }
  }

  func sendInvite(userId: String, contactId: String, contactName: String) async throws {
    let _: SentLendInvite = try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "lending:sendLendInvite",
        with: ["userId": userId, "contactId": contactId, "contactName": contactName]
      )
    }
  }

  func accept(
    inviteId: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice
  ) async throws -> AcceptedLendInvite {
    var args: [String: ConvexEncodable?] = ["inviteId": inviteId, "history": history.rawValue]
    if let contactId { args["contactId"] = contactId }
    if let contactName, !contactName.isEmpty { args["contactName"] = contactName }
    let sendable = args
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:acceptLendInvite", with: sendable)
    }
  }

  func decline(inviteId: String) async throws {
    try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:declineLendInvite", with: ["inviteId": inviteId])
    }
  }

  func cancel(inviteId: String) async throws {
    try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:cancelLendInvite", with: ["inviteId": inviteId])
    }
  }

  func revoke(connectionId: String) async throws {
    try await withTimeout(seconds: 45) {
      try await self.client.mutation(
        "lending:revokeLendConnection",
        with: ["connectionId": connectionId]
      )
    }
  }

  func incomingInvites() async throws -> [IncomingLendInvite] {
    try await firstValue(
      client.subscribe(to: "lending:listIncomingLendInvites", with: [:] as [String: ConvexEncodable?])
    )
  }

  func outgoingInvites() async throws -> [OutgoingLendInvite] {
    try await firstValue(
      client.subscribe(to: "lending:listOutgoingLendInvites", with: [:] as [String: ConvexEncodable?])
    )
  }

  func connections() async throws -> [LendConnectionSummary] {
    try await firstValue(
      client.subscribe(to: "lending:listLendConnections", with: [:] as [String: ConvexEncodable?])
    )
  }
}
