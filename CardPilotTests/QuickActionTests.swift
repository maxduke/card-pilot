import XCTest
@testable import CardPilot

@MainActor
final class QuickActionTests: XCTestCase {
    func testSupportedShortcutTypesMapToActions() {
        XCTAssertEqual(
            CardPilotQuickAction(rawValue: "com.maxduke.CardPilot.quickAction.addTransaction"),
            .addTransaction
        )
        XCTAssertEqual(
            CardPilotQuickAction(rawValue: "com.maxduke.CardPilot.quickAction.promotionProgress"),
            .promotionProgress
        )
        XCTAssertNil(CardPilotQuickAction(rawValue: "com.maxduke.CardPilot.quickAction.unknown"))
    }

    func testRouterDeliversQueuedActionsOnceAndInOrder() {
        let router = CardPilotQuickActionRouter()
        router.enqueue(.addTransaction)
        router.enqueue(.promotionProgress)

        XCTAssertEqual(router.takeNext(), .addTransaction)
        XCTAssertEqual(router.takeNext(), .promotionProgress)
        XCTAssertNil(router.takeNext())
    }
}
