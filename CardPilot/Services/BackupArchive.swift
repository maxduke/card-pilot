import Foundation
import SwiftData

/// Version 1 is independent of the SwiftData schema. Never encode model objects directly.
struct BackupArchive: Codable, Equatable, Sendable {
    var format = "CardPilotBackup"
    var version = 1
    var exportedAt = Date()
    var records: BackupRecords

    static let maximumFileSize = 50 * 1_024 * 1_024

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumFileSize else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        guard data.count <= maximumFileSize else { throw BackupError.tooLarge }
        struct Header: Decodable { let format: String; let version: Int }
        do {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.format == "CardPilotBackup" else { throw BackupError.invalidFile }
            guard header.version == 1 else { throw BackupError.unsupportedVersion }
            let archive = try JSONDecoder().decode(Self.self, from: data)
            guard archive.exportedAt.timeIntervalSince1970.isFinite,
                  (-62_135_596_800...253_402_300_799).contains(archive.exportedAt.timeIntervalSince1970) else {
                throw BackupError.invalidData
            }
            return archive
        } catch let error as BackupError { throw error }
        catch { throw BackupError.invalidFile }
    }
}

enum BackupError: LocalizedError {
    case generatedHistoryTooLarge
    case invalidModelData(String)
    case operationInProgress
    case invalidFile, unsupportedVersion, tooLarge, duplicateID, invalidReference
    case invalidDecimal, conflict, invalidData, verificationFailed, storageFailure, unsavedChanges

    var errorDescription: String? {
        switch self {
        case .generatedHistoryTooLarge: return "备份会生成过多账期，超出可安全处理的范围。当前数据未被替换。"
        case .invalidModelData(let category): return "备份中的\(category)不符合数据约束。"
        case .operationInProgress: return "正在处理另一项备份操作，请稍后重试。"
        case .invalidFile: return "这不是完整的 CardPilot 备份，或文件已经损坏。"
        case .unsupportedVersion: return "此备份版本暂不支持，请使用兼容的 CardPilot 版本。"
        case .tooLarge: return "备份超过 50 MB 或 100,000 条记录的处理上限。"
        case .duplicateID: return "备份包含重复 ID，未恢复任何数据。"
        case .invalidReference: return "备份包含缺失或重复的关系引用，未恢复任何数据。"
        case .invalidDecimal: return "备份金额格式无效或超出精确表示范围。"
        case .conflict: return "备份包含冲突的银行、卡组织、账期、规则、系列或分配记录。"
        case .invalidData: return "备份中的日期、金额、状态或其他字段不符合数据约束。"
        case .verificationFailed: return "新存储核对失败，当前数据未被替换。"
        case .storageFailure: return "无法保存恢复数据或恢复前备份。请检查设备可用空间后重试，原存储仍保留。"
        case .unsavedChanges: return "仍有未保存的修改，请先保存或取消编辑后再备份或恢复。"
        }
    }
}

