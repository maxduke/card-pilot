import CryptoKit
import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import CardPilot

/// Diagnostic only: frozen v0.1.3 models, including the historically valid zero allocation.
@MainActor
final class ReleaseEarlyV3FixtureGenerator: XCTestCase {
    func testGenerateReleaseFixture() throws {
        let files = FileManager.default
        let work = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = URL.temporaryDirectory.appendingPathComponent("CardPilotReleaseFixture-v0.1.3", isDirectory: true)
        XCTAssertFalse(files.fileExists(atPath: output.path), "Never overwrite an earlier fixture")
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        try files.createDirectory(at: output, withIntermediateDirectories: false)
        let sourceURL = work.appendingPathComponent("source.store")
        let source = try container(at: sourceURL)
        try populate(source.mainContext)
        let records = try BackupRecords.capture(ModelContext(source))
        XCTAssertEqual(records.count, 27)
        XCTAssertEqual(records.allocations.filter { $0.qualifyingAmount.value == .zero }.count, 1)
        let storeURL = output.appendingPathComponent("CardPilot-v0.1.3.store")
        try snapshot(from: sourceURL, to: storeURL)
        let verificationURL = work.appendingPathComponent("verification.store")
        try files.copyItem(at: storeURL, to: verificationURL)
        let reopened = try container(at: verificationURL)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(reopened)), records)
        let expectedURL = output.appendingPathComponent("CardPilot-v0.1.3.expected-records.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let expected = try encoder.encode(records)
        try expected.write(to: expectedURL, options: .atomic)
        XCTAssertEqual(try JSONDecoder().decode(BackupRecords.self, from: expected), records)
        let counts = [
            "banks": records.banks.count, "networks": records.networks.count,
            "accounts": records.accounts.count, "cards": records.cards.count,
            "billingRules": records.billingRules.count, "billingCycles": records.billingCycles.count,
            "promotions": records.promotions.count, "transactions": records.transactions.count,
            "allocations": records.allocations.count
        ]
        let exported = try [storeURL, expectedURL].map { url -> [String: Any] in
            let data = try Data(contentsOf: url)
            return ["name": url.lastPathComponent, "bytes": data.count,
                    "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]
        }
        let manifest: [String: Any] = [
            "releaseTag": "v0.1.3", "releaseRevision": "3553b38c19dbb38004d201bdfa7600648b35e6ee",
            "schemaVersion": "3.0.0", "configurationName": "CardPilotPrereleaseV3",
            "operatingSystem": ProcessInfo.processInfo.operatingSystemVersionString,
            "counts": counts, "files": exported,
            "expectedRecordsFormat": "Diagnostic JSON of all native saved fields; not an old backup export",
            "origin": "Synthetic data generated using immutable release models, not a user or old device database"
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
            .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        withExtendedLifetime(source) {}
        print("RELEASE_FIXTURE_OUTPUT=\(output.path)")
    }

    /// Same frozen schema and configuration name, with an isolated test URL.
    private func container(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CardPilotSchemaV3.self)
        let configuration = ModelConfiguration("CardPilotPrereleaseV3", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
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
            endOn: 20250930, eligibleCards: [shared], progressCurrencyCode: "HKD"))
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
        let zeroPurchase = Transaction(card: shared, transactionOn: 20250806, amount: Decimal(string: "7.5")!,
            currencyCode: "HKD", merchant: "零计入历史商户")
        context.insert(zeroPurchase)
        let zeroAllocation = PromotionAllocation(transaction: zeroPurchase, promotion: promotion,
            qualifyingAmount: .zero, currencyCode: "HKD")
        context.insert(zeroAllocation)
        // Both the released model and released editor allowed this persisted fact.
        try zeroAllocation.validate()
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

// Diagnostic serializer only. No new models or archive/import behavior enter the released application.
// The field map follows the current expected-records shape; absent newer optional fields stay nil.
enum BackupError: Error { case invalidDecimal, unsavedChanges, invalidReference }

struct BackupDecimal: Codable, Equatable, Sendable {
    let value: Decimal

    init(_ value: Decimal) { self.value = value }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard text.count <= 170,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, NSDecimalNumber(decimal: value).stringValue == text else {
            throw BackupError.invalidDecimal
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        guard !value.isNaN else { throw BackupError.invalidDecimal }
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: value).stringValue)
    }
}

