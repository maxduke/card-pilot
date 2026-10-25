import CryptoKit
import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import CardPilot

/// Diagnostic only: compile this file against the immutable v0.1.7 application.
@MainActor
final class ReleaseV017FixtureGenerator: XCTestCase {
    func testGenerateReleaseFixture() throws {
        let files = FileManager.default
        let work = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = URL.temporaryDirectory.appendingPathComponent("CardPilotReleaseFixture-v0.1.7", isDirectory: true)
        XCTAssertFalse(files.fileExists(atPath: output.path), "Never overwrite an earlier fixture")
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        try files.createDirectory(at: output, withIntermediateDirectories: false)

        let source = try CardPilotPersistence.makeContainer(at: work.appendingPathComponent("source.store"))
        try populate(source.mainContext)
        let records = try BackupRecords.capture(ModelContext(source))
        let validated = try records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(ModelContext(validated)), records)
        XCTAssertEqual(records.count, 25)

        let storeURL = output.appendingPathComponent("CardPilot-v0.1.7.store")
        try snapshot(from: work.appendingPathComponent("source.store"), to: storeURL)
        // Verify a separate copy, keeping the exported snapshot unopened for mutation.
        let verificationURL = work.appendingPathComponent("verification.store")
        try files.copyItem(at: storeURL, to: verificationURL)
        let reopened = try CardPilotPersistence.makeContainer(at: verificationURL)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(reopened)), records)

        var archive = BackupArchive(records: records)
        archive.exportedAt = Date(timeIntervalSince1970: 1_788_888_888.123456)
        let archiveURL = output.appendingPathComponent("CardPilot-v0.1.7.backup.json")
        try archive.encoded().write(to: archiveURL, options: .atomic)
        XCTAssertEqual(try BackupArchive.decode(Data(contentsOf: archiveURL)), archive)

        let card = try XCTUnwrap(records.cards.first { $0.productName == "共享卡" })
        let promotion = try XCTUnwrap(records.promotions.first { $0.seriesIndex == 1 })
        let draft = TransactionDraft(
            cardID: card.id, kind: .purchase, transactionOn: 20250903, postingOn: 20250904,
            hasPostingDate: true, amountText: "1,234.", currencyCode: "HKD",
            merchant: "尚未提交的商户", category: "日用", notes: "保留未完成金额与手动计入输入",
            status: .active, originalTransactionID: UUID(), selectedPromotionIDs: [promotion.id],
            allocationAmounts: [promotion.id: "50.125"], promotionCurrencies: [promotion.id: "HKD"],
            automaticallySelectedPromotionIDs: [], manuallyDeselectedPromotionIDs: [],
            manuallyEditedAllocationIDs: [promotion.id], editorStep: 1,
            showingInactiveCards: true, showingOtherFields: true
        )
        let drafts = TransactionDraftStore(databaseURL: storeURL)
        try drafts.save(draft)
        XCTAssertEqual(try drafts.load(), draft)
        XCTAssertEqual(draft.version, 1)

        let counts = [
            "banks": records.banks.count, "networks": records.networks.count,
            "accounts": records.accounts.count, "cards": records.cards.count,
            "billingRules": records.billingRules.count, "billingCycles": records.billingCycles.count,
            "promotions": records.promotions.count, "transactions": records.transactions.count,
            "allocations": records.allocations.count
        ]
        let exportedFiles = try [storeURL, archiveURL, drafts.url].map { url -> [String: Any] in
            let data = try Data(contentsOf: url)
            return ["name": url.lastPathComponent, "bytes": data.count,
                    "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        let manifest: [String: Any] = [
            "releaseTag": "v0.1.7", "releaseRevision": "437d303261ec40ed5a7fb7313d2d910da351779f",
            "schemaVersion": "3.0.0", "configurationName": "CardPilotPrereleaseV3",
            "backupVersion": archive.version, "draftVersion": draft.version,
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "counts": counts, "files": exportedFiles,
            "origin": "Synthetic data generated with release source, not a user's database or an old device"
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        withExtendedLifetime(source) {}
        print("RELEASE_FIXTURE_OUTPUT=\(output.path)")
    }

    private func populate(_ context: ModelContext) throws {
        context.autosaveEnabled = false
        let event = Date(timeIntervalSince1970: 1_788_888_888.123456)
        let bank = Bank(name: "历史银行", notes: "银行备注", archivedAt: event, presetCode: "cn.icbc")
        context.insert(bank)
        let networks = CardNetwork.makeBuiltIns()
        networks.forEach(context.insert)
        let custom = CardNetwork(code: "custom", displayName: "自定义组织")
        context.insert(custom)
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202401,
            creditLimit: Decimal(string: "12345678901234567890.123456789")!,
            limitCurrencyCode: "HKD", notes: "共享账户")
        let closed = CreditCardAccount(bank: bank, trackingStartCycleKey: 202401,
            status: .closed, closedOn: 20250830, notes: "已关闭")
        context.insert(account)
        context.insert(closed)
        let card = Card(account: account, productName: "双标历史卡", nickname: "旧卡",
            networks: [networks[0], networks[1]], lastFour: "1234", status: .inactive, notes: "卡备注")
        let shared = Card(account: account, productName: "共享卡", networks: [networks[2]], lastFour: "5678")
        let closedCard = Card(account: closed, productName: "已关闭账户的卡", networks: [custom],
            lastFour: "9012", status: .inactive)
        context.insert(card)
        context.insert(shared)
        context.insert(closedCard)
        for (owner, effective, day) in [(account, nil as Int?, 5), (account, 202501, 8),
                                       (account, 202701, 10), (closed, nil, 20)] {
            context.insert(BillingRuleVersion(account: owner, effectiveCycleKey: effective,
                statementDay: day, repaymentKind: .daysAfterStatement, repaymentValue: 20))
        }
        context.insert(BillingCycleRecord(account: account, cycleKey: 202508,
            statementDateOverride: 20250809, repaymentDateOverride: 20250901, repaidAt: event))
        context.insert(BillingCycleRecord(account: closed, cycleKey: 202507))
        let series = UUID()
        let promotion = Promotion(seriesID: series, seriesIndex: 0, title: "历史促销",
            startOn: 20250801, endOn: 20250831, organizingBanks: [bank], organizingNetworks: [networks[0]],
            eligibleCards: [card, shared], enrollmentStatus: .enrolled, enrolledOn: 20250802,
            enrollmentDeadline: 20250810, qualificationDateBasis: .postingDate, stackingAllowed: false,
            qualificationThreshold: 100, qualifyingCap: 200, perTransactionThreshold: 10,
            progressCurrencyCode: "HKD", rules: "规则", exclusions: "排除", rewardDescription: "奖励",
            notes: "活动备注", archivedAt: event)
        context.insert(promotion)
        context.insert(Promotion(seriesID: series, seriesIndex: 1, title: "下一期", startOn: 20250901,
            endOn: 20250930, eligibleCards: [shared], benefitTransactionCap: 3, progressCurrencyCode: "HKD"))
        let purchase = Transaction(card: card, transactionOn: 20250803, postingOn: 20250804,
            amount: Decimal(string: "12345678901234567890.123456789")!, currencyCode: "HKD",
            merchant: "商户", category: "分类", notes: "交易备注")
        context.insert(purchase)
        let refund = Transaction(card: card, kind: .refund, transactionOn: 20250902,
            amount: Decimal(string: "0.0000000000000000000000000001")!, currencyCode: "HKD",
            merchant: "部分退款商户", originalTransaction: purchase)
        context.insert(refund)
        context.insert(Transaction(card: shared, transactionOn: 20250805, amount: Decimal(string: "88.88")!,
            currencyCode: "HKD", merchant: "已撤销商户", status: .reversed))
        context.insert(PromotionAllocation(transaction: purchase, promotion: promotion,
            qualifyingAmount: Decimal(string: "50.123456789")!, currencyCode: "HKD"))
        context.insert(PromotionAllocation(transaction: refund, promotion: promotion,
            qualifyingAmount: Decimal(string: "0.01")!, currencyCode: "HKD"))
        try context.save()
    }

    /// SQLite's backup API includes committed WAL contents in one consistent snapshot.
    private func snapshot(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        defer {
            if let source { sqlite3_close(source) }
            if let destination { sqlite3_close(destination) }
        }
        func require(_ result: Int32, _ expected: Int32 = SQLITE_OK) throws {
            guard result == expected else {
                throw NSError(domain: "ReleaseFixtureSQLite", code: Int(result))
            }
        }
        try require(sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil))
        try require(sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil))
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw NSError(domain: "ReleaseFixtureSQLite", code: Int(sqlite3_errcode(destination)))
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        try require(step, SQLITE_DONE)
        try require(finish)
    }
}
