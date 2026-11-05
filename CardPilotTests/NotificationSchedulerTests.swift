import Foundation
import UserNotifications
import XCTest
@testable import CardPilot

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    func testTestReminderSurvivesRebuildAndRepeatedTestsUseOneSlot() async throws {
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        try await scheduler.sendTestReminder()
        try await scheduler.sendTestReminder()
        XCTAssertEqual(client.requests.count, 1)
        let test = try XCTUnwrap(client.requests[LocalNotificationScheduler.testIdentifier])
        XCTAssertEqual((test.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 5)
        XCTAssertFalse((test.trigger as? UNTimeIntervalNotificationTrigger)?.repeats ?? true)
        XCTAssertTrue(test.content.userInfo.isEmpty)
        _ = try await scheduler.rebuild(cycles: [], statementOffsets: [], repaymentOffsets: [],
                                       reminderHour: 9, reminderMinute: 0, timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertNotNil(client.requests[LocalNotificationScheduler.testIdentifier])
        XCTAssertFalse(LocalNotificationScheduler.owns(LocalNotificationScheduler.testIdentifier))
    }

    func testTestReminderDeniedDoesNotScheduleAndRequestsPermissionIfUndetermined() async throws {
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        client.status = .denied
        do {
            try await scheduler.sendTestReminder()
            XCTFail("Denied notifications must not be scheduled")
        } catch { XCTAssertEqual(error as? LocalNotificationScheduler.SchedulingError, .permissionDenied) }
        XCTAssertTrue(client.requests.isEmpty)
        client.status = .notDetermined
        client.grantsPermission = false
        do {
            try await scheduler.sendTestReminder()
            XCTFail("Declined permission must not schedule")
        } catch { XCTAssertEqual(error as? LocalNotificationScheduler.SchedulingError, .permissionDenied) }
        XCTAssertTrue(client.requests.isEmpty)
        client.grantsPermission = true
        try await scheduler.sendTestReminder()
        XCTAssertEqual(client.authorizationRequests, 2)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testTestReminderReportsAddFailure() async {
        let client = TestNotificationClient()
        client.failAdds = true
        do {
            try await LocalNotificationScheduler(client: client).sendTestReminder()
            XCTFail("Failed add must be reported")
        } catch { XCTAssertTrue(client.requests.isEmpty) }
    }

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
        XCTAssertNotEqual(plans[0].target, plans[1].target)
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

        let expected = [202609, 202608].map {
            NotificationTarget.billing(BillingCycleTarget(accountID: accountID, cycleKey: $0))
        }
        XCTAssertEqual(plans.map(\.target), expected)
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
            let accountPlans = first48.filter { $0.target == .billing(BillingCycleTarget(accountID: accountID, cycleKey: cycle.cycleKey)) }
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

    func testAddFailureKeepsPreviousRequestsUntilRetry() async throws {
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        let utc = TimeZone(secondsFromGMT: 0)!
        let cycle = try reminderFixture(accountID: UUID(), paid: false)
        let now = try LocalDate(rawValue: 20260901).date(in: utc)
        _ = try await scheduler.rebuild(cycles: [cycle], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0, timeZone: utc, now: now)
        let existing = Set(client.requests.keys)
        let previousHours = client.requests.mapValues {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour
        }
        client.failAdds = true
        do {
            _ = try await scheduler.rebuild(cycles: [cycle], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 10, reminderMinute: 0, timeZone: utc, now: now)
            XCTFail("Expected notification client error")
        } catch TestNotificationClient.Failure.addFailed {}
        XCTAssertEqual(Set(client.requests.keys), existing)
        XCTAssertEqual(client.requests.mapValues {
            ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour
        }, previousHours)
    }

    func testEnrollmentPlansOnlyIncludeOpenUnregisteredDeadlinesAndDeduplicateOffsets() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let eligible = enrollmentFixture()
        let enrolled = enrollmentFixture()
        enrolled.enrollmentStatus = .enrolled
        let notRequired = enrollmentFixture()
        notRequired.enrollmentStatus = .notRequired
        notRequired.enrollmentDeadline = nil
        let archived = enrollmentFixture()
        archived.archivedAt = .now
        let expired = enrollmentFixture()
        expired.enrollmentDeadline = 20260831
        let ended = enrollmentFixture()
        ended.startOn = 20260801
        ended.endOn = 20260831
        ended.enrollmentDeadline = 20260830
        let noDeadline = enrollmentFixture()
        noDeadline.enrollmentDeadline = nil
        let plans = try LocalNotificationScheduler.plans(
            cycles: [], statementOffsets: [], repaymentOffsets: [], reminderHour: 9, reminderMinute: 30,
            timeZone: utc, now: try LocalDate(rawValue: 20260901).date(in: utc),
            promotions: [eligible, enrolled, notRequired, archived, expired, ended, noDeadline],
            enrollmentOffsets: [1, 1, 0, -1, 366]
        )
        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 2)
        XCTAssertTrue(plans.allSatisfy { $0.target == .promotion(eligible.id) && $0.event == .enrollment })
        XCTAssertEqual(plans.map { LocalDate(date: $0.fireDate, timeZone: utc).rawValue }, [20260904, 20260905])
        XCTAssertTrue(plans[0].body.contains(eligible.title))
        XCTAssertTrue(plans[1].body.contains("今天报名截止"))
    }

    func testEnrollmentPlansUseFixedTimeZoneAndSkipElapsedTimes() throws {
        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let promotion = enrollmentFixture()
        let midnight = try LocalDate(rawValue: 20260905).date(in: timeZone)
        func plans(at now: Date) throws -> [LocalNotificationScheduler.ReminderPlan] {
            try LocalNotificationScheduler.plans(
                cycles: [], statementOffsets: [], repaymentOffsets: [], reminderHour: 9, reminderMinute: 30,
                timeZone: timeZone, now: now, promotions: [promotion], enrollmentOffsets: [1, 0]
            )
        }
        let before = try plans(at: midnight.addingTimeInterval(9 * 3600))
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before.first?.fireDate, midnight.addingTimeInterval(9.5 * 3600))
        XCTAssertTrue(try plans(at: midnight.addingTimeInterval(9.5 * 3600)).isEmpty)
        XCTAssertTrue(try plans(at: midnight.addingTimeInterval(10 * 3600)).isEmpty)
    }

    func testEnrollmentAndBillingShareOneChronologicalLimitAndKeepRepaymentPriority() throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let cycle = BillingCycle(cycleKey: 202609, statementDate: try LocalDate(rawValue: 20260905),
            repaymentDate: try LocalDate(rawValue: 20260905), status: .pending, repaidAt: nil)
        let plans = try LocalNotificationScheduler.plans(
            cycles: [.init(accountID: UUID(), accountName: "账户", cycle: cycle)],
            statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0,
            timeZone: utc, now: try LocalDate(rawValue: 20260901).date(in: utc),
            promotions: (0..<50).map { _ in enrollmentFixture() }, enrollmentOffsets: [0]
        )
        XCTAssertEqual(plans.count, 52)
        XCTAssertEqual(plans.first?.event, .repayment)
        XCTAssertEqual(plans.last?.event, .statement)
        XCTAssertTrue(plans.dropFirst().dropLast().allSatisfy { $0.event == .enrollment })
        let result = LocalNotificationScheduler.scheduleResult(for: plans)
        XCTAssertEqual(result.scheduledCount, 48)
        XCTAssertEqual(result.omittedCount, 4)
        XCTAssertEqual(result.firstOmittedDate, plans[48].fireDate)
    }

    func testEnrollmentRebuildUpdatesDeadlineAndRemovesCompletedArchivedDeletedOrDisabledReminders() async throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let now = try LocalDate(rawValue: 20260901).date(in: utc)
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        let promotion = enrollmentFixture()
        let billing = try reminderFixture(accountID: UUID(), paid: false)
        func rebuild(promotions: [Promotion], offsets: [Int] = [0]) async throws {
            _ = try await scheduler.rebuild(
                cycles: [billing], statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0,
                timeZone: utc, now: now, promotions: promotions, enrollmentOffsets: offsets
            )
        }
        try await rebuild(promotions: [promotion])
        let request = try XCTUnwrap(client.requests.values.first { $0.content.userInfo["promotionID"] != nil })
        XCTAssertEqual(NotificationTarget(userInfo: request.content.userInfo), .promotion(promotion.id))
        XCTAssertEqual(client.requests.count, 3)
        promotion.enrollmentDeadline = 20260906
        promotion.title = "更名后的活动"
        try await rebuild(promotions: [promotion])
        let updated = try XCTUnwrap(client.requests[request.identifier])
        XCTAssertEqual((updated.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day, 6)
        XCTAssertTrue(updated.content.body.contains("更名后的活动"))
        for change in 0..<5 {
            switch change {
            case 0: promotion.enrollmentStatus = .enrolled
            case 1: promotion.archivedAt = .now
            case 2: promotion.enrollmentDeadline = nil
            default: break
            }
            try await rebuild(promotions: change == 3 ? [] : [promotion], offsets: change == 4 ? [] : [0])
            XCTAssertNil(client.requests[request.identifier])
            XCTAssertEqual(client.requests.count, 2, "Billing reminders must survive enrollment changes")
            promotion.enrollmentStatus = .notEnrolled
            promotion.archivedAt = nil
            promotion.enrollmentDeadline = 20260906
            try await rebuild(promotions: [promotion])
            XCTAssertNotNil(client.requests[request.identifier])
        }
    }

    func testEnrollmentCompletionWinsOverAnInFlightNotificationAdd() async throws {
        let utc = TimeZone(secondsFromGMT: 0)!
        let now = try LocalDate(rawValue: 20260901).date(in: utc)
        let client = TestNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        let promotion = enrollmentFixture()
        let addStarted = expectation(description: "Enrollment add is suspended")
        client.pauseNextAdd = true
        client.onPausedAdd = { addStarted.fulfill() }
        let old = Task {
            try await scheduler.rebuild(
                cycles: [], statementOffsets: [], repaymentOffsets: [], reminderHour: 9, reminderMinute: 0,
                timeZone: utc, now: now, promotions: [promotion], enrollmentOffsets: [0]
            )
        }
        await fulfillment(of: [addStarted], timeout: 2)
        promotion.enrollmentStatus = .enrolled
        let latestStarted = expectation(description: "Completed enrollment rebuild is enqueued")
        let latest = Task {
            latestStarted.fulfill()
            return try await scheduler.rebuild(
                cycles: [], statementOffsets: [], repaymentOffsets: [], reminderHour: 9, reminderMinute: 0,
                timeZone: utc, now: now, promotions: [promotion], enrollmentOffsets: [0]
            )
        }
        await fulfillment(of: [latestStarted], timeout: 2)
        client.resumeAdd()
        _ = try? await old.value
        let result = try await latest.value
        XCTAssertEqual(result.scheduledCount, 0)
        XCTAssertTrue(client.requests.isEmpty, "A late add must not restore a completed enrollment reminder")
    }

    private func enrollmentFixture() -> Promotion {
        Promotion(title: "待报名活动", startOn: 20260910, endOn: 20260930,
                  enrollmentStatus: .notEnrolled, enrollmentDeadline: 20260905, progressCurrencyCode: "CNY")
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

    var status: UNAuthorizationStatus = .authorized
    var grantsPermission = true
    var authorizationRequests = 0
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        return grantsPermission
    }
    func authorizationStatus() async -> UNAuthorizationStatus { status }
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
