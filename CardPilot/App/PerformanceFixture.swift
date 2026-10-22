#if (DEBUG || PERFORMANCE_TESTING) && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Synthetic data for isolated simulator stores, never the ordinary app store.
@MainActor
enum PerformanceFixture {
    struct Report: Codable {
        let version: Int
        let today: Int
        let timeZone: String
        let banks: Int
        let accounts: Int
        let cards: Int
        let billingCycles: Int
        let promotions: Int
        let transactions: Int
        let allocations: Int
        let firstTransactionOn: Int
        let lastTransactionOn: Int
        let searchMatches: Int
    }

    struct InvalidFixture: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func seed(_ context: ModelContext, transactionCount: Int, today: LocalDate) throws -> Report {
        guard [100, 5_000, 20_000].contains(transactionCount) else {
            throw InvalidFixture(message: "Unsupported performance transaction count")
        }
        let wasAutosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = wasAutosaveEnabled }

        let timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let firstDay = today.addingMonths(-60, timeZone: timeZone)
        let calendar = LocalDate.calendar(timeZone: timeZone)
        let dayCount = calendar.dateComponents([.day], from: firstDay.date(in: timeZone), to: today.date(in: timeZone)).day!
        let dates = (0..<dayCount).map { firstDay.addingDays($0, timeZone: timeZone) }
        let networks = CardNetwork.makeBuiltIns()
        networks.forEach(context.insert)
        let network = networks.first { $0.code == "visa" }!
        var banks: [Bank] = []
        var accounts: [CreditCardAccount] = []
        var cards: [Card] = []
        for index in 0..<10 {
            let bank = Bank(id: id(1, index), name: String(format: "Baseline Bank %02d", index))
            let account = CreditCardAccount(
                id: id(2, index), bank: bank, trackingStartCycleKey: firstDay.monthKey,
                creditLimit: 50_000, limitCurrencyCode: "CNY"
            )
            let rule = BillingRuleVersion(
                id: id(3, index), account: account, statementDay: 1 + index,
                repaymentKind: .daysAfterStatement, repaymentValue: 20
            )
            context.insert(bank)
            context.insert(account)
            context.insert(rule)
            for offset in -60...0 {
                let month = today.addingMonths(offset, timeZone: timeZone)
                context.insert(BillingCycleRecord(
                    id: id(4, index * 61 + offset + 60), account: account, cycleKey: month.monthKey,
                    repaidAt: offset < 0 ? month.date(in: timeZone) : nil
                ))
            }
            for side in 0..<2 {
                let cardIndex = index * 2 + side
                let card = Card(
                    id: id(5, cardIndex), account: account,
                    productName: String(format: "Baseline Card %02d", cardIndex),
                    networks: [network], lastFour: String(format: "%04d", 1000 + cardIndex)
                )
                context.insert(card)
                cards.append(card)
            }
            banks.append(bank)
            accounts.append(account)
        }

        var promotions: [Promotion] = []
        let currentMonth = try LocalDate.firstDay(ofMonthKey: today.monthKey)
        for series in 0..<2 {
            for period in 0..<12 {
                let start = currentMonth.addingMonths(period - 5, timeZone: timeZone)
                let end = start.addingMonths(1, timeZone: timeZone).addingDays(-1, timeZone: timeZone)
                let promotion = Promotion(
                    id: id(6, series * 12 + period), seriesID: id(7, series), seriesIndex: period,
                    title: "Baseline Series \(series) · \(start.monthKey)", startOn: start.rawValue, endOn: end.rawValue,
                    organizingBanks: banks, eligibleCards: cards, qualificationThreshold: 1_000_000,
                    progressCurrencyCode: "CNY", rewardDescription: "Synthetic benchmark reward"
                )
                context.insert(promotion)
                promotions.append(promotion)
            }
        }
        var allocationCount = 0
        for index in 0..<transactionCount {
            // Only the last row uses today: it remains a unique, visible readiness marker.
            let date = index == transactionCount - 1 ? today : dates[index * (dayCount - 1) / (transactionCount - 1)]
            let merchant: String
            if index == transactionCount - 1 { merchant = "Baseline Latest" }
            else if index.isMultiple(of: 100) { merchant = "Baseline 73519 \(index)" }
            else { merchant = "Baseline Merchant \(index % 40)" }
            let transaction = Transaction(
                id: id(8, index), card: cards[index % cards.count], transactionOn: date.rawValue,
                postingOn: date.rawValue, amount: Decimal(50 + index % 950) / 10,
                currencyCode: "CNY", merchant: merchant, category: "Baseline Category \(index % 8)"
            )
            context.insert(transaction)
            try transaction.validate()
            if index.isMultiple(of: 10) || index == transactionCount - 1 {
                for promotion in promotions where promotion.startOn <= date.rawValue && date.rawValue <= promotion.endOn {
                    let allocation = PromotionAllocation(
                        id: id(9, allocationCount), transaction: transaction, promotion: promotion,
                        qualifyingAmount: transaction.amount, currencyCode: "CNY"
                    )
                    context.insert(allocation)
                    try allocation.validate()
                    allocationCount += 1
                }
            }
            if (index + 1).isMultiple(of: 500) { try context.save() }
        }
        try banks.forEach { try $0.validate() }
        try accounts.forEach { try $0.validate(); try $0.validateBillingConfiguration() }
        try cards.forEach { try $0.validate() }
        try promotions.forEach { try $0.validate() }
        try context.save()

        var firstTransaction = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.transactionOn)])
        firstTransaction.fetchLimit = 1
        var lastTransaction = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.transactionOn, order: .reverse)])
        lastTransaction.fetchLimit = 1
        let search = FetchDescriptor<Transaction>(predicate: #Predicate { $0.merchant.contains("73519") })
        let report = Report(
            version: 1, today: today.rawValue, timeZone: timeZone.identifier,
            banks: try context.fetchCount(FetchDescriptor<Bank>()),
            accounts: try context.fetchCount(FetchDescriptor<CreditCardAccount>()),
            cards: try context.fetchCount(FetchDescriptor<Card>()),
            billingCycles: try context.fetchCount(FetchDescriptor<BillingCycleRecord>()),
            promotions: try context.fetchCount(FetchDescriptor<Promotion>()),
            transactions: try context.fetchCount(FetchDescriptor<Transaction>()),
            allocations: try context.fetchCount(FetchDescriptor<PromotionAllocation>()),
            firstTransactionOn: try context.fetch(firstTransaction).first?.transactionOn ?? 0,
            lastTransactionOn: try context.fetch(lastTransaction).first?.transactionOn ?? 0,
            searchMatches: try context.fetchCount(search)
        )
        guard report.banks == 10, report.accounts == 10, report.cards == 20, report.billingCycles == 610,
              report.promotions == 24, report.transactions == transactionCount, report.allocations == allocationCount,
              report.firstTransactionOn == firstDay.rawValue, report.lastTransactionOn == today.rawValue,
              report.searchMatches == transactionCount / 100, allocationCount >= 2 else {
            throw InvalidFixture(message: "Performance fixture population mismatch")
        }
        return report
    }

    private static func id(_ category: Int, _ index: Int) -> UUID {
        UUID(uuidString: String(format: "CA190000-0000-0000-%04X-%012X", category, index))!
    }
}
#endif
