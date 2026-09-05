import XCTest
@testable import CardPilot

final class CardDetailsTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testNextBillingRuleCycleStartsAfterLatestScheduledVersion() {
        XCTAssertEqual(
            nextBillingRuleCycleKey(
                currentMonthKey: 202612,
                existingEffectiveCycleKeys: [202701, 202703],
                timeZone: utc
            ),
            202704
        )
        XCTAssertEqual(
            nextBillingRuleCycleKey(
                currentMonthKey: 202612,
                existingEffectiveCycleKeys: [],
                timeZone: utc
            ),
            202701
        )
    }

    func testApplicablePromotionsPrioritizeActiveAndExcludeEndedOrArchived() throws {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let card = Card(account: account, productName: "测试卡", networks: [], lastFour: "1234")
        let activeLater = Promotion(
            title: "进行中较晚结束",
            startOn: 20260901,
            endOn: 20260930,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )
        let activeSooner = Promotion(
            title: "进行中较早结束",
            startOn: 20260901,
            endOn: 20260920,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )
        let future = Promotion(
            title: "即将开始",
            startOn: 20260915,
            endOn: 20260918,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )
        let ended = Promotion(
            title: "已经结束",
            startOn: 20260801,
            endOn: 20260909,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )
        let archived = Promotion(
            title: "已归档",
            startOn: 20260901,
            endOn: 20260930,
            eligibleCards: [card],
            progressCurrencyCode: "CNY",
            archivedAt: Date()
        )

        let result = applicablePromotionsForCard(
            [future, archived, activeLater, ended, activeSooner],
            cardID: card.id,
            today: try LocalDate(rawValue: 20260910)
        )

        XCTAssertEqual(result.map(\.title), ["进行中较早结束", "进行中较晚结束", "即将开始"])
    }

    func testAccountDetailCyclesKeepsPaidHistoryAndUpcomingCycles() throws {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202607)
        let rule = BillingRuleVersion(
            account: account,
            statementDay: 5,
            repaymentKind: .fixedDay,
            repaymentValue: 20
        )
        let paid = BillingCycleRecord(
            account: account,
            cycleKey: 202607,
            repaidAt: Date(timeIntervalSince1970: 1)
        )
        account.billingRuleVersions = [rule]
        account.billingCycles = [paid]

        let cycles = accountDetailCycles(
            account,
            today: try LocalDate(rawValue: 20260910),
            includesPreviousMonth: true,
            timeZone: utc
        )

        XCTAssertEqual(cycles.map(\.cycleKey), [202608, 202607, 202609, 202610, 202611])
        XCTAssertEqual(cycles.first { $0.cycleKey == 202607 }?.status, .paid)
        XCTAssertEqual(cycles.first { $0.cycleKey == 202608 }?.status, .overdue)
        XCTAssertEqual(cycles.first { $0.cycleKey == 202609 }?.status, .pending)
    }
}
