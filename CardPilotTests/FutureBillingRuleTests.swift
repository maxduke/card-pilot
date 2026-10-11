import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class FutureBillingRuleTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let today = try! LocalDate(rawValue: 20260910)
    private let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 20,
                                           repaymentKind: .fixedDay, repaymentValue: 25)
    private let october = BillingRuleInput(effectiveCycleKey: 202610, statementDay: 5,
                                          repaymentKind: .fixedDay, repaymentValue: 25)
    private let december = BillingRuleInput(effectiveCycleKey: 202612, statementDay: 5,
                                           repaymentKind: .fixedDay, repaymentValue: 25)

    func testCancellationRejectsBaselinePastCurrentMissingAndDuplicateVersions() throws {
        for key: Int? in [nil, 202608, 202609] {
            XCTAssertThrowsError(try FutureBillingRuleCancellation.remainingRules(removing: key,
                rules: [baseline, october], overrides: [:], today: today, timeZone: utc)) {
                XCTAssertEqual($0 as? FutureBillingRuleCancellation.CancellationError, .alreadyEffective)
            }
        }
        XCTAssertThrowsError(try FutureBillingRuleCancellation.remainingRules(removing: 202611,
            rules: [baseline, october], overrides: [:], today: today, timeZone: utc)) {
            XCTAssertEqual($0 as? FutureBillingRuleCancellation.CancellationError, .missingRule)
        }
        XCTAssertThrowsError(try FutureBillingRuleCancellation.remainingRules(removing: 202610,
            rules: [baseline, october, october], overrides: [:], today: today, timeZone: utc)) {
            XCTAssertEqual($0 as? BillingCalculationError, .duplicateEffectiveRule)
        }
        XCTAssertThrowsError(try FutureBillingRuleCancellation.remainingRules(removing: 202610,
            rules: [october], overrides: [:], today: today, timeZone: utc)) {
            XCTAssertEqual($0 as? BillingCalculationError, .missingBaselineRule)
        }
    }

    func testMiddleCancellationUsesPreviousUntilNextAndRetainsHistoricalDates() throws {
        let past = BillingRuleInput(effectiveCycleKey: 202608, statementDay: 15,
                                    repaymentKind: .fixedDay, repaymentValue: 25)
        let input = [baseline, past, october, december]
        let remaining = try FutureBillingRuleCancellation.remainingRules(removing: 202610, rules: input,
            overrides: [:], today: today, timeZone: utc)
        XCTAssertEqual(remaining, [baseline, past, december])
        for key in [202607, 202608, 202609, 202612, 202701] {
            XCTAssertEqual(try BillingCalculator.calculate(accountStatus: .active, closedOn: nil, cycleKey: key,
                rules: input, today: today, timeZone: utc), try BillingCalculator.calculate(
                accountStatus: .active, closedOn: nil, cycleKey: key, rules: remaining, today: today, timeZone: utc))
        }
        XCTAssertEqual(BillingCalculator.applicableRule(from: remaining, forCycleKey: 202611), past)
        XCTAssertEqual(BillingCalculator.applicableRule(from: remaining, forCycleKey: 202612), december)
    }

    func testCancellationRejectsAffectedRepaymentOverrideAndStopsAtNextVersion() throws {
        let invalidAfterRemoval = BillingCycleOverride(statementDate: nil,
            repaymentDate: try LocalDate(rawValue: 20261110), repaidAt: nil)
        XCTAssertNoThrow(try BillingCalculator.calculate(accountStatus: .active, closedOn: nil, cycleKey: 202611,
            rules: [baseline, october, december], override: invalidAfterRemoval, today: today, timeZone: utc))
        XCTAssertThrowsError(try FutureBillingRuleCancellation.remainingRules(removing: 202610,
            rules: [baseline, october, december], overrides: [202611: invalidAfterRemoval], today: today, timeZone: utc)) {
            XCTAssertEqual($0 as? FutureBillingRuleCancellation.CancellationError, .invalidDates(202611))
        }
        let later = BillingCycleOverride(statementDate: nil,
            repaymentDate: try LocalDate(rawValue: 20261210), repaidAt: nil)
        XCTAssertNoThrow(try FutureBillingRuleCancellation.remainingRules(removing: 202610,
            rules: [baseline, october, december], overrides: [202612: later], today: today, timeZone: utc))
        let explicit = BillingCycleOverride(statementDate: try LocalDate(rawValue: 20261105),
            repaymentDate: try LocalDate(rawValue: 20261110), repaidAt: Date(timeIntervalSince1970: 1))
        XCTAssertNoThrow(try FutureBillingRuleCancellation.remainingRules(removing: 202610,
            rules: [baseline, october, december], overrides: [202611: explicit], today: today, timeZone: utc))
    }

    func testCancellationPersistsOnlySelectedRuleAndRetainsBackupFactsAndReminderIdentity() throws {
        let (container, account, selected) = try fixture()
        let selectedID = selected.id
        let before = try BackupRecords.capture(container.mainContext)
        let revision = UserDefaults.standard.integer(forKey: "cardPilot.notificationRevision")
        try FutureBillingRuleActions.cancel(ruleID: selectedID, account: account, context: container.mainContext,
                                            today: today, timeZone: utc)
        let after = try BackupRecords.capture(container.mainContext)
        var expected = before
        expected.billingRules.removeAll { $0.id == selectedID }
        XCTAssertEqual(after, expected)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cardPilot.notificationRevision"), revision &+ 1)
        let restored = try after.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), after)
        let target = BillingCycleTarget(accountID: account.id, cycleKey: 202611)
        let resolved = try BillingCycleActions.resolve(target, accounts: [account], today: today, timeZone: utc)
        XCTAssertEqual(resolved.1.statementDate.rawValue, 20261103)
        XCTAssertEqual(resolved.1.repaymentDate.rawValue, 20261110)
        XCTAssertNotNil(resolved.1.repaidAt)
    }

    func testFailedCancellationRestoresRelationsAndCanRetryWithoutChangingReminders() throws {
        let (container, account, selected) = try fixture()
        let selectedID = selected.id
        let before = try BackupRecords.capture(container.mainContext)
        let revision = UserDefaults.standard.integer(forKey: "cardPilot.notificationRevision")
        enum Failure: Error { case diskFull }
        XCTAssertThrowsError(try FutureBillingRuleActions.cancel(ruleID: selectedID, account: account,
            context: container.mainContext, today: today, timeZone: utc, persist: { _ in throw Failure.diskFull }))
        XCTAssertEqual(try BackupRecords.capture(container.mainContext), before)
        XCTAssertEqual(selected.account?.id, account.id)
        XCTAssertTrue(account.billingRuleVersions.contains { $0.id == selected.id })
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "cardPilot.notificationRevision"), revision)
        try FutureBillingRuleActions.cancel(ruleID: selectedID, account: account, context: container.mainContext,
                                            today: today, timeZone: utc)
        XCTAssertFalse(try container.mainContext.fetch(FetchDescriptor<BillingRuleVersion>()).contains { $0.id == selectedID })
    }

    func testCancellationRechecksCurrentMonthAndRejectsAnotherAccount() throws {
        let (container, account, selected) = try fixture()
        let before = try BackupRecords.capture(container.mainContext)
        XCTAssertThrowsError(try FutureBillingRuleActions.cancel(ruleID: selected.id, account: account,
            context: container.mainContext, today: LocalDate(rawValue: 20261001), timeZone: utc))
        XCTAssertEqual(try BackupRecords.capture(container.mainContext), before)
        let other = CreditCardAccount(bank: account.bank)
        container.mainContext.insert(other)
        container.mainContext.insert(BillingRuleVersion(account: other, statementDay: 1,
                                                        repaymentKind: .daysAfterStatement, repaymentValue: 20))
        try container.mainContext.save()
        XCTAssertThrowsError(try FutureBillingRuleActions.cancel(ruleID: selected.id, account: other,
            context: container.mainContext, today: today, timeZone: utc)) {
            XCTAssertEqual($0 as? FutureBillingRuleCancellation.CancellationError, .missingRule)
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<BillingRuleVersion>()).filter { $0.account?.id == account.id }.count,
                       before.billingRules.count)
    }

    private func fixture() throws -> (ModelContainer, CreditCardAccount, BillingRuleVersion) {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202601)
        container.mainContext.insert(bank)
        container.mainContext.insert(account)
        for input in [baseline, october, december] {
            container.mainContext.insert(BillingRuleVersion(account: account, effectiveCycleKey: input.effectiveCycleKey,
                statementDay: input.statementDay, repaymentKind: input.repaymentKind, repaymentValue: input.repaymentValue))
        }
        container.mainContext.insert(BillingCycleRecord(account: account, cycleKey: 202611,
            statementDateOverride: 20261103, repaymentDateOverride: 20261110, repaidAt: Date(timeIntervalSince1970: 1)))
        try container.mainContext.save()
        let selected = try XCTUnwrap(account.billingRuleVersions.first { $0.effectiveCycleKey == 202610 })
        return (container, account, selected)
    }
}
