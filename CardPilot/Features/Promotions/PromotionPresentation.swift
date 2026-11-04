import SwiftData
import SwiftUI

enum PromotionPresentationStatus: String, CaseIterable, Hashable, Sendable {
    case active
    case upcoming
    case history
}

struct PromotionSeriesGroup: Identifiable {
    let id: String
    let seriesID: UUID?
    let periods: [Promotion]
    let totalPeriodCount: Int
    let representative: Promotion
    let status: PromotionPresentationStatus

    var isSeries: Bool { periods.count > 1 || seriesID != nil }
}

enum PromotionPresentation {
    static func totalPeriodCount(in periods: [Promotion]) -> Int {
        max(periods.count, periods.compactMap(\.seriesIndex).max().map { $0 + 1 } ?? 0)
    }

    static func groups(
        from promotions: [Promotion],
        today: Int,
        includeArchived: Bool,
        searchText: String = ""
    ) -> [PromotionSeriesGroup] {
        let grouped = Dictionary(grouping: promotions) { promotion in
            promotion.seriesID.map { "series:\($0.uuidString)" } ?? "promotion:\(promotion.id.uuidString)"
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return grouped.compactMap { key, allPeriods in
            let values = allPeriods.filter { includeArchived || $0.archivedAt == nil }
            let periods = values.sorted(by: periodOrder)
            let matchingPeriods = query.isEmpty ? periods : periods.filter { matches($0, query: query) }
            guard let representative = representative(in: matchingPeriods, today: today) else { return nil }
            return PromotionSeriesGroup(
                id: key,
                seriesID: representative.seriesID,
                periods: periods,
                totalPeriodCount: totalPeriodCount(in: allPeriods),
                representative: representative,
                status: status(of: representative, today: today)
            )
        }
        .sorted(by: groupOrder)
    }

    static func matches(_ promotion: Promotion, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        let cardValues = promotion.eligibleCards.flatMap { card in
            [
                card.nickname,
                card.productName,
                card.lastFour,
                card.account.bank.name,
                cardNetworkSummary(card.networks)
            ]
        }
        let values = [promotion.title]
            + promotion.organizingBanks.map(\.name)
            + promotion.organizingNetworks.map(\.displayName)
            + cardValues
        return values.contains { $0.localizedCaseInsensitiveContains(normalized) }
    }

    static func status(of promotion: Promotion, today: Int) -> PromotionPresentationStatus {
        guard promotion.archivedAt == nil else { return .history }
        if promotion.startOn > today { return .upcoming }
        return promotion.endOn >= today ? .active : .history
    }

    private static func representative(in periods: [Promotion], today: Int) -> Promotion? {
        let active = periods.filter { $0.archivedAt == nil && $0.startOn <= today && $0.endOn >= today }
        if let value = active.sorted(by: activeOrder).first { return value }

        let upcoming = periods.filter { $0.archivedAt == nil && $0.startOn > today }
        if let value = upcoming.sorted(by: { upcomingOrder($0, $1) }).first { return value }

        let history = periods.filter { $0.archivedAt == nil && $0.endOn < today }
        if let value = history.sorted(by: historyOrder).first { return value }

        return periods.sorted(by: historyOrder).first
    }

    private static func periodOrder(_ lhs: Promotion, _ rhs: Promotion) -> Bool {
        if lhs.seriesIndex != rhs.seriesIndex {
            return (lhs.seriesIndex ?? Int.max) < (rhs.seriesIndex ?? Int.max)
        }
        if lhs.startOn != rhs.startOn { return lhs.startOn < rhs.startOn }
        if lhs.endOn != rhs.endOn { return lhs.endOn < rhs.endOn }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func activeOrder(_ lhs: Promotion, _ rhs: Promotion) -> Bool {
        if lhs.endOn != rhs.endOn { return lhs.endOn < rhs.endOn }
        return periodOrder(lhs, rhs)
    }

    private static func upcomingOrder(_ lhs: Promotion, _ rhs: Promotion) -> Bool {
        if lhs.startOn != rhs.startOn { return lhs.startOn < rhs.startOn }
        return periodOrder(lhs, rhs)
    }

    private static func historyOrder(_ lhs: Promotion, _ rhs: Promotion) -> Bool {
        if lhs.endOn != rhs.endOn { return lhs.endOn > rhs.endOn }
        return periodOrder(lhs, rhs)
    }

    private static func groupOrder(_ lhs: PromotionSeriesGroup, _ rhs: PromotionSeriesGroup) -> Bool {
        let lhsRank = rank(lhs.status)
        let rhsRank = rank(rhs.status)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        switch lhs.status {
        case .active:
            if lhs.representative.endOn != rhs.representative.endOn {
                return lhs.representative.endOn < rhs.representative.endOn
            }
        case .upcoming:
            if lhs.representative.startOn != rhs.representative.startOn {
                return lhs.representative.startOn < rhs.representative.startOn
            }
        case .history:
            if lhs.representative.endOn != rhs.representative.endOn {
                return lhs.representative.endOn > rhs.representative.endOn
            }
        }
        let titleOrder = lhs.representative.title.localizedCaseInsensitiveCompare(rhs.representative.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func rank(_ status: PromotionPresentationStatus) -> Int {
        switch status {
        case .active: return 0
        case .upcoming: return 1
        case .history: return 2
        }
    }
}
