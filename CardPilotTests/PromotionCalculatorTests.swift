import XCTest
@testable import CardPilot

final class PromotionCalculatorTests: XCTestCase {
    func testRefundsSubtractAndReversedTransactionsDoNotCount() throws {
        let progress = try PromotionCalculator.progress(
            targetAmount: 10_000,
            currencyCode: "CNY",
            allocations: [
                (8_000, "CNY", .purchase, .active),
                (500, "CNY", .refund, .active),
                (9_999, "CNY", .purchase, .reversed)
            ]
        )

        XCTAssertEqual(progress.qualifiedAmount, 7_500)
        XCTAssertEqual(progress.remainingAmount, 2_500)
        XCTAssertFalse(progress.isComplete)
    }

    func testProgressCanFallBelowZeroAfterRefunds() throws {
        let progress = try PromotionCalculator.progress(
            targetAmount: 100,
            currencyCode: "CNY",
            allocations: [(200, "CNY", .refund, .active)]
        )
        XCTAssertEqual(progress.qualifiedAmount, -200)
        XCTAssertEqual(progress.remainingAmount, 300)
    }

    func testCurrencyMismatchIsRejected() {
        XCTAssertThrowsError(
            try PromotionCalculator.progress(
                targetAmount: 100,
                currencyCode: "CNY",
                allocations: [(100, "USD", .purchase, .active)]
            )
        ) { error in
            XCTAssertEqual(error as? PromotionCalculationError, .currencyMismatch)
        }
    }
}
