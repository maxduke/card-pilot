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

    func testUnavailableAuthenticationReleasesRecoveryLockAndClearsPolicy() {
        let controller = AppLockController(enabled: true, authenticationAvailable: { false }) { false }
        XCTAssertTrue(controller.disableIfAuthenticationUnavailable())
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.isLocked)
        XCTAssertFalse(controller.disableIfAuthenticationUnavailable())
    }

    func testAvailableAuthenticationKeepsRecoveryLocked() {
        let controller = AppLockController(enabled: true, authenticationAvailable: { true }) { false }
        XCTAssertFalse(controller.disableIfAuthenticationUnavailable())
        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.isLocked)
    }

    func testAuthenticationUIInactivePhaseDoesNotCancelInFlightUnlock() {
        XCTAssertFalse(RootView.shouldRelock(when: .inactive, isAuthenticating: true))
        XCTAssertTrue(RootView.shouldRelock(when: .inactive, isAuthenticating: false))
        XCTAssertTrue(RootView.shouldRelock(when: .background, isAuthenticating: true))
    }
}