/// Decimal strings must be lossless canonical base-10 values, never JSON floating-point numbers.
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

    func canonicalized() -> BackupRecords {
        var result = self
        result.banks.sort { $0.id.uuidString < $1.id.uuidString }
        result.networks.sort { $0.id.uuidString < $1.id.uuidString }
        result.accounts.sort { $0.id.uuidString < $1.id.uuidString }
        result.cards = cards.map { record in
            var record = record
            record.networks.sort { $0.uuidString < $1.uuidString }
            return record
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        result.billingRules.sort { $0.id.uuidString < $1.id.uuidString }
        result.billingCycles.sort { $0.id.uuidString < $1.id.uuidString }
        result.promotions = promotions.map { record in
            var record = record
            record.organizingBanks.sort { $0.uuidString < $1.uuidString }
            record.organizingNetworks.sort { $0.uuidString < $1.uuidString }
            record.eligibleCards.sort { $0.uuidString < $1.uuidString }
            return record
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        result.transactions.sort { $0.id.uuidString < $1.id.uuidString }
        result.allocations.sort { $0.id.uuidString < $1.id.uuidString }
        return result
    }

    static let maximumGeneratedBillingCycles = 20_000

    /// Bound derived work as well as file size. Dashboard history and notification
    /// lookback must not expand a small archive into millions of account-months.
    func validateGeneratedHistory(through lastMonthKey: Int) throws {
        func monthIndex(_ key: Int) throws -> Int {
            guard LocalDate.isValidMonthKey(key) else { throw BackupError.invalidData }
            return key / 100 * 12 + key % 100 - 1
        }
        let lastMonth = try monthIndex(lastMonthKey)
        var lookbackByAccount: [UUID: Int] = [:]
        for rule in billingRules where rule.repaymentKindRaw == RepaymentRuleKind.daysAfterStatement.rawValue {
            guard (1...36_600).contains(rule.repaymentValue) else { throw BackupError.invalidData }
            let months = (rule.repaymentValue + 27) / 28
            lookbackByAccount[rule.account] = max(lookbackByAccount[rule.account] ?? 1, months)
        }
        var generated = billingCycles.filter { $0.repaidAt == nil }.count
        guard generated <= Self.maximumGeneratedBillingCycles else { throw BackupError.generatedHistoryTooLarge }
        for account in accounts {
            let firstMonth = try monthIndex(account.trackingStartCycleKey)
            // Reserve the maximum device reminder horizon too (365 days).
            generated += max(0, lastMonth - firstMonth + 1) + (lookbackByAccount[account.id] ?? 1) + 15
            guard generated <= Self.maximumGeneratedBillingCycles else { throw BackupError.generatedHistoryTooLarge }
        }
    }

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
                benefitTransactionCap: model.benefitTransactionCap,
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

    func insertIntoEmptyStore(_ context: ModelContext) throws {
        guard try Self.capture(context).count == 0 else { throw BackupError.conflict }
        try validateStructure()
        func reference<T>(_ id: UUID, in objects: [UUID: T]) throws -> T {
            guard let value = objects[id] else { throw BackupError.invalidReference }
            return value
        }
        var banksByID: [UUID: Bank] = [:]
        for record in banks {
            let model = Bank(
                id: record.id,
                name: record.name,
                notes: record.notes,
                archivedAt: record.archivedAt,
                presetCode: record.presetCode
            )
            context.insert(model)
            banksByID[record.id] = model
        }
        var networksByID: [UUID: CardNetwork] = [:]
        for record in networks {
            let model = CardNetwork(
                id: record.id, code: record.code, displayName: record.displayName, isBuiltIn: record.isBuiltIn
            )
            context.insert(model)
            networksByID[record.id] = model
        }
        var accountsByID: [UUID: CreditCardAccount] = [:]
        for record in accounts {
            let model = CreditCardAccount(
                id: record.id,
                bank: try reference(record.bank, in: banksByID),
                trackingStartCycleKey: record.trackingStartCycleKey,
                creditLimit: record.creditLimit?.value,
                limitCurrencyCode: record.limitCurrencyCode,
                closedOn: record.closedOn,
                notes: record.notes
            )
            model.statusRaw = record.statusRaw
            context.insert(model)
            accountsByID[record.id] = model
        }
        var cardsByID: [UUID: Card] = [:]
        for record in cards {
            let model = Card(
                id: record.id,
                account: try reference(record.account, in: accountsByID),
                productName: record.productName,
                nickname: record.nickname,
                networks: try record.networks.map { try reference($0, in: networksByID) },
                lastFour: record.lastFour,
                notes: record.notes
            )
            model.statusRaw = record.statusRaw
            context.insert(model)
            cardsByID[record.id] = model
        }
        var billingRulesByID: [UUID: BillingRuleVersion] = [:]
        for record in billingRules {
            let model = BillingRuleVersion(
                id: record.id,
                account: try reference(record.account, in: accountsByID),
                effectiveCycleKey: record.effectiveCycleKey,
                statementDay: record.statementDay,
                repaymentKind: .fixedDay,
                repaymentValue: record.repaymentValue
            )
            model.repaymentKindRaw = record.repaymentKindRaw
            context.insert(model)
            billingRulesByID[record.id] = model
        }
        var billingCyclesByID: [UUID: BillingCycleRecord] = [:]
        for record in billingCycles {
            let model = BillingCycleRecord(
                id: record.id,
                account: try reference(record.account, in: accountsByID),
                cycleKey: record.cycleKey,
                statementDateOverride: record.statementDateOverride,
                repaymentDateOverride: record.repaymentDateOverride,
                repaidAt: record.repaidAt
            )
            context.insert(model)
            billingCyclesByID[record.id] = model
        }
        var promotionsByID: [UUID: Promotion] = [:]
        for record in promotions {
            let model = Promotion(
                id: record.id,
                seriesID: record.seriesID,
                seriesIndex: record.seriesIndex,
                title: record.title,
                startOn: record.startOn,
                endOn: record.endOn,
                organizingBanks: try record.organizingBanks.map { try reference($0, in: banksByID) },
                organizingNetworks: try record.organizingNetworks.map { try reference($0, in: networksByID) },
                eligibleCards: try record.eligibleCards.map { try reference($0, in: cardsByID) },
                enrolledOn: record.enrolledOn,
                enrollmentDeadline: record.enrollmentDeadline,
                stackingAllowed: record.stackingAllowed,
                qualificationThreshold: record.qualificationThreshold?.value,
                qualifyingCap: record.qualifyingCap?.value,
                perTransactionThreshold: record.perTransactionThreshold?.value,
                benefitTransactionCap: record.benefitTransactionCap,
                progressCurrencyCode: record.progressCurrencyCode,
                rules: record.rules,
                exclusions: record.exclusions,
                rewardDescription: record.rewardDescription,
                notes: record.notes,
                archivedAt: record.archivedAt
            )
            model.enrollmentStatusRaw = record.enrollmentStatusRaw
            model.qualificationDateBasisRaw = record.qualificationDateBasisRaw
            context.insert(model)
            promotionsByID[record.id] = model
        }
        var transactionsByID: [UUID: Transaction] = [:]
        for record in transactions {
            let model = Transaction(
                id: record.id,
                card: try reference(record.card, in: cardsByID),
                transactionOn: record.transactionOn,
                postingOn: record.postingOn,
                amount: record.amount.value,
                currencyCode: record.currencyCode,
                merchant: record.merchant,
                category: record.category,
                notes: record.notes
            )
            model.kindRaw = record.kindRaw
            model.statusRaw = record.statusRaw
            context.insert(model)
            transactionsByID[record.id] = model
        }
        for record in transactions {
            if let originalID = record.originalTransaction {
                transactionsByID[record.id]?.originalTransaction = try reference(originalID, in: transactionsByID)
            }
        }
        var allocationsByID: [UUID: PromotionAllocation] = [:]
        for record in allocations {
            let model = PromotionAllocation(
                id: record.id,
                transaction: try reference(record.transaction, in: transactionsByID),
                promotion: try reference(record.promotion, in: promotionsByID),
                qualifyingAmount: record.qualifyingAmount.value,
                currencyCode: record.currencyCode
            )
            context.insert(model)
            allocationsByID[record.id] = model
        }
        // Establish many-to-many relationships after every object is registered.
        // Inserting later related objects can otherwise replace a transient inverse.
        for record in cards {
            cardsByID[record.id]?.networks = try record.networks.map { try reference($0, in: networksByID) }
        }
        for record in promotions {
            let model = try reference(record.id, in: promotionsByID)
            model.organizingBanks = try record.organizingBanks.map { try reference($0, in: banksByID) }
            model.organizingNetworks = try record.organizingNetworks.map { try reference($0, in: networksByID) }
            model.eligibleCards = try record.eligibleCards.map { try reference($0, in: cardsByID) }
        }
        // SwiftData does not consistently materialize inverse collections during
        // insertion. Domain validation reads these collections before the save.
        let rulesByAccount = Dictionary(grouping: billingRules, by: \.account)
        let cyclesByAccount = Dictionary(grouping: billingCycles, by: \.account)
        for (id, account) in accountsByID {
            account.billingRuleVersions = (rulesByAccount[id] ?? []).compactMap { billingRulesByID[$0.id] }
            account.billingCycles = (cyclesByAccount[id] ?? []).compactMap { billingCyclesByID[$0.id] }
        }
        func validate(_ category: String, _ action: () throws -> Void) throws {
            do { try action() }
            catch {
                // These descriptions contain no imported values; keep failures actionable.
                switch error as? ModelValidationError {
                case .invalidNetworkCombination: throw BackupError.invalidModelData(category + "（卡组织组合）")
                case .invalidLastFour: throw BackupError.invalidModelData(category + "（末四位）")
                case .invalidAccountStatus: throw BackupError.invalidModelData(category + "（状态）")
                case .blankName: throw BackupError.invalidModelData(category + "（名称）")
                default: throw BackupError.invalidModelData(category)
                }
            }
        }
        try validate("银行") { try banksByID.values.forEach { try $0.validate() } }
        try validate("卡组织") { try networksByID.values.forEach { try $0.validate() } }
        try validate("账户") { try accountsByID.values.forEach { try $0.validate() } }
        try validate("卡片") { try cardsByID.values.forEach { try $0.validate() } }
        try validate("账务规则") { try billingRulesByID.values.forEach { try $0.validate() } }
        try validate("账期") { try billingCyclesByID.values.forEach { try $0.validate() } }
        try validate("促销") { try promotionsByID.values.forEach { try $0.validate() } }
        try validate("交易") { try transactionsByID.values.forEach { try $0.validate() } }
        try validate("促销分配") { try allocationsByID.values.forEach { try $0.validate() } }
        try validate("账户账务配置") { try accountsByID.values.forEach { try $0.validateBillingConfiguration() } }
        // Explicit historical cycles may be far outside the current dashboard window.
        // Reject dates that would require calendar arithmetic beyond LocalDate's supported years.
        let utc = TimeZone(secondsFromGMT: 0)!
        let sortedRules = rulesByAccount.mapValues { $0.sorted { ($0.effectiveCycleKey ?? 0) < ($1.effectiveCycleKey ?? 0) } }
        for (accountID, cycles) in cyclesByAccount {
            guard let rules = sortedRules[accountID], !rules.isEmpty else { throw BackupError.invalidData }
            var ruleIndex = 0
            for record in cycles.sorted(by: { $0.cycleKey < $1.cycleKey }) {
                while ruleIndex + 1 < rules.count, (rules[ruleIndex + 1].effectiveCycleKey ?? 0) <= record.cycleKey {
                    ruleIndex += 1
                }
                let rule = rules[ruleIndex]
                let month = try LocalDate.firstDay(ofMonthKey: record.cycleKey)
                let statement = try record.statementDateOverride.map { try LocalDate(rawValue: $0) }
                    ?? LocalDate(year: month.year, month: month.month, day: min(rule.statementDay, LocalDate.daysInMonth(year: month.year, month: month.month, timeZone: utc)))
                if rule.repaymentKindRaw == RepaymentRuleKind.fixedDay.rawValue {
                    let day = min(rule.repaymentValue, LocalDate.daysInMonth(year: statement.year, month: statement.month, timeZone: utc))
                    if day <= statement.day, statement.addingMonthsIfPossible(1, timeZone: utc) == nil {
                        throw BackupError.invalidData
                    }
                } else {
                    guard let date = LocalDate.calendar(timeZone: utc).date(byAdding: .day, value: rule.repaymentValue, to: statement.date(in: utc)),
                          (try? LocalDate(rawValue: LocalDate(date: date, timeZone: utc).rawValue)) != nil else {
                        throw BackupError.invalidData
                    }
                }
            }
        }
    }

    func validatedContainer() throws -> ModelContainer {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try insertIntoEmptyStore(context)
        try context.save()
        return container
    }

    private func validateStructure() throws {
        guard count <= 100_000 else { throw BackupError.tooLarge }
        var ids = Set<UUID>()
        for record in banks {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in networks {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in accounts {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in cards {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in billingRules {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in billingCycles {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in promotions {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in transactions {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        for record in allocations {
            guard ids.insert(record.id).inserted else { throw BackupError.duplicateID }
        }
        func unique<T: Hashable>(_ values: [T]) throws {
            guard Set(values).count == values.count else { throw BackupError.conflict }
        }
        func references(_ values: [UUID], in targets: Set<UUID>) throws {
            guard Set(values).count == values.count, values.allSatisfy(targets.contains) else {
                throw BackupError.invalidReference
            }
        }
        try unique(banks.compactMap(\.presetCode))
        try unique(networks.map(\.code))
        try unique(billingRules.map { "\($0.account):\($0.effectiveCycleKey ?? 0)" })
        try unique(billingCycles.map { "\($0.account):\($0.cycleKey)" })
        try unique(allocations.map { "\($0.transaction):\($0.promotion)" })
        try unique(promotions.compactMap { record -> String? in
            record.seriesID.map { "\($0):\(record.seriesIndex ?? -1)" }
        })
        let bankIDs = Set(banks.map(\.id))
        let networkIDs = Set(networks.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        for card in cards { try references(card.networks, in: networkIDs) }
        for promotion in promotions {
            try references(promotion.organizingBanks, in: bankIDs)
            try references(promotion.organizingNetworks, in: networkIDs)
            try references(promotion.eligibleCards, in: cardIDs)
        }
        let eventDates = banks.compactMap(\.archivedAt) + promotions.compactMap(\.archivedAt) + billingCycles.compactMap(\.repaidAt)
        guard eventDates.allSatisfy({
            $0.timeIntervalSince1970.isFinite && (-62_135_596_800...253_402_300_799).contains($0.timeIntervalSince1970)
        }) else { throw BackupError.invalidData }
        // Bound imported arithmetic before it reaches calendar/reminder generation.
        guard billingRules.allSatisfy({ (1...36_600).contains($0.repaymentValue) }) else {
            throw BackupError.invalidData
        }
        guard promotions.allSatisfy({ $0.seriesIndex.map { (0..<120_000).contains($0) } ?? true }) else {
            throw BackupError.invalidData
        }
        let utc = TimeZone(secondsFromGMT: 0)!
        let lastVisibleMonth = LocalDate(date: .now, timeZone: utc).addingMonths(3, timeZone: utc).monthKey
        try validateGeneratedHistory(through: lastVisibleMonth)
        for network in networks where !network.isBuiltIn {
            guard !CardNetwork.builtInDefinitions.contains(where: { $0.code == network.code || $0.id == network.id }) else {
                throw BackupError.conflict
            }
        }
    }
}
