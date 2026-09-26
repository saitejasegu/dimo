import XCTest
@testable import Dimo

final class LendSharingTests: XCTestCase {
  func testLendingPermissionErrorsAreBlockedNotRetried() {
    XCTAssertTrue(isPermanentSyncError("Uncaught Error: Not a member of this lending connection"))
    XCTAssertTrue(isPermanentSyncError("Unknown lending connection"))
    XCTAssertTrue(isPermanentSyncError("Lend id collides with an unshared entry"))
  }

  func testKindFollowsFlowAndBalance() {
    XCTAssertEqual(LendSelectors.kind(for: .got, amount: 50, balance: 100), .repaid)
    XCTAssertEqual(LendSelectors.kind(for: .got, amount: 100, balance: 100), .repaid)
    XCTAssertEqual(LendSelectors.kind(for: .got, amount: 150, balance: 100), .borrowed)
    XCTAssertEqual(LendSelectors.kind(for: .got, amount: 50, balance: 0), .borrowed)
    XCTAssertEqual(LendSelectors.kind(for: .gave, amount: 50, balance: -100), .returned)
    XCTAssertEqual(LendSelectors.kind(for: .gave, amount: 150, balance: -100), .lent)
    XCTAssertEqual(LendSelectors.kind(for: .gave, amount: 50, balance: 20), .lent)
    XCTAssertEqual(LendFlow(kind: .repaid), .got)
    XCTAssertEqual(LendFlow(kind: .returned), .gave)
  }

  func testPeopleSplitIntoActiveAndSettledWithInvitedPeople() {
    func summary(_ id: String, total: Double, at: Int) -> LendContactSummary {
      LendContactSummary(contactName: id, contactId: id, total: total, count: 2, lastOccurredAt: at)
    }
    let invite = OutgoingLendInvite(
      inviteId: "i1", contactName: "Newbie", contactId: "c-new", inviteeEmail: nil,
      inviteePhotoUrl: nil, createdAt: 50
    )
    let people = LendPeople.split(
      summaries: [summary("small", total: -5, at: 1), summary("big", total: 90, at: 2), summary("done", total: 0, at: 3)],
      outgoingInvites: [invite]
    )
    XCTAssertEqual(people.active.map(\.contactId), ["big", "small"])
    XCTAssertEqual(people.settled.map(\.contactId), ["c-new", "done"])
  }

  func testWireDecodesSharingMetadataAndEncodesOnlyCurrency() throws {
    let payload = try WirePayload.decode(entityType: .lend, dict: [
      "id": "lend-1",
      "contactName": "Alice",
      "contactId": "dimo:conn1",
      "amountMinor": 50_000.0,
      "occurredAt": 100.0,
      "comment": "",
      "kind": "borrowed",
      "currency": "USD",
      "connectionId": "conn1",
      "createdBy": "contact",
      "lastEditedBy": "me",
    ])
    guard case .lend(let lend) = payload else { return XCTFail("not a lend") }
    XCTAssertEqual(lend.kind, .borrowed)
    XCTAssertEqual(lend.currency, "USD")
    XCTAssertEqual(lend.connectionId, "conn1")
    XCTAssertEqual(lend.createdBy, .contact)
    XCTAssertEqual(lend.lastEditedBy, .me)

    let encoded = WirePayload.encode(payload)
    XCTAssertEqual(encoded["currency"] as? String, "USD")
    XCTAssertNil(encoded["connectionId"])
    XCTAssertNil(encoded["createdBy"])
  }

  func testLegacyWireLendStillDecodes() throws {
    let payload = try WirePayload.decode(entityType: .lend, dict: [
      "id": "lend-1",
      "contactName": "Sam",
      "amountMinor": 100.0,
      "occurredAt": 1.0,
      "comment": "",
    ])
    guard case .lend(let lend) = payload else { return XCTFail("not a lend") }
    XCTAssertEqual(lend.contactId, "Sam")
    XCTAssertEqual(lend.kind, .lent)
    XCTAssertNil(lend.currency)
    XCTAssertNil(lend.createdBy)
  }

  func testSharingColumnsPersistLocally() throws {
    let userId = "test-\(UUID().uuidString)"
    let queue = try AppDatabase.activate(userId: userId)
    defer { try? AppDatabase.deleteAllLocalDatabases() }
    let repo = Repository(db: queue)
    try repo.initializeLocalDatabase()

    try repo.saveEntity(entityType: .lend, payload: .lend(LendEntity(
      id: "lend-1",
      contactName: "Alice",
      contactId: "dimo:conn1",
      amountMinor: 50_000,
      occurredAt: 100,
      comment: "",
      kind: .borrowed,
      currency: "EUR",
      connectionId: "conn1",
      createdBy: .contact,
      lastEditedBy: .me
    )))

    let stored = try repo.activeEntities(type: .lend)
    guard case .lend(let lend)? = stored.first?.payload else { return XCTFail("missing lend") }
    XCTAssertEqual(lend.currency, "EUR")
    XCTAssertEqual(lend.connectionId, "conn1")
    XCTAssertEqual(lend.createdBy, .contact)
    XCTAssertEqual(lend.lastEditedBy, .me)
  }

  func testSummaryUsesNewestCurrencyAndFlagsSharedLedgers() {
    func lend(_ id: String, contactId: String, currency: String?, at occurredAt: Int) -> Lend {
      Lend(
        id: id,
        contactName: "Alice",
        contactId: contactId,
        amount: 10,
        comment: "",
        time: "",
        day: "",
        amountMinor: 1_000,
        occurredAt: occurredAt,
        kind: .lent,
        currency: currency
      )
    }
    let summaries = LendSelectors.contactSummaries([
      lend("old", contactId: "dimo:conn1", currency: "INR", at: 1),
      lend("new", contactId: "dimo:conn1", currency: "USD", at: 2),
      lend("private", contactId: "cn-bob", currency: nil, at: 3),
    ])
    let shared = summaries.first { $0.contactId == "dimo:conn1" }
    XCTAssertEqual(shared?.currency, "USD")
    XCTAssertEqual(shared?.isShared, true)
    XCTAssertEqual(summaries.first { $0.contactId == "cn-bob" }?.isShared, false)
  }
}
