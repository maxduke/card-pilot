import XCTest
@testable import CardPilot

final class AccountSummaryTests: XCTestCase {
    func testAccountLabelsDistinguishCardsAndSpeakRepaymentDates() throws {
        let bank = Bank(name: "同一家银行")
        let first = CreditCardAccount(bank: bank)
        let second = CreditCardAccount(bank: bank)
        first.cards = [Card(account: first, productName: "日常卡", networks: [], lastFour: "1234")]
        second.cards = [Card(account: second, productName: "旅行卡", networks: [], lastFour: "5678")]
        XCTAssertNotEqual(CardPilotUI.accountName(first), CardPilotUI.accountName(second))
        XCTAssertTrue(CardPilotUI.accountName(first).contains("1234"))
        let summary = CardAccountBillingSummary(nextStatementDate: try LocalDate(rawValue: 20260910), nextRepaymentDate: try LocalDate(rawValue: 20260903), nextRepaymentStatus: .overdue)
        let label = CardPilotUI.accountAccessibilityLabel(first, summary: summary)
        XCTAssertTrue(label.contains("下次账单 2026年09月10日"))
        XCTAssertTrue(label.contains("逾期还款 2026年09月03日"))
    }
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

    func testIncludesExplicitUnpaidCycleBeforeTrackingStart() throws {
        let summary = CardAccountBillingSummaryCalculator.calculate(
            status: .active,
            closedOn: nil,
            trackingStartCycleKey: 202608,
            rules: [BillingRuleInput(
                effectiveCycleKey: nil,
                statementDay: 5,
                repaymentKind: .fixedDay,
                repaymentValue: 20
            )],
            overrides: [
                202607: BillingCycleOverride(statementDate: nil, repaymentDate: nil, repaidAt: nil)
            ],
            today: try LocalDate(rawValue: 20260810),
            timeZone: utc
        )

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

    func testPresetOnboardingReusesUntaggedCatalogBankAndPrefersTaggedMatch() throws {
        let preset = try XCTUnwrap(BankPreset.catalog.first { $0.code == "cn.icbc" })
        let untagged = Bank(name: " 工商银行 ")
        let otherPreset = Bank(name: "工商银行", presetCode: "hk.icbcasia")

        XCTAssertEqual(matchingPresetBanks([untagged, otherPreset], preset: preset).map(\.id), [untagged.id])

        let tagged = Bank(name: "工商银行", presetCode: preset.code)
        XCTAssertEqual(matchingPresetBanks([untagged, tagged], preset: preset).map(\.id), [tagged.id])
    }
}
