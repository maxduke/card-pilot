import XCTest
@testable import CardPilot

final class BillingRuleOverrideTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                           repaymentKind: .fixedDay, repaymentValue: 20)
    private let october = BillingRuleInput(effectiveCycleKey: 202610, statementDay: 20,
                                          repaymentKind: .fixedDay, repaymentValue: 20)

    func testConflictIdentifiesEarliestAffectedCycleRegardlessOfInsertionOrder() throws {
        let today = try LocalDate(rawValue: 20260930)
        let octoberDates = BillingCycleOverride(statementDate: nil,
            repaymentDate: try LocalDate(rawValue: 20261015), repaidAt: nil)
        let novemberDates = BillingCycleOverride(statementDate: nil,
            repaymentDate: try LocalDate(rawValue: 20261115), repaidAt: .now)
        for entries in [[(202611, novemberDates), (202610, octoberDates)],
                        [(202610, octoberDates), (202611, novemberDates)]] {
            XCTAssertEqual(try BillingCalculator.firstInvalidOverrideCycleKey(
                affectedBy: october, rules: [baseline, october], overrides: Dictionary(uniqueKeysWithValues: entries),
                today: today, timeZone: utc), 202610)
        }
    }

    func testConflictIdentificationAcceptsCorrectionAndStopsAtNextVersion() throws {
        let today = try LocalDate(rawValue: 20260930)
        let november = BillingRuleInput(effectiveCycleKey: 202611, statementDay: 5,
                                       repaymentKind: .fixedDay, repaymentValue: 20)
        let overrides = [
            202610: BillingCycleOverride(statementDate: nil,
                repaymentDate: try LocalDate(rawValue: 20261025), repaidAt: nil),
            202611: BillingCycleOverride(statementDate: nil,
                repaymentDate: try LocalDate(rawValue: 20261115), repaidAt: .now)
        ]
        XCTAssertEqual(try BillingCalculator.firstInvalidOverrideCycleKey(
            affectedBy: october, rules: [baseline, october], overrides: overrides,
            today: today, timeZone: utc), 202611)
        XCTAssertNil(try BillingCalculator.firstInvalidOverrideCycleKey(
            affectedBy: october, rules: [baseline, october, november], overrides: overrides,
            today: today, timeZone: utc))
        XCTAssertNil(try BillingCalculator.firstInvalidOverrideCycleKey(
            affectedBy: nil, rules: [baseline, october], overrides: overrides,
            today: today, timeZone: utc))
    }

    func testConflictIdentificationPreservesConfigurationErrors() throws {
        let dates = BillingCycleOverride(statementDate: nil,
            repaymentDate: try LocalDate(rawValue: 20261025), repaidAt: nil)
        XCTAssertThrowsError(try BillingCalculator.firstInvalidOverrideCycleKey(
            affectedBy: october, rules: [october], overrides: [202610: dates],
            today: LocalDate(rawValue: 20260930), timeZone: utc)) { error in
            XCTAssertEqual(error as? BillingCalculationError, .missingBaselineRule)
        }
    }

    func testRuleChangeRejectsAnUnchangedOverrideThatWouldHideTheBill() throws {
        let today = try LocalDate(rawValue: 20260930)
        let dates = BillingCycleOverride(statementDate: nil, repaymentDate: try LocalDate(rawValue: 20261015), repaidAt: nil)
        XCTAssertNoThrow(try BillingCalculator.calculate(accountStatus: .active, closedOn: nil,
            cycleKey: 202610, rules: [baseline], override: dates, today: today, timeZone: utc))
        XCTAssertThrowsError(try BillingCalculator.validateOverridesAffectedByRuleChange(
            october, rules: [baseline, october], overrides: [202610: dates], today: today, timeZone: utc
        )) { error in
            XCTAssertEqual(error as? BillingCalculationError, .invalidOverride)
        }
    }

    func testRuleChangeAcceptsAnOverrideCorrectedInTheSameSave() throws {
        let dates = BillingCycleOverride(statementDate: nil, repaymentDate: try LocalDate(rawValue: 20261025), repaidAt: nil)
        XCTAssertNoThrow(try BillingCalculator.validateOverridesAffectedByRuleChange(
            october, rules: [baseline, october], overrides: [202610: dates],
            today: LocalDate(rawValue: 20260930), timeZone: utc
        ))
    }

    func testValidationStopsAtTheNextScheduledVersion() throws {
        let november = BillingRuleInput(effectiveCycleKey: 202611, statementDay: 5,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let dates = BillingCycleOverride(statementDate: nil, repaymentDate: try LocalDate(rawValue: 20261115), repaidAt: nil)
        let today = try LocalDate(rawValue: 20260930)
        XCTAssertThrowsError(try BillingCalculator.validateOverridesAffectedByRuleChange(
            october, rules: [baseline, october], overrides: [202611: dates], today: today, timeZone: utc
        ))
        XCTAssertNoThrow(try BillingCalculator.validateOverridesAffectedByRuleChange(
            october, rules: [baseline, october, november], overrides: [202611: dates], today: today, timeZone: utc
        ))
    }

    func testClosureVisibilityDoesNotPreventPreservingFutureRecords() throws {
        let today = try LocalDate(rawValue: 20260930)
        let dates = BillingCycleOverride(statementDate: nil, repaymentDate: try LocalDate(rawValue: 20261025), repaidAt: nil)
        XCTAssertThrowsError(try BillingCalculator.calculate(accountStatus: .closed, closedOn: today,
            cycleKey: 202610, rules: [baseline, october], override: dates, today: today, timeZone: utc)) { error in
            XCTAssertEqual(error as? BillingCalculationError, .accountClosed)
        }
        XCTAssertNoThrow(try BillingCalculator.validateOverridesAffectedByRuleChange(
            nil, rules: [baseline, october], overrides: [202610: dates], today: today, timeZone: utc
        ))
        XCTAssertNoThrow(try BillingCalculator.validateOverridesAffectedByRuleChange(
            october, rules: [baseline, october], overrides: [202610: dates], today: today, timeZone: utc
        ))
    }
}
