import Foundation
import SwiftData

enum CreditCardAccountStatus: String, Codable, CaseIterable, Sendable {
    case active
    case closed
}

enum CardStatus: String, Codable, CaseIterable, Sendable {
    case active
    case inactive
}

enum RepaymentRuleKind: String, Codable, CaseIterable, Sendable {
    case fixedDay
    case daysAfterStatement
}

enum EnrollmentStatus: String, Codable, CaseIterable, Sendable {
    case notRequired
    case notEnrolled
    case enrolled
}

enum QualificationDateBasis: String, Codable, CaseIterable, Sendable {
    case transactionDate
    case postingDate
    case unknown
}

enum TransactionKind: String, Codable, CaseIterable, Sendable {
    case purchase
    case refund
}

enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case reversed
}

enum BankPresetRegion: String, Codable, CaseIterable, Hashable, Sendable {
    case mainland
    case hongKong
}

struct BankPreset: Identifiable, Equatable, Sendable {
    let code: String
    let displayName: String
    let englishName: String
    let region: BankPresetRegion
    let defaultCurrencyCode: String
    let searchableNames: [String]
    let monogram: String
    let sortOrder: Int

    var id: String { code }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return searchableNames.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static let catalog: [BankPreset] = [
        preset("cn.icbc", "工商银行", "Industrial and Commercial Bank of China", .mainland, "工", 0, "ICBC"),
        preset("cn.abc", "农业银行", "Agricultural Bank of China", .mainland, "农", 1, "ABC"),
        preset("cn.boc", "中国银行", "Bank of China", .mainland, "中", 2, "BOC"),
        preset("cn.ccb", "建设银行", "China Construction Bank", .mainland, "建", 3, "CCB"),
        preset("cn.bocom", "交通银行", "Bank of Communications", .mainland, "交", 4, "BOCOM"),
        preset("cn.psbc", "邮储银行", "Postal Savings Bank of China", .mainland, "邮", 5, "PSBC"),
        preset("cn.cmb", "招商银行", "China Merchants Bank", .mainland, "招", 6, "CMB"),
        preset("cn.citic", "中信银行", "China CITIC Bank", .mainland, "信", 7, "CITIC"),
        preset("cn.ceb", "光大银行", "China Everbright Bank", .mainland, "光", 8, "CEB"),
        preset("cn.cmbc", "民生银行", "China Minsheng Bank", .mainland, "民", 9, "CMBC"),
        preset("cn.spdb", "浦发银行", "Shanghai Pudong Development Bank", .mainland, "浦", 10, "SPDB"),
        preset("cn.cib", "兴业银行", "Industrial Bank", .mainland, "兴", 11, "CIB"),
        preset("cn.pingan", "平安银行", "Ping An Bank", .mainland, "平", 12, "PINGAN"),
        preset("cn.cgb", "广发银行", "China Guangfa Bank", .mainland, "广", 13, "CGB"),
        preset("cn.hxb", "华夏银行", "Hua Xia Bank", .mainland, "华", 14, "HXB"),
        preset("cn.czbank", "浙商银行", "China Zheshang Bank", .mainland, "浙", 15, "CZB"),
        preset("cn.hfbank", "恒丰银行", "Hengfeng Bank", .mainland, "恒", 16, "HFB"),
        preset("cn.cbhb", "渤海银行", "China Bohai Bank", .mainland, "渤", 17, "CBHB"),
        preset("hk.hsbc", "汇丰", "HSBC", .hongKong, "汇", 18),
        preset("hk.hangseng", "恒生", "Hang Seng Bank", .hongKong, "恒", 19),
        preset("hk.bochk", "中银香港", "Bank of China (Hong Kong)", .hongKong, "中", 20, "BOCHK"),
        preset("hk.scb", "渣打香港", "Standard Chartered Hong Kong", .hongKong, "渣", 21, "SCB"),
        preset("hk.bea", "东亚银行", "Bank of East Asia", .hongKong, "东", 22, "BEA"),
        preset("hk.citibank", "花旗香港", "Citibank Hong Kong", .hongKong, "花", 23, "CITIBANK"),
        preset("hk.dbs", "星展香港", "DBS Hong Kong", .hongKong, "星", 24, "DBS"),
        preset("hk.dahsing", "大新银行", "Dah Sing Bank", .hongKong, "大", 25, "DAHSING"),
        preset("hk.citicintl", "中信银行（国际）", "CITIC Bank International", .hongKong, "信", 26, "CITIC"),
        preset("hk.ccba", "建行亚洲", "China Construction Bank (Asia)", .hongKong, "建", 27, "CCBA"),
        preset("hk.icbcasia", "工银亚洲", "ICBC (Asia)", .hongKong, "工", 28, "ICBC")
    ]

