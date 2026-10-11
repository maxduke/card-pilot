#if DEBUG && targetEnvironment(simulator)
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class UITestFixtureTests: XCTestCase {
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
}
#endif
