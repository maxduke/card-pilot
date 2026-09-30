import SwiftData
import XCTest
@testable import CardPilot

final class TransactionsTests: XCTestCase {
    func testAllocationWarningPreservesManualAmountsAndDoesNotInferExchangeRates() {
        XCTAssertTrue(transactionAllocationExceedsAmount(transactionAmount: 100, transactionCurrencyCode: "CNY",
            allocationAmount: 1000, allocationCurrencyCode: "CNY"))
        XCTAssertFalse(transactionAllocationExceedsAmount(transactionAmount: 100, transactionCurrencyCode: "CNY",
            allocationAmount: 100, allocationCurrencyCode: "CNY"))
        XCTAssertFalse(transactionAllocationExceedsAmount(transactionAmount: 100, transactionCurrencyCode: "HKD",
            allocationAmount: 1000, allocationCurrencyCode: "CNY"))
        XCTAssertFalse(transactionAllocationExceedsAmount(transactionAmount: nil, transactionCurrencyCode: "CNY",
            allocationAmount: 1000, allocationCurrencyCode: "CNY"))
        XCTAssertFalse(transactionAllocationExceedsAmount(transactionAmount: 100, transactionCurrencyCode: "CNY",
            allocationAmount: nil, allocationCurrencyCode: "CNY"))
    }

    func testRefundSuggestionUsesRemainingAllocationAndExcludesSelfAndReversedRefunds() {
        let card = makeCard()
        let promotion = makePromotion(card: card)
        let original = Transaction(card: card, transactionOn: 20260801, amount: 1000, currencyCode: "CNY", merchant: "原消费")
        original.allocations = [PromotionAllocation(transaction: original, promotion: promotion,
                                                    qualifyingAmount: 500, currencyCode: "CNY")]
        let earlier = Transaction(card: card, kind: .refund, transactionOn: 20260802, amount: 200,
                                  currencyCode: "CNY", merchant: "首次退款", originalTransaction: original)
        earlier.allocations = [PromotionAllocation(transaction: earlier, promotion: promotion,
                                                   qualifyingAmount: 200, currencyCode: "CNY")]
        let editing = Transaction(card: card, kind: .refund, transactionOn: 20260803, amount: 100,
                                  currencyCode: "CNY", merchant: "本次退款", originalTransaction: original)
        editing.allocations = [PromotionAllocation(transaction: editing, promotion: promotion,
                                                   qualifyingAmount: 100, currencyCode: "CNY")]
        let reversed = Transaction(card: card, kind: .refund, transactionOn: 20260804, amount: 400,
                                   currencyCode: "CNY", merchant: "已冲正退款", originalTransaction: original, status: .reversed)
        reversed.allocations = [PromotionAllocation(transaction: reversed, promotion: promotion,
                                                    qualifyingAmount: 400, currencyCode: "CNY")]
        original.refunds = [earlier, editing, reversed]
        XCTAssertEqual(suggestedRefundAllocationAmount(refundAmount: 1000, refundCurrencyCode: "CNY",
            promotion: promotion, original: original, excludingTransactionID: editing.id), 300)
        XCTAssertEqual(suggestedRefundAllocationAmount(refundAmount: 50, refundCurrencyCode: "CNY",
            promotion: promotion, original: original, excludingTransactionID: editing.id), 50)
        XCTAssertEqual(suggestedRefundAllocationAmount(refundAmount: 1000, refundCurrencyCode: "CNY",
            promotion: promotion, original: original, excludingTransactionID: nil), 200)
        earlier.allocations[0].qualifyingAmount = 500
        XCTAssertEqual(suggestedRefundAllocationAmount(refundAmount: 100, refundCurrencyCode: "CNY",
            promotion: promotion, original: original, excludingTransactionID: editing.id), 0)
    }

    func testRefundSuggestionDoesNotGuessCrossCurrencyAmount() {
        let card = makeCard()
        let promotion = makePromotion(card: card)
        let original = Transaction(card: card, transactionOn: 20260801, amount: 100, currencyCode: "HKD", merchant: "原消费")
        XCTAssertNil(suggestedRefundAllocationAmount(refundAmount: 100, refundCurrencyCode: "HKD",
            promotion: promotion, original: original, excludingTransactionID: nil))
        XCTAssertNil(suggestedRefundAllocationAmount(refundAmount: 100, refundCurrencyCode: "CNY",
            promotion: promotion, original: original, excludingTransactionID: nil))
        XCTAssertEqual(suggestedRefundAllocationAmount(refundAmount: 100, refundCurrencyCode: "CNY",
            promotion: promotion, original: nil, excludingTransactionID: nil), 100)
    }

