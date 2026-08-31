import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class PersistenceTests: XCTestCase {
    func testModelsRoundTripInMemory() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let bank = Bank(name: "测试银行")
        let network = CardNetwork.makeBuiltIns()[0]
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202608, creditLimit: 20_000)
        let card = Card(account: account, productName: "测试卡", network: network, lastFour: "1234")
        let rule = BillingRuleVersion(
            account: account,
            statementDay: 5,
            repaymentKind: .daysAfterStatement,
            repaymentValue: 20
        )

        context.insert(bank)
        context.insert(network)
        context.insert(account)
        context.insert(card)
        context.insert(rule)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).first?.lastFour, "1234")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreditCardAccount>()).first?.trackingStartCycleKey, 202608)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BillingRuleVersion>()).count, 1)
    }

    func testAccountRejectsDuplicateBaselineRules() throws {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        account.billingRuleVersions = [
            BillingRuleVersion(account: account, statementDay: 1, repaymentKind: .fixedDay, repaymentValue: 10),
            BillingRuleVersion(account: account, statementDay: 2, repaymentKind: .fixedDay, repaymentValue: 11)
        ]

        XCTAssertThrowsError(try account.validateBillingConfiguration()) { error in
            XCTAssertEqual(error as? ModelValidationError, .duplicateBillingRule)
        }
    }

    func testPromotionEnrollmentDeadlineMayBeUnsetUnlessEnrollmentIsNotRequired() throws {
        let enrolledPromotion = Promotion(
            title: "可选报名截止日",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notEnrolled,
            enrollmentDeadline: nil,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try enrolledPromotion.validate())

        let enrolledWithoutDeadline = Promotion(
            title: "已报名但无截止日",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .enrolled,
            enrolledOn: nil,
            enrollmentDeadline: nil,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try enrolledWithoutDeadline.validate())

        let invalidPromotion = Promotion(
            title: "不需要报名",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notRequired,
            enrollmentDeadline: 20260810,
            targetAmount: 100,
            progressCurrencyCode: "CNY"
        )
        XCTAssertThrowsError(try invalidPromotion.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidEnrollment)
        }
    }

    func testDeletingAccountDependenciesAllowsAccountDeletion() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let bank = Bank(name: "可删除账户银行")
        let account = CreditCardAccount(bank: bank)
        let rule = BillingRuleVersion(account: account, statementDay: 5, repaymentKind: .fixedDay, repaymentValue: 10)
        let cycle = BillingCycleRecord(account: account, cycleKey: 202608)
        context.insert(bank)
        context.insert(account)
        context.insert(rule)
        context.insert(cycle)
        try context.save()

        context.delete(account)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CreditCardAccount>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BillingCycleRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BillingRuleVersion>()).isEmpty)
    }

    func testRefundMayOmitOriginalPurchase() throws {
        let bank = Bank(name: "退款测试银行")
        let account = CreditCardAccount(bank: bank)
        let card = Card(account: account, productName: "测试卡", network: CardNetwork.makeBuiltIns()[0], lastFour: "1234")
        let refund = Transaction(
            card: card,
            kind: .refund,
            transactionOn: 20260810,
            amount: 100,
            currencyCode: "CNY",
            merchant: "测试商户"
        )
        XCTAssertNoThrow(try refund.validate())
    }

    func testBillingChildrenRequireAnAccountOwner() throws {
        let bank = Bank(name: "孤儿记录测试银行")
        let account = CreditCardAccount(bank: bank)
        let rule = BillingRuleVersion(account: account, statementDay: 5, repaymentKind: .fixedDay, repaymentValue: 10)
        let cycle = BillingCycleRecord(account: account, cycleKey: 202608)

        rule.account = nil
        cycle.account = nil

        XCTAssertThrowsError(try rule.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .missingAccountOwner)
        }
        XCTAssertThrowsError(try cycle.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .missingAccountOwner)
        }
    }

    func testNewBillingRuleMustStartAfterCurrentMonthWithoutRejectingHistory() throws {
        let account = CreditCardAccount(bank: Bank(name: "规则版本测试银行"))
        let baseline = BillingRuleVersion(account: account, statementDay: 5, repaymentKind: .fixedDay, repaymentValue: 10)
        let historical = BillingRuleVersion(
            account: account,
            effectiveCycleKey: 202607,
            statementDay: 6,
            repaymentKind: .fixedDay,
            repaymentValue: 11
        )
        account.billingRuleVersions = [baseline, historical]
        XCTAssertNoThrow(try account.validateBillingConfiguration())

        let current = BillingRuleVersion(
            account: account,
            effectiveCycleKey: 202608,
            statementDay: 7,
            repaymentKind: .fixedDay,
            repaymentValue: 12
        )
        XCTAssertThrowsError(try account.validateNewBillingRule(current, currentMonthKey: 202608)) { error in
            XCTAssertEqual(error as? ModelValidationError, .effectiveCycleMustBeFuture)
        }

        let future = BillingRuleVersion(
            account: account,
            effectiveCycleKey: 202609,
            statementDay: 8,
            repaymentKind: .fixedDay,
            repaymentValue: 13
        )
        XCTAssertNoThrow(try account.validateNewBillingRule(future, currentMonthKey: 202608))
    }

}
