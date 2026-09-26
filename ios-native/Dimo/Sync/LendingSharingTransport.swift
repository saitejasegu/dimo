import ConvexMobile
import Foundation

/// Invite code handed out by `createLendInvite` / `inviteLendContactByEmail`.
struct LendInviteCode: Decodable, Sendable, Equatable {
  var code: String
  var expiresAt: Double

  /// Shareable link; the web app handles it and native apps accept the code.
  var link: URL { LendInviteLinks.webURL(code: code) }
}

struct LendInvitePreview: Decodable, Sendable, Equatable {
  var inviterName: String
  /// `pending`, `accepted` or `revoked`.
  var status: String
  var expiresAt: Double
  var isOwnInvite: Bool

  var isAcceptable: Bool {
    status == "pending" && !isOwnInvite && expiresAt > Date().timeIntervalSince1970 * 1000
  }
}

/// An invite addressed to this account by its verified email.
struct IncomingLendInvite: Decodable, Sendable, Identifiable, Equatable {
  var code: String
  var inviterName: String
  var expiresAt: Double

  var id: String { code }
}

/// An invite this account sent that nobody has accepted yet.
struct OutgoingLendInvite: Decodable, Sendable, Identifiable, Equatable {
  var code: String
  var contactName: String
  var contactId: String?
  var expiresAt: Double

  var id: String { code }
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

enum LendInviteLinks {
  static let webBase = "https://dimoapp.xyz/invite"

  static func webURL(code: String) -> URL {
    var components = URLComponents(string: webBase)!
    components.queryItems = [URLQueryItem(name: "code", value: code)]
    return components.url!
  }

  /// Accepts `dimo://invite/CODE`, `dimo://invite?code=CODE` and the web link.
  static func code(from url: URL) -> String? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryCode = components?.queryItems?.first { $0.name == "code" }?.value
    let isInviteURL: Bool
    switch url.scheme {
    case "dimo":
      isInviteURL = url.host == "invite"
    case "https":
      isInviteURL = url.host == "dimoapp.xyz" && url.path.hasPrefix("/invite")
    default:
      isInviteURL = false
    }
    guard isInviteURL else { return nil }
    let pathCode = url.pathComponents.dropFirst().last.flatMap { $0 == "invite" ? nil : $0 }
    let raw = queryCode ?? (url.scheme == "dimo" ? pathCode : nil)
    return raw.map(normalize).flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Same normalisation as the server: uppercase letters and digits only.
  static func normalize(_ code: String) -> String {
    code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }

  /// Plain-text invite for the share sheet.
  static func message(inviterName: String, code: String) -> String {
    let grouped = code.count == 10 ? "\(code.prefix(5))-\(code.suffix(5))" : code
    return """
    \(inviterName) wants to keep a shared lending ledger with you on Dimo.

    Open \(webURL(code: code).absoluteString)
    or enter code \(grouped) in Dimo → Lending → Join.
    """
  }
}

/// Authenticated calls for collaborative lending (`convex/lending.ts`).
final class LendingSharingTransport: @unchecked Sendable {
  private let client: ConvexClientWithAuth<WorkOSSession>

  init(client: ConvexClientWithAuth<WorkOSSession>) {
    self.client = client
  }

  func createInvite(contactId: String?, contactName: String, email: String?) async throws -> LendInviteCode {
    var args: [String: ConvexEncodable?] = ["contactName": contactName]
    if let contactId { args["contactId"] = contactId }
    if let email, !email.isEmpty {
      args["email"] = email
      let sendable = args
      return try await withTimeout(seconds: 45) {
        try await self.client.mutation("lending:inviteLendContactByEmail", with: sendable)
      }
    }
    let sendable = args
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:createLendInvite", with: sendable)
    }
  }

  func preview(code: String) async throws -> LendInvitePreview? {
    try await firstValue(
      client.subscribe(to: "lending:previewLendInvite", with: ["code": code])
    )
  }

  func accept(
    code: String,
    contactId: String?,
    contactName: String?,
    history: LendHistoryChoice
  ) async throws -> AcceptedLendInvite {
    var args: [String: ConvexEncodable?] = ["code": code, "history": history.rawValue]
    if let contactId { args["contactId"] = contactId }
    if let contactName, !contactName.isEmpty { args["contactName"] = contactName }
    let sendable = args
    return try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:acceptLendInvite", with: sendable)
    }
  }

  func decline(code: String) async throws {
    try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:declineLendInvite", with: ["code": code])
    }
  }

  func cancel(code: String) async throws {
    try await withTimeout(seconds: 45) {
      try await self.client.mutation("lending:cancelLendInvite", with: ["code": code])
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
