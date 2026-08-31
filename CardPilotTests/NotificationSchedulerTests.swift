import XCTest
@testable import CardPilot

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    func testPlansAreUniquePerAccountAndOffsetsAreDeduplicated() throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let cycle = BillingCycle(
            cycleKey: 202609,
            statementDate: try LocalDate(rawValue: 20260905),
            repaymentDate: try LocalDate(rawValue: 20260925),
            status: .pending,
            repaidAt: nil
        )
        let plans = try LocalNotificationScheduler.plans(
            cycles: [
                BillingReminderCycle(accountID: UUID(), accountName: "账户一", cycle: cycle),
                BillingReminderCycle(accountID: UUID(), accountName: "账户二", cycle: cycle)
            ],
            statementOffsets: [1, 1],
            repaymentOffsets: [0],
            reminderHour: 9,
            reminderMinute: 0,
            timeZone: timeZone,
            now: try LocalDate(rawValue: 20260901).date(in: timeZone)
        )

        XCTAssertEqual(plans.count, 4)
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 4)
        XCTAssertTrue(plans.allSatisfy { $0.identifier.hasPrefix(LocalNotificationScheduler.identifierPrefix) })
        XCTAssertNotEqual(plans[0].accountID, plans[1].accountID)
    }

    func testEachAccountOrdersPlansByFireDateBeforeRoundRobin() throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let accountID = UUID()
        let distantCycle = BillingCycle(
            cycleKey: 202608,
            statementDate: try LocalDate(rawValue: 20260805),
            repaymentDate: try LocalDate(rawValue: 20261001),
            status: .pending,
            repaidAt: nil
        )
        let soonerCycle = BillingCycle(
            cycleKey: 202609,
            statementDate: try LocalDate(rawValue: 20260905),
            repaymentDate: try LocalDate(rawValue: 20260920),
            status: .pending,
            repaidAt: nil
        )

        let plans = try LocalNotificationScheduler.plans(
            cycles: [
                BillingReminderCycle(accountID: accountID, accountName: "账户", cycle: distantCycle),
                BillingReminderCycle(accountID: accountID, accountName: "账户", cycle: soonerCycle)
            ],
            statementOffsets: [],
            repaymentOffsets: [0],
            reminderHour: 9,
            reminderMinute: 0,
            timeZone: timeZone,
            now: try LocalDate(rawValue: 20260906).date(in: timeZone)
        )

        XCTAssertEqual(plans.map(\.cycleKey), [202609, 202608])
    }

    func testReminderCycleOffsetsLookBackForLongRelativeRepaymentRules() {
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 0)), Array(-1...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 28)), Array(-1...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 29)), Array(-2...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 90)), Array(-4...3))
    }
}
