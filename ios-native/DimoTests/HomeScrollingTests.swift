import SwiftUI
import XCTest
@testable import Dimo

@MainActor
final class HomeScrollingTests: XCTestCase {
  func testLongHistoryLoadsOnScrollAndResetsForFilter() async throws {
    // No repository or sync coordinator is started: the fixture stays in memory.
    let store = AppStore(
      userId: "home-scroll-test", profileName: "Scroll test", profileEmail: "",
      authProvider: WorkOSAuthProvider()
    )
    store.entities.transactions = (0..<300).map { index in
      Transaction(
        id: "scroll-\(index)", name: "Fixture \(index)", category: "Dining",
        time: "10:00 AM", day: index < 125 ? "Today" : "Day \(index / 25)",
        amount: 10
      )
    }
    store.nav.filter = TransactionFilter(categories: ["Dining"])
    let host = UIHostingController(rootView:
      HomeScreen(store: store, entities: store.entities, nav: store.nav, onOpenSettings: {})
        .environment(AppEnvironment())
    )
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
    let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKey()
    }
    try await settleLayout()

    let scroll = try XCTUnwrap(verticalScrollView(in: host.view))
    // The first day deliberately exceeds a page. It must not eagerly load the
    // rest of history, and the next page must advance beyond those 125 rows.
    XCTAssertLessThan(scroll.contentSize.height, 10_000)
    for _ in 0..<8 {
      scroll.setContentOffset(
        CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)),
        animated: false
      )
      try await settleLayout()
    }
    // Each card is at least 60 points high, before inter-row spacing and headers.
    // Reaching this height proves pagination continued beyond the first day.
    XCTAssertGreaterThan(scroll.contentSize.height, 300 * 60)

    store.nav.filter = TransactionFilter(query: "Fixture 299")
    try await settleLayout()
    XCTAssertLessThan(scroll.contentSize.height, 1_000)
    XCTAssertLessThanOrEqual(scroll.contentOffset.y, 1)
  }

  private func settleLayout() async throws {
    try await Task.sleep(for: .milliseconds(350))
  }

  private func verticalScrollView(in view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView, scroll.bounds.height > 200 { return scroll }
    return view.subviews.lazy.compactMap { self.verticalScrollView(in: $0) }.first
  }
}
