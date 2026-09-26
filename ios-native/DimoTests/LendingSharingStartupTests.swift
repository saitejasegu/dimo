import GRDB
import XCTest
@testable import Dimo

@MainActor
final class LendingSharingStartupTests: XCTestCase {
  private var invite: OutgoingLendInvite {
    OutgoingLendInvite(
      inviteId: "invite", contactName: "Alice", contactId: "contact-alice", createdAt: 1
    )
  }

  func testCachedPendingInviteIsAvailableBeforeNetworkStarts() throws {
    let db = try DatabaseQueue()
    try AppDatabase.migrator.migrate(db)
    let repo = Repository(db: db)
    let snapshot = LendingSharingSnapshot(connections: [], incomingInvites: [], outgoingInvites: [invite])
    try repo.saveLendingSharingSnapshot(snapshot)
    let relaunched = LendingSharingStore()
    relaunched.restore(try repo.lendingSharingSnapshot()) { _ in }
    XCTAssertEqual(relaunched.pendingInvite(contactId: "contact-alice"), invite)
    XCTAssertFalse(relaunched.isOnline)
    let otherAccountDB = try DatabaseQueue()
    try AppDatabase.migrator.migrate(otherAccountDB)
    XCTAssertNil(try Repository(db: otherAccountDB).lendingSharingSnapshot())
  }

  func testOutgoingInvitesPublishBeforePhotoAndConnectionsFinish() async {
    let gate = SharingGate()
    let received = expectation(description: "Invite published while other requests are blocked")
    let expected = invite
    let store = LendingSharingStore()
    var didReceive = false
    store.restore(nil) { snapshot in
      if snapshot.outgoingInvites == [expected], !didReceive {
        didReceive = true
        received.fulfill()
      }
    }
    store.attach(SharingStub(
      loadConnections: { await gate.wait(); return [] },
      loadOutgoing: { [expected] },
      publishPhoto: { await gate.wait() }
    ))
    let refresh = Task { await store.refresh() }
    await fulfillment(of: [received], timeout: 2)
    XCTAssertEqual(store.pendingInvite(contactId: "contact-alice"), expected)
    await gate.release()
    await refresh.value
  }

  func testOfflineRefreshPreservesCachedInviteAndSuccessfulEmptyResponseClearsIt() async {
    let store = LendingSharingStore()
    store.restore(.init(connections: [], incomingInvites: [], outgoingInvites: [invite])) { _ in }
    store.attach(SharingStub(loadOutgoing: { throw LendingSharingError.offline }))
    await store.refresh()
    XCTAssertEqual(store.outgoingInvites, [invite])
    store.attach(SharingStub())
    await store.refresh()
    XCTAssertTrue(store.outgoingInvites.isEmpty)
  }

  func testLateResponseCannotRestoreInviteAfterSignOut() async {
    let gate = SharingGate()
    let started = expectation(description: "Request started")
    let expected = invite
    let store = LendingSharingStore()
    store.attach(SharingStub(loadOutgoing: {
      started.fulfill()
      await gate.wait()
      return [expected]
    }))
    let refresh = Task { await store.refresh() }
    await fulfillment(of: [started], timeout: 2)
    store.attach(nil)
    await gate.release()
    await refresh.value
    XCTAssertTrue(store.outgoingInvites.isEmpty)
  }

  func testOlderRefreshCannotOverwriteNewerResult() async {
    let gate = SharingGate()
    let started = expectation(description: "Old request started")
    let expected = invite
    let store = LendingSharingStore()
    store.attach(SharingStub(loadOutgoing: {
      started.fulfill()
      await gate.wait()
      return [expected]
    }))
    let oldRefresh = Task { await store.refresh() }
    await fulfillment(of: [started], timeout: 2)
    store.attach(SharingStub())
    await store.refresh()
    await gate.release()
    await oldRefresh.value
    XCTAssertTrue(store.outgoingInvites.isEmpty)
  }
}

private actor SharingGate {
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if released { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func release() {
    released = true
    waiters.forEach { $0.resume() }
    waiters = []
  }
}

private struct SharingStub: LendingSharingAPI {
  var loadConnections: @Sendable () async throws -> [LendConnectionSummary] = { [] }
  var loadOutgoing: @Sendable () async throws -> [OutgoingLendInvite] = { [] }
  var publishPhoto: @Sendable () async throws -> Void = {}
  func connections() async throws -> [LendConnectionSummary] { try await loadConnections() }
  func outgoingInvites() async throws -> [OutgoingLendInvite] { try await loadOutgoing() }
  func incomingInvites() async throws -> [IncomingLendInvite] { [] }
  func setProfilePhoto(_ photoUrl: String?) async throws { try await publishPhoto() }
  func searchUsers(query: String) async throws -> [LendUser] { [] }
  func reshare(connectionId: String) async throws {}
  func sendInvite(userId: String, contactId: String, contactName: String) async throws {}
  func accept(inviteId: String, contactId: String?, contactName: String?, history: LendHistoryChoice) async throws -> AcceptedLendInvite {
    throw LendingSharingError.offline
  }
  func decline(inviteId: String) async throws {}
  func cancel(inviteId: String) async throws {}
  func revoke(connectionId: String) async throws {}
}
