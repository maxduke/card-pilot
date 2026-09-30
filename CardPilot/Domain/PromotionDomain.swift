import Foundation

struct PromotionPeriod: Equatable, Sendable {
    let startOn: Int
    let endOn: Int
}

enum PromotionSeriesEditScope: String, CaseIterable, Hashable, Sendable {
    case thisOnly
    case thisAndFuture
}

struct PromotionCardRecommendation: Identifiable, Equatable {
    let card: Card
    let reasons: [String]

    var id: UUID { card.id }

    static func == (lhs: PromotionCardRecommendation, rhs: PromotionCardRecommendation) -> Bool {
        lhs.card.id == rhs.card.id && lhs.reasons == rhs.reasons
    }
}

enum PromotionEligibility {
    /// Recommends active cards matching the selected organizer dimensions.
    /// Organizers in each dimension are a union; bank and network dimensions intersect.
    static func recommendations(
        organizingBanks: [Bank],
        organizingNetworks: [CardNetwork],
        cards: [Card]
    ) -> [PromotionCardRecommendation] {
        guard !organizingBanks.isEmpty || !organizingNetworks.isEmpty else { return [] }

        let bankIDs = Set(organizingBanks.map(\.id))
        let networkIDs = Set(organizingNetworks.map(\.id))
        return cards
            .filter { card in
                guard card.status == .active, card.account.status == .active else { return false }
                let bankMatches = bankIDs.isEmpty || bankIDs.contains(card.account.bank.id)
                let networkMatches = networkIDs.isEmpty || card.networks.contains { networkIDs.contains($0.id) }
                return bankMatches && networkMatches
            }
            .map { card in
                var reasons: [String] = []
                if !bankIDs.isEmpty, let bank = organizingBanks.first(where: { $0.id == card.account.bank.id }) {
                    reasons.append("银行：\(bank.name)")
                }
                if !networkIDs.isEmpty {
                    reasons.append(contentsOf: card.networks
                        .filter { networkIDs.contains($0.id) }
                        .map { "卡组织：\($0.displayName)" })
                }
                return PromotionCardRecommendation(card: card, reasons: reasons)
            }
            .sorted { lhs, rhs in
                let lhsBank = lhs.card.account.bank.name
                let rhsBank = rhs.card.account.bank.name
                if lhsBank != rhsBank {
                    return lhsBank.localizedCaseInsensitiveCompare(rhsBank) == .orderedAscending
                }
                let lhsName = lhs.card.nickname.isEmpty ? lhs.card.productName : lhs.card.nickname
                let rhsName = rhs.card.nickname.isEmpty ? rhs.card.productName : rhs.card.nickname
                if lhsName != rhsName {
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                if lhs.card.lastFour != rhs.card.lastFour { return lhs.card.lastFour < rhs.card.lastFour }
                return lhs.card.id.uuidString < rhs.card.id.uuidString
            }
    }
}

struct PromotionPeriodState: Equatable {
    let enrollmentStatus: EnrollmentStatus
    let enrolledOn: Int?
    let enrollmentDeadline: Int?
    let archivedAt: Date?
}

enum PromotionSeriesCalculator {
    /// Builds complete monthly periods from the original date anchors; each period is calculated
    /// from offset 0, so a clamped February date never drifts subsequent periods.
    static func monthlyPeriods(startOn: Int, endOn: Int, through repeatUntil: Int) -> [PromotionPeriod] {
        guard let start = try? LocalDate(rawValue: startOn),
              let end = try? LocalDate(rawValue: endOn),
              let until = try? LocalDate(rawValue: repeatUntil),
              startOn <= endOn,
              endOn <= repeatUntil else { return [] }

        let startMonthIndex = start.year * 12 + start.month
        let untilMonthIndex = until.year * 12 + until.month
        guard untilMonthIndex >= startMonthIndex else { return [] }

        return (0...(untilMonthIndex - startMonthIndex)).compactMap { offset in
            guard let shiftedStart = start.addingMonthsIfPossible(offset),
                  let shiftedEnd = end.addingMonthsIfPossible(offset),
                  shiftedEnd.rawValue <= repeatUntil else { return nil }
            return PromotionPeriod(startOn: shiftedStart.rawValue, endOn: shiftedEnd.rawValue)
        }
    }

    static func shiftedDate(_ rawValue: Int, byMonths months: Int) -> Int? {
        guard let date = try? LocalDate(rawValue: rawValue) else { return nil }
        return date.addingMonthsIfPossible(months)?.rawValue
    }

    /// Shared rules may change across a series, but enrollment and archiving are period facts.
    static func editedPeriodState(
        for period: Promotion,
        editing selected: Promotion,
        enrollmentStatus: EnrollmentStatus,
        enrolledOn: Int?,
        enrollmentDeadline: Int?,
        archived: Bool,
        now: Date = Date()
    ) -> PromotionPeriodState {
        let isSelected = period.id == selected.id
        let status = isSelected ? enrollmentStatus : period.enrollmentStatus
        let offset = (period.seriesIndex ?? 0) - (selected.seriesIndex ?? 0)
        let deadline = enrollmentDeadline.flatMap { shiftedDate($0, byMonths: offset) }
        return PromotionPeriodState(
            enrollmentStatus: status,
            enrolledOn: isSelected ? (status == .enrolled ? enrolledOn : nil) : period.enrolledOn,
            enrollmentDeadline: status == .notRequired ? nil : deadline,
            archivedAt: isSelected ? (archived ? (period.archivedAt ?? now) : nil) : period.archivedAt
        )
    }

