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
}
#endif
