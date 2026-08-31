import Foundation
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

    func testPaidCycleKeepsStatementReminderAndDropsRepaymentReminder() throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let cycle = BillingCycle(
            cycleKey: 202609,
            statementDate: try LocalDate(rawValue: 20260905),
            repaymentDate: try LocalDate(rawValue: 20260925),
            status: .paid,
            repaidAt: Date()
        )

        let plans = try LocalNotificationScheduler.plans(
            cycles: [BillingReminderCycle(accountID: UUID(), accountName: "账户", cycle: cycle)],
            statementOffsets: [0],
            repaymentOffsets: [0],
            reminderHour: 9,
            reminderMinute: 0,
            timeZone: timeZone,
            now: try LocalDate(rawValue: 20260901).date(in: timeZone)
        )

        XCTAssertEqual(plans.map(\.event), [.statement])
    }

    func testPriorityPlansKeepBothEventsForEachAccountBeforeTheLimit() throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let cycle = BillingCycle(
            cycleKey: 202609,
            statementDate: try LocalDate(rawValue: 20260920),
            repaymentDate: try LocalDate(rawValue: 20260925),
            status: .pending,
            repaidAt: nil
        )
        let accountIDs = (1...13).map { index in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        }
        let plans = try LocalNotificationScheduler.plans(
            cycles: accountIDs.map { id in
                BillingReminderCycle(accountID: id, accountName: "账户", cycle: cycle)
            },
            statementOffsets: [0, 1],
            repaymentOffsets: [0, 1],
            reminderHour: 9,
            reminderMinute: 0,
            timeZone: timeZone,
            now: try LocalDate(rawValue: 20260901).date(in: timeZone)
        )

        let first48 = plans.prefix(LocalNotificationScheduler.requestLimit)
        for accountID in accountIDs {
            let accountPlans = first48.filter { $0.accountID == accountID }
            XCTAssertTrue(accountPlans.contains { $0.event == .statement }, "缺少账单提醒：\(accountID)")
            XCTAssertTrue(accountPlans.contains { $0.event == .repayment }, "缺少还款提醒：\(accountID)")
        }
        XCTAssertEqual(plans.count, 52)
    }

    func testNotificationWarningReflectsAuthorizationStatus() {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let noOmissions = NotificationScheduleResult(scheduledCount: 4, omittedCount: 0, lastScheduledDate: nil)
        let omitted = NotificationScheduleResult(
            scheduledCount: 48,
            omittedCount: 4,
            lastScheduledDate: try! LocalDate(rawValue: 20260920).date(in: timeZone)
        )

        XCTAssertEqual(notificationWarningMessage(status: .denied, result: omitted, timeZone: timeZone), "通知权限已关闭，请前往系统设置开启。")
        XCTAssertEqual(notificationWarningMessage(status: .notDetermined, result: noOmissions, timeZone: timeZone), "尚未授权通知权限。")
        XCTAssertEqual(notificationWarningMessage(status: .authorized, result: noOmissions, timeZone: timeZone), "")
        XCTAssertTrue(notificationWarningMessage(status: .authorized, result: omitted, timeZone: timeZone).contains("另有 4 条"))
    }

    func testReminderCycleOffsetsLookBackForLongRelativeRepaymentRules() {
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 0)), Array(-1...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 28)), Array(-1...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 29)), Array(-2...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 90)), Array(-4...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 0, maxReminderOffset: 29)), Array(-1...3))
        XCTAssertEqual(Array(RootView.reminderCycleOffsets(maxDaysAfterStatement: 0, maxReminderOffset: 90)), Array(-1...4))
    }

    func testReminderCycleKeysExcludeGeneratedHistoryButKeepSavedHistory() {
        XCTAssertEqual(
            RootView.reminderCycleKeys(
                generated: [202607, 202608, 202609],
                savedUnpaid: [202606],
                trackingStartCycleKey: 202608
            ),
            Set([202606, 202608, 202609])
        )
    }
}
