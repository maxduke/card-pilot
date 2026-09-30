import XCTest
@testable import CardPilot

final class BillingRuleOverrideTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                           repaymentKind: .fixedDay, repaymentValue: 20)
    private let october = BillingRuleInput(effectiveCycleKey: 202610, statementDay: 20,
                                          repaymentKind: .fixedDay, repaymentValue: 20)

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
