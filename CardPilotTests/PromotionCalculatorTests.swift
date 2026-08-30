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

    func testUnknownDateBasisAcceptsEitherTransactionOrPostingDate() {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        let network = CardNetwork.makeBuiltIns()[0]
        let card = Card(account: account, productName: "测试卡", network: network, lastFour: "1234")
        let promotion = Promotion(
            title: "测试活动",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            qualificationDateBasis: .unknown,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let transaction = Transaction(
            card: card,
            transactionOn: 20260731,
            postingOn: 20260801,
            amount: 100,
            currencyCode: "CNY",
            merchant: "测试商户"
        )

        XCTAssertTrue(PromotionCalculator.includes(transaction, in: promotion))
        transaction.postingOn = 20260901
        XCTAssertFalse(PromotionCalculator.includes(transaction, in: promotion))
    }
}
