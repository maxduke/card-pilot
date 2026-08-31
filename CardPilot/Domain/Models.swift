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
    case invalidQualifyingAmount
    case invalidTransactionAmount
    case invalidTransactionRelationship
    case duplicateBillingRule
    case duplicateBillingCycle
    case duplicatePromotionAllocation
    case promotionCurrencyLocked
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
    var name: String
    var notes: String
    var archivedAt: Date?

    @Relationship(deleteRule: .deny, inverse: \CreditCardAccount.bank)
    var accounts: [CreditCardAccount] = []

    @Relationship(deleteRule: .deny, inverse: \Promotion.organizingBanks)
    var organizedPromotions: [Promotion] = []

    init(id: UUID = UUID(), name: String, notes: String = "", archivedAt: Date? = nil) {
        self.id = id
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
        ("jcb", "JCB", UUID(uuidString: "00000000-0000-0000-0000-000000000005")!),
        ("other", "其他", UUID(uuidString: "00000000-0000-0000-0000-000000000006")!)
    ]

    var id: UUID
    var code: String
    var displayName: String
    var isBuiltIn: Bool

    @Relationship(deleteRule: .deny, inverse: \Card.network)
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

    var network: CardNetwork

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
        network: CardNetwork,
        lastFour: String,
        status: CardStatus = .active,
        notes: String = ""
    ) {
        self.id = id
        self.account = account
        self.productName = productName
        self.nickname = nickname
        self.network = network
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
    var title: String
    var startOn: Int
    var endOn: Int
    var enrollmentStatusRaw: String
    var enrolledOn: Int?
    var enrollmentDeadline: Int?
    var qualificationDateBasisRaw: String
    var stackingAllowed: Bool
    var targetAmount: Decimal
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
        targetAmount: Decimal,
        progressCurrencyCode: String,
        rules: String = "",
        exclusions: String = "",
        rewardDescription: String = "",
        notes: String = "",
        archivedAt: Date? = nil
    ) {
        self.id = id
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
        self.targetAmount = targetAmount
        self.progressCurrencyCode = progressCurrencyCode
        self.rules = rules
        self.exclusions = exclusions
        self.rewardDescription = rewardDescription
        self.notes = notes
        self.archivedAt = archivedAt
    }

    func validate() throws {
        guard hasText(title) else { throw ModelValidationError.blankTitle }
        guard (try? LocalDate(rawValue: startOn)) != nil,
              (try? LocalDate(rawValue: endOn)) != nil else { throw ModelValidationError.invalidDate }
        guard startOn <= endOn else { throw ModelValidationError.invalidDateRange }
        guard isValidCurrencyCode(progressCurrencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(progressCurrencyCode)
        }
        guard targetAmount > .zero else { throw ModelValidationError.invalidTargetAmount }
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

enum CardPilotSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

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
        let schema = Schema(versionedSchema: CardPilotSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
