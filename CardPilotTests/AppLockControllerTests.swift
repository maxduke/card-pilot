import XCTest
@testable import CardPilot

@MainActor
final class AppLockControllerTests: XCTestCase {
    func testBackgroundInvalidatesAuthenticationAlreadyInFlight() async {
        var continuation: CheckedContinuation<Bool, Never>?
        let controller = AppLockController(enabled: true) {
            await withCheckedContinuation { continuation = $0 }
        }
        let authentication = Task { await controller.unlock() }
        while continuation == nil { await Task.yield() }

        controller.applicationDidEnterBackground()
        continuation?.resume(returning: true)

        let result = await authentication.value
        XCTAssertFalse(result)
        XCTAssertTrue(controller.isLocked)
    }
}
