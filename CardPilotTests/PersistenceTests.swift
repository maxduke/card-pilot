import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class PersistenceTests: XCTestCase {
    func testModelsRoundTripInMemory() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let bank = Bank(name: "测试银行", presetCode: "cn.icbc")
        let network = CardNetwork.makeBuiltIns()[0]
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202608, creditLimit: 20_000)
        let card = Card(account: account, productName: "测试卡", networks: [network], lastFour: "1234")
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<Card>()).first?.networks.map(\.code), ["unionpay"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Bank>()).first?.presetCode, "cn.icbc")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CreditCardAccount>()).first?.trackingStartCycleKey, 202608)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BillingRuleVersion>()).count, 1)
    }

    func testBankPresetCatalogCoversMainlandAndHongKong() {
        XCTAssertEqual(BankPreset.catalog.count, 29)
        XCTAssertEqual(BankPreset.mainlandPresets.count, 18)
        XCTAssertEqual(BankPreset.hongKongPresets.count, 11)
        XCTAssertEqual(Set(BankPreset.catalog.map(\.code)).count, 29)
        XCTAssertTrue(BankPreset.mainlandPresets.allSatisfy { $0.defaultCurrencyCode == "CNY" })
        XCTAssertTrue(BankPreset.hongKongPresets.allSatisfy { $0.defaultCurrencyCode == "HKD" })
        XCTAssertTrue(BankPreset.catalog.first { $0.matches("ICBC") }?.displayName == "工商银行")
        XCTAssertTrue(BankPreset.catalog.first { $0.matches("汇丰") }?.region == .hongKong)
    }

    func testCardAcceptsOnlyTheThreeBuiltInDualNetworkSets() throws {
        let account = CreditCardAccount(bank: Bank(name: "测试银行"))
        let networks = Dictionary(uniqueKeysWithValues: CardNetwork.makeBuiltIns().map { ($0.code, $0) })

        for secondary in ["visa", "mastercard", "jcb"] {
            let card = Card(
                account: account,
                productName: "双标卡",
                networks: [networks["unionpay"]!, networks[secondary]!],
                lastFour: "1234"
            )
            XCTAssertNoThrow(try card.validate())
        }

        let custom = CardNetwork(code: "custom", displayName: "自定义")
        XCTAssertNoThrow(try Card(
            account: account,
            productName: "自定义卡",
            networks: [custom],
            lastFour: "1234"
        ).validate())
        XCTAssertThrowsError(try Card(
            account: account,
            productName: "无卡组织",
            networks: [],
            lastFour: "1234"
        ).validate())
        XCTAssertThrowsError(try Card(
            account: account,
            productName: "非法双标卡",
            networks: [networks["visa"]!, networks["mastercard"]!],
            lastFour: "1234"
        ).validate())
        XCTAssertThrowsError(try Card(
            account: account,
            productName: "非法双标卡",
            networks: [networks["unionpay"]!, custom],
            lastFour: "1234"
        ).validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidNetworkCombination)
        }
    }

    func testPromotionAmountRulesAreOptionalButMustBePositive() {
        let promotion = Promotion(
            title: "无金额规则活动",
            startOn: 20260801,
            endOn: 20260831,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try promotion.validate())

        let invalidPromotions = [
            Promotion(title: "无效达标门槛", startOn: 20260801, endOn: 20260831, qualificationThreshold: .zero, progressCurrencyCode: "CNY"),
            Promotion(title: "无效计入上限", startOn: 20260801, endOn: 20260831, qualifyingCap: .zero, progressCurrencyCode: "CNY"),
            Promotion(title: "无效单笔门槛", startOn: 20260801, endOn: 20260831, perTransactionThreshold: .zero, progressCurrencyCode: "CNY")
        ]
        for promotion in invalidPromotions {
            XCTAssertThrowsError(try promotion.validate())
        }

        let benefitPromotion = Promotion(
            title: "逐笔优惠活动",
            startOn: 20260801,
            endOn: 20260831,
            perTransactionThreshold: 10,
            benefitTransactionCap: 10,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try benefitPromotion.validate())

        for promotion in [
            Promotion(title: "无效优惠笔数上限", startOn: 20260801, endOn: 20260831, benefitTransactionCap: 0, progressCurrencyCode: "CNY"),
            Promotion(title: "逐笔与累计门槛冲突", startOn: 20260801, endOn: 20260831, qualificationThreshold: 100, benefitTransactionCap: 10, progressCurrencyCode: "CNY"),
            Promotion(title: "逐笔与累计上限冲突", startOn: 20260801, endOn: 20260831, qualifyingCap: 100, benefitTransactionCap: 10, progressCurrencyCode: "CNY")
        ] {
            XCTAssertThrowsError(try promotion.validate())
        }
    }

    func testPromotionAllocationRequiresPositiveAmount() throws {
        let bank = Bank(name: "测试银行")
        let account = CreditCardAccount(bank: bank)
        let card = Card(
            account: account,
            productName: "测试卡",
            networks: [CardNetwork.makeBuiltIns()[0]],
            lastFour: "1234"
        )
        let promotion = Promotion(
            title: "测试促销",
            startOn: 20260801,
            endOn: 20260831,
            eligibleCards: [card],
            progressCurrencyCode: "CNY"
        )

        XCTAssertThrowsError(try PromotionAllocation(
            transaction: Transaction(
                card: card,
                transactionOn: 20260801,
                amount: 10,
                currencyCode: "CNY",
                merchant: "测试商户"
            ),
            promotion: promotion,
            qualifyingAmount: .zero,
            currencyCode: "CNY"
        ).validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidQualifyingAmount)
        }
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
            qualificationThreshold: 100,
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
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try enrolledWithoutDeadline.validate())

        let invalidPromotion = Promotion(
            title: "不需要报名",
            startOn: 20260801,
            endOn: 20260831,
            enrollmentStatus: .notRequired,
            enrollmentDeadline: 20260810,
            qualificationThreshold: 100,
            progressCurrencyCode: "CNY"
        )
        XCTAssertThrowsError(try invalidPromotion.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidEnrollment)
        }
    }

    func testPromotionSeriesFieldsRoundTripInPrereleaseSchema() throws {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let seriesID = UUID()
        let promotion = Promotion(
            seriesID: seriesID,
            seriesIndex: 2,
            title: "系列周期",
            startOn: 20261001,
            endOn: 20261031,
            benefitTransactionCap: 10,
            progressCurrencyCode: "CNY"
        )
        XCTAssertNoThrow(try promotion.validate())
        context.insert(promotion)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Promotion>())
        XCTAssertEqual(fetched.first?.seriesID, seriesID)
        XCTAssertEqual(fetched.first?.seriesIndex, 2)
        XCTAssertEqual(fetched.first?.benefitTransactionCap, 10)
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
        let card = Card(account: account, productName: "测试卡", networks: [CardNetwork.makeBuiltIns()[0]], lastFour: "1234")
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

    func testCurrencyCodeMustBeAnISO4217Identifier() {
        XCTAssertTrue(isValidCurrencyCode("CNY"))
        XCTAssertFalse(isValidCurrencyCode("ZZZ"))
        XCTAssertFalse(isValidCurrencyCode("cny"))
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
        XCTAssertThrowsError(try account.validateNewBillingRuleEffectiveCycle(current.effectiveCycleKey, currentMonthKey: 202608)) { error in
            XCTAssertEqual(error as? ModelValidationError, .effectiveCycleMustBeFuture)
        }

        let future = BillingRuleVersion(
            account: account,
            effectiveCycleKey: 202609,
            statementDay: 8,
            repaymentKind: .fixedDay,
            repaymentValue: 13
        )
        XCTAssertNoThrow(try account.validateNewBillingRuleEffectiveCycle(future.effectiveCycleKey, currentMonthKey: 202608))
    }

}
