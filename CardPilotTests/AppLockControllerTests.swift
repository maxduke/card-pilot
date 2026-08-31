import XCTest
@testable import CardPilot

@MainActor
final class AppLockControllerTests: XCTestCase {
    func testBackgroundRelocksAfterSuccessfulAuthentication() async {
        let controller = AppLockController(enabled: true) { true }
        let result = await controller.unlock()
        XCTAssertTrue(result)
        XCTAssertFalse(controller.isLocked)
        controller.applicationDidEnterBackground()
        XCTAssertTrue(controller.isLocked)
    }

    func testAuthenticationUIInactivePhaseDoesNotCancelInFlightUnlock() {
        XCTAssertFalse(RootView.shouldRelock(when: .inactive, isAuthenticating: true))
        XCTAssertTrue(RootView.shouldRelock(when: .inactive, isAuthenticating: false))
        XCTAssertTrue(RootView.shouldRelock(when: .background, isAuthenticating: true))
    }
}
