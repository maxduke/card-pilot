import XCTest
@testable import CardPilot

final class PromotionCalculatorTests: XCTestCase {
    func testRefundsSubtractAndReversedTransactionsDoNotCount() throws {
        let progress = try PromotionCalculator.progress(
            qualificationThreshold: 10_000,
            qualifyingCap: 12_000,
            currencyCode: "CNY",
            allocations: [
                (8_000, "CNY", .purchase, .active),
                (500, "CNY", .refund, .active),
                (9_999, "CNY", .purchase, .reversed)
            ]
        )

        XCTAssertEqual(progress.qualifiedAmount, 7_500)
        XCTAssertEqual(progress.remainingToThreshold, 2_500)
        XCTAssertEqual(progress.remainingCap, 4_500)
        XCTAssertFalse(progress.isComplete)
    }

    func testProgressCanFallBelowZeroAfterRefunds() throws {
        let progress = try PromotionCalculator.progress(
            qualificationThreshold: 100,
            currencyCode: "CNY",
            allocations: [(200, "CNY", .refund, .active)]
        )
        XCTAssertEqual(progress.qualifiedAmount, -200)
        XCTAssertEqual(progress.remainingToThreshold, 300)
    }

    func testCurrencyMismatchIsRejected() {
        XCTAssertThrowsError(
            try PromotionCalculator.progress(
                qualificationThreshold: 100,
                currencyCode: "CNY",
                allocations: [(100, "USD", .purchase, .active)]
            )
        ) { error in
            XCTAssertEqual(error as? PromotionCalculationError, .currencyMismatch)
        }
    }

    func testProgressWithoutThresholdNeverCompletesAndExposesOptionalRules() throws {
        let progress = try PromotionCalculator.progress(
            qualifyingCap: 500,
            currencyCode: "CNY",
            allocations: [(600, "CNY", .purchase, .active)]
        )

        XCTAssertEqual(progress.qualifiedAmount, 600)
        XCTAssertNil(progress.remainingToThreshold)
        XCTAssertEqual(progress.remainingCap, 0)
        XCTAssertFalse(progress.isComplete)
    }

    func testProgressWithoutAmountRulesKeepsNetAmountWithoutCompletion() throws {
        let progress = try PromotionCalculator.progress(
            currencyCode: "CNY",
            allocations: [(120, "CNY", .purchase, .active)]
        )

        XCTAssertEqual(progress.qualifiedAmount, 120)
        XCTAssertNil(progress.remainingToThreshold)
        XCTAssertNil(progress.remainingCap)
        XCTAssertFalse(progress.isComplete)
    }

