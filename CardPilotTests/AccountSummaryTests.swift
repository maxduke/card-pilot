import XCTest
@testable import CardPilot

final class AccountSummaryTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testUsesSavedOverridesAndSkipsPaidRepaymentForActiveAccount() throws {
        let today = try LocalDate(rawValue: 20260810)
        let rules = [BillingRuleInput(
            effectiveCycleKey: nil,
            statementDay: 5,
            repaymentKind: .fixedDay,
            repaymentValue: 20
        )]
        let summary = CardAccountBillingSummaryCalculator.calculate(
            status: .active,
            closedOn: nil,
            trackingStartCycleKey: 202607,
            rules: rules,
            overrides: [
                202607: BillingCycleOverride(
                    statementDate: nil,
                    repaymentDate: nil,
                    repaidAt: Date(timeIntervalSince1970: 1)
                ),
                202608: BillingCycleOverride(
                    statementDate: try LocalDate(rawValue: 20260812),
                    repaymentDate: try LocalDate(rawValue: 20260825),
                    repaidAt: Date(timeIntervalSince1970: 1)
                ),
                202609: BillingCycleOverride(
                    statementDate: nil,
                    repaymentDate: try LocalDate(rawValue: 20260927),
                    repaidAt: nil
                )
            ],
            today: today,
            timeZone: utc
        )

        XCTAssertEqual(summary.nextStatementDate, try LocalDate(rawValue: 20260812))
        XCTAssertEqual(summary.nextRepaymentDate, try LocalDate(rawValue: 20260927))
        XCTAssertEqual(summary.nextRepaymentStatus, .pending)
    }

    func testKeepsUnpaidOverdueCycleAndDoesNotShowStatementAfterClose() throws {
        let summary = CardAccountBillingSummaryCalculator.calculate(
            status: .closed,
            closedOn: try LocalDate(rawValue: 20260805),
            trackingStartCycleKey: 202607,
            rules: [BillingRuleInput(
                effectiveCycleKey: nil,
                statementDay: 5,
                repaymentKind: .fixedDay,
                repaymentValue: 20
            )],
            today: try LocalDate(rawValue: 20260825),
            timeZone: utc
        )

        XCTAssertNil(summary.nextStatementDate)
        XCTAssertEqual(summary.nextRepaymentDate, try LocalDate(rawValue: 20260720))
        XCTAssertEqual(summary.nextRepaymentStatus, .overdue)
    }

    func testAccountEditorBanksExcludeArchivedUnlessAlreadySelected() {
        let active = Bank(name: "使用中银行")
        let archived = Bank(name: "已归档银行", archivedAt: Date())

        XCTAssertEqual(selectableAccountBanks([archived, active], currentBankID: nil).map(\.id), [active.id])
        XCTAssertEqual(
            selectableAccountBanks([archived, active], currentBankID: archived.id).map(\.id),
            [archived.id, active.id]
        )
    }
}
