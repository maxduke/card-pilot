import XCTest
@testable import CardPilot

@MainActor
final class DayRefreshIntegrationTests: XCTestCase {
    func testRefreshedDayMovesBillingToOverdueWithoutChangingStoredFacts() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = try LocalDate(rawValue: 20261001).date(in: zone)
        let clock = DayClock(now: midnight.addingTimeInterval(-1), timeZone: zone)
        let account = CreditCardAccount(bank: Bank(name: "测试银行"), trackingStartCycleKey: 202609)
        let rule = BillingRuleVersion(account: account, statementDay: 1, repaymentKind: .fixedDay, repaymentValue: 30)
        account.billingRuleVersions = [rule]
        let target = BillingCycleTarget(accountID: account.id, cycleKey: 202609)

        XCTAssertEqual(accountBillingSummary(account, today: clock.day.today, timeZone: zone).nextRepaymentStatus, .pending)
        XCTAssertEqual(try BillingCycleActions.resolve(target, accounts: [account], today: clock.day.today, timeZone: zone).1.status, .pending)
        clock.refresh(now: midnight, timeZone: zone)
        XCTAssertEqual(accountBillingSummary(account, today: clock.day.today, timeZone: zone).nextRepaymentStatus, .overdue)
        let cycle = try BillingCycleActions.resolve(target, accounts: [account], today: clock.day.today, timeZone: zone).1
        XCTAssertEqual(cycle.status, .overdue)
        XCTAssertEqual(cycle.cycleKey, 202609)
        XCTAssertEqual(cycle.repaymentDate.rawValue, 20260930)
        XCTAssertTrue(account.billingCycles.isEmpty)
        XCTAssertEqual(account.billingRuleVersions.count, 1)
    }

    func testRefreshedDayUpdatesDashboardCardAndSeriesTogether() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let midnight = try LocalDate(rawValue: 20261001).date(in: zone)
        let clock = DayClock(now: midnight.addingTimeInterval(-1), timeZone: zone)
        let card = Card(account: CreditCardAccount(bank: Bank(name: "测试银行")), productName: "测试卡", networks: [], lastFour: "1234")
        let seriesID = UUID()
        let ending = Promotion(title: "九月活动", startOn: 20260901, endOn: 20260930,
            eligibleCards: [card], enrollmentStatus: .notEnrolled, enrollmentDeadline: 20260930,
            qualificationThreshold: 100, progressCurrencyCode: "CNY")
        let starting = Promotion(title: "十月活动", startOn: 20261001, endOn: 20261031,
            eligibleCards: [card], qualificationThreshold: 100, progressCurrencyCode: "CNY")
        ending.seriesID = seriesID
        ending.seriesIndex = 0
        starting.seriesID = seriesID
        starting.seriesIndex = 1
        let promotions = [ending, starting]

        XCTAssertEqual(dashboardPromotionsToContinue(promotions, today: clock.day.today).map(\.id), [ending.id])
        XCTAssertEqual(promotionsWithEnrollmentDeadlineWithin(promotions, today: clock.day.today).map(\.id), [ending.id])
        XCTAssertEqual(PromotionPresentation.groups(from: promotions, today: clock.day.today.rawValue, includeArchived: false).first?.representative.id, ending.id)

        clock.refresh(now: midnight, timeZone: zone)
        XCTAssertEqual(dashboardPromotionsToContinue(promotions, today: clock.day.today).map(\.id), [starting.id])
        XCTAssertTrue(promotionsWithEnrollmentDeadlineWithin(promotions, today: clock.day.today).isEmpty)
        XCTAssertEqual(applicablePromotionsForCard(promotions, cardID: card.id, today: clock.day.today).map(\.id), [starting.id])
        XCTAssertEqual(PromotionPresentation.groups(from: promotions, today: clock.day.today.rawValue, includeArchived: false).first?.representative.id, starting.id)
        XCTAssertEqual(PromotionPresentation.status(of: ending, today: clock.day.today.rawValue), .history)
        XCTAssertEqual(PromotionPresentation.status(of: starting, today: clock.day.today.rawValue), .active)
    }
}