    static func editablePeriods(
        in promotions: [Promotion],
        from target: Promotion,
        today: Int
    ) -> [Promotion] {
        guard let seriesID = target.seriesID,
              let seriesIndex = target.seriesIndex else { return [target] }
        let targets = promotions
            .filter {
                $0.id != target.id
                    && $0.seriesID == seriesID
                    && ($0.seriesIndex ?? -1) >= seriesIndex
                    && $0.endOn >= today
            }
        return ([target] + targets)
            .sorted { ($0.seriesIndex ?? Int.max) < ($1.seriesIndex ?? Int.max) }
    }
}

extension Promotion {
    func copiedToNextMonth() -> Promotion? {
        guard let startOn = PromotionSeriesCalculator.shiftedDate(startOn, byMonths: 1),
              let endOn = PromotionSeriesCalculator.shiftedDate(endOn, byMonths: 1) else { return nil }
        return Promotion(
            title: title,
            startOn: startOn,
            endOn: endOn,
            organizingBanks: organizingBanks,
            organizingNetworks: organizingNetworks,
            eligibleCards: eligibleCards,
            enrollmentStatus: enrollmentStatus == .notRequired ? .notRequired : .notEnrolled,
            enrolledOn: nil,
            enrollmentDeadline: enrollmentDeadline.flatMap { PromotionSeriesCalculator.shiftedDate($0, byMonths: 1) },
            qualificationDateBasis: qualificationDateBasis,
            stackingAllowed: stackingAllowed,
            qualificationThreshold: qualificationThreshold,
            qualifyingCap: qualifyingCap,
            perTransactionThreshold: perTransactionThreshold,
            benefitTransactionCap: benefitTransactionCap,
            progressCurrencyCode: progressCurrencyCode,
            rules: rules,
            exclusions: exclusions,
            rewardDescription: rewardDescription,
            notes: notes
        )
    }

    /// Consumes the new first period instead of leaving a related, throwaway model in SwiftData.
    static func makeMonthlySeries(startingWith firstPeriod: Promotion, through repeatUntil: Int) -> [Promotion] {
        let periods = PromotionSeriesCalculator.monthlyPeriods(
            startOn: firstPeriod.startOn,
            endOn: firstPeriod.endOn,
            through: repeatUntil
        )
        guard !periods.isEmpty else { return [] }
        let seriesID = UUID()
        firstPeriod.seriesID = seriesID
        firstPeriod.seriesIndex = 0
        return periods.enumerated().map { index, period in
            if index == 0 { return firstPeriod }
            return Promotion(
                seriesID: seriesID,
                seriesIndex: index,
                title: firstPeriod.title,
                startOn: period.startOn,
                endOn: period.endOn,
                organizingBanks: firstPeriod.organizingBanks,
                organizingNetworks: firstPeriod.organizingNetworks,
                eligibleCards: firstPeriod.eligibleCards,
                enrollmentStatus: firstPeriod.enrollmentStatus == .notRequired ? .notRequired : .notEnrolled,
                enrolledOn: nil,
                enrollmentDeadline: firstPeriod.enrollmentDeadline.flatMap { PromotionSeriesCalculator.shiftedDate($0, byMonths: index) },
                qualificationDateBasis: firstPeriod.qualificationDateBasis,
                stackingAllowed: firstPeriod.stackingAllowed,
                qualificationThreshold: firstPeriod.qualificationThreshold,
                qualifyingCap: firstPeriod.qualifyingCap,
                perTransactionThreshold: firstPeriod.perTransactionThreshold,
                benefitTransactionCap: firstPeriod.benefitTransactionCap,
                progressCurrencyCode: firstPeriod.progressCurrencyCode,
                rules: firstPeriod.rules,
                exclusions: firstPeriod.exclusions,
                rewardDescription: firstPeriod.rewardDescription,
                notes: firstPeriod.notes,
                archivedAt: firstPeriod.archivedAt
            )
        }
    }
}

enum PromotionAllocationSelection {
    static func availableTransactions(
        _ transactions: [Transaction],
        for promotion: Promotion,
        editing allocation: PromotionAllocation? = nil
    ) -> [Transaction] {
        let allocatedIDs = Set(promotion.allocations.filter { $0.id != allocation?.id }.map(\.transaction.id))
        return transactions
            .filter { !allocatedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsRecommended = PromotionCalculator.includes(lhs, in: promotion)
                let rhsRecommended = PromotionCalculator.includes(rhs, in: promotion)
                if lhsRecommended != rhsRecommended { return lhsRecommended }
                if lhs.transactionOn != rhs.transactionOn { return lhs.transactionOn > rhs.transactionOn }
                let merchantOrder = lhs.merchant.localizedCaseInsensitiveCompare(rhs.merchant)
                if merchantOrder != .orderedSame { return merchantOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func initialTransaction(
        in transactions: [Transaction],
        for promotion: Promotion,
        editing allocation: PromotionAllocation? = nil
    ) -> Transaction? {
        if let allocation { return allocation.transaction }
        return availableTransactions(transactions, for: promotion)
            .first { PromotionCalculator.includes($0, in: promotion) }
    }
}
