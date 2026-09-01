import Foundation

struct PromotionProgress: Equatable {
    let qualifiedAmount: Decimal
    let qualificationThreshold: Decimal?
    let qualifyingCap: Decimal?

    var remainingToThreshold: Decimal? {
        qualificationThreshold.map { max(.zero, $0 - qualifiedAmount) }
    }

    var remainingCap: Decimal? {
        qualifyingCap.map { max(.zero, $0 - qualifiedAmount) }
    }

    var isComplete: Bool {
        guard let qualificationThreshold else { return false }
        return qualifiedAmount >= qualificationThreshold
    }
}

enum PromotionCalculationError: Error, Equatable {
    case invalidTarget
    case currencyMismatch
}

enum PromotionCalculator {
    static func progress(
        qualificationThreshold: Decimal? = nil,
        qualifyingCap: Decimal? = nil,
        currencyCode: String,
        allocations: [(amount: Decimal, currencyCode: String, kind: TransactionKind, status: TransactionStatus)]
    ) throws -> PromotionProgress {
        guard [qualificationThreshold, qualifyingCap].compactMap(\.self).allSatisfy({ $0 > .zero }) else {
            throw PromotionCalculationError.invalidTarget
        }
        guard allocations.allSatisfy({ $0.currencyCode == currencyCode }) else {
            throw PromotionCalculationError.currencyMismatch
        }

        let total = allocations.reduce(Decimal.zero) { result, allocation in
            guard allocation.status == .active else { return result }
            return result + (allocation.kind == .refund ? -allocation.amount : allocation.amount)
        }
        return PromotionProgress(
            qualifiedAmount: total,
            qualificationThreshold: qualificationThreshold,
            qualifyingCap: qualifyingCap
        )
    }

    static func progress(for promotion: Promotion) throws -> PromotionProgress {
        try progress(
            qualificationThreshold: promotion.qualificationThreshold,
            qualifyingCap: promotion.qualifyingCap,
            currencyCode: promotion.progressCurrencyCode,
            allocations: promotion.allocations.map {
                ($0.qualifyingAmount, $0.currencyCode, $0.transaction.kind, $0.transaction.status)
            }
        )
    }

    static func suggestedQualifyingAmount(
        transactionAmount: Decimal,
        transactionCurrencyCode: String,
        promotionCurrencyCode: String,
        perTransactionThreshold: Decimal?,
        currentQualifiedAmount: Decimal,
        qualifyingCap: Decimal?
    ) -> Decimal? {
        guard transactionCurrencyCode == promotionCurrencyCode else { return nil }
        guard transactionAmount > .zero else { return .zero }
        if let perTransactionThreshold, transactionAmount < perTransactionThreshold {
            return .zero
        }
        guard let qualifyingCap else { return transactionAmount }
        return min(transactionAmount, max(.zero, qualifyingCap - currentQualifiedAmount))
    }

    static func overRefundedPromotionIDs(
        originalAllocations: [(promotionID: UUID, qualifyingAmount: Decimal)],
        refundAllocations: [(promotionID: UUID, qualifyingAmount: Decimal)],
        otherRefundAllocations: [(transactionID: UUID, promotionID: UUID, qualifyingAmount: Decimal, status: TransactionStatus)],
        excludingTransactionID: UUID?
    ) -> Set<UUID> {
        let originalAmounts = originalAllocations.reduce(into: [UUID: Decimal]()) { amounts, allocation in
            amounts[allocation.promotionID, default: .zero] += allocation.qualifyingAmount
        }
        let refundedAmounts = otherRefundAllocations.reduce(into: [UUID: Decimal]()) { amounts, allocation in
            guard allocation.status == .active,
                  allocation.transactionID != excludingTransactionID else { return }
            amounts[allocation.promotionID, default: .zero] += allocation.qualifyingAmount
        }
        let proposedAmounts = refundAllocations.reduce(into: [UUID: Decimal]()) { amounts, allocation in
            amounts[allocation.promotionID, default: .zero] += allocation.qualifyingAmount
        }
        return Set(proposedAmounts.compactMap { promotionID, proposedAmount in
            let balance = max(.zero, (originalAmounts[promotionID] ?? .zero)
                - (refundedAmounts[promotionID] ?? .zero))
            return proposedAmount > balance ? promotionID : nil
        })
    }

    static func refundExceedsOriginalAmount(
        originalAmount: Decimal,
        proposedRefundAmount: Decimal,
        otherRefunds: [(transactionID: UUID, amount: Decimal, status: TransactionStatus)],
        excludingTransactionID: UUID?
    ) -> Bool {
        let total = otherRefunds.reduce(proposedRefundAmount) { total, refund in
            guard refund.status == .active,
                  refund.transactionID != excludingTransactionID else { return total }
            return total + refund.amount
        }
        return total > originalAmount
    }

    static func includes(_ transaction: Transaction, in promotion: Promotion) -> Bool {
        let date: Int?
        switch promotion.qualificationDateBasis {
        case .transactionDate:
            date = transaction.transactionOn
        case .postingDate:
            date = transaction.postingOn
        case .unknown:
            date = transaction.postingOn.map { postingOn in
                (promotion.startOn...promotion.endOn).contains(postingOn) ? postingOn : transaction.transactionOn
            } ?? transaction.transactionOn
        }
        return transaction.status == .active
            && promotion.archivedAt == nil
            && promotion.eligibleCards.contains(where: { $0.id == transaction.card.id })
            && date.map { promotion.startOn <= $0 && $0 <= promotion.endOn } == true
    }
}
