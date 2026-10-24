#if DEBUG && targetEnvironment(simulator)
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class PerformanceFixtureTests: XCTestCase {
    func testPerformanceFixtureRestoresSharedAccountsHistoryAndMonthlyAllocations() throws {
        for rawDate in [20260228, 20261024, 20261231] {
            let today = try LocalDate(rawValue: rawDate)
            let container = try CardPilotPersistence.makeContainer(inMemory: true)
            let report = try PerformanceFixture.seed(container.mainContext, transactionCount: 100, today: today)
            let records = try BackupRecords.capture(container.mainContext)
            let restored = try records.validatedContainer()
            XCTAssertEqual(try BackupRecords.capture(restored.mainContext), records)
            XCTAssertEqual(report.transactions, 100)
            XCTAssertEqual(report.billingCycles, 610)
            let accounts = try restored.mainContext.fetch(FetchDescriptor<CreditCardAccount>())
            XCTAssertEqual(accounts.count, 10)
            XCTAssertTrue(accounts.allSatisfy { $0.cards.count == 2 && $0.billingCycles.count == 61 })
            XCTAssertTrue(accounts.allSatisfy { $0.billingCycles.filter { $0.repaidAt != nil }.count == 60 })
            let transactions = try restored.mainContext.fetch(FetchDescriptor<Transaction>())
            XCTAssertEqual(transactions.map(\.transactionOn).min(), today.addingMonths(-60).rawValue)
            XCTAssertEqual(transactions.map(\.transactionOn).max(), today.rawValue)
            XCTAssertEqual(transactions.filter { $0.merchant.contains("73519") }.count, report.searchMatches)
            let latest = try XCTUnwrap(transactions.first { $0.merchant == "Baseline Latest" })
            XCTAssertEqual(latest.allocations.count, 2)
            XCTAssertTrue(latest.allocations.allSatisfy { $0.promotion.seriesIndex == 5 && $0.qualifyingAmount == latest.amount })
        }
    }
}
#endif
