#if DEBUG && targetEnvironment(simulator)
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class UITestFixtureTests: XCTestCase {
    func testFutureRuleFixtureRestoresValidAndInvalidCancellationScenarios() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for rawDate in [20260101, 20260910, 20261231] {
            let today = try LocalDate(rawValue: rawDate)
            let container = try CardPilotPersistence.makeContainer(inMemory: true)
            try UITestBootstrap.seed(container.mainContext, scenario: .futureRules, today: today)
            let records = try BackupRecords.capture(container.mainContext)
            let restored = try records.validatedContainer()
            XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
            let cards = try restored.mainContext.fetch(FetchDescriptor<Card>())
            for name in ["UI Shared", "UI Foreign"] {
                let account = try XCTUnwrap(cards.first { $0.productName == name }?.account)
                XCTAssertEqual(account.billingRuleVersions.count, 3)
                let record = try XCTUnwrap(account.billingCycles.first)
                let overrides = [record.cycleKey: BillingCycleOverride(
                    statementDate: try record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                    repaymentDate: try record.repaymentDateOverride.map { try LocalDate(rawValue: $0) }, repaidAt: nil)]
                let validate = {
                    try FutureBillingRuleCancellation.remainingRules(removing: today.addingMonths(1).monthKey,
                        rules: account.billingRuleVersions.map(\.billingRuleInput), overrides: overrides,
                        today: today, timeZone: timeZone)
                }
                if name == "UI Shared" { XCTAssertEqual(try validate().count, 2) }
                else {
                    XCTAssertThrowsError(try validate()) {
                        XCTAssertEqual($0 as? FutureBillingRuleCancellation.CancellationError, .invalidDates(record.cycleKey))
                    }
                }
            }
        }
    }

    func testAccountHistoryFixtureRestoresFullPaidAndUnpaidCyclesWithSavedDates() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for rawDate in [20260101, 20260910, 20261231] {
            let today = try LocalDate(rawValue: rawDate)
            let container = try CardPilotPersistence.makeContainer(inMemory: true)
            try UITestBootstrap.seed(container.mainContext, scenario: .accountHistory, today: today)
            let records = try BackupRecords.capture(container.mainContext)
            let restored = try records.validatedContainer()
            XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
            let card = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<Card>()).first { $0.productName == "UI Shared" })
            XCTAssertEqual(card.account.cards.count, 2)
            let cycles = accountDetailCycles(card.account, today: today, includesTrackedHistory: true, timeZone: timeZone)
            XCTAssertEqual(cycles.count, 23)
            XCTAssertEqual(filterAccountHistoryCycles(cycles, year: nil, month: nil, status: .paid).count, 8)
            XCTAssertEqual(filterAccountHistoryCycles(cycles, year: nil, month: nil, status: .unpaid).count, 15)
            let explicit = try XCTUnwrap(cycles.first { $0.cycleKey == today.addingMonths(5).monthKey })
            XCTAssertEqual(explicit.statementDate.day, 3)
            XCTAssertEqual(explicit.repaymentDate.day, 6)
            XCTAssertTrue(cycles.contains { $0.cycleKey == today.addingMonths(-20).monthKey && $0.status == .paid })
        }
    }

    func testCoreFixturePassesFullBackupValidation() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext)
        let records = try BackupRecords.capture(container.mainContext)
        // UI fixtures must obey the same model and relationship rules as user data.
        // This catches noncanonical built-in network identities as well as invalid links.
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let cards = try restored.mainContext.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(Set(cards.map { $0.account.id }).count, 2)
        XCTAssertEqual(cards.first { $0.productName == "UI Foreign" }?.account.limitCurrencyCode, "HKD")
        let promotion = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<Promotion>()).first)
        XCTAssertEqual(promotion.eligibleCards.map(\.productName), ["UI Primary"])
    }

    func testPromotionAmountsFixtureRestoresOptionalRulesAndPreservesCoreDefaults() throws {
        let today = try LocalDate(rawValue: 20261012)
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext, scenario: .promotionAmounts, today: today)
        let records = try BackupRecords.capture(container.mainContext)
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let promotion = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<Promotion>()).first)
        XCTAssertEqual(promotion.title, "UI Spend")
        XCTAssertEqual(promotion.qualifyingCap, Decimal(5000))
        XCTAssertEqual(promotion.perTransactionThreshold, Decimal(100))
        XCTAssertEqual(promotion.qualificationThreshold, Decimal(1000))
        XCTAssertEqual(promotion.progressCurrencyCode, "CNY")
        XCTAssertEqual(promotion.eligibleCards.map(\.productName), ["UI Primary"])
        XCTAssertEqual(promotion.startOn, today.addingDays(-7).rawValue)
        XCTAssertEqual(promotion.endOn, today.addingDays(30).rawValue)
        XCTAssertTrue(promotion.allocations.isEmpty)
        let core = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(core.mainContext, today: today)
        let corePromotion = try XCTUnwrap(core.mainContext.fetch(FetchDescriptor<Promotion>()).first)
        XCTAssertNil(corePromotion.qualifyingCap)
        XCTAssertNil(corePromotion.perTransactionThreshold)
    }

    func testAllocationFeedbackFixtureRestoresOrderedCandidatesWithoutSavedAllocations() throws {
        let today = try LocalDate(rawValue: 20261231)
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext, scenario: .allocationFeedback, today: today)
        let records = try BackupRecords.capture(container.mainContext)
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let promotions = try restored.mainContext.fetch(FetchDescriptor<Promotion>())
            .sorted { $0.endOn < $1.endOn }
        XCTAssertEqual(promotions.map(\.title), ["UI Spend", "UI Second", "UI Middle 1", "UI Middle 2", "UI Middle 3", "UI Last"])
        XCTAssertEqual(Set(promotions.map(\.endOn)).count, 6)
        for promotion in promotions {
            XCTAssertEqual(promotion.eligibleCards.map(\.productName), ["UI Primary"])
            XCTAssertTrue(promotion.allocations.isEmpty)
            XCTAssertTrue(PromotionCalculator.shouldAutomaticallySelect(
                promotion, transactionAmount: Decimal(string: "125.50")!, transactionCurrencyCode: "CNY"
            ))
        }
    }

    func testPromotionOverviewFixtureRestoresDistinctProgressModes() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext, scenario: .promotionOverview)
        let records = try BackupRecords.capture(container.mainContext)
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let promotions = try restored.mainContext.fetch(FetchDescriptor<Promotion>())
        let progress = try Dictionary(uniqueKeysWithValues: promotions.map {
            ($0.title, try PromotionCalculator.progress(for: $0))
        })
        XCTAssertEqual(progress["UI Spend"]?.remainingToThreshold, 1000)
        XCTAssertNil(progress["UI Amount Cap"]?.qualificationThreshold)
        XCTAssertEqual(progress["UI Amount Cap"]?.remainingCap, 500)
        XCTAssertEqual(progress["UI Available"]?.remainingTransactionCount, 2)
        XCTAssertEqual(progress["UI Exhausted"]?.remainingTransactionCount, 0)
        XCTAssertEqual(progress["UI Reached"]?.remainingToThreshold, 0)
    }

    func testDashboardFixtureRestoresTwentyCardsWithFiveDistinctActions() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        for rawDate in [20260101, 20260302, 20260910, 20261231] {
            let today = try LocalDate(rawValue: rawDate)
            let container = try CardPilotPersistence.makeContainer(inMemory: true)
            try UITestBootstrap.seed(container.mainContext, scenario: .dashboardActions, today: today)
            let records = try BackupRecords.capture(container.mainContext)
            let restored = try records.validatedContainer()
            XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)

            let cards = try restored.mainContext.fetch(FetchDescriptor<Card>())
            XCTAssertEqual(cards.count, 20)
            XCTAssertEqual(Set(cards.map { $0.account.id }).count, 4)
            let accounts = try restored.mainContext.fetch(FetchDescriptor<CreditCardAccount>())
            let repayments = dashboardBillingItems(for: accounts, today: today, timeZone: timeZone).filter {
                $0.kind == .repayment && dashboardActionPeriod(for: $0.date, isOverdue: $0.status == .overdue, today: today) != nil
            }
            XCTAssertEqual(repayments.count, 3)
            XCTAssertEqual(Set(repayments.map { $0.account.id }).count, 3)
            let promotions = try restored.mainContext.fetch(FetchDescriptor<Promotion>())
            let enrollment = promotionsWithEnrollmentDeadlineWithin(promotions, today: today)
            XCTAssertEqual(enrollment.count, 2)
            XCTAssertTrue(enrollment.contains { $0.startOn > today.rawValue })
            XCTAssertEqual(
                dashboardActionCounts(billingItems: repayments, enrollmentPromotions: enrollment, today: today),
                DashboardActionCounts(overdue: 1, today: 2, nextSevenDays: 2)
            )
        }
    }

    func testLinkedRefundFixtureRestoresCurrencyAssociationAndIndependentReversal() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext, scenario: .linkedRefunds)
        let records = try BackupRecords.capture(container.mainContext)
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let transactions = try restored.mainContext.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 4)
        let original = try XCTUnwrap(transactions.first { $0.merchant == "UI Original Purchase" })
        XCTAssertEqual(original.currencyCode, "CNY")
        XCTAssertEqual(original.card.account.limitCurrencyCode, "HKD")
        XCTAssertEqual(original.refunds.count, 1)
        XCTAssertEqual(original.refunds.first?.originalTransaction?.id, original.id)
        XCTAssertEqual(original.refunds.first?.allocations.first?.qualifyingAmount, 40)
        let promotion = try XCTUnwrap(original.allocations.first?.promotion)
        XCTAssertEqual(try PromotionCalculator.progress(for: promotion).qualifiedAmount, 60)
        XCTAssertEqual(transactions.first { $0.merchant == "UI Reversed Purchase" }?.status, .reversed)
        XCTAssertNil(transactions.first { $0.merchant == "UI Unlinked Refund" }?.originalTransaction)
    }

    func testRefundIdentityFixtureRestoresDistinctOriginalAmountsCurrenciesAndStatuses() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        try UITestBootstrap.seed(container.mainContext, scenario: .refundIdentity)
        let records = try BackupRecords.capture(container.mainContext)
        let restored = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
        let transactions = try restored.mainContext.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(transactions.count, 2)
        let original = try XCTUnwrap(transactions.first { $0.merchant == "星河百货中心生活用品与家居电器联合专柜" })
        let alternate = try XCTUnwrap(transactions.first { $0.merchant == "UI Alternate Original" })
        XCTAssertEqual(original.card.id, alternate.card.id)
        XCTAssertEqual(original.card.account.limitCurrencyCode, "HKD")
        XCTAssertTrue(transactions.allSatisfy { $0.kind == .purchase && $0.originalTransaction == nil && $0.refunds.isEmpty })
        XCTAssertEqual(original.transactionOn, 20261010)
        XCTAssertEqual(original.amount, Decimal(string: "100.25"))
        XCTAssertEqual(original.currencyCode, "CNY")
        XCTAssertEqual(original.status, .reversed)
        XCTAssertEqual(alternate.transactionOn, 20261009)
        XCTAssertEqual(alternate.amount, Decimal(string: "65.5"))
        XCTAssertEqual(alternate.currencyCode, "HKD")
        XCTAssertEqual(alternate.status, .active)
    }

    func testTransactionFilterFixtureRestoresDistinctDatesCurrenciesAndStatuses() throws {
        for rawDate in [20240229, 20270101, 20270131] {
            let today = try LocalDate(rawValue: rawDate)
            let container = try CardPilotPersistence.makeContainer(inMemory: true)
            try UITestBootstrap.seed(container.mainContext, scenario: .transactionFilters, today: today)
            let records = try BackupRecords.capture(container.mainContext)
            let restored = try records.validatedContainer()
            XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
            let transactions = try restored.mainContext.fetch(FetchDescriptor<Transaction>())
            XCTAssertEqual(transactions.count, 8)
            let range = TransactionDatePeriod.lastMonth.range(today: today, customRange: nil)
            let matches = filterTransactions(transactions, cardID: nil, kind: nil, promotionID: nil, status: nil, searchText: "", dateRange: range, currencyCode: "CNY")
            XCTAssertEqual(matches.count, 2)
            XCTAssertTrue(matches.contains { $0.status == .reversed })
            XCTAssertEqual(filterTransactions(transactions, cardID: nil, kind: nil, promotionID: nil, status: .active, searchText: "", dateRange: range, currencyCode: "CNY").count, 1)
        }
    }
}
#endif
