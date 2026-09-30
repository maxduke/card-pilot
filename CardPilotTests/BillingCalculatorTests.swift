import XCTest
@testable import CardPilot

final class BillingCalculatorTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testSparseRecordKeepsPreTrackingCycleIdentityAfterUndo() throws {
        let empty = BillingCycleOverride(statementDate: nil, repaymentDate: nil, repaidAt: nil)
        XCTAssertTrue(empty.requiresRecord(cycleKey: 202608, trackingStartCycleKey: 202609))
        XCTAssertFalse(empty.requiresRecord(cycleKey: 202609, trackingStartCycleKey: 202609))
        XCTAssertFalse(empty.requiresRecord(cycleKey: 202610, trackingStartCycleKey: 202609))
        let overridden = BillingCycleOverride(statementDate: try LocalDate(rawValue: 20260905),
                                             repaymentDate: nil, repaidAt: nil)
        XCTAssertTrue(overridden.requiresRecord(cycleKey: 202609, trackingStartCycleKey: 202609))
        let paid = BillingCycleOverride(statementDate: nil, repaymentDate: nil, repaidAt: .now)
        XCTAssertTrue(paid.requiresRecord(cycleKey: 202609, trackingStartCycleKey: 202609))
    }

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

    func testInitialCycleIncludesPreviousMonthUntilItsRepaymentDate() throws {
        let rule = BillingRuleInput(effectiveCycleKey: nil, statementDay: 20,
                                    repaymentKind: .fixedDay, repaymentValue: 8)
        for day in [20260905, 20260908] {
            let cycle = try BillingCalculator.initialCycle(rule: rule, today: LocalDate(rawValue: day), timeZone: utc)
            XCTAssertEqual(cycle.cycleKey, 202608)
            XCTAssertEqual(cycle.statementDate.rawValue, 20260820)
            XCTAssertEqual(cycle.repaymentDate.rawValue, 20260908)
        }
        let afterDue = try BillingCalculator.initialCycle(rule: rule, today: LocalDate(rawValue: 20260909), timeZone: utc)
        XCTAssertEqual(afterDue.cycleKey, 202609)
        XCTAssertEqual(afterDue.repaymentDate.rawValue, 20261008)
    }

    func testInitialCycleKeepsCurrentMonthWhenNoPreviousBillIsDue() throws {
        let cycle = try BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                   repaymentKind: .fixedDay, repaymentValue: 20),
            today: LocalDate(rawValue: 20260910), timeZone: utc
        )
        XCTAssertEqual(cycle.cycleKey, 202609)
    }

    func testInitialCycleHandlesYearRolloverAndLeapMonthEnd() throws {
        let year = try BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: 31,
                                   repaymentKind: .fixedDay, repaymentValue: 8),
            today: LocalDate(rawValue: 20260105), timeZone: utc
        )
        XCTAssertEqual(year.cycleKey, 202512)
        XCTAssertEqual(year.repaymentDate.rawValue, 20260108)
        let leap = try BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: 31,
                                   repaymentKind: .daysAfterStatement, repaymentValue: 2),
            today: LocalDate(rawValue: 20240301), timeZone: utc
        )
        XCTAssertEqual(leap.cycleKey, 202402)
        XCTAssertEqual(leap.statementDate.rawValue, 20240229)
        XCTAssertEqual(leap.repaymentDate.rawValue, 20240302)
    }

    func testInitialCycleIncludesEarliestPendingLongOffsetBill() throws {
        let cycle = try BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: 20,
                                   repaymentKind: .daysAfterStatement, repaymentValue: 90),
            today: LocalDate(rawValue: 20260905), timeZone: utc
        )
        XCTAssertEqual(cycle.cycleKey, 202606)
        XCTAssertEqual(cycle.repaymentDate.rawValue, 20260918)
    }

    func testInitialCycleUsesHomeDateAcrossDeviceMonthBoundary() throws {
        let home = TimeZone(identifier: "Asia/Shanghai")!
        let instant = try LocalDate(rawValue: 20260831).date(in: utc).addingTimeInterval(20 * 60 * 60)
        let today = LocalDate(date: instant, timeZone: home)
        let cycle = try BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: 20,
                                   repaymentKind: .fixedDay, repaymentValue: 8),
            today: today, timeZone: home
        )
        XCTAssertEqual(today.rawValue, 20260901)
        XCTAssertEqual(cycle.cycleKey, 202608)
    }

    func testFutureRuleMonthOnlyChangeUsesRuleApplicableToThatMonth() throws {
        let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let december = BillingRuleInput(effectiveCycleKey: 202612, statementDay: 10,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let initial = BillingRuleInput(effectiveCycleKey: 202701, statementDay: 10,
                                       repaymentKind: .fixedDay, repaymentValue: 20)
        let november = BillingRuleInput(effectiveCycleKey: 202611, statementDay: 10,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        XCTAssertEqual(try BillingCalculator.futureRuleChange(initial: initial, requested: november,
            rules: [baseline, december], currentMonthKey: 202609), november)
        XCTAssertNil(try BillingCalculator.futureRuleChange(initial: initial, requested: initial,
            rules: [baseline, december], currentMonthKey: 202609))
    }

    func testFutureRuleCanCorrectScheduledVersionWithoutChangingHistory() throws {
        let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let december = BillingRuleInput(effectiveCycleKey: 202612, statementDay: 10,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let correction = BillingRuleInput(effectiveCycleKey: 202612, statementDay: 12,
                                          repaymentKind: .fixedDay, repaymentValue: 25)
        let change = try XCTUnwrap(BillingCalculator.futureRuleChange(initial: december, requested: correction,
            rules: [baseline, december], currentMonthKey: 202609))
        let updatedRules = [baseline, change]
        XCTAssertEqual(BillingCalculator.applicableRule(from: updatedRules, forCycleKey: 202611), baseline)
        XCTAssertEqual(BillingCalculator.applicableRule(from: updatedRules, forCycleKey: 202612), correction)
        for currentMonth in [202612, 202701] {
            XCTAssertThrowsError(try BillingCalculator.futureRuleChange(initial: december, requested: correction,
                rules: [baseline, december], currentMonthKey: currentMonth)) { error in
                XCTAssertEqual(error as? ModelValidationError, .effectiveCycleMustBeFuture)
            }
        }
    }

    func testFutureRuleDoesNotCreateRedundantVersionsOrTouchUneditedRulesAfterRollover() throws {
        let baseline = BillingRuleInput(effectiveCycleKey: nil, statementDay: 5,
                                        repaymentKind: .fixedDay, repaymentValue: 20)
        let initial = BillingRuleInput(effectiveCycleKey: 202610, statementDay: 5,
                                       repaymentKind: .fixedDay, repaymentValue: 20)
        let redundant = BillingRuleInput(effectiveCycleKey: 202611, statementDay: 5,
                                         repaymentKind: .fixedDay, repaymentValue: 20)
        XCTAssertNil(try BillingCalculator.futureRuleChange(initial: initial, requested: redundant,
            rules: [baseline], currentMonthKey: 202609))
        XCTAssertNil(try BillingCalculator.futureRuleChange(initial: initial, requested: initial,
            rules: [baseline], currentMonthKey: 202610))
    }

}
