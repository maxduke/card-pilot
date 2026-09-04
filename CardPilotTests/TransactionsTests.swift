import XCTest
@testable import CardPilot

final class TransactionsTests: XCTestCase {
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
            promotionsAwaitingPostingDate([postingDatePromotion, manualPromotion], cardID: card.id, hasPostingDate: false).map(\.id),
            [postingDatePromotion.id]
        )
        XCTAssertTrue(
            promotionsAwaitingPostingDate([postingDatePromotion], cardID: card.id, hasPostingDate: true).isEmpty
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
