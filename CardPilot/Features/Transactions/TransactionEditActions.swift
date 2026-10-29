import Foundation
import SwiftData
#if PERFORMANCE_TESTING && targetEnvironment(simulator)
import os
#endif

struct TransactionEditValues {
    var kind: TransactionKind
    var transactionOn: Int
    var postingOn: Int?
    var amount: Decimal
    var currencyCode: String
    var merchant: String
    var category: String
    var notes: String
    var status: TransactionStatus

    func validate() throws {
        guard amount > .zero else { throw ModelValidationError.invalidTransactionAmount }
        guard isValidCurrencyCode(currencyCode) else { throw ModelValidationError.invalidCurrencyCode(currencyCode) }
        _ = try LocalDate(rawValue: transactionOn)
        if let postingOn { _ = try LocalDate(rawValue: postingOn) }
    }

    func apply(to transaction: Transaction) {
        transaction.kind = kind
        transaction.transactionOn = transactionOn
        transaction.postingOn = postingOn
        transaction.amount = amount
        transaction.currencyCode = currencyCode
        transaction.merchant = merchant
        transaction.category = category
        transaction.notes = notes
        transaction.status = status
    }
}

@MainActor
enum TransactionEditActions {
    @discardableResult
    static func save(values: TransactionEditValues, transaction: Transaction?, newID: UUID, card: Card,
                     original: Transaction?, allocations: [(promotion: Promotion, amount: Decimal)],
                     context: ModelContext, persist: (ModelContext) throws -> Void = { try $0.save() }) throws -> Transaction {
        #if PERFORMANCE_TESTING && targetEnvironment(simulator)
        let signposter = PerformanceSignposts.transactions
        let interval = signposter.beginInterval("TransactionCommit", id: signposter.makeSignpostID())
        defer { signposter.endInterval("TransactionCommit", interval) }
        #endif
        // Validate values before managed relationships can insert any new objects.
        try values.validate()
        if let original {
            guard values.kind == .refund, original.kind == .purchase,
                  original.card.id == card.id, original.id != transaction?.id else {
                throw ModelValidationError.invalidTransactionRelationship
            }
        }
        if let transaction, !transaction.refunds.isEmpty,
           values.kind != .purchase || transaction.card.id != card.id {
            throw ModelValidationError.invalidTransactionRelationship
        }
        guard Set(allocations.map { $0.promotion.id }).count == allocations.count else {
            throw ModelValidationError.duplicatePromotionAllocation
        }
        for allocation in allocations {
            guard allocation.amount > .zero else { throw ModelValidationError.invalidQualifyingAmount }
            guard isValidCurrencyCode(allocation.promotion.progressCurrencyCode) else {
                throw ModelValidationError.invalidCurrencyCode(allocation.promotion.progressCurrencyCode)
            }
        }

        let previousValues = transaction.map {
            TransactionEditValues(kind: $0.kind, transactionOn: $0.transactionOn, postingOn: $0.postingOn,
                amount: $0.amount, currencyCode: $0.currencyCode, merchant: $0.merchant,
                category: $0.category, notes: $0.notes, status: $0.status)
        }
        let previousCard = transaction?.card
        let previousOriginal = transaction?.originalTransaction
        let previousAllocations = transaction?.allocations ?? []
        let allocationValues = previousAllocations.map { ($0, $0.qualifyingAmount, $0.currencyCode) }
        var insertedAllocations: [PromotionAllocation] = []
        let target = transaction ?? Transaction(id: newID, card: card, kind: values.kind,
            transactionOn: values.transactionOn, postingOn: values.postingOn, amount: values.amount,
            currencyCode: values.currencyCode, merchant: values.merchant, category: values.category,
            notes: values.notes, originalTransaction: original, status: values.status)
        do {
            target.card = card
            target.originalTransaction = original
            values.apply(to: target)
            try target.validate()
            if transaction == nil { context.insert(target) }
            let selectedIDs = Set(allocations.map { $0.promotion.id })
            for allocation in previousAllocations where !selectedIDs.contains(allocation.promotion.id) {
                // Deletion owns inverse cleanup; removing from the array first would
                // nullify the allocation's required transaction/promotion relationship.
                context.delete(allocation)
            }
            for item in allocations {
                if let allocation = previousAllocations.first(where: { $0.promotion.id == item.promotion.id }) {
                    allocation.qualifyingAmount = item.amount
                    allocation.currencyCode = item.promotion.progressCurrencyCode
                    try allocation.validate()
                } else {
                    let allocation = PromotionAllocation(transaction: target, promotion: item.promotion,
                        qualifyingAmount: item.amount, currencyCode: item.promotion.progressCurrencyCode)
                    insertedAllocations.append(allocation)
                    context.insert(allocation)
                    try allocation.validate()
                }
            }
            // Register this synchronous edit before either saving or an injected failure.
            context.processPendingChanges()
            try persist(context)
            return target
        } catch {
            context.processPendingChanges()
            // Remove only new objects, children first. Never nullify required inverses
            // by replacing a parent's array while those children are still live.
            for allocation in insertedAllocations { context.delete(allocation) }
            context.processPendingChanges()
            if transaction == nil {
                target.originalTransaction = nil
                context.delete(target)
            } else {
                previousValues?.apply(to: target)
                if let previousCard { target.card = previousCard }
                target.originalTransaction = previousOriginal
            }
            for (allocation, amount, currency) in allocationValues where !allocation.isDeleted {
                allocation.qualifyingAmount = amount
                allocation.currencyCode = currency
            }
            context.processPendingChanges()
            context.rollback()
            throw error
        }
    }
}