    func testDraftIdentifiesDeletedAndChangedCurrencyPromotionsWithoutInvalidatingOthers() {
        let unchanged = makePromotion(card: makeCard())
        let changed = makePromotion(card: makeCard())
        changed.progressCurrencyCode = "HKD"
        let deletedID = UUID()
        XCTAssertEqual(invalidDraftPromotionIDs(selectedIDs: [unchanged.id, changed.id, deletedID],
            savedCurrencies: [unchanged.id: "CNY", changed.id: "CNY", deletedID: "CNY"],
            promotions: [unchanged, changed]), [changed.id, deletedID])
        XCTAssertTrue(invalidDraftPromotionIDs(selectedIDs: [changed.id], savedCurrencies: [:],
            promotions: [unchanged, changed]).isEmpty, "Explicitly reselecting an activity accepts its current currency.")
    }

    func testPostingDateSuggestionsExcludeExpiredPeriodsButKeepBoundaryAndFuturePeriodsSearchable() {
        let card = makeCard()
        let expired = makePromotion(card: card)
        expired.endOn = 20260830
        let boundary = makePromotion(card: card)
        let future = makePromotion(card: card)
        future.startOn = 20260901
        future.endOn = 20260930
        for promotion in [expired, boundary, future] { promotion.qualificationDateBasis = .postingDate }
        XCTAssertEqual(promotionsAwaitingPostingDate([expired, boundary, future], cardID: card.id,
            hasPostingDate: false, transactionOn: 20260831).map(\.id), [boundary.id, future.id])
        XCTAssertEqual(promotionsMatchingSearch([expired], searchText: expired.title).map(\.id), [expired.id],
                       "Excluded suggestions must remain available for manual historical exceptions.")
        XCTAssertTrue(promotionsAwaitingPostingDate([boundary], cardID: nil,
            hasPostingDate: false, transactionOn: 20260831).isEmpty)
    }

    func testReversalWarningOnlyAppliesToPurchasesWithActiveRefunds() {
        let card = makeCard()
        let original = Transaction(card: card, transactionOn: 20260801, amount: 1000, currencyCode: "CNY", merchant: "原消费")
        let refund = Transaction(card: card, kind: .refund, transactionOn: 20260802, amount: 300,
                                 currencyCode: "CNY", merchant: "退款", originalTransaction: original)
        original.refunds = [refund]
        XCTAssertTrue(transactionHasActiveRefunds(original))
        XCTAssertFalse(transactionHasActiveRefunds(refund))
        original.reverse()
        XCTAssertEqual(refund.status, .active, "The original and refund remain independent facts.")
        refund.reverse()
        XCTAssertFalse(transactionHasActiveRefunds(original))
    }

    @MainActor
    func testInvalidSaveDoesNotMutateRelationshipsOrInsertDraft() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let card = makeCard()
        let promotion = makePromotion(card: card)
        context.insert(card)
        context.insert(promotion)
        try context.save()
        let original = Transaction(card: card, transactionOn: 20260801, amount: 1000, currencyCode: "CNY", merchant: "原消费")
        context.insert(original)
        try context.save()
        var values = saveValues()
        values.kind = .refund
        XCTAssertThrowsError(try TransactionEditActions.save(values: values, transaction: nil, newID: UUID(),
            card: card, original: original, allocations: [(promotion, 0)], context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertTrue(original.refunds.isEmpty)
        XCTAssertTrue(promotion.allocations.isEmpty)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testFailedNewRefundSaveRestoresInverseRelationshipsAndAllowsRetry() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let card = makeCard()
        let promotion = makePromotion(card: card)
        context.insert(card)
        context.insert(promotion)
        let original = Transaction(card: card, transactionOn: 20260801, amount: 1000, currencyCode: "CNY", merchant: "原消费")
        context.insert(original)
        try context.save()
        var values = saveValues()
        values.kind = .refund
        let draftID = UUID()
        XCTAssertThrowsError(try TransactionEditActions.save(values: values, transaction: nil, newID: draftID,
            card: card, original: original, allocations: [(promotion, 100)], context: context,
            persist: { _ in throw DraftError.unreadable }))
        XCTAssertEqual(card.transactions.map(\.id), [original.id])
        XCTAssertTrue(original.refunds.isEmpty)
        XCTAssertTrue(promotion.allocations.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PromotionAllocation>()), 0)
        let saved = try TransactionEditActions.save(values: values, transaction: nil, newID: draftID,
            card: card, original: original, allocations: [(promotion, 100)], context: context)
        XCTAssertEqual(saved.id, draftID)
        XCTAssertEqual(original.refunds.map(\.id), [draftID])
        XCTAssertEqual(promotion.allocations.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 2)
        XCTAssertEqual(try PromotionCalculator.progress(for: promotion).qualifiedAmount, -100)
    }

