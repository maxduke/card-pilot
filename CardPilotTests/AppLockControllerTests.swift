import XCTest
@testable import CardPilot

@MainActor
final class AppLockControllerTests: XCTestCase {
    func testBackgroundInvalidatesAuthenticationAlreadyInFlight() async {
        let authenticationStarted = expectation(description: "authentication started")
        let controller = AppLockController(enabled: true) {
            authenticationStarted.fulfill()
            try? await Task.sleep(nanoseconds: 100_000_000)
            return true
        }
        let authentication = Task { await controller.unlock() }
        await fulfillment(of: [authenticationStarted], timeout: 2)

        controller.applicationDidEnterBackground()

        let result = await authentication.value
        XCTAssertFalse(result)
        XCTAssertTrue(controller.isLocked)
    }
}
