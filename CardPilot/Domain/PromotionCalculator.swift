import Foundation

struct PromotionProgress: Equatable {
    let qualifiedAmount: Decimal
    let targetAmount: Decimal

    var remainingAmount: Decimal { max(.zero, targetAmount - qualifiedAmount) }
    var isComplete: Bool { qualifiedAmount >= targetAmount }
}

enum PromotionCalculationError: Error, Equatable {
    case invalidTarget
    case currencyMismatch
}

enum PromotionCalculator {
    static func progress(
        targetAmount: Decimal,
        currencyCode: String,
        allocations: [(amount: Decimal, currencyCode: String, kind: TransactionKind, status: TransactionStatus)]
    ) throws -> PromotionProgress {
        guard targetAmount > .zero else { throw PromotionCalculationError.invalidTarget }
        guard allocations.allSatisfy({ $0.currencyCode == currencyCode }) else {
            throw PromotionCalculationError.currencyMismatch
        }

        let total = allocations.reduce(Decimal.zero) { result, allocation in
            guard allocation.status == .active else { return result }
            return result + (allocation.kind == .refund ? -allocation.amount : allocation.amount)
        }
        return PromotionProgress(qualifiedAmount: total, targetAmount: targetAmount)
    }

    static func progress(for promotion: Promotion) throws -> PromotionProgress {
        try progress(
            targetAmount: promotion.targetAmount,
            currencyCode: promotion.progressCurrencyCode,
            allocations: promotion.allocations.map {
                ($0.qualifyingAmount, $0.currencyCode, $0.transaction.kind, $0.transaction.status)
            }
        )
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
