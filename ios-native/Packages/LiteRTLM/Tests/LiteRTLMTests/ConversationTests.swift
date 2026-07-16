import XCTest
@testable import LiteRTLM

final class ConversationTests: XCTestCase {
  func testCloseDeletesNativeConversationExactlyOnceAndIsIdempotent() throws {
    var cancelCount = 0
    var deleteCount = 0

    do {
      let handle = try XCTUnwrap(OpaquePointer(bitPattern: 1))
      let conversation = Conversation(
        handle: handle,
        toolManager: ToolManager(tools: []),
        cancelNativeProcessing: { _ in cancelCount += 1 },
        deleteNativeConversation: { _ in deleteCount += 1 }
      )

      XCTAssertTrue(conversation.isAlive)
      conversation.close()
      XCTAssertFalse(conversation.isAlive)
      conversation.close()
      XCTAssertEqual(cancelCount, 1)
      XCTAssertEqual(deleteCount, 1)
    }

    // deinit is a safety net and must not delete an already-closed handle.
    XCTAssertEqual(cancelCount, 1)
    XCTAssertEqual(deleteCount, 1)
  }
}
