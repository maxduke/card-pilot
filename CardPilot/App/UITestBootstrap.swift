#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Explicit simulator-only opt-in. Each test owns a store; relaunches reopen that store.
/// No production store or persistent device preferences are removed or replaced.
@MainActor
enum UITestBootstrap {
    static func makeStore() -> BackupStore? {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["CARDPILOT_UI_SCENARIO"],
              ["empty", "core", "promotionOverview"].contains(scenario),
              let rawID = environment["CARDPILOT_UI_SESSION"],
              let session = UUID(uuidString: rawID) else { return nil }
        let directory = URL.temporaryDirectory.appendingPathComponent("CardPilotUITests/\(session.uuidString)", isDirectory: true)
        return BackupStore(directory: directory, openLegacy: {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("test.store")
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            let container = try CardPilotPersistence.makeContainer(at: url)
            if isNew && scenario != "empty" {
                try seed(container.mainContext, includePromotionOverview: scenario == "promotionOverview")
            }
            return container
        })
    }

    static func seed(_ context: ModelContext, includePromotionOverview: Bool = false) throws {
        let today = LocalDate(date: .now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let bank = Bank(name: "UI Test Bank")
        let networks = CardNetwork.makeBuiltIns()
        let network = networks.first { $0.code == "visa" }!
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: today.monthKey)
        let rule = BillingRuleVersion(account: account, statementDay: 1, repaymentKind: .daysAfterStatement, repaymentValue: 20)
        let card = Card(account: account, productName: "UI Primary", networks: [network], lastFour: "1234")
        let sibling = Card(account: account, productName: "UI Shared", networks: [network], lastFour: "5678")
        let foreignAccount = CreditCardAccount(bank: bank, trackingStartCycleKey: today.monthKey, limitCurrencyCode: "HKD")
        let foreignRule = BillingRuleVersion(account: foreignAccount, statementDay: 1, repaymentKind: .daysAfterStatement, repaymentValue: 20)
        let foreignCard = Card(account: foreignAccount, productName: "UI Foreign", networks: [network], lastFour: "9012")
        let promotion = Promotion(
            title: "UI Spend", startOn: today.addingDays(-7).rawValue, endOn: today.addingDays(30).rawValue,
            eligibleCards: [card], qualificationThreshold: Decimal(1000), progressCurrencyCode: "CNY"
        )
        context.insert(bank)
        networks.forEach(context.insert)
        context.insert(account)
        context.insert(rule)
        context.insert(card)
        context.insert(sibling)
        context.insert(foreignAccount)
        context.insert(foreignRule)
        context.insert(foreignCard)
        context.insert(promotion)
        if includePromotionOverview {
            promotion.rewardDescription = "达标奖励以银行规则为准"
            let amountCap = Promotion(
                title: "UI Amount Cap", startOn: promotion.startOn, endOn: promotion.endOn,
                eligibleCards: [card], qualifyingCap: 500, progressCurrencyCode: "CNY"
            )
            let available = Promotion(
                title: "UI Available", startOn: promotion.startOn, endOn: promotion.endOn,
                eligibleCards: [card], benefitTransactionCap: 4, progressCurrencyCode: "CNY"
            )
            let exhausted = Promotion(
                title: "UI Exhausted", startOn: promotion.startOn, endOn: promotion.endOn,
                eligibleCards: [card], benefitTransactionCap: 2, progressCurrencyCode: "CNY"
            )
            let reached = Promotion(
                title: "UI Reached", startOn: promotion.startOn, endOn: promotion.endOn,
                eligibleCards: [card], qualificationThreshold: 100, progressCurrencyCode: "CNY"
            )
            [amountCap, available, exhausted, reached].forEach(context.insert)
            for index in 1...2 {
                let transaction = Transaction(
                    card: card, transactionOn: today.rawValue, amount: 50,
                    currencyCode: "CNY", merchant: "UI Benefit \(index)"
                )
                context.insert(transaction)
                for target in [available, exhausted, reached] {
                    context.insert(PromotionAllocation(
                        transaction: transaction, promotion: target, qualifyingAmount: 50, currencyCode: "CNY"
                    ))
                }
            }
        }
        try context.save()
    }
}
#endif
