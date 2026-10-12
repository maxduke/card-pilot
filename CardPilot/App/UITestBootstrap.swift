#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Explicit simulator-only opt-in. Each test owns a store; relaunches reopen that store.
/// No production store or persistent device preferences are removed or replaced.
@MainActor
enum UITestBootstrap {
    enum Scenario: String {
        case empty
        case core
        case promotionOverview
        case dashboardActions
        case linkedRefunds
        case refundIdentity
        case transactionFilters
        case accountHistory
        case futureRules
    }

    static func makeStore() -> BackupStore? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawScenario = environment["CARDPILOT_UI_SCENARIO"],
              let scenario = Scenario(rawValue: rawScenario),
              let rawID = environment["CARDPILOT_UI_SESSION"],
              let session = UUID(uuidString: rawID) else { return nil }
        let directory = URL.temporaryDirectory.appendingPathComponent("CardPilotUITests/\(session.uuidString)", isDirectory: true)
        return BackupStore(directory: directory, openLegacy: {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("test.store")
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            let container = try CardPilotPersistence.makeContainer(at: url)
            if isNew && scenario != .empty {
                try seed(container.mainContext, scenario: scenario)
            }
            return container
        })
    }

    static func seed(
        _ context: ModelContext,
        scenario: Scenario = .core,
        today: LocalDate = LocalDate(date: .now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
    ) throws {
        guard scenario != .empty else { return }
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
        if scenario == .promotionOverview {
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
        if scenario == .dashboardActions {
            let statement = today.addingDays(-2)
            account.trackingStartCycleKey = statement.monthKey
            context.insert(BillingCycleRecord(
                account: account, cycleKey: statement.monthKey,
                statementDateOverride: statement.rawValue,
                repaymentDateOverride: today.addingDays(-1).rawValue
            ))
            // Keep the foreign account's 21st-day schedule from changing the
            // expected action counts as the simulator's current date changes.
            context.insert(BillingCycleRecord(account: foreignAccount, cycleKey: today.monthKey, repaidAt: .now))
            for (name, repaymentDays, lastFour) in [("UI Today", 2, "2222"), ("UI Next Week", 9, "3333")] {
                let actionAccount = CreditCardAccount(bank: bank, trackingStartCycleKey: statement.monthKey)
                context.insert(actionAccount)
                context.insert(BillingRuleVersion(
                    account: actionAccount, statementDay: statement.day,
                    repaymentKind: .daysAfterStatement, repaymentValue: repaymentDays
                ))
                context.insert(Card(account: actionAccount, productName: name, networks: [network], lastFour: lastFour))
            }
            for index in 1...15 {
                context.insert(Card(
                    account: account, productName: "UI Shared \(index)", networks: [network],
                    lastFour: String(format: "%04d", 6000 + index)
                ))
            }
            promotion.enrollmentStatus = .notEnrolled
            promotion.enrollmentDeadline = today.rawValue
            context.insert(Promotion(
                title: "UI Upcoming Enrollment", startOn: today.addingDays(8).rawValue,
                endOn: today.addingDays(30).rawValue, eligibleCards: [card],
                enrollmentStatus: .notEnrolled, enrollmentDeadline: today.addingDays(7).rawValue,
                progressCurrencyCode: "CNY"
            ))
        }
        if scenario == .linkedRefunds {
            promotion.eligibleCards.append(foreignCard)
            let original = Transaction(
                card: foreignCard, transactionOn: today.addingDays(-2).rawValue,
                amount: 100, currencyCode: "CNY", merchant: "UI Original Purchase"
            )
            context.insert(original)
            context.insert(PromotionAllocation(
                transaction: original, promotion: promotion, qualifyingAmount: 100, currencyCode: "CNY"
            ))
            let partial = Transaction(
                card: foreignCard, kind: .refund, transactionOn: today.addingDays(-1).rawValue,
                amount: 40, currencyCode: "CNY", merchant: "UI Earlier Refund", originalTransaction: original
            )
            context.insert(partial)
            context.insert(PromotionAllocation(
                transaction: partial, promotion: promotion, qualifyingAmount: 40, currencyCode: "CNY"
            ))
            context.insert(Transaction(
                card: sibling, transactionOn: today.addingDays(-2).rawValue,
                amount: 80, currencyCode: "CNY", merchant: "UI Reversed Purchase", status: .reversed
            ))
            context.insert(Transaction(
                card: sibling, kind: .refund, transactionOn: today.rawValue,
                amount: 15, currencyCode: "CNY", merchant: "UI Unlinked Refund"
            ))
        }
        if scenario == .refundIdentity {
            context.insert(Transaction(
                card: foreignCard, transactionOn: 20261010,
                amount: Decimal(string: "100.25")!, currencyCode: "CNY",
                merchant: "星河百货中心生活用品与家居电器联合专柜", status: .reversed
            ))
            context.insert(Transaction(
                card: foreignCard, transactionOn: 20261009,
                amount: Decimal(string: "65.5")!, currencyCode: "HKD", merchant: "UI Alternate Original"
            ))
        }
        if scenario == .transactionFilters {
            let first = try LocalDate(year: today.year, month: today.month, day: 1)
            let previous = first.addingMonths(-1)
            let dates: [(String, LocalDate, String, TransactionKind, TransactionStatus)] = [
                ("UI Current CNY", today, "CNY", .purchase, .active),
                ("UI Current HKD", first, "HKD", .purchase, .active),
                ("UI Current Refund", today, "CNY", .refund, .active),
                ("UI Previous CNY", first.addingDays(-1), "CNY", .purchase, .active),
                ("UI Previous HKD", previous, "HKD", .refund, .active),
                ("UI Previous Reversed", previous, "CNY", .purchase, .reversed),
                ("UI Older CNY", previous.addingDays(-1), "CNY", .purchase, .active),
                ("UI Future HKD", first.addingMonths(1), "HKD", .purchase, .active)
            ]
            for (merchant, date, currency, kind, status) in dates {
                context.insert(Transaction(card: sibling, kind: kind, transactionOn: date.rawValue,
                                           amount: 10, currencyCode: currency, merchant: merchant, status: status))
            }
        }
        if scenario == .accountHistory {
            account.trackingStartCycleKey = today.addingMonths(-18).monthKey
            for offset in -18 ... -12 {
                context.insert(BillingCycleRecord(account: account, cycleKey: today.addingMonths(offset).monthKey,
                                                  repaidAt: today.addingDays(-1).date(in: TimeZone(identifier: "Asia/Shanghai")!)))
            }
            context.insert(BillingCycleRecord(account: account, cycleKey: today.addingMonths(-20).monthKey,
                                              repaidAt: today.addingDays(-1).date(in: TimeZone(identifier: "Asia/Shanghai")!)))
            let future = today.addingMonths(5)
            context.insert(BillingCycleRecord(
                account: account, cycleKey: future.monthKey,
                statementDateOverride: try LocalDate(year: future.year, month: future.month, day: 3).rawValue,
                repaymentDateOverride: try LocalDate(year: future.year, month: future.month, day: 6).rawValue
            ))
        }
        if scenario == .futureRules {
            for target in [account, foreignAccount] {
                target.trackingStartCycleKey = today.addingMonths(-1).monthKey
                let baseline = target === account ? rule : foreignRule
                baseline.statementDay = 20
                baseline.repaymentKind = .fixedDay
                baseline.repaymentValue = 25
                context.insert(BillingRuleVersion(account: target, effectiveCycleKey: today.addingMonths(1).monthKey,
                                                  statementDay: 5, repaymentKind: .fixedDay, repaymentValue: 25))
                context.insert(BillingRuleVersion(account: target, effectiveCycleKey: today.addingMonths(3).monthKey,
                                                  statementDay: 10, repaymentKind: .fixedDay, repaymentValue: 26))
                let overridden = today.addingMonths(2)
                context.insert(BillingCycleRecord(
                    account: target, cycleKey: overridden.monthKey,
                    statementDateOverride: target === account
                        ? try LocalDate(year: overridden.year, month: overridden.month, day: 3).rawValue : nil,
                    repaymentDateOverride: try LocalDate(year: overridden.year, month: overridden.month, day: 10).rawValue
                ))
            }
        }
        try context.save()
    }
}
#endif
