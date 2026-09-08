import SwiftData
import UserNotifications
import XCTest
@testable import CardPilot

@MainActor
final class NotificationBillingTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private var today: LocalDate { try! LocalDate(rawValue: 20260901) }

    func testNotificationPayloadAcceptsExistingFormatAndRejectsInvalidTarget() {
        let id = UUID()
        XCTAssertEqual(BillingCycleTarget(userInfo: ["accountID": id.uuidString, "cycleKey": 202609]),
                       BillingCycleTarget(accountID: id, cycleKey: 202609))
        for payload: [AnyHashable: Any] in [
            [:], ["accountID": "missing", "cycleKey": 202609],
            ["accountID": id.uuidString, "cycleKey": 202613],
            ["accountID": id.uuidString, "cycleKey": "202609"]
        ] {
            XCTAssertNil(BillingCycleTarget(userInfo: payload))
        }
    }

    func testColdLaunchAndBackgroundKeepTargetUntilActiveAndAuthenticated() async {
        let router = NotificationRouter()
        let target = BillingCycleTarget(accountID: UUID(), cycleKey: 202609)
        var succeeds = false
        let lock = AppLockController(enabled: true, authenticationAvailable: { true },
                                     authenticateDeviceOwner: { succeeds })
        router.receive(target) // Response can arrive before RootView exists.
        XCTAssertNil(router.takeTarget(isActive: false, isLocked: lock.isLocked, isBusy: false))
        _ = await lock.unlock()
        XCTAssertNil(router.takeTarget(isActive: true, isLocked: lock.isLocked, isBusy: false))
        XCTAssertEqual(router.pendingTarget, target)
        succeeds = true
        _ = await lock.unlock()
        XCTAssertEqual(router.takeTarget(isActive: true, isLocked: lock.isLocked, isBusy: false), target)
        XCTAssertNil(router.pendingTarget)
        lock.applicationDidEnterBackground()
        router.receive(target)
        XCTAssertNil(router.takeTarget(isActive: false, isLocked: lock.isLocked, isBusy: false))
        _ = await lock.unlock()
        XCTAssertEqual(router.takeTarget(isActive: true, isLocked: lock.isLocked, isBusy: false), target)
    }

    func testColdLaunchSourcesCoalesceButLaterNotificationClicksStillOpen() {
        let target = BillingCycleTarget(accountID: UUID(), cycleKey: 202609)
        for firstSource: NotificationRouter.ResponseSource in [.sceneConnection, .notificationCenter] {
            let router = NotificationRouter()
            let secondSource: NotificationRouter.ResponseSource = firstSource == .sceneConnection ? .notificationCenter : .sceneConnection
            let date = Date(timeIntervalSince1970: 1_780_000_000)
            router.receive(target, requestID: "reminder", deliveredAt: date, source: firstSource)
            XCTAssertEqual(router.takeTarget(isActive: true, isLocked: false, isBusy: false), target)
            router.receive(target, requestID: "reminder", deliveredAt: date, source: secondSource)
            XCTAssertNil(router.pendingTarget)
            router.receive(target, requestID: "reminder", deliveredAt: date, source: .notificationCenter)
            XCTAssertEqual(router.takeTarget(isActive: true, isLocked: false, isBusy: false), target)
            router.receive(target, requestID: "reminder", deliveredAt: date.addingTimeInterval(60), source: .notificationCenter)
            XCTAssertEqual(router.pendingTarget, target)
        }
    }

    func testNestedPresentationsAndRestoreDeferLatestNotificationWithoutLosingIt() {
        let router = NotificationRouter()
        let editor = UUID(), picker = UUID()
        let first = BillingCycleTarget(accountID: UUID(), cycleKey: 202609)
        let last = BillingCycleTarget(accountID: UUID(), cycleKey: 202610)
        router.presentationOpened(editor)
        router.presentationOpened(editor) // Reappearing content is idempotent.
        router.presentationOpened(picker)
        router.receive(first)
        router.receive(last)
        XCTAssertNil(router.takeTarget(isActive: true, isLocked: false, isBusy: false))
        router.presentationClosed(picker)
        XCTAssertNil(router.takeTarget(isActive: true, isLocked: false, isBusy: false))
        router.presentationClosed(editor)
        XCTAssertNil(router.takeTarget(isActive: true, isLocked: false, isBusy: true))
        XCTAssertEqual(router.takeTarget(isActive: true, isLocked: false, isBusy: false), last)
        XCTAssertNil(router.takeTarget(isActive: true, isLocked: false, isBusy: false))
    }

    func testResolveUsesExactAccountAndCycleIncludingPaidHistory() throws {
        let container = try fixture()
        let accounts = try container.mainContext.fetch(FetchDescriptor<CreditCardAccount>())
        let account = try XCTUnwrap(accounts.first)
        let record = BillingCycleRecord(account: account, cycleKey: 202608, repaidAt: .now)
        container.mainContext.insert(record)
        try container.mainContext.save()
        let target = BillingCycleTarget(accountID: account.id, cycleKey: 202608)
        let resolved = try BillingCycleActions.resolve(target, accounts: accounts, today: today, timeZone: utc)
        XCTAssertEqual(resolved.0.id, account.id)
        XCTAssertEqual(resolved.1.cycleKey, 202608)
        XCTAssertEqual(resolved.1.status, .paid)
        XCTAssertThrowsError(try BillingCycleActions.resolve(target, accounts: [], today: today))
        XCTAssertThrowsError(try BillingCycleActions.resolve(.init(accountID: account.id, cycleKey: 202607),
                                                              accounts: accounts, today: today))
        account.status = .closed
        account.closedOn = 20260910
        try container.mainContext.save()
        XCTAssertThrowsError(try BillingCycleActions.resolve(.init(accountID: account.id, cycleKey: 202610),
                                                              accounts: accounts, today: today))
    }

    func testRepaymentUndoPreservesOverridesAndNeverCreatesDuplicateRecords() throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        try BillingCycleActions.save(.dates(statement: 20260908, repayment: 20261002), account: account,
                                     cycleKey: 202609, context: context, today: today, timeZone: utc)
        for _ in 0..<2 {
            try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                         context: context, today: today, timeZone: utc)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 1)
        try BillingCycleActions.save(.repayment(nil), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        let reader = ModelContext(container)
        let record = try XCTUnwrap(reader.fetch(FetchDescriptor<BillingCycleRecord>()).first)
        XCTAssertNil(record.repaidAt)
        XCTAssertEqual(record.statementDateOverride, 20260908)
        XCTAssertEqual(record.repaymentDateOverride, 20261002)
        XCTAssertEqual(record.account?.id, account.id)
    }

    func testUndoWithoutOverridesRemovesSparseRecordAndRepaidCanBeSavedAgain() throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        try BillingCycleActions.save(.repayment(nil), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 0)
        XCTAssertTrue(account.billingCycles.isEmpty)
        try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 1)
    }

    func testDateAdjustmentRecalculatesRepaymentAndPreservesPaidStatusAndRules() throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        let completed = Date(timeIntervalSince1970: 1_780_000_000)
        try BillingCycleActions.save(.repayment(completed), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        try BillingCycleActions.save(.dates(statement: 20260930, repayment: nil), account: account,
                                     cycleKey: 202609, context: context, today: today, timeZone: utc)
        let target = BillingCycleTarget(accountID: account.id, cycleKey: 202609)
        let result = try BillingCycleActions.resolve(target, accounts: [account], today: today, timeZone: utc).1
        XCTAssertEqual(result.repaymentDate.rawValue, 20261020)
        XCTAssertEqual(result.repaidAt, completed)
        XCTAssertEqual(account.billingRuleVersions.count, 1)
        XCTAssertEqual(account.billingRuleVersions.first?.statementDay, 5)
        try BillingCycleActions.save(.dates(statement: nil, repayment: nil), account: account,
                                     cycleKey: 202609, context: context, today: today, timeZone: utc)
        XCTAssertEqual(try BillingCycleActions.resolve(target, accounts: [account], today: today, timeZone: utc).1.repaymentDate.rawValue, 20260925)
        XCTAssertEqual(account.billingCycles.first?.repaidAt, completed)
    }

    func testInvalidDatesDoNotMutateNewOrExistingRecord() throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        XCTAssertThrowsError(try BillingCycleActions.save(.dates(statement: 20260910, repayment: 20260909),
            account: account, cycleKey: 202609, context: context, today: today, timeZone: utc))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 0)
        XCTAssertTrue(account.billingCycles.isEmpty)
        try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        let completed = account.billingCycles.first?.repaidAt
        XCTAssertThrowsError(try BillingCycleActions.save(.dates(statement: 20260910, repayment: 20260910),
            account: account, cycleKey: 202609, context: context, today: today, timeZone: utc))
        let reader = ModelContext(container)
        let record = try XCTUnwrap(reader.fetch(FetchDescriptor<BillingCycleRecord>()).first)
        XCTAssertEqual(record.repaidAt, completed)
        XCTAssertNil(record.statementDateOverride)
        XCTAssertNil(record.repaymentDateOverride)
    }

    func testPersistenceFailureRestoresRelationshipAndAllowsRetry() throws {
        enum Failure: Error { case diskFull }
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        let defaults = UserDefaults.standard
        let revision = defaults.integer(forKey: "cardPilot.notificationRevision")
        XCTAssertThrowsError(try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
            context: context, today: today, timeZone: utc, persist: { _ in throw Failure.diskFull }))
        XCTAssertTrue(account.billingCycles.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 0)
        XCTAssertEqual(defaults.integer(forKey: "cardPilot.notificationRevision"), revision)
        try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        let completed = try XCTUnwrap(account.billingCycles.first?.repaidAt)
        XCTAssertThrowsError(try BillingCycleActions.save(.dates(statement: 20260908, repayment: nil), account: account,
            cycleKey: 202609, context: context, today: today, timeZone: utc, persist: { _ in throw Failure.diskFull }))
        XCTAssertEqual(account.billingCycles.first?.repaidAt, completed)
        XCTAssertNil(account.billingCycles.first?.statementDateOverride)
        // Also cover a failed sparse-record deletion, then an ordinary retry.
        XCTAssertThrowsError(try BillingCycleActions.save(.repayment(nil), account: account, cycleKey: 202609,
            context: context, today: today, timeZone: utc, persist: { _ in throw Failure.diskFull }))
        XCTAssertEqual(account.billingCycles.count, 1)
        XCTAssertEqual(account.billingCycles.first?.repaidAt, completed)
        let reader = ModelContext(container)
        XCTAssertEqual(try reader.fetch(FetchDescriptor<BillingCycleRecord>()).first?.repaidAt, completed)
        try BillingCycleActions.save(.repayment(nil), account: account, cycleKey: 202609,
                                     context: context, today: today, timeZone: utc)
        XCTAssertTrue(account.billingCycles.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BillingCycleRecord>()), 0)
    }

    func testDuplicateCycleRejectedBeforeMutation() throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        context.insert(BillingCycleRecord(account: account, cycleKey: 202609, statementDateOverride: 20260906))
        context.insert(BillingCycleRecord(account: account, cycleKey: 202609, statementDateOverride: 20260907))
        try context.save()
        XCTAssertThrowsError(try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: 202609,
                                                        context: context, today: today, timeZone: utc))
        XCTAssertTrue(account.billingCycles.allSatisfy { $0.repaidAt == nil })
    }

    func testSavedOperationsRebuildTheExactNotificationTargetAndDates() async throws {
        let container = try fixture()
        let context = container.mainContext
        let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>()).first)
        let target = BillingCycleTarget(accountID: account.id, cycleKey: 202609)
        let client = BillingFlowNotificationClient()
        let scheduler = LocalNotificationScheduler(client: client)
        func rebuild() async throws {
            let cycle = try BillingCycleActions.resolve(target, accounts: [account], today: today, timeZone: utc).1
            _ = try await scheduler.rebuild(cycles: [.init(accountID: account.id, accountName: "测试账户", cycle: cycle)],
                statementOffsets: [0], repaymentOffsets: [0], reminderHour: 9, reminderMinute: 0,
                timeZone: utc, now: today.date(in: utc))
        }
        try await rebuild()
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests.values.allSatisfy { BillingCycleTarget(userInfo: $0.content.userInfo) == target })
        try BillingCycleActions.save(.repayment(.now), account: account, cycleKey: target.cycleKey,
                                     context: context, today: today, timeZone: utc)
        try await rebuild()
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.requests.keys.allSatisfy { $0.contains(".statement.") })
        try BillingCycleActions.save(.repayment(nil), account: account, cycleKey: target.cycleKey,
                                     context: context, today: today, timeZone: utc)
        try BillingCycleActions.save(.dates(statement: 20260930, repayment: nil), account: account,
                                     cycleKey: target.cycleKey, context: context, today: today, timeZone: utc)
        try await rebuild()
        XCTAssertEqual(client.requests.count, 2)
        let repayment = try XCTUnwrap(client.requests.values.first { $0.identifier.contains(".repayment.") })
        let components = try XCTUnwrap((repayment.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertEqual(components.month, 10)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(BillingCycleTarget(userInfo: repayment.content.userInfo)?.cycleKey, 202609)
    }

    private func fixture() throws -> ModelContainer {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let account = CreditCardAccount(bank: Bank(name: "测试银行"), trackingStartCycleKey: 202609)
        container.mainContext.insert(account)
        container.mainContext.insert(BillingRuleVersion(account: account, statementDay: 5,
                                                       repaymentKind: .daysAfterStatement, repaymentValue: 20))
        try container.mainContext.save()
        return container
    }
}

@MainActor
private final class BillingFlowNotificationClient: NotificationClient {
    var requests: [String: UNNotificationRequest] = [:]
    func requestAuthorization() async throws -> Bool { true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func pendingRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func removeRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { requests.removeValue(forKey: id) }
    }
    func add(_ request: UNNotificationRequest) async throws { requests[request.identifier] = request }
}
