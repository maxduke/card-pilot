import XCTest
@testable import CardPilot

final class DashboardTests: XCTestCase {
    func testMonthKeysAreInclusiveAndHandleYearBoundary() {
        XCTAssertEqual(LocalDate.monthKeys(from: 202411, through: 202502), [202411, 202412, 202501, 202502])
        XCTAssertEqual(LocalDate.monthKeys(from: 202503, through: 202502), [])
        XCTAssertEqual(LocalDate.monthKeys(from: 202513, through: 202602), [])
        XCTAssertEqual(LocalDate.monthKeys(from: 202701, through: 202612), [])
    }

    func testEnrollmentDeadlineFilterIncludesBoundaryAndDoesNotRequirePromotionStarted() {
        let today = try! LocalDate(rawValue: 20260810)
        let notStarted = Promotion(
            title: "尚未开始但报名临近截止",
            startOn: 20260820,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260817,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let atBoundary = Promotion(
            title: "第七天截止",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260817,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let afterWindow = Promotion(
            title: "第八天截止",
            startOn: 20260801,
            endOn: 20260901,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260818,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let enrolled = Promotion(
            title: "已报名",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .enrolled,
            enrollmentDeadline: 20260817,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let archived = Promotion(
            title: "已归档",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260817,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY",
            archivedAt: Date()
        )

        XCTAssertEqual(
            promotionsWithEnrollmentDeadlineWithin([notStarted, atBoundary, afterWindow, enrolled, archived], today: today).map(\.title),
            ["尚未开始但报名临近截止", "第七天截止"]
        )
    }

    func testDashboardContinuePromotionsOnlyShowsIncompleteAmountOrCountTargets() throws {
        let today = try LocalDate(rawValue: 20260810)
        let amountTarget = Promotion(
            title: "累计目标",
            startOn: 20260801,
            endOn: 20260831,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let countTarget = Promotion(
            title: "逐笔目标",
            startOn: 20260801,
            endOn: 20260831,
            benefitTransactionCap: 10,
            progressCurrencyCode: "CNY"
        )
        let card = Card(
            account: CreditCardAccount(bank: Bank(name: "测试银行")),
            productName: "测试卡",
            networks: [CardNetwork.makeBuiltIns()[0]],
            lastFour: "1234"
        )
        let completed = Promotion(
            title: "已完成累计目标",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let completedTransaction = Transaction(
            card: card,
            transactionOn: 20260801,
            amount: 100,
            currencyCode: "CNY",
            merchant: "测试商户"
        )
        completed.allocations.append(PromotionAllocation(
            transaction: completedTransaction,
            promotion: completed,
            qualifyingAmount: 100,
            currencyCode: "CNY"
        ))
        let enrollmentPending = Promotion(
            title: "待报名",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260815,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        let capOnly = Promotion(
            title: "仅累计上限",
            startOn: 20260801,
            endOn: 20260831,
            qualifyingCap: 100,
            progressCurrencyCode: "CNY"
        )
        let textOnly = Promotion(
            title: "文字规则",
            startOn: 20260801,
            endOn: 20260831,
            progressCurrencyCode: "CNY"
        )
        let future = Promotion(
            title: "未来活动",
            startOn: 20260811,
            endOn: 20260831,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )

        XCTAssertEqual(
            dashboardPromotionsToContinue(
                [textOnly, future, capOnly, completed, enrollmentPending, countTarget, amountTarget],
                today: today,
                excludingEnrollmentDeadlineIDs: [enrollmentPending.id]
            ).map(\.title),
            ["累计目标", "逐笔目标"]
        )
    }

    func testAccountTrackingStartCycleKeyValidation() throws {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"), trackingStartCycleKey: 202613)
        XCTAssertThrowsError(try account.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidCycleKey)
        }
    }

    func testAccountDefaultsTrackingStartToCurrentLocalMonth() {
        let before = LocalDate(date: .now, timeZone: .current).monthKey
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let after = LocalDate(date: .now, timeZone: .current).monthKey
        XCTAssertTrue(account.trackingStartCycleKey == before || account.trackingStartCycleKey == after)
    }

    func testRepaymentSelectionKeepsAllOverdueAndNearestPendingPerAccount() throws {
        let accountOne = CreditCardAccount(bank: Bank(name: "银行一"))
        let accountTwo = CreditCardAccount(bank: Bank(name: "银行二"))
        func item(
            account: CreditCardAccount,
            cycleKey: Int,
            kind: DashboardBillingItem.Kind,
            date: Int,
            status: BillingCycle.Status
        ) throws -> DashboardBillingItem {
            DashboardBillingItem(
                account: account,
                cycleKey: cycleKey,
                kind: kind,
                date: try LocalDate(rawValue: date),
                status: status
            )
        }

        let items = try [
            item(account: accountOne, cycleKey: 202608, kind: .statement, date: 20260805, status: .pending),
            item(account: accountOne, cycleKey: 202609, kind: .statement, date: 20260905, status: .pending),
            item(account: accountOne, cycleKey: 202606, kind: .repayment, date: 20260625, status: .overdue),
            item(account: accountOne, cycleKey: 202607, kind: .repayment, date: 20260725, status: .overdue),
            item(account: accountOne, cycleKey: 202609, kind: .repayment, date: 20260925, status: .pending),
            item(account: accountOne, cycleKey: 202610, kind: .repayment, date: 20261025, status: .pending),
            item(account: accountTwo, cycleKey: 202606, kind: .repayment, date: 20260620, status: .overdue),
            item(account: accountTwo, cycleKey: 202609, kind: .repayment, date: 20260920, status: .pending),
            item(account: accountTwo, cycleKey: 202610, kind: .repayment, date: 20261020, status: .pending)
        ]

        let selected = selectDashboardBillingItems(items)
        XCTAssertEqual(selected.filter { $0.kind == .statement }.count, 1)
        XCTAssertEqual(selected.filter { $0.kind == .statement }.map(\.cycleKey), [202608])
        XCTAssertEqual(selected.filter { $0.status == .overdue }.count, 3)
        XCTAssertEqual(selected.filter { $0.account.id == accountOne.id }.map(\.cycleKey).sorted(), [202606, 202607, 202608, 202609])
        XCTAssertEqual(selected.filter { $0.account.id == accountTwo.id }.map(\.cycleKey).sorted(), [202606, 202609])
    }
}
