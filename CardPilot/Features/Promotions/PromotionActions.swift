import SwiftData
import SwiftUI

@MainActor
struct PromotionRelationshipSnapshot {
    private let banks: [(Bank, [Promotion])]
    private let networks: [(CardNetwork, [Promotion])]
    private let cards: [(Card, [Promotion])]

    init(promotions: [Promotion], banks: [Bank] = [], networks: [CardNetwork] = [], cards: [Card] = [],
         excluding excludedIDs: Set<UUID> = []) {
        var bankIDs = Set<UUID>()
        var networkIDs = Set<UUID>()
        var cardIDs = Set<UUID>()
        self.banks = (banks + promotions.flatMap(\.organizingBanks))
            .filter { bankIDs.insert($0.id).inserted }
            .map { ($0, $0.organizedPromotions.filter { !excludedIDs.contains($0.id) }) }
        self.networks = (networks + promotions.flatMap(\.organizingNetworks))
            .filter { networkIDs.insert($0.id).inserted }
            .map { ($0, $0.organizedPromotions.filter { !excludedIDs.contains($0.id) }) }
        self.cards = (cards + promotions.flatMap(\.eligibleCards))
            .filter { cardIDs.insert($0.id).inserted }
            .map { ($0, $0.eligiblePromotions.filter { !excludedIDs.contains($0.id) }) }
    }

    func restore() {
        for (bank, promotions) in banks { bank.organizedPromotions = promotions }
        for (network, promotions) in networks { network.organizedPromotions = promotions }
        for (card, promotions) in cards { card.eligiblePromotions = promotions }
    }
}

@MainActor
struct PromotionEditSnapshot {
    private let restoreValues: (Promotion) -> Void

    init(_ promotion: Promotion) {
        let title = promotion.title
        let startOn = promotion.startOn
        let endOn = promotion.endOn
        let banks = promotion.organizingBanks
        let networks = promotion.organizingNetworks
        let cards = promotion.eligibleCards
        let status = promotion.enrollmentStatus
        let enrolledOn = promotion.enrolledOn
        let deadline = promotion.enrollmentDeadline
        let basis = promotion.qualificationDateBasis
        let stacking = promotion.stackingAllowed
        let threshold = promotion.qualificationThreshold
        let cap = promotion.qualifyingCap
        let perTransactionThreshold = promotion.perTransactionThreshold
        let benefitCap = promotion.benefitTransactionCap
        let currency = promotion.progressCurrencyCode
        let rules = promotion.rules
        let exclusions = promotion.exclusions
        let reward = promotion.rewardDescription
        let notes = promotion.notes
        let archivedAt = promotion.archivedAt
        restoreValues = { target in
            target.title = title
            target.startOn = startOn
            target.endOn = endOn
            target.organizingBanks = banks
            target.organizingNetworks = networks
            target.eligibleCards = cards
            target.enrollmentStatus = status
            target.enrolledOn = enrolledOn
            target.enrollmentDeadline = deadline
            target.qualificationDateBasis = basis
            target.stackingAllowed = stacking
            target.qualificationThreshold = threshold
            target.qualifyingCap = cap
            target.perTransactionThreshold = perTransactionThreshold
            target.benefitTransactionCap = benefitCap
            target.progressCurrencyCode = currency
            target.rules = rules
            target.exclusions = exclusions
            target.rewardDescription = reward
            target.notes = notes
            target.archivedAt = archivedAt
        }
    }

    func restore(_ promotion: Promotion) { restoreValues(promotion) }
}

@MainActor
enum PromotionCreationActions {
    static func save(_ promotions: [Promotion], context: ModelContext,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let relationships = PromotionRelationshipSnapshot(promotions: promotions, excluding: Set(promotions.map(\.id)))
        do {
            try promotions.forEach { try $0.validate() }
            promotions.forEach { context.insert($0) }
            try persist(context)
        } catch {
            // Relationships can insert a new model before insert() is called explicitly.
            for promotion in promotions {
                promotion.organizingBanks = []
                promotion.organizingNetworks = []
                promotion.eligibleCards = []
            }
            relationships.restore()
            context.rollback()
            throw error
        }
    }
}

@MainActor
enum PromotionArchiveActions {
    static func setArchived(_ archived: Bool, for promotion: Promotion, context: ModelContext,
                            now: Date = Date(),
                            persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        let previous = promotion.archivedAt
        promotion.archivedAt = archived ? (previous ?? now) : nil
        context.processPendingChanges()
        do {
            try persist(context)
        } catch {
            promotion.archivedAt = previous
            context.processPendingChanges()
            context.rollback()
            throw error
        }
    }
}

@MainActor
enum PromotionAllocationActions {
    static func save(_ amount: Decimal, transaction: Transaction, promotion: Promotion,
                     allocation: PromotionAllocation?, context: ModelContext,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        guard amount > .zero else { throw ModelValidationError.invalidQualifyingAmount }
        guard isValidCurrencyCode(promotion.progressCurrencyCode) else {
            throw ModelValidationError.invalidCurrencyCode(promotion.progressCurrencyCode)
        }
        if let allocation,
           allocation.transaction.id != transaction.id || allocation.promotion.id != promotion.id {
            throw ModelValidationError.invalidTransactionRelationship
        }
        guard !transaction.allocations.contains(where: {
            $0.id != allocation?.id && $0.promotion.id == promotion.id
        }) else { throw ModelValidationError.duplicatePromotionAllocation }
        let previousAmount = allocation?.qualifyingAmount
        let previousCurrency = allocation?.currencyCode
        let target = allocation ?? PromotionAllocation(transaction: transaction, promotion: promotion,
                                                        qualifyingAmount: amount, currencyCode: promotion.progressCurrencyCode)
        do {
            target.qualifyingAmount = amount
            target.currencyCode = promotion.progressCurrencyCode
            try target.validate()
            if allocation == nil { context.insert(target) }
            // Register this synchronous edit before either saving or an injected failure.
            context.processPendingChanges()
            try persist(context)
        } catch {
            context.processPendingChanges()
            if allocation == nil {
                context.delete(target)
            } else {
                if let previousAmount { target.qualifyingAmount = previousAmount }
                if let previousCurrency { target.currencyCode = previousCurrency }
            }
            context.processPendingChanges()
            context.rollback()
            throw error
        }
    }
}