    static var mainlandPresets: [BankPreset] { catalog.filter { $0.region == .mainland } }
    static var hongKongPresets: [BankPreset] { catalog.filter { $0.region == .hongKong } }

    private static func preset(
        _ code: String,
        _ displayName: String,
        _ englishName: String,
        _ region: BankPresetRegion,
        _ monogram: String,
        _ sortOrder: Int,
        _ abbreviation: String? = nil
    ) -> BankPreset {
        BankPreset(
            code: code,
            displayName: displayName,
            englishName: englishName,
            region: region,
            defaultCurrencyCode: region == .mainland ? "CNY" : "HKD",
            searchableNames: [displayName, englishName, code] + (abbreviation.map { [$0] } ?? []),
            monogram: monogram,
            sortOrder: sortOrder
        )
    }
}

enum ModelValidationError: Error, Equatable {
    case blankName
    case blankTitle
    case invalidCurrencyCode(String)
    case invalidCreditLimit
    case invalidAccountStatus
    case invalidLastFour
    case invalidStatementDay
    case invalidRepaymentValue
    case invalidCycleKey
    case invalidDate
    case invalidDateRange
    case invalidEnrollment
    case invalidTargetAmount
    case invalidNetworkCombination
    case invalidQualifyingAmount
    case invalidTransactionAmount
    case invalidTransactionRelationship
    case duplicateBillingRule
    case duplicateBillingCycle
    case duplicatePromotionAllocation
    case promotionCurrencyLocked
    case invalidPromotionSeries
    case missingAccountOwner
    case effectiveCycleMustBeFuture
}

func isValidCurrencyCode(_ code: String) -> Bool {
    code == code.uppercased() && Locale.Currency(code).isISOCurrency
}

private func hasText(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

@Model
final class Bank {
    var id: UUID
    var presetCode: String?
    var name: String
    var notes: String
    var archivedAt: Date?

    @Relationship(deleteRule: .deny, inverse: \CreditCardAccount.bank)
    var accounts: [CreditCardAccount] = []

    @Relationship(deleteRule: .deny, inverse: \Promotion.organizingBanks)
    var organizedPromotions: [Promotion] = []

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        archivedAt: Date? = nil,
        presetCode: String? = nil
    ) {
        self.id = id
        self.presetCode = presetCode
        self.name = name
        self.notes = notes
        self.archivedAt = archivedAt
    }

    func validate() throws {
        guard hasText(name) else { throw ModelValidationError.blankName }
    }
}

