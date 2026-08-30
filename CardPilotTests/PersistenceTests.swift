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
        let account = CreditCardAccount(bank: bank, creditLimit: 20_000)
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
}
