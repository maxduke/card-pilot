import Foundation

struct PromotionProgress: Equatable {
    let qualifiedAmount: Decimal
    let qualificationThreshold: Decimal?
    let qualifyingCap: Decimal?
    let benefitTransactionCap: Int?
    let usedTransactionCount: Int

    init(
        qualifiedAmount: Decimal,
        qualificationThreshold: Decimal?,
        qualifyingCap: Decimal?,
        benefitTransactionCap: Int? = nil,
        usedTransactionCount: Int = 0
    ) {
        self.qualifiedAmount = qualifiedAmount
        self.qualificationThreshold = qualificationThreshold
        self.qualifyingCap = qualifyingCap
        self.benefitTransactionCap = benefitTransactionCap
        self.usedTransactionCount = usedTransactionCount
    }

    var remainingToThreshold: Decimal? {
        qualificationThreshold.map { max(.zero, $0 - qualifiedAmount) }
    }

    var remainingCap: Decimal? {
        qualifyingCap.map { max(.zero, $0 - qualifiedAmount) }
    }

    var remainingTransactionCount: Int? {
        benefitTransactionCap.map { max(0, $0 - usedTransactionCount) }
    }

    var isComplete: Bool {
        if let benefitTransactionCap {
            return usedTransactionCount >= benefitTransactionCap
        }
        guard let qualificationThreshold else { return false }
        return qualifiedAmount >= qualificationThreshold
    }
}

enum PromotionCalculationError: Error, Equatable {
    case invalidTarget
    case currencyMismatch
}

private struct PromotionAllocationInput {
    let transactionID: UUID?
    let amount: Decimal
    let currencyCode: String
    let kind: TransactionKind
    let status: TransactionStatus
}

enum PromotionCalculator {
    static func progress(
        qualificationThreshold: Decimal? = nil,
        qualifyingCap: Decimal? = nil,
        currencyCode: String,
        allocations: [(amount: Decimal, currencyCode: String, kind: TransactionKind, status: TransactionStatus)]
    ) throws -> PromotionProgress {
        try progress(
            qualificationThreshold: qualificationThreshold,
            qualifyingCap: qualifyingCap,
            currencyCode: currencyCode,
            allocations: allocations.map {
                PromotionAllocationInput(
                    transactionID: nil,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    kind: $0.kind,
                    status: $0.status
                )
            }
        )
    }

    static func progress(
        qualificationThreshold: Decimal? = nil,
        qualifyingCap: Decimal? = nil,
        benefitTransactionCap: Int,
        currencyCode: String,
        allocations: [(transactionID: UUID, amount: Decimal, currencyCode: String, kind: TransactionKind, status: TransactionStatus)]
    ) throws -> PromotionProgress {
        try progress(
            qualificationThreshold: qualificationThreshold,
            qualifyingCap: qualifyingCap,
            benefitTransactionCap: benefitTransactionCap,
            currencyCode: currencyCode,
            allocations: allocations.map {
                PromotionAllocationInput(
                    transactionID: $0.transactionID,
                    amount: $0.amount,
                    currencyCode: $0.currencyCode,
                    kind: $0.kind,
                    status: $0.status
                )
            }
        )
    }

    private static func progress(
        qualificationThreshold: Decimal?,
        qualifyingCap: Decimal?,
        benefitTransactionCap: Int? = nil,
        currencyCode: String,
        allocations: [PromotionAllocationInput]
    ) throws -> PromotionProgress {
        guard [qualificationThreshold, qualifyingCap].compactMap(\.self).allSatisfy({ $0 > .zero }) else {
            throw PromotionCalculationError.invalidTarget
        }
        guard benefitTransactionCap.map({ $0 > 0 }) ?? true,
              benefitTransactionCap == nil || (qualificationThreshold == nil && qualifyingCap == nil) else {
            throw PromotionCalculationError.invalidTarget
        }
        guard allocations.allSatisfy({ $0.currencyCode == currencyCode }) else {
            throw PromotionCalculationError.currencyMismatch
        }

        let total = allocations.reduce(Decimal.zero) { result, allocation in
            guard allocation.status == .active else { return result }
            return result + (allocation.kind == .refund ? -allocation.amount : allocation.amount)
        }
        let usedTransactionCount: Int
        if benefitTransactionCap == nil {
            usedTransactionCount = 0
        } else {
            usedTransactionCount = Set(allocations.compactMap { allocation in
                guard let transactionID = allocation.transactionID,
                      allocation.amount > .zero,
                      allocation.kind == .purchase,
                      allocation.status == .active else { return nil }
                return transactionID
            }).count
        }
        return PromotionProgress(
            qualifiedAmount: total,
            qualificationThreshold: qualificationThreshold,
            qualifyingCap: qualifyingCap,
            benefitTransactionCap: benefitTransactionCap,
            usedTransactionCount: usedTransactionCount
        )
    }

    static func progress(for promotion: Promotion) throws -> PromotionProgress {
        try progress(
            qualificationThreshold: promotion.qualificationThreshold,
            qualifyingCap: promotion.qualifyingCap,
            benefitTransactionCap: promotion.benefitTransactionCap,
            currencyCode: promotion.progressCurrencyCode,
            allocations: promotion.allocations.map {
                PromotionAllocationInput(
                    transactionID: $0.transaction.id,
                    amount: $0.qualifyingAmount,
                    currencyCode: $0.currencyCode,
                    kind: $0.transaction.kind,
                    status: $0.transaction.status
                )
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

    static func shouldAutomaticallySelect(
        _ promotion: Promotion,
        transactionAmount: Decimal,
        transactionCurrencyCode: String
    ) -> Bool {
        guard promotion.benefitTransactionCap == nil,
              let progress = try? progress(for: promotion),
              let suggestion = suggestedQualifyingAmount(
                  transactionAmount: transactionAmount,
                  transactionCurrencyCode: transactionCurrencyCode,
                  promotionCurrencyCode: promotion.progressCurrencyCode,
                  perTransactionThreshold: promotion.perTransactionThreshold,
                  currentQualifiedAmount: progress.qualifiedAmount,
                  qualifyingCap: promotion.qualifyingCap
              ) else { return false }
        return suggestion > .zero
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
