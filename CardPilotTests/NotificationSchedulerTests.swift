import Foundation
import UserNotifications
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

    func testPlansOrderByFireDateAcrossBillingCycles() throws {
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
            lastScheduledDate: try! LocalDate(rawValue: 20260920).date(in: timeZone),
            firstOmittedDate: try! LocalDate(rawValue: 20260921).date(in: timeZone)
        )

        XCTAssertEqual(notificationWarningMessage(status: .denied, result: omitted, timeZone: timeZone), "通知权限已关闭，请前往系统设置开启。")
        XCTAssertEqual(notificationWarningMessage(status: .notDetermined, result: noOmissions, timeZone: timeZone), "尚未授权通知权限。")
        XCTAssertEqual(notificationWarningMessage(status: .authorized, result: noOmissions, timeZone: timeZone), "")
        XCTAssertTrue(notificationWarningMessage(status: .authorized, result: omitted, timeZone: timeZone).contains("另有 4 条"))
        XCTAssertTrue(notificationWarningMessage(status: .authorized, result: omitted, timeZone: timeZone).contains("2026-09-21"))
        XCTAssertFalse(notificationWarningMessage(status: .authorized, result: omitted, timeZone: timeZone).contains("安排至"))
    }

    func testTenAccountsHaveNoEarlierOmissionsThanTheScheduledWindow() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let cycles = try (0..<10).flatMap { index -> [BillingReminderCycle] in
            let accountID = UUID()
            return try (9...12).map { month in
                BillingReminderCycle(accountID: accountID, accountName: "账户 \(index)", cycle: BillingCycle(
                    cycleKey: 202600 + month,
                    statementDate: try LocalDate(year: 2026, month: month, day: 10 + index),
                    repaymentDate: try LocalDate(year: 2026, month: month, day: 20 + index),
                    status: .pending, repaidAt: nil
                ))
            }
        }
        let plans = try LocalNotificationScheduler.plans(
            cycles: cycles, statementOffsets: [7, 3, 1, 0], repaymentOffsets: [7, 3, 1, 0],
            reminderHour: 9, reminderMinute: 0, timeZone: utc,
            now: try LocalDate(rawValue: 20260905).date(in: utc)
        )
        let result = LocalNotificationScheduler.scheduleResult(for: plans)
        XCTAssertEqual(result.scheduledCount, 48)
        XCTAssertEqual(result.omittedCount, plans.count - 48)
        let lastScheduled = try XCTUnwrap(result.lastScheduledDate)
        let firstOmitted = try XCTUnwrap(result.firstOmittedDate)
        XCTAssertGreaterThanOrEqual(firstOmitted, lastScheduled)
        XCTAssertEqual(result.nextScheduledDate, plans.map(\.fireDate).min())
        XCTAssertTrue(plans.dropFirst(48).allSatisfy { $0.fireDate >= lastScheduled })
    }

    func testSimultaneousRemindersPrioritizeRepayment() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let cycle = BillingCycle(cycleKey: 202609, statementDate: try LocalDate(rawValue: 20260910), repaymentDate: try LocalDate(rawValue: 20260920), status: .pending, repaidAt: nil)
        let plans = try LocalNotificationScheduler.plans(
            cycles: [BillingReminderCycle(accountID: UUID(), accountName: "账户", cycle: cycle)],
            statementOffsets: [0], repaymentOffsets: [10], reminderHour: 9, reminderMinute: 0,
            timeZone: utc, now: try LocalDate(rawValue: 20260901).date(in: utc)
        )
        XCTAssertEqual(plans.map(\.event), [.repayment, .statement])
    }

    func testRebuildRemovesPaidRemindersAndPreservesUnownedRequests() async throws {
        let client = TestNotificationClient()
        let external = UNNotificationRequest(identifier: "unowned", content: UNMutableNotificationContent(), trigger: nil)
        client.requests[external.identifier] = external
        let scheduler = LocalNotificationScheduler(client: client)
        let utc = TimeZone(secondsFromGMT: 0)!
        let accountID = UUID()
        let pending = try reminderFixture(accountID: accountID, paid: false)
        _ = try await scheduler.rebuild(cycles: [pending], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: try LocalDate(rawValue: 20260901).date(in: utc))
        XCTAssertEqual(client.requests.count, 3)

        let paid = try reminderFixture(accountID: accountID, paid: true)
        _ = try await scheduler.rebuild(cycles: [paid], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: try LocalDate(rawValue: 20260901).date(in: utc))
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertNotNil(client.requests["unowned"])
        XCTAssertFalse(client.requests.keys.contains { $0.contains("repayment") })
        let request = try XCTUnwrap(client.requests.values.first { $0.identifier.hasPrefix("cardpilot.") })
        XCTAssertEqual(request.content.userInfo["accountID"] as? String, accountID.uuidString)
        XCTAssertTrue(request.content.body.contains("尾号 1234"))
    }

    func testNewerRebuildWaitsForInFlightAddAndWins() async throws {
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        let utc = TimeZone(secondsFromGMT: 0)!
        let accountID = UUID()
        let pending = try reminderFixture(accountID: accountID, paid: false)
        let paid = try reminderFixture(accountID: accountID, paid: true)
        let now = try LocalDate(rawValue: 20260901).date(in: utc)
        let addStarted = expectation(description: "Old add is suspended")
        client.pauseNextAdd = true
        client.onPausedAdd = { addStarted.fulfill() }
        let old = Task {
            try await scheduler.rebuild(cycles: [pending], statementOffsets: [], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: now)
        }
        await fulfillment(of: [addStarted], timeout: 2)

        let latestStarted = expectation(description: "New rebuild is enqueued")
        let latest = Task {
            latestStarted.fulfill()
            return try await scheduler.rebuild(cycles: [paid], statementOffsets: [], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: now)
        }
        await fulfillment(of: [latestStarted], timeout: 2)
        client.resumeAdd()
        _ = try? await old.value
        let result = try await latest.value
        XCTAssertEqual(result.scheduledCount, 0)
        XCTAssertTrue(client.requests.isEmpty, "A stale add must not restore the paid reminder")
    }

    func testAddFailureDoesNotEraseStillValidRequests() async throws {
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        let utc = TimeZone(secondsFromGMT: 0)!
        let cycle = try reminderFixture(accountID: UUID(), paid: false)
        let now = try LocalDate(rawValue: 20260901).date(in: utc)
        _ = try await scheduler.rebuild(cycles: [cycle], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: now)
        let existing = Set(client.requests.keys)
        client.failAdds = true
        do {
            _ = try await scheduler.rebuild(cycles: [cycle], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: now)
            XCTFail("Expected notification client error")
        } catch TestNotificationClient.Failure.addFailed {}
        XCTAssertEqual(Set(client.requests.keys), existing)
    }

    private func reminderFixture(accountID: UUID, paid: Bool) throws -> BillingReminderCycle {
        BillingReminderCycle(accountID: accountID, accountName: "招商银行 · 日常卡 · 尾号 1234", cycle: BillingCycle(
            cycleKey: 202609, statementDate: try LocalDate(rawValue: 20260910), repaymentDate: try LocalDate(rawValue: 20260920),
            status: paid ? .paid : .pending, repaidAt: paid ? Date() : nil
        ))
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

@MainActor
private final class TestNotificationClient: NotificationClient {
    enum Failure: Error { case addFailed }
    var requests: [String: UNNotificationRequest] = [:]
    var pauseNextAdd = false
    var failAdds = false
    var onPausedAdd: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func removeRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }
    func add(_ request: UNNotificationRequest) async throws {
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onPausedAdd?()
            }
        }
        if failAdds { throw Failure.addFailed }
        requests[request.identifier] = request
    }
    func resumeAdd() {
        continuation?.resume()
        continuation = nil
    }
}
