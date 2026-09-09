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
              ["empty", "core"].contains(scenario),
              let rawID = environment["CARDPILOT_UI_SESSION"],
              let session = UUID(uuidString: rawID) else { return nil }
        let directory = URL.temporaryDirectory.appendingPathComponent("CardPilotUITests/\(session.uuidString)", isDirectory: true)
        return BackupStore(directory: directory, openLegacy: {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("test.store")
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            let container = try CardPilotPersistence.makeContainer(at: url)
            if isNew && scenario == "core" { try seed(container.mainContext) }
            return container
        })
    }

    private static func seed(_ context: ModelContext) throws {
        let today = LocalDate(date: .now, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let bank = Bank(name: "UI Test Bank")
        let network = CardNetwork(code: "visa", displayName: "Visa", isBuiltIn: true)
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: today.monthKey)
        let rule = BillingRuleVersion(account: account, statementDay: 1, repaymentKind: .daysAfterStatement, repaymentValue: 20)
        let card = Card(account: account, productName: "UI Primary", networks: [network], lastFour: "1234")
        let sibling = Card(account: account, productName: "UI Shared", networks: [network], lastFour: "5678")
        let promotion = Promotion(
            title: "UI Spend", startOn: today.addingDays(-7).rawValue, endOn: today.addingDays(30).rawValue,
            eligibleCards: [card], qualificationThreshold: Decimal(1000), progressCurrencyCode: "CNY"
        )
        context.insert(bank)
        context.insert(network)
        context.insert(account)
        context.insert(rule)
        context.insert(card)
        context.insert(sibling)
        context.insert(promotion)
        try context.save()
    }
}
#endif
