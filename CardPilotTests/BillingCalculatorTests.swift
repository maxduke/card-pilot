import XCTest
@testable import CardPilot

final class BillingCalculatorTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testMonthEndClampingAndFixedRepaymentRollForward() throws {
        let cycle = try BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: 202502,
            rules: [
                BillingRuleInput(
                    effectiveCycleKey: nil,
                    statementDay: 31,
                    repaymentKind: .fixedDay,
                    repaymentValue: 28
                )
            ],
            today: try LocalDate(rawValue: 20250201),
            timeZone: utc
        )

        XCTAssertEqual(cycle.statementDate, try LocalDate(rawValue: 20250228))
        XCTAssertEqual(cycle.repaymentDate, try LocalDate(rawValue: 20250328))
    }

    func testRuleVersionAndStatementOverrideRecalculateRelativeRepayment() throws {
        let cycle = try BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: 202603,
            rules: [
                BillingRuleInput(effectiveCycleKey: nil, statementDay: 5, repaymentKind: .daysAfterStatement, repaymentValue: 20),
                BillingRuleInput(effectiveCycleKey: 202603, statementDay: 8, repaymentKind: .daysAfterStatement, repaymentValue: 10)
            ],
            override: BillingCycleOverride(
                statementDate: try LocalDate(rawValue: 20260309),
                repaymentDate: nil,
                repaidAt: nil
            ),
            today: try LocalDate(rawValue: 20260301),
            timeZone: utc
        )

        XCTAssertEqual(cycle.statementDate.rawValue, 20260309)
        XCTAssertEqual(cycle.repaymentDate.rawValue, 20260319)
    }

    func testApplicableRuleUsesLatestEffectiveVersionAndKeepsBaselineUnbounded() {
        let rules = [
            BillingRuleInput(effectiveCycleKey: 202609, statementDay: 9, repaymentKind: .fixedDay, repaymentValue: 20),
            BillingRuleInput(effectiveCycleKey: nil, statementDay: 5, repaymentKind: .fixedDay, repaymentValue: 15),
            BillingRuleInput(effectiveCycleKey: 202608, statementDay: 8, repaymentKind: .fixedDay, repaymentValue: 18)
        ]

        XCTAssertEqual(BillingCalculator.applicableRule(from: rules, forCycleKey: 202607)?.statementDay, 5)
        XCTAssertEqual(BillingCalculator.applicableRule(from: rules, forCycleKey: 202608)?.statementDay, 8)
        XCTAssertEqual(BillingCalculator.applicableRule(from: rules, forCycleKey: 202610)?.statementDay, 9)
    }

    func testDuplicateBaselineIsRejected() throws {
        XCTAssertThrowsError(
            try BillingCalculator.calculate(
                accountStatus: .active,
                closedOn: nil,
                cycleKey: 202601,
                rules: [
                    BillingRuleInput(effectiveCycleKey: nil, statementDay: 1, repaymentKind: .fixedDay, repaymentValue: 10),
                    BillingRuleInput(effectiveCycleKey: nil, statementDay: 2, repaymentKind: .fixedDay, repaymentValue: 10)
                ],
                today: try LocalDate(rawValue: 20260101),
                timeZone: utc
            )
        ) { error in
            XCTAssertEqual(error as? BillingCalculationError, .duplicateBaselineRule)
        }
    }

    func testFixedRepaymentMustBeStrictlyAfterStatement() throws {
        for (repaymentDay, expected) in [(20, 20260120), (15, 20260215), (10, 20260210)] {
            let cycle = try BillingCalculator.calculate(
                accountStatus: .active,
                closedOn: nil,
                cycleKey: 202601,
                rules: [BillingRuleInput(
                    effectiveCycleKey: nil,
                    statementDay: 15,
                    repaymentKind: .fixedDay,
                    repaymentValue: repaymentDay
                )],
                today: try LocalDate(rawValue: 20260101),
                timeZone: utc
            )
            XCTAssertEqual(cycle.repaymentDate.rawValue, expected)
        }
    }

    func testDaysAfterStatementCrossesLeapDayAndYear() throws {
        let leapCycle = try BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: 202402,
            rules: [BillingRuleInput(effectiveCycleKey: nil, statementDay: 28, repaymentKind: .daysAfterStatement, repaymentValue: 2)],
            today: try LocalDate(rawValue: 20240201),
            timeZone: utc
        )
        let yearCycle = try BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: 202412,
            rules: [BillingRuleInput(effectiveCycleKey: nil, statementDay: 31, repaymentKind: .daysAfterStatement, repaymentValue: 1)],
            today: try LocalDate(rawValue: 20241201),
            timeZone: utc
        )
        XCTAssertEqual(leapCycle.repaymentDate.rawValue, 20240301)
        XCTAssertEqual(yearCycle.repaymentDate.rawValue, 20250101)
    }

    func testRepaymentOverrideMustFollowStatementDate() throws {
        XCTAssertThrowsError(try BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: 202608,
            rules: [BillingRuleInput(
                effectiveCycleKey: nil,
                statementDay: 10,
                repaymentKind: .daysAfterStatement,
                repaymentValue: 20
            )],
            override: BillingCycleOverride(
                statementDate: try LocalDate(rawValue: 20260815),
                repaymentDate: try LocalDate(rawValue: 20260815),
                repaidAt: nil
            ),
            today: try LocalDate(rawValue: 20260801),
            timeZone: utc
        )) { error in
            XCTAssertEqual(error as? BillingCalculationError, .invalidOverride)
        }
    }
}