struct BackupRecords: Codable, Equatable, Sendable {
    var banks: [BankRecord] = []
    var networks: [CardNetworkRecord] = []
    var accounts: [CreditCardAccountRecord] = []
    var cards: [CardRecord] = []
    var billingRules: [BillingRuleVersionRecord] = []
    var billingCycles: [BillingCycleRecordRecord] = []
    var promotions: [PromotionRecord] = []
    var transactions: [TransactionRecord] = []
    var allocations: [PromotionAllocationRecord] = []
    var count: Int { banks.count + networks.count + accounts.count + cards.count + billingRules.count + billingCycles.count + promotions.count + transactions.count + allocations.count }

    struct BankRecord: Codable, Equatable, Sendable {
        var id: UUID
        var presetCode: String?
        var name: String
        var notes: String
        var archivedAt: Date?
    }

    struct CardNetworkRecord: Codable, Equatable, Sendable {
        var id: UUID
        var code: String
        var displayName: String
        var isBuiltIn: Bool
    }

    struct CreditCardAccountRecord: Codable, Equatable, Sendable {
        var id: UUID
        var trackingStartCycleKey: Int
        var creditLimit: BackupDecimal?
        var limitCurrencyCode: String
        var statusRaw: String
        var closedOn: Int?
        var notes: String
        var bank: UUID
        var customName: String? = nil
    }

    struct CardRecord: Codable, Equatable, Sendable {
        var id: UUID
        var productName: String
        var nickname: String
        var lastFour: String
        var statusRaw: String
        var notes: String
        var account: UUID
        var networks: [UUID]
    }

    struct BillingRuleVersionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var effectiveCycleKey: Int?
        var statementDay: Int
        var repaymentKindRaw: String
        var repaymentValue: Int
        var account: UUID
    }

    struct BillingCycleRecordRecord: Codable, Equatable, Sendable {
        var id: UUID
        var cycleKey: Int
        var statementDateOverride: Int?
        var repaymentDateOverride: Int?
        var repaidAt: Date?
        var account: UUID
    }

    struct PromotionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var seriesID: UUID?
        var seriesIndex: Int?
        var title: String
        var startOn: Int
        var endOn: Int
        var enrollmentStatusRaw: String
        var enrolledOn: Int?
        var enrollmentDeadline: Int?
        var qualificationDateBasisRaw: String
        var stackingAllowed: Bool
        var qualificationThreshold: BackupDecimal?
        var qualifyingCap: BackupDecimal?
        var perTransactionThreshold: BackupDecimal?
        var benefitTransactionCap: Int?
        var progressCurrencyCode: String
        var rules: String
        var exclusions: String
        var rewardDescription: String
        var notes: String
        var archivedAt: Date?
        var organizingBanks: [UUID]
        var organizingNetworks: [UUID]
        var eligibleCards: [UUID]
    }

    struct TransactionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var kindRaw: String
        var transactionOn: Int
        var postingOn: Int?
        var amount: BackupDecimal
        var currencyCode: String
        var merchant: String
        var category: String
        var notes: String
        var statusRaw: String
        var card: UUID
        var originalTransaction: UUID?
    }

    struct PromotionAllocationRecord: Codable, Equatable, Sendable {
        var id: UUID
        var qualifyingAmount: BackupDecimal
        var currencyCode: String
        var transaction: UUID
        var promotion: UUID
    }

}