@Model
final class CardNetwork {
    static let builtInDefinitions: [(code: String, displayName: String, id: UUID)] = [
        ("unionpay", "银联", UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        ("visa", "Visa", UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
        ("mastercard", "Mastercard", UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
        ("amex", "American Express", UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
        ("jcb", "JCB", UUID(uuidString: "00000000-0000-0000-0000-000000000005")!)
    ]

    var id: UUID
    var code: String
    var displayName: String
    var isBuiltIn: Bool

    @Relationship(deleteRule: .deny, inverse: \Card.networks)
    var cards: [Card] = []

    @Relationship(deleteRule: .deny, inverse: \Promotion.organizingNetworks)
    var organizedPromotions: [Promotion] = []

    init(id: UUID = UUID(), code: String, displayName: String, isBuiltIn: Bool = false) {
        self.id = id
        self.code = code
        self.displayName = displayName
        self.isBuiltIn = isBuiltIn
    }

    static func makeBuiltIns() -> [CardNetwork] {
        builtInDefinitions.map { CardNetwork(id: $0.id, code: $0.code, displayName: $0.displayName, isBuiltIn: true) }
    }

    func validate() throws {
        guard hasText(code), hasText(displayName) else { throw ModelValidationError.blankName }
        if isBuiltIn {
            guard Self.builtInDefinitions.contains(where: { $0.id == id && $0.code == code }) else {
                throw ModelValidationError.invalidNetworkCombination
            }
        }
    }
}

@Model
final class CreditCardAccount {
    var id: UUID
    /// The nominal billing month from which this account participates in dashboard tracking.
    var trackingStartCycleKey: Int
    var creditLimit: Decimal?
    var limitCurrencyCode: String
    var statusRaw: String
    var closedOn: Int?
    var notes: String

    var bank: Bank

    @Relationship(deleteRule: .deny, inverse: \Card.account)
    var cards: [Card] = []

    @Relationship(deleteRule: .cascade, inverse: \BillingRuleVersion.account)
    var billingRuleVersions: [BillingRuleVersion] = []

    @Relationship(deleteRule: .cascade, inverse: \BillingCycleRecord.account)
    var billingCycles: [BillingCycleRecord] = []

    var status: CreditCardAccountStatus {
        get { CreditCardAccountStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        bank: Bank,
        trackingStartCycleKey: Int = LocalDate(date: Date(), timeZone: .current).monthKey,
        creditLimit: Decimal? = nil,
        limitCurrencyCode: String = "CNY",
        status: CreditCardAccountStatus = .active,
        closedOn: Int? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.trackingStartCycleKey = trackingStartCycleKey
        self.bank = bank
        self.creditLimit = creditLimit
        self.limitCurrencyCode = limitCurrencyCode
        self.statusRaw = status.rawValue
        self.closedOn = closedOn
        self.notes = notes
    }

    func close(on date: LocalDate) {
        status = .closed
        closedOn = date.rawValue
    }

    func validate() throws {
        guard LocalDate.isValidMonthKey(trackingStartCycleKey) else {
            throw ModelValidationError.invalidCycleKey
        }
        if let creditLimit, creditLimit <= .zero { throw ModelValidationError.invalidCreditLimit }
        guard isValidCurrencyCode(limitCurrencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(limitCurrencyCode)
        }
        guard let status = CreditCardAccountStatus(rawValue: statusRaw) else {
            throw ModelValidationError.invalidAccountStatus
        }
        switch status {
        case .active:
            guard closedOn == nil else { throw ModelValidationError.invalidAccountStatus }
        case .closed:
            guard let closedOn, (try? LocalDate(rawValue: closedOn)) != nil else {
                throw ModelValidationError.invalidAccountStatus
            }
        }
    }

    func validateBillingConfiguration() throws {
        try billingRuleVersions.forEach { try $0.validate() }
        guard billingRuleVersions.filter({ $0.effectiveCycleKey == nil }).count == 1 else {
            throw ModelValidationError.duplicateBillingRule
        }
        let versionKeys = billingRuleVersions.compactMap(\.effectiveCycleKey)
        guard Set(versionKeys).count == versionKeys.count else {
            throw ModelValidationError.duplicateBillingRule
        }
        let cycleKeys = billingCycles.map(\.cycleKey)
        guard Set(cycleKeys).count == cycleKeys.count else {
            throw ModelValidationError.duplicateBillingCycle
        }
        try billingCycles.forEach { try $0.validate() }
    }

    func validateNewBillingRuleEffectiveCycle(_ effectiveCycleKey: Int?, currentMonthKey: Int) throws {
        guard LocalDate.isValidMonthKey(currentMonthKey),
              let effectiveCycleKey,
              LocalDate.isValidMonthKey(effectiveCycleKey) else {
            throw ModelValidationError.invalidCycleKey
        }
        guard effectiveCycleKey > currentMonthKey else {
            throw ModelValidationError.effectiveCycleMustBeFuture
        }
    }
}

@Model
final class Card {
    var id: UUID
    var productName: String
    var nickname: String
    var lastFour: String
    var statusRaw: String
    var notes: String

    var account: CreditCardAccount

    var networks: [CardNetwork]

    @Relationship(deleteRule: .deny, inverse: \Transaction.card)
    var transactions: [Transaction] = []

    @Relationship(deleteRule: .deny, inverse: \Promotion.eligibleCards)
    var eligiblePromotions: [Promotion] = []

    var status: CardStatus {
        get { CardStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        account: CreditCardAccount,
        productName: String,
        nickname: String = "",
        networks: [CardNetwork],
        lastFour: String,
        status: CardStatus = .active,
        notes: String = ""
    ) {
        self.id = id
        self.account = account
        self.productName = productName
        self.nickname = nickname
        self.networks = networks
        self.lastFour = lastFour
        self.statusRaw = status.rawValue
        self.notes = notes
    }

    func validate() throws {
        guard hasText(productName) else { throw ModelValidationError.blankName }
        guard lastFour.utf8.count == 4,
              lastFour.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw ModelValidationError.invalidLastFour
        }
        guard CardStatus(rawValue: statusRaw) != nil else { throw ModelValidationError.invalidAccountStatus }
        guard (1...2).contains(networks.count),
              Set(networks.map(\.id)).count == networks.count else {
            throw ModelValidationError.invalidNetworkCombination
        }
        try networks.forEach { try $0.validate() }
        let codes = Set(networks.map(\.code))
        guard networks.count == 1 || (
            networks.allSatisfy { $0.isBuiltIn }
                && codes.count == 2
                && codes.contains("unionpay")
                && codes.intersection(Set(["visa", "mastercard", "jcb"])).count == 1
        ) else {
            throw ModelValidationError.invalidNetworkCombination
        }
    }
}

@Model
final class BillingRuleVersion {
    var id: UUID
    var effectiveCycleKey: Int?
    var statementDay: Int
    var repaymentKindRaw: String
    var repaymentValue: Int

    var account: CreditCardAccount?

    var repaymentKind: RepaymentRuleKind {
        get { RepaymentRuleKind(rawValue: repaymentKindRaw) ?? .fixedDay }
        set { repaymentKindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        account: CreditCardAccount,
        effectiveCycleKey: Int? = nil,
        statementDay: Int,
        repaymentKind: RepaymentRuleKind,
        repaymentValue: Int
    ) {
        self.id = id
        self.account = account
        self.effectiveCycleKey = effectiveCycleKey
        self.statementDay = statementDay
        self.repaymentKindRaw = repaymentKind.rawValue
        self.repaymentValue = repaymentValue
    }

    func validate() throws {
        guard account != nil else { throw ModelValidationError.missingAccountOwner }
        guard (1...31).contains(statementDay) else { throw ModelValidationError.invalidStatementDay }
        guard RepaymentRuleKind(rawValue: repaymentKindRaw) != nil else {
            throw ModelValidationError.invalidRepaymentValue
        }
        switch repaymentKind {
        case .fixedDay:
            guard (1...31).contains(repaymentValue) else { throw ModelValidationError.invalidRepaymentValue }
        case .daysAfterStatement:
            guard repaymentValue >= 1 else { throw ModelValidationError.invalidRepaymentValue }
        }
        if let effectiveCycleKey,
           !LocalDate.isValidMonthKey(effectiveCycleKey) {
            throw ModelValidationError.invalidCycleKey
        }
    }
}

@Model
final class BillingCycleRecord {
    var id: UUID
    var cycleKey: Int
    var statementDateOverride: Int?
    var repaymentDateOverride: Int?
    var repaidAt: Date?

    var account: CreditCardAccount?

    init(
        id: UUID = UUID(),
        account: CreditCardAccount,
        cycleKey: Int,
        statementDateOverride: Int? = nil,
        repaymentDateOverride: Int? = nil,
        repaidAt: Date? = nil
    ) {
        self.id = id
        self.account = account
        self.cycleKey = cycleKey
        self.statementDateOverride = statementDateOverride
        self.repaymentDateOverride = repaymentDateOverride
        self.repaidAt = repaidAt
    }

    func validate() throws {
        guard account != nil else { throw ModelValidationError.missingAccountOwner }
        guard LocalDate.isValidMonthKey(cycleKey) else { throw ModelValidationError.invalidCycleKey }
        if let statementDateOverride, (try? LocalDate(rawValue: statementDateOverride)) == nil {
            throw ModelValidationError.invalidDate
        }
        if let repaymentDateOverride, (try? LocalDate(rawValue: repaymentDateOverride)) == nil {
            throw ModelValidationError.invalidDate
        }
    }
}

@Model
final class Promotion {
    var id: UUID
    /// Promotions in one monthly series share an ID and keep their zero-based period index.
    /// A nil ID means this is a standalone promotion.
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
    var qualificationThreshold: Decimal?
    var qualifyingCap: Decimal?
    var perTransactionThreshold: Decimal?
    var progressCurrencyCode: String
    var rules: String
    var exclusions: String
    var rewardDescription: String
    var notes: String
    var archivedAt: Date?

    var organizingBanks: [Bank] = []

    var organizingNetworks: [CardNetwork] = []

    var eligibleCards: [Card] = []

    @Relationship(deleteRule: .deny, inverse: \PromotionAllocation.promotion)
    var allocations: [PromotionAllocation] = []

    var enrollmentStatus: EnrollmentStatus {
        get { EnrollmentStatus(rawValue: enrollmentStatusRaw) ?? .notRequired }
        set { enrollmentStatusRaw = newValue.rawValue }
    }

    var qualificationDateBasis: QualificationDateBasis {
        get { QualificationDateBasis(rawValue: qualificationDateBasisRaw) ?? .unknown }
        set { qualificationDateBasisRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        seriesID: UUID? = nil,
        seriesIndex: Int? = nil,
        title: String,
        startOn: Int,
        endOn: Int,
        organizingBanks: [Bank] = [],
        organizingNetworks: [CardNetwork] = [],
        eligibleCards: [Card] = [],
        enrollmentStatus: EnrollmentStatus = .notRequired,
        enrolledOn: Int? = nil,
        enrollmentDeadline: Int? = nil,
        qualificationDateBasis: QualificationDateBasis = .transactionDate,
        stackingAllowed: Bool = true,
        qualificationThreshold: Decimal? = nil,
        qualifyingCap: Decimal? = nil,
        perTransactionThreshold: Decimal? = nil,
        progressCurrencyCode: String,
        rules: String = "",
        exclusions: String = "",
        rewardDescription: String = "",
        notes: String = "",
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seriesIndex = seriesIndex
        self.title = title
        self.startOn = startOn
        self.endOn = endOn
        self.organizingBanks = organizingBanks
        self.organizingNetworks = organizingNetworks
        self.eligibleCards = eligibleCards
        self.enrollmentStatusRaw = enrollmentStatus.rawValue
        self.enrolledOn = enrolledOn
        self.enrollmentDeadline = enrollmentDeadline
        self.qualificationDateBasisRaw = qualificationDateBasis.rawValue
        self.stackingAllowed = stackingAllowed
        self.qualificationThreshold = qualificationThreshold
        self.qualifyingCap = qualifyingCap
        self.perTransactionThreshold = perTransactionThreshold
        self.progressCurrencyCode = progressCurrencyCode
        self.rules = rules
        self.exclusions = exclusions
        self.rewardDescription = rewardDescription
        self.notes = notes
        self.archivedAt = archivedAt
    }

    func validate() throws {
        guard (seriesID == nil && seriesIndex == nil)
                || (seriesID != nil && seriesIndex.map { $0 >= 0 } == true) else {
            throw ModelValidationError.invalidPromotionSeries
        }
        guard hasText(title) else { throw ModelValidationError.blankTitle }
        guard (try? LocalDate(rawValue: startOn)) != nil,
              (try? LocalDate(rawValue: endOn)) != nil else { throw ModelValidationError.invalidDate }
        guard startOn <= endOn else { throw ModelValidationError.invalidDateRange }
        guard isValidCurrencyCode(progressCurrencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(progressCurrencyCode)
        }
        for amount in [qualificationThreshold, qualifyingCap, perTransactionThreshold].compactMap(\.self) {
            guard amount > .zero else { throw ModelValidationError.invalidTargetAmount }
        }
        guard EnrollmentStatus(rawValue: enrollmentStatusRaw) != nil,
              QualificationDateBasis(rawValue: qualificationDateBasisRaw) != nil else {
            throw ModelValidationError.invalidEnrollment
        }
        if enrollmentStatus != .enrolled && enrolledOn != nil {
            throw ModelValidationError.invalidEnrollment
        }
        if enrollmentStatus == .notRequired && enrollmentDeadline != nil {
            throw ModelValidationError.invalidEnrollment
        }
        if let enrollmentDeadline {
            guard (try? LocalDate(rawValue: enrollmentDeadline)) != nil,
                  enrollmentDeadline <= endOn else { throw ModelValidationError.invalidEnrollment }
        }
        if let enrolledOn, (try? LocalDate(rawValue: enrolledOn)) == nil {
            throw ModelValidationError.invalidDate
        }
    }

    func setProgressCurrencyCode(_ code: String) throws {
        guard allocations.isEmpty || code == progressCurrencyCode else {
            throw ModelValidationError.promotionCurrencyLocked
        }
        guard isValidCurrencyCode(code) else { throw ModelValidationError.invalidCurrencyCode(code) }
        progressCurrencyCode = code
    }
}

@Model
final class Transaction {
    var id: UUID
    var kindRaw: String
    var transactionOn: Int
    var postingOn: Int?
    var amount: Decimal
    var currencyCode: String
    var merchant: String
    var category: String
    var notes: String
    var statusRaw: String

    var card: Card

    var originalTransaction: Transaction?

    @Relationship(deleteRule: .deny, inverse: \Transaction.originalTransaction)
    var refunds: [Transaction] = []

    @Relationship(deleteRule: .deny, inverse: \PromotionAllocation.transaction)
    var allocations: [PromotionAllocation] = []

    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .purchase }
        set { kindRaw = newValue.rawValue }
    }

    var status: TransactionStatus {
        get { TransactionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        card: Card,
        kind: TransactionKind = .purchase,
        transactionOn: Int,
        postingOn: Int? = nil,
        amount: Decimal,
        currencyCode: String,
        merchant: String,
        category: String = "",
        notes: String = "",
        originalTransaction: Transaction? = nil,
        status: TransactionStatus = .active
    ) {
        self.id = id
        self.card = card
        self.kindRaw = kind.rawValue
        self.transactionOn = transactionOn
        self.postingOn = postingOn
        self.amount = amount
        self.currencyCode = currencyCode
        self.merchant = merchant
        self.category = category
        self.notes = notes
        self.originalTransaction = originalTransaction
        self.statusRaw = status.rawValue
    }

    func reverse() {
        status = .reversed
    }

    func validate() throws {
        guard amount > .zero else { throw ModelValidationError.invalidTransactionAmount }
        guard isValidCurrencyCode(currencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(currencyCode)
        }
        guard (try? LocalDate(rawValue: transactionOn)) != nil else { throw ModelValidationError.invalidDate }
        if let postingOn, (try? LocalDate(rawValue: postingOn)) == nil {
            throw ModelValidationError.invalidDate
        }
        guard TransactionKind(rawValue: kindRaw) != nil,
              TransactionStatus(rawValue: statusRaw) != nil else {
            throw ModelValidationError.invalidTransactionRelationship
        }
        switch kind {
        case .purchase:
            guard originalTransaction == nil else { throw ModelValidationError.invalidTransactionRelationship }
        case .refund:
            if let originalTransaction {
                guard originalTransaction.kind == .purchase,
                      originalTransaction.card.id == card.id else {
                    throw ModelValidationError.invalidTransactionRelationship
                }
            }
        }
        guard refunds.allSatisfy({
            $0.kind == .refund
                && $0.originalTransaction?.id == id
                && $0.card.id == card.id
        }) else {
            throw ModelValidationError.invalidTransactionRelationship
        }
    }
}

@Model
final class PromotionAllocation {
    var id: UUID
    var qualifyingAmount: Decimal
    var currencyCode: String

    var transaction: Transaction

    var promotion: Promotion

    init(
        id: UUID = UUID(),
        transaction: Transaction,
        promotion: Promotion,
        qualifyingAmount: Decimal,
        currencyCode: String
    ) {
        self.id = id
        self.transaction = transaction
        self.promotion = promotion
        self.qualifyingAmount = qualifyingAmount
        self.currencyCode = currencyCode
    }

    func validate() throws {
        guard qualifyingAmount >= .zero else { throw ModelValidationError.invalidQualifyingAmount }
        guard isValidCurrencyCode(currencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(currencyCode)
        }
        guard currencyCode == promotion.progressCurrencyCode else {
            throw ModelValidationError.invalidCurrencyCode(currencyCode)
        }
        guard !transaction.allocations.contains(where: {
            $0.id != id && $0.promotion.id == promotion.id
        }) else {
            throw ModelValidationError.duplicatePromotionAllocation
        }
    }
}

enum CardPilotSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Bank.self,
            CardNetwork.self,
            CreditCardAccount.self,
            Card.self,
            BillingRuleVersion.self,
            BillingCycleRecord.self,
            Promotion.self,
            Transaction.self,
            PromotionAllocation.self
        ]
    }
}

enum CardPilotPersistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CardPilotSchemaV3.self)
        let configuration = ModelConfiguration(
            "CardPilotPrereleaseV3",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
