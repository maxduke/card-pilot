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
}
