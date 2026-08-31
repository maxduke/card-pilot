import XCTest
@testable import CardPilot

final class TransactionsTests: XCTestCase {
    func testTransactionFilterDefaultsToAllAndMatchesCardMerchantOrCategory() {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        let network = CardNetwork.makeBuiltIns()[0]
        let firstCard = Card(account: account, productName: "主卡", network: network, lastFour: "1234")
        let secondCard = Card(account: account, productName: "副卡", network: network, lastFour: "5678")
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
            network: CardNetwork.makeBuiltIns()[0],
            lastFour: "1234"
        )
        let postingDatePromotion = Promotion(
            title: "入账日活动",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            qualificationDateBasis: .postingDate,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let manualPromotion = Promotion(
            title: "手动例外活动",
            startOn: 20260701,
            endOn: 20260731,
            targetAmount: 100,
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
}
