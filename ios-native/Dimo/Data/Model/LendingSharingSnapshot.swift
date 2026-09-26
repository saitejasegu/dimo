import Foundation

/// Last known sharing metadata, cached only in the account's local database.
/// The server remains authoritative and refresh replaces successful sections.
struct LendingSharingSnapshot: Codable, Equatable, Sendable {
  var connections: [LendConnectionSummary]
  var incomingInvites: [IncomingLendInvite]
  var outgoingInvites: [OutgoingLendInvite]
}