extension BackupRecords {
    static func capture(_ context: ModelContext) throws -> BackupRecords {
        guard !context.hasChanges else { throw BackupError.unsavedChanges }
        var result = BackupRecords()
        result.banks = try context.fetch(FetchDescriptor<Bank>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return BankRecord(
                id: model.id,
                presetCode: model.presetCode,
                name: model.name,
                notes: model.notes,
                archivedAt: model.archivedAt
            )
        }
        result.networks = try context.fetch(FetchDescriptor<CardNetwork>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return CardNetworkRecord(
                id: model.id,
                code: model.code,
                displayName: model.displayName,
                isBuiltIn: model.isBuiltIn
            )
        }
        result.accounts = try context.fetch(FetchDescriptor<CreditCardAccount>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return CreditCardAccountRecord(
                id: model.id,
                trackingStartCycleKey: model.trackingStartCycleKey,
                creditLimit: model.creditLimit.map(BackupDecimal.init),
                limitCurrencyCode: model.limitCurrencyCode,
                statusRaw: model.statusRaw,
                closedOn: model.closedOn,
                notes: model.notes,
                bank: model.bank.id
            )
        }
        result.cards = try context.fetch(FetchDescriptor<Card>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return CardRecord(
                id: model.id,
                productName: model.productName,
                nickname: model.nickname,
                lastFour: model.lastFour,
                statusRaw: model.statusRaw,
                notes: model.notes,
                account: model.account.id,
                networks: model.networks.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
        result.billingRules = try context.fetch(FetchDescriptor<BillingRuleVersion>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            guard let accountID = model.account?.id else { throw BackupError.invalidReference }
            return BillingRuleVersionRecord(
                id: model.id,
                effectiveCycleKey: model.effectiveCycleKey,
                statementDay: model.statementDay,
                repaymentKindRaw: model.repaymentKindRaw,
                repaymentValue: model.repaymentValue,
                account: accountID
            )
        }
        result.billingCycles = try context.fetch(FetchDescriptor<BillingCycleRecord>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            guard let accountID = model.account?.id else { throw BackupError.invalidReference }
            return BillingCycleRecordRecord(
                id: model.id,
                cycleKey: model.cycleKey,
                statementDateOverride: model.statementDateOverride,
                repaymentDateOverride: model.repaymentDateOverride,
                repaidAt: model.repaidAt,
                account: accountID
            )
        }
        result.promotions = try context.fetch(FetchDescriptor<Promotion>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return PromotionRecord(
                id: model.id,
                seriesID: model.seriesID,
                seriesIndex: model.seriesIndex,
                title: model.title,
                startOn: model.startOn,
                endOn: model.endOn,
                enrollmentStatusRaw: model.enrollmentStatusRaw,
                enrolledOn: model.enrolledOn,
                enrollmentDeadline: model.enrollmentDeadline,
                qualificationDateBasisRaw: model.qualificationDateBasisRaw,
                stackingAllowed: model.stackingAllowed,
                qualificationThreshold: model.qualificationThreshold.map(BackupDecimal.init),
                qualifyingCap: model.qualifyingCap.map(BackupDecimal.init),
                perTransactionThreshold: model.perTransactionThreshold.map(BackupDecimal.init),
                benefitTransactionCap: nil,
                progressCurrencyCode: model.progressCurrencyCode,
                rules: model.rules,
                exclusions: model.exclusions,
                rewardDescription: model.rewardDescription,
                notes: model.notes,
                archivedAt: model.archivedAt,
                organizingBanks: model.organizingBanks.map(\.id).sorted { $0.uuidString < $1.uuidString },
                organizingNetworks: model.organizingNetworks.map(\.id).sorted { $0.uuidString < $1.uuidString },
                eligibleCards: model.eligibleCards.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
        result.transactions = try context.fetch(FetchDescriptor<Transaction>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return TransactionRecord(
                id: model.id,
                kindRaw: model.kindRaw,
                transactionOn: model.transactionOn,
                postingOn: model.postingOn,
                amount: BackupDecimal(model.amount),
                currencyCode: model.currencyCode,
                merchant: model.merchant,
                category: model.category,
                notes: model.notes,
                statusRaw: model.statusRaw,
                card: model.card.id,
                originalTransaction: model.originalTransaction?.id
            )
        }
        result.allocations = try context.fetch(FetchDescriptor<PromotionAllocation>()).sorted { $0.id.uuidString < $1.id.uuidString }.map { model in
            return PromotionAllocationRecord(
                id: model.id,
                qualifyingAmount: BackupDecimal(model.qualifyingAmount),
                currencyCode: model.currencyCode,
                transaction: model.transaction.id,
                promotion: model.promotion.id
            )
        }
        return result
    }

}
