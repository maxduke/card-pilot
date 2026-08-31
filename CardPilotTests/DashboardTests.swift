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
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let atBoundary = Promotion(
            title: "第七天截止",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260817,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let afterWindow = Promotion(
            title: "第八天截止",
            startOn: 20260801,
            endOn: 20260901,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260818,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let enrolled = Promotion(
            title: "已报名",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .enrolled,
            enrollmentDeadline: 20260817,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        let archived = Promotion(
            title: "已归档",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: 20260817,
            targetAmount: 100,
            progressCurrencyCode: "CNY",
            archivedAt: Date()
        )

        XCTAssertEqual(
            promotionsWithEnrollmentDeadlineWithin([notStarted, atBoundary, afterWindow, enrolled, archived], today: today).map(\.title),
            ["尚未开始但报名临近截止", "第七天截止"]
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
}
