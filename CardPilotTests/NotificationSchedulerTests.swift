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
    }
}
