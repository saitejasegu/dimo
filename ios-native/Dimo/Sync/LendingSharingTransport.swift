import ConvexMobile
import Foundation

/// A Dimo account found by its verified email.
struct LendUser: Decodable, Sendable, Equatable {
  var userId: String
  var name: String
  var email: String
  /// `none`, `self`, `connected`, `invited` or `invitedYou`.
  var relation: String
  /// Your contactId for them: the shared ledger when connected, or the
  /// contact a pending invite is for.
  var contactId: String?
}

/// An invite waiting for this account to accept or decline.
struct IncomingLendInvite: Decodable, Sendable, Identifiable, Equatable {
  var inviteId: String
  var inviterName: String
  var inviterEmail: String?
  var createdAt: Double

  var id: String { inviteId }
}

/// An invite this account sent that hasn't been accepted yet.
struct OutgoingLendInvite: Decodable, Sendable, Identifiable, Equatable {
  var inviteId: String
  var contactName: String
  var contactId: String?
  var inviteeEmail: String?
  var createdAt: Double

  var id: String { inviteId }
}

struct LendConnectionSummary: Decodable, Sendable, Identifiable, Equatable {
  var connectionId: String
  /// `dimo:<connectionId>`, the contactId every shared entry carries.
  var contactId: String
  var contactName: String
  /// `active` or `revoked`.
  var status: String
  var createdAt: Double
  var revokedAt: Double?

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

struct VerifiedEmailResult: Decodable, Sendable {
  /// False when the deployment has no WorkOS API key configured.
  var available: Bool
  var email: String?
}

/// Whose past entries make up the shared ledger when both sides already
/// tracked each other; the other side's duplicates are deleted.
enum LendHistoryChoice: String, CaseIterable, Identifiable, Sendable {
  case both
  case inviter
  case accepter

  var id: String { rawValue }
}

/// Authenticated calls for collaborative lending (`convex/lending.ts`).
final class LendingSharingTransport: @unchecked Sendable {
  private let client: ConvexClientWithAuth<WorkOSSession>

  init(client: ConvexClientWithAuth<WorkOSSession>) {
    self.client = client
  }

  func findUser(email: String) async throws -> LendUser? {
    try await firstValue(
      client.subscribe(to: "lending:findLendUser", with: ["email": email])
    )
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

  func refreshVerifiedEmail() async throws -> VerifiedEmailResult {
    try await withTimeout(seconds: 45) {
      try await self.client.action("lendingEmail:refreshVerifiedEmail", with: [:])
    }
  }
}