    func testSuggestionHonorsCurrencyThresholdAndRemainingCap() {
        XCTAssertNil(PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: 100,
            transactionCurrencyCode: "USD",
            promotionCurrencyCode: "CNY",
            perTransactionThreshold: nil,
            currentQualifiedAmount: 0,
            qualifyingCap: nil
        ))
        XCTAssertEqual(PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: 99,
            transactionCurrencyCode: "CNY",
            promotionCurrencyCode: "CNY",
            perTransactionThreshold: 100,
            currentQualifiedAmount: 0,
            qualifyingCap: nil
        ), 0)
        XCTAssertEqual(PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: 100,
            transactionCurrencyCode: "CNY",
            promotionCurrencyCode: "CNY",
            perTransactionThreshold: 100,
            currentQualifiedAmount: 0,
            qualifyingCap: nil
        ), 100)
        XCTAssertEqual(PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: 200,
            transactionCurrencyCode: "CNY",
            promotionCurrencyCode: "CNY",
            perTransactionThreshold: 100,
            currentQualifiedAmount: 450,
            qualifyingCap: 500
        ), 50)
        XCTAssertEqual(PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: 200,
            transactionCurrencyCode: "CNY",
            promotionCurrencyCode: "CNY",
            perTransactionThreshold: nil,
            currentQualifiedAmount: 700,
            qualifyingCap: 500
        ), 0)
    }

    func testUnknownDateBasisAcceptsEitherTransactionOrPostingDate() {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        let network = CardNetwork.makeBuiltIns()[0]
        let card = Card(account: account, productName: "测试卡", networks: [network], lastFour: "1234")
        let promotion = Promotion(
            title: "测试活动",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            qualificationDateBasis: .unknown,
            qualificationThreshold: 100,
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

    func testOverRefundedPromotionIDsUseOnlyOtherActiveRefunds() {
        let promotionID = UUID()
        let editingRefundID = UUID()
        let otherRefundID = UUID()
        let otherRefunds: [(transactionID: UUID, promotionID: UUID, qualifyingAmount: Decimal, status: TransactionStatus)] = [
            (otherRefundID, promotionID, 30, .active),
            (editingRefundID, promotionID, 90, .active),
            (UUID(), promotionID, 100, .reversed)
        ]
        let withinBalance = PromotionCalculator.overRefundedPromotionIDs(
            originalAllocations: [(promotionID, 100)],
            refundAllocations: [(promotionID, 60)],
            otherRefundAllocations: otherRefunds,
            excludingTransactionID: editingRefundID
        )
        let overRefunded = PromotionCalculator.overRefundedPromotionIDs(
            originalAllocations: [(promotionID, 100)],
            refundAllocations: [(promotionID, 80)],
            otherRefundAllocations: otherRefunds,
            excludingTransactionID: editingRefundID
        )

        XCTAssertTrue(withinBalance.isEmpty)
        XCTAssertEqual(overRefunded, Set([promotionID]))
    }

    func testOverRefundedPromotionIDsAggregateMultipleProposedRefunds() {
        let promotionID = UUID()

        XCTAssertEqual(
            PromotionCalculator.overRefundedPromotionIDs(
                originalAllocations: [(promotionID, 100)],
                refundAllocations: [(promotionID, 60), (promotionID, 50)],
                otherRefundAllocations: [],
                excludingTransactionID: nil
            ),
            Set([promotionID])
        )
    }

    func testRefundTotalExcludesReversedAndEditingRefunds() {
        let editingRefundID = UUID()
        let overRefunded = PromotionCalculator.refundExceedsOriginalAmount(
            originalAmount: 100,
            proposedRefundAmount: 60,
            otherRefunds: [
                (editingRefundID, 90, .active),
                (UUID(), 50, .active),
                (UUID(), 100, .reversed)
            ],
            excludingTransactionID: editingRefundID
        )

        XCTAssertTrue(overRefunded)
        XCTAssertFalse(PromotionCalculator.refundExceedsOriginalAmount(
            originalAmount: 100,
            proposedRefundAmount: .zero,
            otherRefunds: [],
            excludingTransactionID: nil
        ))
        XCTAssertTrue(PromotionCalculator.refundExceedsOriginalAmount(
            originalAmount: 50,
            proposedRefundAmount: .zero,
            otherRefunds: [(UUID(), 80, .active)],
            excludingTransactionID: nil
        ))
    }

    func testEligibleCardRecommendationsUnionEachOrganizerKindAndIntersectKinds() {
        let bankA = Bank(name: "银行 A")
        let bankB = Bank(name: "银行 B")
        let accountA = CreditCardAccount(bank: bankA)
        let accountB = CreditCardAccount(bank: bankB)
        let networks = Dictionary(uniqueKeysWithValues: CardNetwork.makeBuiltIns().map { ($0.code, $0) })
        let visa = networks["visa"]!
        let mastercard = networks["mastercard"]!
        let visaA = Card(account: accountA, productName: "Visa A", networks: [visa], lastFour: "1001")
        let mastercardA = Card(account: accountA, productName: "Mastercard A", networks: [mastercard], lastFour: "1002")
        let visaB = Card(account: accountB, productName: "Visa B", networks: [visa], lastFour: "1003")
        let inactive = Card(account: accountA, productName: "停用卡", networks: [visa], lastFour: "1004", status: .inactive)

        let recommendations = PromotionEligibility.recommendations(
            organizingBanks: [bankA, bankB],
            organizingNetworks: [visa],
            cards: [mastercardA, inactive, visaB, visaA]
        )

        XCTAssertEqual(recommendations.map(\.card.id), [visaA.id, visaB.id])
        XCTAssertEqual(recommendations.first?.reasons, ["银行：银行 A", "卡组织：Visa"])
        XCTAssertTrue(PromotionEligibility.recommendations(
            organizingBanks: [],
            organizingNetworks: [],
            cards: [visaA]
        ).isEmpty)
    }

    func testMonthlyPeriodsUseOriginalAnchorsAndRequireCompleteLastPeriod() {
        XCTAssertEqual(
            PromotionSeriesCalculator.monthlyPeriods(
                startOn: 20260131,
                endOn: 20260228,
                through: 20260428
            ),
            [
                PromotionPeriod(startOn: 20260131, endOn: 20260228),
                PromotionPeriod(startOn: 20260228, endOn: 20260328),
                PromotionPeriod(startOn: 20260331, endOn: 20260428)
            ]
        )
        XCTAssertEqual(
            PromotionSeriesCalculator.monthlyPeriods(
                startOn: 20260131,
                endOn: 20260228,
                through: 20260427
            ).count,
            2
        )
    }

    func testMonthlySeriesCreatesIndependentPromotionsAndCopyStartsActive() throws {
        let template = Promotion(
            title: "月度活动",
            startOn: 20260131,
            endOn: 20260228,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY",
            archivedAt: Date()
        )
        let periods = Promotion.makeMonthlySeries(from: template, through: 20260428)
        XCTAssertEqual(periods.count, 3)
        XCTAssertEqual(Set(periods.compactMap(\.seriesID)).count, 1)
        XCTAssertEqual(periods.compactMap(\.seriesIndex), [0, 1, 2])
        XCTAssertEqual(periods.map(\.startOn), [20260131, 20260228, 20260331])
        XCTAssertTrue(periods.allSatisfy { $0.allocations.isEmpty })

        let copied = try XCTUnwrap(template.copiedToNextMonth())
        XCTAssertNil(copied.seriesID)
        XCTAssertNil(copied.archivedAt)
        XCTAssertEqual(copied.startOn, 20260228)
        XCTAssertEqual(copied.endOn, 20260328)
        XCTAssertNotEqual(copied.id, template.id)
    }
}
