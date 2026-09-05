import XCTest
@testable import CardPilot

final class UIWorkflowSupportTests: XCTestCase {
    func testActionCountsSeparateOverdueTodayAndNextSevenDays() throws {
        let today = try LocalDate(rawValue: 20260910)
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        func billing(_ rawDate: Int, status: BillingCycle.Status) throws -> DashboardBillingItem {
            DashboardBillingItem(
                account: account,
                cycleKey: 202609,
                kind: .repayment,
                date: try LocalDate(rawValue: rawDate),
                status: status
            )
        }
        let todayEnrollment = Promotion(
            title: "今天截止",
            startOn: 20260901,
            endOn: 20260930,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260910,
            progressCurrencyCode: "CNY"
        )
        let upcomingEnrollment = Promotion(
            title: "七天内截止",
            startOn: 20260901,
            endOn: 20260930,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260917,
            progressCurrencyCode: "CNY"
        )

        let counts = try dashboardActionCounts(
            billingItems: [
                billing(20260908, status: .overdue),
                billing(20260910, status: .pending),
                billing(20260916, status: .pending)
            ],
            enrollmentPromotions: [todayEnrollment, upcomingEnrollment],
            today: today
        )

        XCTAssertEqual(counts, DashboardActionCounts(overdue: 1, today: 2, nextSevenDays: 2))
        XCTAssertEqual(counts.total, 5)
    }

    func testTransactionSaveFeedbackDescribesAmountKindAndAllocations() {
        XCTAssertEqual(
            TransactionSaveFeedback.make(
                kind: .purchase,
                amount: 128,
                currencyCode: "CNY",
                allocationCount: 2,
                isNew: true
            ).message,
            "已记录 128 CNY · 计入 2 个活动"
        )
        XCTAssertEqual(
            TransactionSaveFeedback.make(
                kind: .refund,
                amount: 10,
                currencyCode: "HKD",
                allocationCount: 0,
                isNew: false
            ).message,
            "退款已更新 · 10 HKD · 未计入活动"
        )
    }
}
