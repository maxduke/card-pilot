import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class PromotionPersistenceTests: XCTestCase {
    private enum SaveError: Error { case failed }

    func testArchivingOnePeriodPreservesAllocationsAndOtherPeriodsAcrossReadback() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, _, card) = try makeCard(in: context)
        let periods = Promotion.makeMonthlySeries(startingWith: Promotion(
            title: "月度活动", startOn: 20260101, endOn: 20260131,
            eligibleCards: [card], qualificationThreshold: 100, progressCurrencyCode: "CNY"
        ), through: 20260331)
        try PromotionCreationActions.save(periods, context: context)
        let selected = periods[1]
        let transaction = Transaction(card: card, transactionOn: 20260205, amount: 60,
                                      currencyCode: "CNY", merchant: "测试商户")
        context.insert(transaction)
        try PromotionAllocationActions.save(60, transaction: transaction, promotion: selected,
                                            allocation: nil, context: context)
        let date = Date(timeIntervalSince1970: 1_000)
        try PromotionArchiveActions.setArchived(true, for: selected, context: context, now: date)
        try PromotionArchiveActions.setArchived(true, for: selected, context: context, now: date.addingTimeInterval(60))

        let reader = ModelContext(container)
        let saved = try reader.fetch(FetchDescriptor<Promotion>())
        let archived = try XCTUnwrap(saved.first { $0.id == selected.id })
        XCTAssertEqual(archived.archivedAt, date)
        XCTAssertEqual(saved.filter { $0.archivedAt == nil }.count, 2)
        XCTAssertEqual(archived.allocations.count, 1)
        XCTAssertEqual(try PromotionCalculator.progress(for: archived).qualifiedAmount, 60)
        XCTAssertEqual(archived.eligibleCards.map(\.id), [card.id])
        XCTAssertFalse(PromotionCalculator.includes(transaction, in: selected))

        try PromotionArchiveActions.setArchived(false, for: selected, context: context)
        XCTAssertTrue(PromotionCalculator.includes(transaction, in: selected))
        XCTAssertEqual(try PromotionCalculator.progress(for: selected).qualifiedAmount, 60)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Promotion>()).allSatisfy { $0.archivedAt == nil })
    }

    func testArchiveAndRestoreFailuresKeepThePreviouslySavedState() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let promotion = Promotion(title: "活动", startOn: 20260101, endOn: 20260131, progressCurrencyCode: "CNY")
        try PromotionCreationActions.save([promotion], context: context)
        let date = Date(timeIntervalSince1970: 1_000)
        for previouslyArchived in [false, true] {
            try PromotionArchiveActions.setArchived(previouslyArchived, for: promotion, context: context, now: date)
            XCTAssertThrowsError(try PromotionArchiveActions.setArchived(!previouslyArchived, for: promotion,
                context: context, persist: { _ in throw SaveError.failed }))
            XCTAssertEqual(promotion.archivedAt, previouslyArchived ? date : nil)
            XCTAssertFalse(context.hasChanges)
            let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Promotion>()).first)
            XCTAssertEqual(saved.archivedAt, previouslyArchived ? date : nil)
        }
    }

    func testMonthlySeriesWithPersistedRelationshipsReopensWithoutStandaloneTemplate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("series.store")
        let expectedIDs: Set<UUID>
        do {
            let container = try CardPilotPersistence.makeContainer(at: url)
            let context = container.mainContext
            context.autosaveEnabled = false
            let (bank, network, card) = try makeCard(in: context)
            let first = Promotion(title: "月度活动", startOn: 20260101, endOn: 20260131,
                                  organizingBanks: [bank], organizingNetworks: [network], eligibleCards: [card],
                                  enrollmentStatus: .enrolled, enrolledOn: 20260105,
                                  progressCurrencyCode: "CNY")
            let periods = Promotion.makeMonthlySeries(startingWith: first, through: 20260331)
            expectedIDs = Set(periods.map(\.id))
            try PromotionCreationActions.save(periods, context: context)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Promotion>()), 3)
        }
        let reopened = try CardPilotPersistence.makeContainer(at: url)
        let context = reopened.mainContext
        let periods = try context.fetch(FetchDescriptor<Promotion>()).sorted { ($0.seriesIndex ?? -1) < ($1.seriesIndex ?? -1) }
        XCTAssertEqual(Set(periods.map(\.id)), expectedIDs)
        XCTAssertEqual(periods.map(\.seriesIndex), [0, 1, 2])
        XCTAssertEqual(Set(periods.compactMap(\.seriesID)).count, 1)
        XCTAssertEqual(periods.map(\.enrollmentStatus), [.enrolled, .notEnrolled, .notEnrolled])
        XCTAssertEqual(periods.map(\.enrolledOn), [20260105, nil, nil])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Bank>()).first?.organizedPromotions.count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CardNetwork>()).first?.organizedPromotions.count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).first?.eligiblePromotions.count, 3)
    }

    func testFailedSeriesSaveRestoresExistingInverseRelationships() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let (bank, network, card) = try makeCard(in: context)
        let existing = Promotion(title: "保留活动", startOn: 20260101, endOn: 20260131,
                                 organizingBanks: [bank], organizingNetworks: [network], eligibleCards: [card],
                                 progressCurrencyCode: "CNY")
        try PromotionCreationActions.save([existing], context: context)
        let first = Promotion(title: "月度活动", startOn: 20260101, endOn: 20260131,
                              organizingBanks: [bank], organizingNetworks: [network], eligibleCards: [card],
                              progressCurrencyCode: "CNY")
        let periods = Promotion.makeMonthlySeries(startingWith: first, through: 20260331)
        XCTAssertThrowsError(try PromotionCreationActions.save(periods, context: context, persist: { _ in throw SaveError.failed }))
        XCTAssertEqual(bank.organizedPromotions.map(\.id), [existing.id])
        XCTAssertEqual(network.organizedPromotions.map(\.id), [existing.id])
        XCTAssertEqual(card.eligiblePromotions.map(\.id), [existing.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Promotion>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testStandaloneCreationFailurePreservesRelationshipsAndFreshRetrySucceeds() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let (bank, network, card) = try makeCard(in: context)
        let existing = Promotion(title: "保留活动", startOn: 20260101, endOn: 20260131,
                                 organizingBanks: [bank], organizingNetworks: [network], eligibleCards: [card],
                                 progressCurrencyCode: "CNY")
        try PromotionCreationActions.save([existing], context: context)
        let id = UUID()
        func standalone() -> Promotion {
            Promotion(id: id, title: "独立活动", startOn: 20260101, endOn: 20260131,
                      organizingBanks: [bank], organizingNetworks: [network], eligibleCards: [card],
                      enrollmentStatus: .enrolled, enrolledOn: 20260105, progressCurrencyCode: "CNY")
        }
        XCTAssertThrowsError(try PromotionCreationActions.save([standalone()], context: context,
            persist: { _ in throw SaveError.failed }))
        XCTAssertEqual(bank.organizedPromotions.map(\.id), [existing.id])
        XCTAssertEqual(network.organizedPromotions.map(\.id), [existing.id])
        XCTAssertEqual(card.eligiblePromotions.map(\.id), [existing.id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Promotion>()), 1)
        XCTAssertFalse(context.hasChanges)

        try PromotionCreationActions.save([standalone()], context: context)
        let reader = ModelContext(container)
        let saved = try XCTUnwrap(reader.fetch(FetchDescriptor<Promotion>()).first { $0.id == id })
        XCTAssertNil(saved.seriesID)
        XCTAssertNil(saved.seriesIndex)
        XCTAssertEqual(saved.enrollmentStatus, .enrolled)
        XCTAssertEqual(saved.enrolledOn, 20260105)
        XCTAssertEqual(saved.organizingBanks.map(\.id), [bank.id])
        XCTAssertEqual(saved.eligibleCards.map(\.id), [card.id])
        XCTAssertEqual(try reader.fetchCount(FetchDescriptor<Promotion>()), 2)
    }

    func testAllocationFailureRestoresProgressAndAllowsRetry() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let (_, _, card) = try makeCard(in: context)
        let promotion = Promotion(title: "活动", startOn: 20260101, endOn: 20260131,
                                  eligibleCards: [card], progressCurrencyCode: "CNY")
        let transaction = Transaction(card: card, transactionOn: 20260105, amount: 100,
                                      currencyCode: "CNY", merchant: "商户")
        context.insert(promotion)
        context.insert(transaction)
        try context.save()
        XCTAssertThrowsError(try PromotionAllocationActions.save(100, transaction: transaction, promotion: promotion,
            allocation: nil, context: context, persist: { _ in throw SaveError.failed }))
        XCTAssertTrue(transaction.allocations.isEmpty)
        XCTAssertTrue(promotion.allocations.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromotionAllocation>()), 0)
        XCTAssertFalse(context.hasChanges)

        try PromotionAllocationActions.save(100, transaction: transaction, promotion: promotion,
                                            allocation: nil, context: context)
        let allocation = try XCTUnwrap(transaction.allocations.first)
        XCTAssertThrowsError(try PromotionAllocationActions.save(200, transaction: transaction, promotion: promotion,
            allocation: allocation, context: context, persist: { _ in throw SaveError.failed }))
        XCTAssertEqual(allocation.qualifyingAmount, 100)
        XCTAssertEqual(try PromotionCalculator.progress(for: promotion).qualifiedAmount, 100)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromotionAllocation>()), 1)
        XCTAssertFalse(context.hasChanges)
    }

    private func makeCard(in context: ModelContext) throws -> (Bank, CardNetwork, Card) {
        let bank = Bank(name: "测试银行")
        let network = CardNetwork.makeBuiltIns()[0]
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202601)
        let rule = BillingRuleVersion(account: account, statementDay: 5, repaymentKind: .daysAfterStatement, repaymentValue: 20)
        let card = Card(account: account, productName: "测试卡", networks: [network], lastFour: "1234")
        context.insert(bank)
        context.insert(network)
        context.insert(account)
        context.insert(rule)
        context.insert(card)
        try context.save()
        return (bank, network, card)
    }
}