    @MainActor
    func testFailedEditRestoresAmountAndDeletedAllocationThenRetainsManualAmountOnRetry() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let card = makeCard()
        let promotion = makePromotion(card: card)
        context.insert(card)
        context.insert(promotion)
        try context.save()
        var values = saveValues()
        values.amount = 1000
        let transaction = try TransactionEditActions.save(values: values, transaction: nil, newID: UUID(),
            card: card, original: nil, allocations: [(promotion, 1000)], context: context)
        let allocationID = try XCTUnwrap(transaction.allocations.first).id
        values.amount = 100
        XCTAssertThrowsError(try TransactionEditActions.save(values: values, transaction: transaction, newID: UUID(),
            card: card, original: nil, allocations: [], context: context,
            persist: { _ in throw DraftError.unreadable }))
        XCTAssertEqual(transaction.amount, 1000)
        XCTAssertEqual(transaction.allocations.map(\.id), [allocationID])
        XCTAssertEqual(promotion.allocations.map(\.id), [allocationID])
        XCTAssertEqual(try PromotionCalculator.progress(for: promotion).qualifiedAmount, 1000)
        try TransactionEditActions.save(values: values, transaction: transaction, newID: UUID(),
            card: card, original: nil, allocations: [(promotion, 1000)], context: context)
        XCTAssertEqual(transaction.amount, 100)
        XCTAssertEqual(transaction.allocations.first?.qualifyingAmount, 1000,
                       "A warning must not silently rewrite a manually confirmed allocation.")
    }

    private func makeCard() -> Card {
        Card(account: CreditCardAccount(bank: Bank(name: "测试银行")), productName: "主卡",
             networks: [CardNetwork.makeBuiltIns()[0]], lastFour: "1234")
    }

    private func makePromotion(card: Card) -> Promotion {
        Promotion(title: "测试活动", startOn: 20260801, endOn: 20260831, eligibleCards: [card], progressCurrencyCode: "CNY")
    }

    private func saveValues() -> TransactionEditValues {
        TransactionEditValues(kind: .purchase, transactionOn: 20260802, postingOn: nil, amount: 100,
            currencyCode: "CNY", merchant: "测试商户", category: "", notes: "", status: .active)
    }

    func testPromotionFilterLabelDistinguishesSeriesPeriods() {
        let promotion = Promotion(
            seriesID: UUID(),
            seriesIndex: 1,
            title: "月度活动",
            startOn: 20260201,
            endOn: 20260228,
            progressCurrencyCode: "CNY"
        )

        let label = promotionFilterLabel(promotion)

        XCTAssertTrue(label.contains("第 2 期"))
        XCTAssertTrue(label.contains(CardPilotUI.dateRangeText(start: 20260201, end: 20260228)))
    }

    func testTransactionFilterDefaultsToAllAndMatchesCardMerchantOrCategory() {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        let network = CardNetwork.makeBuiltIns()[0]
        let firstCard = Card(account: account, productName: "主卡", networks: [network], lastFour: "1234")
        let secondCard = Card(account: account, productName: "副卡", networks: [network], lastFour: "5678")
        let coffee = Transaction(
            card: firstCard,
            transactionOn: 20260801,
            amount: 20,
            currencyCode: "CNY",
            merchant: "Coffee Shop",
            category: "餐饮"
        )
        let groceries = Transaction(
            card: firstCard,
            transactionOn: 20260802,
            amount: 30,
            currencyCode: "CNY",
            merchant: "超市",
            category: "日常"
        )
        let travel = Transaction(
            card: secondCard,
            transactionOn: 20260803,
            amount: 40,
            currencyCode: "CNY",
            merchant: "机场",
            category: "旅行"
        )

        let transactions = [coffee, groceries, travel]
        XCTAssertEqual(filterTransactions(transactions, cardID: nil, searchText: "").count, 3)
        XCTAssertEqual(filterTransactions(transactions, cardID: firstCard.id, searchText: "").count, 2)
        XCTAssertEqual(filterTransactions(transactions, cardID: nil, searchText: "coffee").map(\.id), [coffee.id])
        XCTAssertEqual(filterTransactions(transactions, cardID: nil, searchText: "旅行").map(\.id), [travel.id])
        XCTAssertEqual(filterTransactions(transactions, cardID: firstCard.id, searchText: "日常").map(\.id), [groceries.id])
    }

    func testPostingDatePromotionsRemainVisibleWithoutBeingCandidatesAndSearchFindsOthers() {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let card = Card(
            account: account,
            productName: "测试卡",
            networks: [CardNetwork.makeBuiltIns()[0]],
            lastFour: "1234"
        )
        let postingDatePromotion = Promotion(
            title: "入账日活动",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            qualificationDateBasis: .postingDate,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let manualPromotion = Promotion(
            title: "手动例外活动",
            startOn: 20260701,
            endOn: 20260731,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )

        XCTAssertEqual(
            promotionsAwaitingPostingDate([postingDatePromotion, manualPromotion], cardID: card.id, hasPostingDate: false, transactionOn: 20260801).map(\.id),
            [postingDatePromotion.id]
        )
        XCTAssertTrue(
            promotionsAwaitingPostingDate([postingDatePromotion], cardID: card.id, hasPostingDate: true, transactionOn: 20260801).isEmpty
        )
        XCTAssertEqual(
            promotionsMatchingSearch([postingDatePromotion, manualPromotion], searchText: "例外").map(\.id),
            [manualPromotion.id]
        )
    }

    func testTransactionsGroupByDateAndUseStableUUIDOrderWithinDate() {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let card = Card(
            account: account,
            productName: "测试卡",
            networks: [CardNetwork.makeBuiltIns()[0]],
            lastFour: "1234"
        )
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let sameDayLaterID = Transaction(
            id: laterID,
            card: card,
            transactionOn: 20260801,
            amount: 20,
            currencyCode: "CNY",
            merchant: "较晚 ID"
        )
        let sameDayEarlierID = Transaction(
            id: earlierID,
            card: card,
            transactionOn: 20260801,
            amount: 10,
            currencyCode: "CNY",
            merchant: "较早 ID"
        )
        let newerDate = Transaction(
            card: card,
            transactionOn: 20260802,
            amount: 30,
            currencyCode: "CNY",
            merchant: "新日期"
        )

        let sections = groupedTransactionsByDate([sameDayLaterID, newerDate, sameDayEarlierID])

        XCTAssertEqual(sections.map { $0.date }, [20260802, 20260801])
        XCTAssertEqual(sections[1].transactions.map(\.id), [earlierID, laterID])
    }

    func testTransactionFilterSupportsTypeStatusAndPromotion() {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let card = Card(
            account: account,
            productName: "测试卡",
            networks: [CardNetwork.makeBuiltIns()[0]],
            lastFour: "1234"
        )
        let purchase = Transaction(
            card: card,
            transactionOn: 20260801,
            amount: 20,
            currencyCode: "CNY",
            merchant: "消费"
        )
        let refund = Transaction(
            card: card,
            kind: .refund,
            transactionOn: 20260802,
            amount: 5,
            currencyCode: "CNY",
            merchant: "退款",
            originalTransaction: purchase,
            status: .reversed
        )
        let promotion = Promotion(
            title: "测试促销",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )
        purchase.allocations.append(
            PromotionAllocation(
                transaction: purchase,
                promotion: promotion,
                qualifyingAmount: 20,
                currencyCode: "CNY"
            )
        )

        XCTAssertEqual(
            filterTransactions([purchase, refund], cardID: card.id, kind: .refund, promotionID: nil, status: .reversed, searchText: "").map(\.id),
            [refund.id]
        )
        XCTAssertEqual(
            filterTransactions([purchase, refund], cardID: nil, kind: nil, promotionID: promotion.id, status: nil, searchText: "").map(\.id),
            [purchase.id]
        )
    }
}
