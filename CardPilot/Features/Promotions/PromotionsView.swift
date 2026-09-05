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
            guard query.isEmpty || periods.contains(where: { matches($0, query: query) }) else { return nil }
            guard let representative = representative(in: periods, today: today) else { return nil }
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

struct PromotionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query private var cards: [Card]

    @State private var showingEditor = false
    @State private var editingPromotion: Promotion?
    @State private var showingArchived = false
    @State private var showingHistory = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var promotionPendingDeletion: Promotion?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label(trimmedSearchText.isEmpty ? "还没有促销活动" : "没有匹配的促销", systemImage: trimmedSearchText.isEmpty ? "gift" : "magnifyingglass")
                    } description: {
                        Text(trimmedSearchText.isEmpty ? "记录一个活动，随时查看还差多少、还能用几次。" : "试试活动标题、银行、卡组织或卡片末四位。")
                    } actions: {
                        if trimmedSearchText.isEmpty {
                            Button("添加活动", systemImage: "plus") {
                                editingPromotion = nil
                                showingEditor = true
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("清除搜索") { searchText = "" }
                        }
                    }
                } else {
                    List {
                        promotionSection(title: "进行中", groups: activeGroups)
                        promotionSection(title: "即将开始", groups: upcomingGroups)
                        if !historyGroups.isEmpty {
                            Section {
                                if showingHistory || !trimmedSearchText.isEmpty {
                                    ForEach(historyGroups) { group in
                                        promotionLink(for: group)
                                    }
                                    .onDelete { offsets in
                                        if let group = offsets.map({ historyGroups[$0] }).first {
                                            requestDelete(group.representative)
                                        }
                                    }
                                } else {
                                    Button {
                                        withAnimation { showingHistory = true }
                                    } label: {
                                        Label("显示 \(historyGroups.count) 个历史活动", systemImage: "clock.arrow.circlepath")
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            } header: {
                                HStack {
                                    Text("历史")
                                    Spacer()
                                    if showingHistory {
                                        Button("收起") {
                                            withAnimation { showingHistory = false }
                                        }
                                        .font(.caption.weight(.medium))
                                        .textCase(nil)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("促销")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingArchived.toggle()
                    } label: {
                        Label(showingArchived ? "隐藏归档" : "显示归档", systemImage: showingArchived ? "archivebox.fill" : "archivebox")
                    }
                    .labelStyle(.titleOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingPromotion = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加促销活动")
                }
            }
            .searchable(text: $searchText, prompt: "搜索活动、主办方或适用卡")
            .onChange(of: searchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showingHistory = true
                }
            }
            .sheet(isPresented: $showingEditor) {
                PromotionEditorView(promotion: editingPromotion, banks: banks, networks: networks, cards: cards)
            }
            .confirmationDialog("确认删除促销？", isPresented: $showingDeleteConfirmation) {
                Button("永久删除", role: .destructive) {
                    if let promotionPendingDeletion {
                        delete(promotionPendingDeletion)
                    }
                    promotionPendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    promotionPendingDeletion = nil
                }
            } message: {
                Text("将永久删除“" + (promotionPendingDeletion?.title ?? "该促销") + "”。")
            }
            .alert("无法完成操作", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groups: [PromotionSeriesGroup] {
        PromotionPresentation.groups(
            from: promotions,
            today: CardPilotUI.rawDate(Date()),
            includeArchived: showingArchived,
            searchText: searchText
        )
    }

    private var activeGroups: [PromotionSeriesGroup] {
        groups.filter { $0.status == .active }
    }

    private var upcomingGroups: [PromotionSeriesGroup] {
        groups.filter { $0.status == .upcoming }
    }

    private var historyGroups: [PromotionSeriesGroup] {
        groups.filter { $0.status == .history }
    }

    @ViewBuilder
    private func promotionSection(title: String, groups: [PromotionSeriesGroup]) -> some View {
        if !groups.isEmpty {
            Section(title) {
                ForEach(groups) { group in
                    promotionLink(for: group)
                }
                .onDelete { offsets in
                    if let group = offsets.map({ groups[$0] }).first {
                        requestDelete(group.representative)
                    }
                }
            }
        }
    }

    private func promotionLink(for group: PromotionSeriesGroup) -> some View {
        NavigationLink {
            PromotionDetailView(promotion: group.representative)
        } label: {
            PromotionRow(group: group)
        }
        .contextMenu {
            Button {
                editingPromotion = group.representative
                showingEditor = true
            } label: {
                Label("编辑当前期", systemImage: "pencil")
            }
            Button(role: .destructive) {
                requestDelete(group.representative)
            } label: {
                Label("删除当前期", systemImage: "trash")
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func requestDelete(_ promotion: Promotion) {
        guard promotion.allocations.isEmpty else {
            errorMessage = "该促销已有交易分配，不能删除；如不再使用可在编辑中归档。"
            return
        }
        promotionPendingDeletion = promotion
        showingDeleteConfirmation = true
    }

    private func delete(_ promotion: Promotion) {
        guard promotion.allocations.isEmpty else {
            errorMessage = "该促销已有交易分配，不能删除；如不再使用可在编辑中归档。"
            return
        }
        modelContext.delete(promotion)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "促销未删除：\(error.localizedDescription)"
        }
    }
}

private struct PromotionRow: View {
    let group: PromotionSeriesGroup
    private var promotion: Promotion { group.representative }
    private var progress: PromotionProgress? { try? PromotionCalculator.progress(for: promotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(promotion.title)
                        .font(.headline)
                        .lineLimit(2)
                    if group.isSeries {
                        Text("系列 · \(periodText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusBadge
            }
            if !promotion.rewardDescription.isEmpty {
                Text(promotion.rewardDescription)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(organizerText)
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
                    .lineLimit(1)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                enrollmentBadge
                if promotion.archivedAt != nil {
                    Label("已归档", systemImage: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if let progress {
                PromotionProgressSummary(promotion: promotion, progress: progress, compact: true)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("查看促销详情")
    }

    private var periodText: String {
        guard let index = promotion.seriesIndex else { return group.isSeries ? "多期活动" : "独立活动" }
        return "第 \(index + 1) 期，共 \(group.totalPeriodCount) 期"
    }

    private var organizerText: String {
        let banks = promotion.organizingBanks.map(\.name)
        let networks = promotion.organizingNetworks.map(\.displayName)
        let values = banks + networks
        return values.isEmpty ? "未指定主办方" : values.joined(separator: "、")
    }

    private var enrollmentText: String {
        switch promotion.enrollmentStatus {
        case .notRequired: return "无需报名"
        case .notEnrolled: return "待报名"
        case .enrolled: return "已报名"
        }
    }

    private var statusText: String {
        switch group.status {
        case .active: return "进行中"
        case .upcoming: return "即将开始"
        case .history: return "历史"
        }
    }

    private var statusColor: Color {
        switch group.status {
        case .active: return .secondary
        case .upcoming: return .accentColor
        case .history: return .secondary
        }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var enrollmentBadge: some View {
        Label(enrollmentText, systemImage: promotion.enrollmentStatus == .enrolled ? "checkmark.circle.fill" : "person.badge.clock")
            .font(.caption2.weight(.medium))
            .foregroundStyle(promotion.enrollmentStatus == .notEnrolled ? .orange : .secondary)
    }

    private var accessibilityText: String {
        var values = [promotion.title, statusText, organizerText, periodText, CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn), enrollmentText]
        if let progress {
            if let cap = progress.benefitTransactionCap {
                values.append("已用 \(progress.usedTransactionCount)/\(cap) 笔，剩余 \(progress.remainingTransactionCount ?? cap) 笔")
            } else if let threshold = progress.qualificationThreshold {
                values.append("进度 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))，目标 \(CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))")
            } else {
                values.append("已计入 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
            }
        }
        return values.joined(separator: "，")
    }
}

private struct PromotionProgressSummary: View {
    let promotion: Promotion
    let progress: PromotionProgress
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            if let cap = progress.benefitTransactionCap {
                Text("已用 \(progress.usedTransactionCount) / \(cap) 笔")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(progress.isComplete ? .green : .primary)
                Text(progress.isComplete ? "优惠笔数已用完" : "还可完成 \(progress.remainingTransactionCount ?? cap) 笔")
                    .font(.caption)
                    .foregroundStyle(progress.isComplete ? .green : .secondary)
            } else if let threshold = progress.qualificationThreshold {
                ProgressView(
                    value: decimalDouble(min(max(.zero, progress.qualifiedAmount), threshold)),
                    total: decimalDouble(threshold)
                )
                .tint(progress.isComplete ? .green : .accentColor)
                Text("\(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode)) / \(CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(progress.isComplete ? .green : .primary)
                Text(progress.isComplete ? "已达标" : "还需 \(CardPilotUI.amountText(progress.remainingToThreshold ?? threshold, currencyCode: promotion.progressCurrencyCode))")
                    .font(.caption)
                    .foregroundStyle(progress.isComplete ? .green : .secondary)
                if let cap = progress.qualifyingCap {
                    Text("计入上限剩余 \(CardPilotUI.amountText(progress.remainingCap ?? cap, currencyCode: promotion.progressCurrencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let cap = progress.qualifyingCap {
                Text("已计入 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .body)
                Text("剩余可计入 \(CardPilotUI.amountText(progress.remainingCap ?? cap, currencyCode: promotion.progressCurrencyCode))")
                    .font(.caption)
                    .foregroundStyle((progress.remainingCap ?? cap) == .zero ? .green : .secondary)
            } else {
                Text("已计入净额：\(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private enum PromotionEditorStep: Int, CaseIterable, Hashable {
    case basics
    case eligibility
    case rules

    var title: String {
        switch self {
        case .basics: return "基本"
        case .eligibility: return "适用范围"
        case .rules: return "报名与规则"
        }
    }

    var subtitle: String {
        switch self {
        case .basics: return "信息与金额"
        case .eligibility: return "主办方与卡片"
        case .rules: return "确认并保存"
        }
    }
}

private enum PromotionProgressMode: String, CaseIterable, Hashable {
    case cumulative
    case perTransaction

    var title: String {
        switch self {
        case .cumulative: return "累计消费"
        case .perTransaction: return "逐笔优惠"
        }
    }
}

private struct PromotionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let promotion: Promotion?
    let banks: [Bank]
    let networks: [CardNetwork]
    let cards: [Card]

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var repeatsMonthly: Bool
    @State private var repeatUntilDate: Date
    @State private var progressMode: PromotionProgressMode
    @State private var qualificationThresholdText: String
    @State private var qualifyingCapText: String
    @State private var perTransactionThresholdText: String
    @State private var benefitTransactionCapText: String
    @State private var currencyCode: String
    @State private var selectedBankIDs: Set<UUID>
    @State private var selectedNetworkIDs: Set<UUID>
    @State private var selectedCardIDs: Set<UUID>
    @State private var enrollmentStatus: EnrollmentStatus
    @State private var hasEnrolledOn: Bool
    @State private var enrolledOn: Date
    @State private var hasEnrollmentDeadline: Bool
    @State private var enrollmentDeadline: Date
    @State private var qualificationDateBasis: QualificationDateBasis
    @State private var stackingAllowed: Bool
    @State private var rules: String
    @State private var exclusions: String
    @State private var rewardDescription: String
    @State private var notes: String
    @State private var archived: Bool
    @State private var seriesEditScope: PromotionSeriesEditScope
    @State private var step: PromotionEditorStep = .basics
    @State private var showingOrganizerPicker = false
    @State private var showingCardPicker = false
    @State private var errorMessage: String?
    @Query private var allPromotions: [Promotion]

    init(promotion: Promotion?, banks: [Bank], networks: [CardNetwork], cards: [Card]) {
        self.promotion = promotion
        self.banks = banks
        self.networks = networks
        self.cards = cards
        _title = State(initialValue: promotion?.title ?? "")
        _startDate = State(initialValue: promotion.flatMap { try? LocalDate(rawValue: $0.startOn).date(in: CardPilotUI.homeTimeZone) } ?? Date())
        _endDate = State(initialValue: promotion.flatMap { try? LocalDate(rawValue: $0.endOn).date(in: CardPilotUI.homeTimeZone) } ?? Date())
        _repeatsMonthly = State(initialValue: false)
        _repeatUntilDate = State(initialValue: promotion.flatMap { try? LocalDate(rawValue: $0.endOn).date(in: CardPilotUI.homeTimeZone) } ?? Date())
        _progressMode = State(initialValue: promotion?.benefitTransactionCap == nil ? .cumulative : .perTransaction)
        _qualificationThresholdText = State(initialValue: promotion.flatMap { $0.qualificationThreshold.map(CardPilotUI.editableAmountText) } ?? "")
        _qualifyingCapText = State(initialValue: promotion.flatMap { $0.qualifyingCap.map(CardPilotUI.editableAmountText) } ?? "")
        _perTransactionThresholdText = State(initialValue: promotion.flatMap { $0.perTransactionThreshold.map(CardPilotUI.editableAmountText) } ?? "")
        _benefitTransactionCapText = State(initialValue: promotion?.benefitTransactionCap.map { String($0) } ?? "")
        _currencyCode = State(initialValue: promotion?.progressCurrencyCode ?? "CNY")
        _selectedBankIDs = State(initialValue: Set(promotion?.organizingBanks.map(\.id) ?? []))
        _selectedNetworkIDs = State(initialValue: Set(promotion?.organizingNetworks.map(\.id) ?? []))
        _selectedCardIDs = State(initialValue: Set(promotion?.eligibleCards.map(\.id) ?? []))
        _enrollmentStatus = State(initialValue: promotion?.enrollmentStatus ?? .notRequired)
        _hasEnrolledOn = State(initialValue: promotion?.enrolledOn != nil)
        _enrolledOn = State(initialValue: promotion.flatMap { $0.enrolledOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _hasEnrollmentDeadline = State(initialValue: promotion?.enrollmentDeadline != nil)
        _enrollmentDeadline = State(initialValue: promotion.flatMap { $0.enrollmentDeadline.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _qualificationDateBasis = State(initialValue: promotion?.qualificationDateBasis ?? .transactionDate)
        _stackingAllowed = State(initialValue: promotion?.stackingAllowed ?? true)
        _rules = State(initialValue: promotion?.rules ?? "")
        _exclusions = State(initialValue: promotion?.exclusions ?? "")
        _rewardDescription = State(initialValue: promotion?.rewardDescription ?? "")
        _notes = State(initialValue: promotion?.notes ?? "")
        _archived = State(initialValue: promotion?.archivedAt != nil)
        _seriesEditScope = State(initialValue: .thisOnly)
    }

    private var editSnapshot: String {
        editorSnapshot(title, startDate, endDate, repeatsMonthly, repeatUntilDate, progressMode, qualificationThresholdText, qualifyingCapText, perTransactionThresholdText, benefitTransactionCapText, currencyCode, selectedBankIDs.map(\.uuidString).sorted(), selectedNetworkIDs.map(\.uuidString).sorted(), selectedCardIDs.map(\.uuidString).sorted(), enrollmentStatus, hasEnrolledOn, enrolledOn, hasEnrollmentDeadline, enrollmentDeadline, qualificationDateBasis, stackingAllowed, rules, exclusions, rewardDescription, notes, archived, seriesEditScope)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editorStepIndicator
                }
                switch step {
                case .basics:
                    basicsStep
                case .eligibility:
                    eligibilityStep
                case .rules:
                    rulesStep
                }

                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .navigationTitle(promotion == nil ? "添加促销" : "编辑促销")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        if step != .basics {
                            Button {
                                retreat()
                            } label: {
                                Label("上一步", systemImage: "chevron.left")
                            }
                        }
                        EditorCancelButton()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .rules {
                        Button("保存", action: save)
                    } else {
                        Button("下一步", action: advance)
                    }
                }
            }
            .sheet(isPresented: $showingOrganizerPicker) {
                OrganizerSelectionView(
                    banks: banks,
                    networks: organizerNetworks,
                    selectedBankIDs: $selectedBankIDs,
                    selectedNetworkIDs: $selectedNetworkIDs
                )
            }
            .sheet(isPresented: $showingCardPicker) {
                CardSelectionView(
                    cards: sortedCards,
                    recommendations: recommendedCards,
                    selectedCardIDs: $selectedCardIDs
                )
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var editorStepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(PromotionEditorStep.allCases, id: \.self) { item in
                if item != .basics {
                    Rectangle()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                }
                VStack(spacing: 3) {
                    Image(systemName: item.rawValue <= step.rawValue ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary)
                    Text(item.title)
                        .font(.caption.weight(item == step ? .semibold : .regular))
                        .foregroundStyle(item == step ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(step.rawValue + 1) 步，共 3 步：\(step.title)，\(step.subtitle)")
    }

    private var basicsStep: some View {
        Group {
            Section("基本信息") {
                TextField("活动标题", text: $title)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    .disabled(promotion?.seriesID != nil)
                DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    .disabled(promotion?.seriesID != nil)
                if promotion == nil {
                    Toggle("每月重复", isOn: $repeatsMonthly)
                    if repeatsMonthly {
                        DatePicker("系列结束日期", selection: $repeatUntilDate, displayedComponents: .date)
                        Text("将创建 \(monthlyPeriodPreview.count) 个完整周期")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if promotion?.seriesID != nil {
                    Picker("编辑范围", selection: $seriesEditScope) {
                        Text("仅本期").tag(PromotionSeriesEditScope.thisOnly)
                        Text("本期及以后").tag(PromotionSeriesEditScope.thisAndFuture)
                    }
                    Text("系列日期由首期锚点按月生成，不能单独修改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("金额与进度") {
                Picker("进度类型", selection: $progressMode) {
                    ForEach(PromotionProgressMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if progressMode == .perTransaction {
                    TextField("优惠笔数上限", text: $benefitTransactionCapText)
                        .keyboardType(.numberPad)
                    TextField("单笔满足金额（可选）", text: $perTransactionThresholdText)
                        .keyboardType(.decimalPad)
                    Text("每笔符合条件的消费计 1 笔；这里只记录已用笔数，不计算优惠金额。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("累计达标门槛（可选）", text: $qualificationThresholdText)
                        .keyboardType(.decimalPad)
                    TextField("累计计入上限（可选）", text: $qualifyingCapText)
                        .keyboardType(.decimalPad)
                    TextField("单笔计入门槛（可选）", text: $perTransactionThresholdText)
                        .keyboardType(.decimalPad)
                }
                CurrencyPickerView(selection: $currencyCode, title: "进度币种")
                    .disabled(promotion?.allocations.isEmpty == false)
                if promotion?.allocations.isEmpty == false {
                    Text("已有促销分配，进度币种已锁定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(progressMode == .perTransaction
                     ? "笔数上限必须为正整数；单笔满足金额留空表示不设门槛。"
                     : "不适用的规则留空；填写的金额必须大于 0。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var eligibilityStep: some View {
        Group {
            Section("主办方") {
                selectionSummary(
                    title: "银行与卡组织",
                    value: organizerSummary,
                    systemImage: "building.2"
                )
                Button {
                    showingOrganizerPicker = true
                } label: {
                    Label("管理主办方", systemImage: "slider.horizontal.3")
                }
                Text("只选择活动主办的实际卡组织；双标卡组合请在适用卡中明确勾选。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("适用卡") {
                selectionSummary(
                    title: "已选择卡片",
                    value: selectedCardIDs.isEmpty ? "尚未选择适用卡" : "\(selectedCardIDs.count) 张卡",
                    systemImage: "creditcard"
                )
                if !selectedCardsPreview.isEmpty {
                    Text(selectedCardsPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Button {
                    showingCardPicker = true
                } label: {
                    Label("搜索并选择适用卡", systemImage: "magnifyingglass")
                }
                Text(recommendedCards.isEmpty
                     ? "选择主办方后会提供启用卡推荐；也可以手动搜索全部卡片。"
                     : "已根据主办方找到 \(recommendedCards.count) 张推荐卡，请确认后再保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rulesStep: some View {
        Group {
            Section("报名与资格") {
                Picker("报名状态", selection: $enrollmentStatus) {
                    Text("不需要报名").tag(EnrollmentStatus.notRequired)
                    Text("尚未报名").tag(EnrollmentStatus.notEnrolled)
                    Text("已报名").tag(EnrollmentStatus.enrolled)
                }
                if enrollmentStatus == .enrolled {
                    Toggle("记录报名日期", isOn: $hasEnrolledOn)
                    if hasEnrolledOn {
                        DatePicker("报名日期", selection: $enrolledOn, displayedComponents: .date)
                    }
                }
                if enrollmentStatus != .notRequired {
                    Toggle("设置报名截止日", isOn: $hasEnrollmentDeadline)
                    if hasEnrollmentDeadline {
                        DatePicker("报名截止日", selection: $enrollmentDeadline, displayedComponents: .date)
                    }
                }
                Picker("资格日期依据", selection: $qualificationDateBasis) {
                    Text("交易日期").tag(QualificationDateBasis.transactionDate)
                    Text("入账日期").tag(QualificationDateBasis.postingDate)
                    Text("未知（交易日或入账日）").tag(QualificationDateBasis.unknown)
                }
            }
            Section("规则与奖励") {
                TextField("规则（首版仅自动计算累计消费与优惠笔数）", text: $rules, axis: .vertical)
                TextField("排除项", text: $exclusions, axis: .vertical)
                TextField("奖励说明", text: $rewardDescription, axis: .vertical)
                TextField("备注", text: $notes, axis: .vertical)
            }
            Section("状态") {
                Toggle("允许与其他活动叠加", isOn: $stackingAllowed)
                Toggle("归档", isOn: $archived)
            }
            Section("保存前确认") {
                LabeledContent("活动", value: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : title)
                LabeledContent("有效期", value: CardPilotUI.dateRangeText(start: CardPilotUI.rawDate(startDate), end: CardPilotUI.rawDate(endDate)))
                LabeledContent("主办方", value: organizerSummary)
                LabeledContent("适用卡", value: selectedCardIDs.isEmpty ? "尚未选择" : "\(selectedCardIDs.count) 张")
                LabeledContent("进度规则", value: progressSummary)
                LabeledContent("报名", value: enrollmentSummary)
            }
        }
    }

    private var organizerSummary: String {
        let selectedBanks = banks.filter { selectedBankIDs.contains($0.id) }.map(\.name)
        let selectedNetworks = networks.filter { selectedNetworkIDs.contains($0.id) }.map(\.displayName)
        let values = selectedBanks + selectedNetworks
        return values.isEmpty ? "未指定" : values.joined(separator: "、")
    }

    private var selectedCardsPreview: String {
        sortedCards
            .filter { selectedCardIDs.contains($0.id) }
            .prefix(3)
            .map(cardName)
            .joined(separator: "、")
            + (selectedCardIDs.count > 3 ? " 等" : "")
    }

    private var enrollmentSummary: String {
        switch enrollmentStatus {
        case .notRequired: return "无需报名"
        case .notEnrolled: return "尚未报名"
        case .enrolled: return "已报名"
        }
    }

    private var progressSummary: String {
        if progressMode == .perTransaction {
            let cap = benefitTransactionCapText.trimmingCharacters(in: .whitespacesAndNewlines)
            return cap.isEmpty ? "逐笔优惠，未填写笔数上限" : "逐笔优惠，最多 \(cap) 笔"
        }
        return qualificationThresholdText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "累计记录"
            : "累计达标"
    }

    private func selectionSummary(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func advance() {
        if step == .basics, !validateBasicsStep() { return }
        errorMessage = nil
        guard let next = PromotionEditorStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
        }
    }

    private func validateBasicsStep() -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请先填写活动标题。"
            return false
        }
        guard startDate <= endDate else {
            errorMessage = "结束日期不能早于开始日期。"
            return false
        }
        guard isValidCurrencyCode(currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) else {
            errorMessage = "请选择有效的进度币种。"
            return false
        }
        guard validateProgressFields() else { return false }
        guard !repeatsMonthly || monthlyPeriodPreview.count >= 2 else {
            errorMessage = "系列结束日期必须容纳至少两个完整周期。"
            return false
        }
        return true
    }

    private func validateProgressFields() -> Bool {
        switch progressMode {
        case .cumulative:
            return parseOptionalAmount(qualificationThresholdText, label: "累计达标门槛").isValid
                && parseOptionalAmount(qualifyingCapText, label: "累计计入上限").isValid
                && parseOptionalAmount(perTransactionThresholdText, label: "单笔计入门槛").isValid
        case .perTransaction:
            guard parseOptionalAmount(perTransactionThresholdText, label: "单笔满足金额").isValid else { return false }
            return parsePositiveInteger(benefitTransactionCapText, label: "优惠笔数上限").isValid
        }
    }

    private func retreat() {
        guard let previous = PromotionEditorStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = previous
        }
    }

    private func binding(for id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) }
            }
        )
    }

    private var organizerNetworks: [CardNetwork] {
        let builtInOrder = Dictionary(uniqueKeysWithValues: CardNetwork.builtInDefinitions.enumerated().map { ($0.element.code, $0.offset) })
        return networks.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            if lhs.isBuiltIn {
                return (builtInOrder[lhs.code] ?? Int.max) < (builtInOrder[rhs.code] ?? Int.max)
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var sortedCards: [Card] {
        cards.sorted {
            let lhsBank = $0.account.bank.name
            let rhsBank = $1.account.bank.name
            if lhsBank != rhsBank { return lhsBank.localizedCaseInsensitiveCompare(rhsBank) == .orderedAscending }
            return cardName($0).localizedCaseInsensitiveCompare(cardName($1)) == .orderedAscending
        }
    }

    private var recommendedCards: [PromotionCardRecommendation] {
        PromotionEligibility.recommendations(
            organizingBanks: banks.filter { selectedBankIDs.contains($0.id) },
            organizingNetworks: networks.filter { selectedNetworkIDs.contains($0.id) },
            cards: cards
        )
    }

    private var monthlyPeriodPreview: [PromotionPeriod] {
        guard repeatsMonthly else { return [] }
        return PromotionSeriesCalculator.monthlyPeriods(
            startOn: CardPilotUI.rawDate(startDate),
            endOn: CardPilotUI.rawDate(endDate),
            through: CardPilotUI.rawDate(repeatUntilDate)
        )
    }

    private var otherCards: [Card] {
        let recommendedIDs = Set(recommendedCards.map(\.card.id))
        return sortedCards.filter { !recommendedIDs.contains($0.id) }
    }

    private func cardName(_ card: Card) -> String {
        let name = card.nickname.isEmpty ? card.productName : card.nickname
        return name
    }

    @ViewBuilder
    private func cardRow(_ card: Card, reasons: [String] = []) -> some View {
        HStack(spacing: 10) {
            BankBadge(bank: card.account.bank)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(cardName(card))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if card.networks.count == 2 {
                        Text("双标")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    CardNetworksBadges(networks: card.networks)
                    Text("•••• \(card.lastFour)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(reasons.isEmpty ? card.account.bank.name : reasons.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedTitle.isEmpty else { errorMessage = "活动标题不能为空。"; return }
        guard startDate <= endDate else { errorMessage = "结束日期不能早于开始日期。"; return }
        guard isValidCurrencyCode(normalizedCurrency) else {
            errorMessage = "进度币种应为有效的 ISO 4217 代码。"
            return
        }
        if let promotion, promotion.progressCurrencyCode != normalizedCurrency, !promotion.allocations.isEmpty {
            errorMessage = "已有促销分配后不能修改进度币种。"
            return
        }
        let threshold: (value: Decimal?, isValid: Bool)
        let cap: (value: Decimal?, isValid: Bool)
        let perTransactionThreshold: (value: Decimal?, isValid: Bool)
        let benefitTransactionCap: (value: Int?, isValid: Bool)
        switch progressMode {
        case .cumulative:
            threshold = parseOptionalAmount(qualificationThresholdText, label: "累计达标门槛")
            cap = parseOptionalAmount(qualifyingCapText, label: "累计计入上限")
            perTransactionThreshold = parseOptionalAmount(perTransactionThresholdText, label: "单笔计入门槛")
            benefitTransactionCap = (nil, true)
        case .perTransaction:
            threshold = (nil, true)
            cap = (nil, true)
            perTransactionThreshold = parseOptionalAmount(perTransactionThresholdText, label: "单笔满足金额")
            benefitTransactionCap = parsePositiveInteger(benefitTransactionCapText, label: "优惠笔数上限")
        }
        guard threshold.isValid, cap.isValid, perTransactionThreshold.isValid, benefitTransactionCap.isValid else { return }

        let startOn = CardPilotUI.rawDate(startDate)
        let endOn = CardPilotUI.rawDate(endDate)
        let status = enrollmentStatus
        let enrolledValue = status == .enrolled && hasEnrolledOn ? CardPilotUI.rawDate(enrolledOn) : nil
        let deadlineValue = status == .notRequired || !hasEnrollmentDeadline ? nil : CardPilotUI.rawDate(enrollmentDeadline)
        if let deadlineValue, deadlineValue > endOn {
            errorMessage = "报名截止日不能晚于活动结束日。"
            return
        }
        let selectedBanks = banks.filter { selectedBankIDs.contains($0.id) }
        let selectedNetworks = networks.filter { selectedNetworkIDs.contains($0.id) }
        let selectedCards = cards.filter { selectedCardIDs.contains($0.id) }

        if promotion == nil && repeatsMonthly {
            guard monthlyPeriodPreview.count >= 2 else {
                errorMessage = "系列结束日期必须容纳至少两个完整周期。"
                return
            }
            let template = Promotion(
                title: normalizedTitle,
                startOn: startOn,
                endOn: endOn,
                organizingBanks: selectedBanks,
                organizingNetworks: selectedNetworks,
                eligibleCards: selectedCards,
                enrollmentStatus: status,
                enrolledOn: enrolledValue,
                enrollmentDeadline: deadlineValue,
                qualificationDateBasis: qualificationDateBasis,
                stackingAllowed: stackingAllowed,
                qualificationThreshold: threshold.value,
                qualifyingCap: cap.value,
                perTransactionThreshold: perTransactionThreshold.value,
                benefitTransactionCap: benefitTransactionCap.value,
                progressCurrencyCode: normalizedCurrency,
                rules: rules,
                exclusions: exclusions,
                rewardDescription: rewardDescription,
                notes: notes,
                archivedAt: archived ? Date() : nil
            )
            let targets = Promotion.makeMonthlySeries(from: template, through: CardPilotUI.rawDate(repeatUntilDate))
            do {
                try targets.forEach { try $0.validate() }
                targets.forEach { modelContext.insert($0) }
                try modelContext.save()
                dismiss()
            } catch {
                modelContext.rollback()
                errorMessage = "促销未保存：\(error.localizedDescription)"
            }
            return
        }

        let target = promotion ?? Promotion(
            title: normalizedTitle,
            startOn: startOn,
            endOn: endOn,
            organizingBanks: selectedBanks,
            organizingNetworks: selectedNetworks,
            eligibleCards: selectedCards,
            enrollmentStatus: status,
            enrolledOn: enrolledValue,
            enrollmentDeadline: deadlineValue,
            qualificationDateBasis: qualificationDateBasis,
            stackingAllowed: stackingAllowed,
            qualificationThreshold: threshold.value,
            qualifyingCap: cap.value,
            perTransactionThreshold: perTransactionThreshold.value,
            benefitTransactionCap: benefitTransactionCap.value,
            progressCurrencyCode: normalizedCurrency,
            rules: rules,
            exclusions: exclusions,
            rewardDescription: rewardDescription,
            notes: notes,
            archivedAt: archived ? Date() : nil
        )
        let targets = seriesTargets(for: target)
        guard !targets.contains(where: { !$0.allocations.isEmpty && $0.progressCurrencyCode != normalizedCurrency }) else {
            errorMessage = "系列中已有促销分配的周期不能修改进度币种。"
            return
        }
        for candidate in targets {
            candidate.title = normalizedTitle
            if candidate.id == target.id || candidate.seriesID == nil {
                candidate.startOn = startOn
                candidate.endOn = endOn
            }
            candidate.organizingBanks = selectedBanks
            candidate.organizingNetworks = selectedNetworks
            candidate.eligibleCards = selectedCards
            candidate.enrollmentStatus = status
            candidate.enrolledOn = seriesDateValue(enrolledValue, source: target, target: candidate)
            candidate.enrollmentDeadline = seriesDateValue(deadlineValue, source: target, target: candidate)
            candidate.qualificationDateBasis = qualificationDateBasis
            candidate.stackingAllowed = stackingAllowed
            candidate.qualificationThreshold = threshold.value
            candidate.qualifyingCap = cap.value
            candidate.perTransactionThreshold = perTransactionThreshold.value
            candidate.benefitTransactionCap = benefitTransactionCap.value
            candidate.progressCurrencyCode = normalizedCurrency
            candidate.rules = rules
            candidate.exclusions = exclusions
            candidate.rewardDescription = rewardDescription
            candidate.notes = notes
            candidate.archivedAt = archived ? (candidate.archivedAt ?? Date()) : nil
        }
        do {
            try targets.forEach { candidate in
                if let deadline = candidate.enrollmentDeadline, deadline > candidate.endOn {
                    throw ModelValidationError.invalidEnrollment
                }
                try candidate.validate()
            }
            if promotion == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "促销未保存：\(error.localizedDescription)"
        }
    }

    private func seriesTargets(for target: Promotion) -> [Promotion] {
        guard seriesEditScope == .thisAndFuture else { return [target] }
        return PromotionSeriesCalculator.editablePeriods(
            in: allPromotions,
            from: target,
            today: CardPilotUI.rawDate(Date())
        )
    }

    private func seriesDateValue(_ value: Int?, source: Promotion, target: Promotion) -> Int? {
        guard let value else { return nil }
        guard seriesEditScope == .thisAndFuture,
              let sourceIndex = source.seriesIndex,
              let targetIndex = target.seriesIndex else { return value }
        return PromotionSeriesCalculator.shiftedDate(value, byMonths: targetIndex - sourceIndex) ?? value
    }

    private func parseOptionalAmount(_ text: String, label: String) -> (value: Decimal?, isValid: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return (nil, true) }
        guard let amount = CardPilotUI.decimal(normalized), amount > .zero else {
            errorMessage = "\(label)应为大于 0 的数字，或留空。"
            return (nil, false)
        }
        return (amount, true)
    }

    private func parsePositiveInteger(_ text: String, label: String) -> (value: Int?, isValid: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(normalized), value > 0 else {
            errorMessage = "\(label)应为大于 0 的整数。"
            return (nil, false)
        }
        return (value, true)
    }
}

private struct OrganizerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let banks: [Bank]
    let networks: [CardNetwork]
    @Binding var selectedBankIDs: Set<UUID>
    @Binding var selectedNetworkIDs: Set<UUID>
    @State private var searchText = ""

    private var filteredBanks: [Bank] {
        banks.filter { bank in
            (bank.archivedAt == nil || selectedBankIDs.contains(bank.id))
                && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || bank.name.localizedCaseInsensitiveContains(searchText)
                )
        }
    }

    private var filteredNetworks: [CardNetwork] {
        networks.filter { network in
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || network.displayName.localizedCaseInsensitiveContains(searchText)
                || network.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if filteredBanks.isEmpty {
                        Text("没有匹配的银行")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredBanks, id: \.id) { bank in
                            Toggle(isOn: binding(for: bank.id, in: $selectedBankIDs)) {
                                HStack(spacing: 10) {
                                    BankBadge(bank: bank)
                                    Text(bank.name)
                                }
                            }
                        }
                    }
                } header: {
                    Text("银行")
                }
                Section {
                    if filteredNetworks.isEmpty {
                        Text("没有匹配的卡组织")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredNetworks, id: \.id) { network in
                            Toggle(isOn: binding(for: network.id, in: $selectedNetworkIDs)) {
                                HStack(spacing: 10) {
                                    CardNetworkBadge(network: network)
                                    Text(network.displayName)
                                }
                            }
                        }
                    }
                } header: {
                    Text("卡组织")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "搜索银行或卡组织")
            .navigationTitle("选择主办方")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func binding(for id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isSelected in
                if isSelected {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }
}

private struct CardSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let cards: [Card]
    let recommendations: [PromotionCardRecommendation]
    @Binding var selectedCardIDs: Set<UUID>
    @State private var searchText = ""

    private var recommendationIDs: Set<UUID> {
        Set(recommendations.map(\.card.id))
    }

    private var filteredRecommendations: [PromotionCardRecommendation] {
        recommendations.filter { matches($0.card) }
    }

    private var filteredOtherCards: [Card] {
        cards.filter { !recommendationIDs.contains($0.id) && matches($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(selectedCardIDs.isEmpty ? "未选择卡片" : "已选择 \(selectedCardIDs.count) 张")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !filteredRecommendations.isEmpty {
                            Button(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "全选推荐" : "全选搜索结果") {
                                selectedCardIDs.formUnion(filteredRecommendations.map(\.card.id))
                            }
                            .font(.subheadline.weight(.medium))
                        }
                    }
                    if selectedCardIDs.isEmpty {
                        Text("可以不限定适用卡；选择后将只把匹配卡片的交易作为自动候选。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !filteredRecommendations.isEmpty {
                    Section("主办方推荐") {
                        ForEach(filteredRecommendations) { recommendation in
                            cardToggle(recommendation.card, reasons: recommendation.reasons)
                        }
                    }
                }
                if !filteredOtherCards.isEmpty {
                    Section("其他卡片") {
                        ForEach(filteredOtherCards, id: \.id) { card in
                            cardToggle(card)
                        }
                    }
                }
                if filteredRecommendations.isEmpty && filteredOtherCards.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "搜索银行、卡片、卡号或卡组织")
            .navigationTitle("选择适用卡")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") { selectedCardIDs.removeAll() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func cardToggle(_ card: Card, reasons: [String] = []) -> some View {
        Toggle(isOn: binding(for: card.id)) {
            PromotionCardSelectionRow(card: card, reasons: reasons)
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedCardIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedCardIDs.insert(id)
                } else {
                    selectedCardIDs.remove(id)
                }
            }
        )
    }

    private func matches(_ card: Card) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let name = card.nickname.isEmpty ? card.productName : card.nickname
        let values = [name, card.productName, card.lastFour, card.account.bank.name]
            + card.networks.map(\.displayName)
            + card.networks.map(\.code)
        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct PromotionCardSelectionRow: View {
    let card: Card
    let reasons: [String]

    private var cardName: String {
        card.nickname.isEmpty ? card.productName : card.nickname
    }

    var body: some View {
        HStack(spacing: 10) {
            BankBadge(bank: card.account.bank)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(cardName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if card.networks.count == 2 {
                        Text("双标")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    CardNetworksBadges(networks: card.networks)
                    Text("•••• \(card.lastFour)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(reasons.isEmpty ? card.account.bank.name : reasons.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let reasonText = reasons.isEmpty ? "" : "，\(reasons.joined(separator: "、"))"
        return "\(card.account.bank.name)，\(cardName)，卡号末四位 \(card.lastFour)\(reasonText)"
    }
}

struct PromotionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let promotion: Promotion
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query private var cards: [Card]
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @State private var showingTransactionEditor = false
    @Query private var allPromotions: [Promotion]
    @State private var showingAllocationEditor = false
    @State private var editingAllocation: PromotionAllocation?
    @State private var showingPromotionEditor = false
    @State private var selectedPeriodID: UUID
    @State private var allocationPendingDeletion: PromotionAllocation?
    @State private var showingAllocationDeleteConfirmation = false
    @State private var errorMessage: String?

    init(promotion: Promotion) {
        self.promotion = promotion
        _selectedPeriodID = State(initialValue: promotion.id)
    }

    private var seriesPromotions: [Promotion] {
        guard let seriesID = promotion.seriesID else { return [promotion] }
        let values = allPromotions
            .filter { $0.seriesID == seriesID }
            .sorted(by: promotionPeriodOrder)
        return values.isEmpty ? [promotion] : values
    }

    private var displayedPromotion: Promotion {
        seriesPromotions.first(where: { $0.id == selectedPeriodID }) ?? seriesPromotions.first ?? promotion
    }

    private var displayedPeriodIndex: Int {
        seriesPromotions.firstIndex(where: { $0.id == displayedPromotion.id }) ?? 0
    }

    private var progress: PromotionProgress? {
        try? PromotionCalculator.progress(for: displayedPromotion)
    }

    private var sortedAllocations: [PromotionAllocation] {
        displayedPromotion.allocations.sorted {
            if $0.transaction.transactionOn != $1.transaction.transactionOn {
                return $0.transaction.transactionOn > $1.transaction.transactionOn
            }
            let lhsMerchant = $0.transaction.merchant.localizedCaseInsensitiveCompare($1.transaction.merchant)
            if lhsMerchant != .orderedSame { return lhsMerchant == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        List {
            if seriesPromotions.count > 1 {
                seriesSection
            }
            Section("更新进度") {
                VStack(spacing: 12) {
                    Button {
                        showingTransactionEditor = true
                    } label: {
                        centeredActionLabel("记录新消费", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cards.isEmpty)
                    .accessibilityIdentifier("recordPromotionTransaction")

                    Button {
                        addAllocation()
                    } label: {
                        centeredActionLabel("选择已有交易", systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(transactions.isEmpty)
                    .accessibilityIdentifier("allocateExistingTransaction")
                }
                .padding(.vertical, 4)

                if cards.isEmpty {
                    Text("添加信用卡后即可记录新消费。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if transactions.isEmpty {
                    Text("目前没有可选择的已有交易，可以先记录一笔新消费。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("进度") {
                if let progress {
                    PromotionProgressSummary(promotion: displayedPromotion, progress: progress, compact: false)
                } else {
                    Text("暂时无法计算进度。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("计入活动的交易") {
                if sortedAllocations.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("还没有计入活动的交易")
                            .font(.subheadline.weight(.medium))
                        Text("使用上方入口记录新消费，或从已有交易中选择。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    ForEach(sortedAllocations, id: \.id) { allocation in
                        Button {
                            editingAllocation = allocation
                            showingAllocationEditor = true
                        } label: {
                            allocationRow(allocation)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(allocationAccessibilityText(allocation))
                        .accessibilityHint("编辑这笔促销分配")
                    }
                    .onDelete { offsets in
                        if let allocation = offsets.map({ sortedAllocations[$0] }).first {
                            requestDeleteAllocation(allocation)
                        }
                    }
                }
            }
            Section("报名与资格") {
                LabeledContent("报名状态", value: enrollmentText)
                if displayedPromotion.enrollmentStatus == .notEnrolled {
                    Button("标记已报名", systemImage: "person.crop.circle.badge.checkmark", action: markEnrolled)
                    Text("请先在银行完成报名，再更新这里的记录。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let enrolledOn = displayedPromotion.enrolledOn {
                    LabeledContent("报名日期", value: CardPilotUI.dateText(enrolledOn))
                }
                if let deadline = displayedPromotion.enrollmentDeadline {
                    LabeledContent("报名截止", value: CardPilotUI.dateText(deadline))
                }
                LabeledContent("资格日期依据", value: qualificationBasisText)
            }
            Section("活动信息") {
                LabeledContent("本期有效期", value: CardPilotUI.dateRangeText(start: displayedPromotion.startOn, end: displayedPromotion.endOn))
                LabeledContent("系列", value: displayedPromotion.seriesID == nil ? "独立活动" : periodIndexText(displayedPromotion))
                LabeledContent("叠加", value: displayedPromotion.stackingAllowed ? "允许" : "不允许")
                LabeledContent("状态", value: presentationStatusText)
                if displayedPromotion.archivedAt != nil {
                    LabeledContent("归档", value: "已归档")
                }
                if !displayedPromotion.organizingBanks.isEmpty {
                    LabeledContent("银行主办方", value: displayedPromotion.organizingBanks.map(\.name).joined(separator: "、"))
                }
                if !displayedPromotion.organizingNetworks.isEmpty {
                    LabeledContent("卡组织主办方") {
                        HStack(spacing: 5) {
                            ForEach(displayedPromotion.organizingNetworks, id: \.id) { network in
                                CardNetworkBadge(network: network)
                            }
                        }
                    }
                }
                if let threshold = displayedPromotion.qualificationThreshold {
                    LabeledContent("累计达标门槛", value: CardPilotUI.amountText(threshold, currencyCode: displayedPromotion.progressCurrencyCode))
                }
                if let cap = displayedPromotion.qualifyingCap {
                    LabeledContent("累计计入上限", value: CardPilotUI.amountText(cap, currencyCode: displayedPromotion.progressCurrencyCode))
                }
                if let perTransactionThreshold = displayedPromotion.perTransactionThreshold {
                    LabeledContent(
                        displayedPromotion.benefitTransactionCap == nil ? "单笔计入门槛" : "单笔满足金额",
                        value: CardPilotUI.amountText(perTransactionThreshold, currencyCode: displayedPromotion.progressCurrencyCode)
                    )
                }
                if let benefitTransactionCap = displayedPromotion.benefitTransactionCap {
                    LabeledContent("优惠笔数上限", value: "\(benefitTransactionCap) 笔")
                }
            }
            if !displayedPromotion.rewardDescription.isEmpty
                || !displayedPromotion.rules.isEmpty
                || !displayedPromotion.exclusions.isEmpty
                || !displayedPromotion.notes.isEmpty {
                Section("奖励与规则") {
                    if !displayedPromotion.rewardDescription.isEmpty {
                        detailTextRow(title: "奖励", text: displayedPromotion.rewardDescription)
                    }
                    if !displayedPromotion.rules.isEmpty {
                        detailTextRow(title: "规则", text: displayedPromotion.rules)
                    }
                    if !displayedPromotion.exclusions.isEmpty {
                        detailTextRow(title: "排除项", text: displayedPromotion.exclusions)
                    }
                    if !displayedPromotion.notes.isEmpty {
                        detailTextRow(title: "备注", text: displayedPromotion.notes)
                    }
                }
            }
            if !displayedPromotion.eligibleCards.isEmpty {
                Section("适用卡") {
                    ForEach(displayedPromotion.eligibleCards.sorted { cardName($0) < cardName($1) }, id: \.id) { card in
                        PromotionCardSelectionRow(card: card, reasons: [])
                    }
                }
            } else {
                Section("适用卡") {
                    Text("尚未选择适用卡。本活动不会出现在自动推荐中，你仍可手动计入交易。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(displayedPromotion.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingPromotionEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("编辑促销")
            }
            if displayedPromotion.seriesID == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        copyToNextMonth()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制到下个月")
                }
            }
        }
        .sheet(isPresented: $showingTransactionEditor) {
            TransactionEditorView(transaction: nil, cards: cards, promotions: allPromotions, transactions: transactions, initialPromotion: displayedPromotion)
        }
        .sheet(isPresented: $showingPromotionEditor) {
            PromotionEditorView(promotion: displayedPromotion, banks: banks, networks: networks, cards: cards)
        }
        .sheet(isPresented: $showingAllocationEditor) {
            AllocationEditorView(promotion: displayedPromotion, allocation: editingAllocation)
        }
        .confirmationDialog("确认删除分配？", isPresented: $showingAllocationDeleteConfirmation) {
            Button("删除分配", role: .destructive) {
                if let allocationPendingDeletion {
                    deleteAllocation(allocationPendingDeletion)
                }
                allocationPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                allocationPendingDeletion = nil
            }
        } message: {
            Text("将移除“\(pendingAllocationLabel)”在本期的促销分配。")
        }
        .alert("无法完成操作", isPresented: errorPresented) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func centeredActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Label(title, systemImage: systemImage)
                .font(.headline)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var seriesSection: some View {
        Section("促销系列") {
            HStack {
                Button {
                    selectPeriod(at: displayedPeriodIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(displayedPeriodIndex == 0)
                .accessibilityLabel("上一期")
                Spacer()
                Menu {
                    ForEach(seriesPromotions, id: \.id) { period in
                        Button {
                            selectedPeriodID = period.id
                        } label: {
                            Label(
                                "\(periodIndexText(period)) · \(periodStatusText(period))",
                                systemImage: period.id == displayedPromotion.id ? "checkmark" : "calendar"
                            )
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(periodIndexText(displayedPromotion))
                            .font(.subheadline.weight(.semibold))
                        Text(CardPilotUI.dateRangeText(start: displayedPromotion.startOn, end: displayedPromotion.endOn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("选择促销期")
                Spacer()
                Button {
                    selectPeriod(at: displayedPeriodIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(displayedPeriodIndex >= seriesPromotions.count - 1)
                .accessibilityLabel("下一期")
            }
            Text("本期、往期和后续期都保留独立进度；可从这里快速切换。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func allocationRow(_ allocation: PromotionAllocation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: allocation.transaction.kind == .refund ? "arrow.uturn.backward.circle.fill" : "cart.circle.fill")
                .font(.title3)
                .foregroundStyle(allocation.transaction.kind == .refund ? Color.orange : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(allocation.transaction.merchant.isEmpty ? "未填写商户" : allocation.transaction.merchant)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(CardPilotUI.dateText(allocation.transaction.transactionOn)) · \(transactionCardText(allocation.transaction))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(allocation.transaction.kind == .refund ? "−" : "+")\(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(allocation.transaction.kind == .refund ? .orange : .primary)
        }
        .contentShape(Rectangle())
    }

    private func allocationAccessibilityText(_ allocation: PromotionAllocation) -> String {
        let merchant = allocation.transaction.merchant.isEmpty ? "未填写商户" : allocation.transaction.merchant
        let sign = allocation.transaction.kind == .refund ? "退款" : "消费"
        return "\(merchant)，\(sign)，\(CardPilotUI.dateText(allocation.transaction.transactionOn))，\(transactionCardText(allocation.transaction))，计入 \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))"
    }

    private func transactionCardText(_ transaction: Transaction) -> String {
        let name = transaction.card.nickname.isEmpty ? transaction.card.productName : transaction.card.nickname
        return "\(transaction.card.account.bank.name) \(name)，末四位 \(transaction.card.lastFour)"
    }

    private func detailTextRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enrollmentText: String {
        switch displayedPromotion.enrollmentStatus {
        case .notRequired: return "无需报名"
        case .notEnrolled: return "尚未报名"
        case .enrolled: return "已报名"
        }
    }

    private var qualificationBasisText: String {
        switch displayedPromotion.qualificationDateBasis {
        case .transactionDate: return "交易日期"
        case .postingDate: return "入账日期"
        case .unknown: return "交易日期或入账日期"
        }
    }

    private var presentationStatusText: String {
        switch PromotionPresentation.status(of: displayedPromotion, today: CardPilotUI.rawDate(Date())) {
        case .active: return "进行中"
        case .upcoming: return "即将开始"
        case .history: return displayedPromotion.archivedAt == nil ? "已结束" : "已归档"
        }
    }

    private func periodIndexText(_ period: Promotion) -> String {
        guard let index = period.seriesIndex else { return "独立活动" }
        return "第 \(index + 1) 期，共 \(PromotionPresentation.totalPeriodCount(in: seriesPromotions)) 期"
    }

    private func periodStatusText(_ period: Promotion) -> String {
        switch PromotionPresentation.status(of: period, today: CardPilotUI.rawDate(Date())) {
        case .active: return "进行中"
        case .upcoming: return "即将开始"
        case .history: return period.archivedAt == nil ? "已结束" : "已归档"
        }
    }

    private func promotionPeriodOrder(_ lhs: Promotion, _ rhs: Promotion) -> Bool {
        if lhs.seriesIndex != rhs.seriesIndex {
            return (lhs.seriesIndex ?? Int.max) < (rhs.seriesIndex ?? Int.max)
        }
        if lhs.startOn != rhs.startOn { return lhs.startOn < rhs.startOn }
        if lhs.endOn != rhs.endOn { return lhs.endOn < rhs.endOn }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func selectPeriod(at index: Int) {
        guard seriesPromotions.indices.contains(index) else { return }
        selectedPeriodID = seriesPromotions[index].id
    }

    private func markEnrolled() {
        displayedPromotion.enrollmentStatus = .enrolled
        displayedPromotion.enrolledOn = CardPilotUI.rawDate(.now)
        do {
            try displayedPromotion.validate()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "报名状态未保存：\(error.localizedDescription)"
        }
    }

    private func addAllocation() {
        editingAllocation = nil
        showingAllocationEditor = true
    }

    private func requestDeleteAllocation(_ allocation: PromotionAllocation) {
        allocationPendingDeletion = allocation
        showingAllocationDeleteConfirmation = true
    }

    private func deleteAllocation(_ allocation: PromotionAllocation) {
        modelContext.delete(allocation)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "分配未删除：\(error.localizedDescription)"
        }
    }

    private var pendingAllocationLabel: String {
        guard let allocation = allocationPendingDeletion else { return "这笔交易" }
        let merchant = allocation.transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return merchant.isEmpty ? "这笔交易" : merchant
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func copyToNextMonth() {
        guard let copy = displayedPromotion.copiedToNextMonth() else {
            errorMessage = "无法生成下个月的完整日期。"
            return
        }
        do {
            try copy.validate()
            modelContext.insert(copy)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "促销未复制：\(error.localizedDescription)"
        }
    }

    private func cardName(_ card: Card) -> String {
        card.nickname.isEmpty ? card.productName : card.nickname
    }
}

private struct AllocationEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let promotion: Promotion
    let allocation: PromotionAllocation?
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]

    @State private var transactionID: UUID
    @State private var amountText: String
    @State private var transactionSearchText = ""
    @State private var showingTransactionChoices = false
    @State private var errorMessage: String?
    @State private var overRefundWarningMessage: String?

    init(promotion: Promotion, allocation: PromotionAllocation?) {
        self.promotion = promotion
        self.allocation = allocation
        _transactionID = State(initialValue: allocation?.transaction.id ?? UUID())
        _amountText = State(initialValue: allocation.map { CardPilotUI.editableAmountText($0.qualifyingAmount) } ?? "")
    }

    private var candidateTransactions: [Transaction] {
        orderedTransactions.filter { transaction in
            PromotionCalculator.includes(transaction, in: promotion)
                || allocation?.transaction.id == transaction.id
        }
    }

    private var orderedTransactions: [Transaction] {
        transactions.sorted {
            if $0.transactionOn != $1.transactionOn {
                return $0.transactionOn > $1.transactionOn
            }
            let lhsMerchant = $0.merchant.localizedCaseInsensitiveCompare($1.merchant)
            if lhsMerchant != .orderedSame { return lhsMerchant == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var filteredTransactions: [Transaction] {
        let query = transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orderedTransactions }
        return orderedTransactions.filter { transaction in
            transactionLabel(transaction).localizedCaseInsensitiveContains(query)
                || transaction.card.account.bank.name.localizedCaseInsensitiveContains(query)
                || transaction.card.productName.localizedCaseInsensitiveContains(query)
                || transaction.card.nickname.localizedCaseInsensitiveContains(query)
                || transaction.card.lastFour.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedTransaction: Transaction? {
        transactions.first { $0.id == transactionID }
    }

    private var editSnapshot: String {
        editorSnapshot(transactionID, amountText)
    }

    var body: some View {
        NavigationStack {
            editorForm
            .onAppear(perform: setInitialAmount)
            .onChange(of: transactionID) { _, _ in setInitialAmountIfBlank() }
            .onChange(of: transactionSearchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showingTransactionChoices = true
                }
            }
            .navigationTitle(allocation == nil ? "添加促销分配" : "编辑促销分配")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .alert("退款分配超出可退范围", isPresented: overRefundWarningPresented) {
                Button("取消", role: .cancel) {}
                Button("仍然保存", role: .destructive) { save(allowingOverRefund: true) }
            } message: {
                Text(overRefundWarningMessage ?? "")
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var editorForm: some View {
        Form {
            transactionSection
            if let errorMessage {
                InlineErrorView(message: errorMessage)
            }
        }
    }

    private var transactionSection: some View {
        Section("交易") {
            if transactions.isEmpty {
                Text("请先添加交易。")
                    .foregroundStyle(.secondary)
            } else {
                if let selectedTransaction {
                    selectedTransactionRow(selectedTransaction)
                }
                if allocation == nil {
                    DisclosureGroup(isExpanded: $showingTransactionChoices) {
                        TextField("搜索商户、日期、卡片或末四位", text: $transactionSearchText)
                            .textInputAutocapitalization(.never)
                        if filteredTransactions.isEmpty {
                            Text("没有匹配的交易。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredTransactions, id: \.id) { transaction in
                                Button {
                                    transactionID = transaction.id
                                    showingTransactionChoices = false
                                } label: {
                                    transactionRow(transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } label: {
                        Label("更换交易（\(filteredTransactions.count) 笔）", systemImage: "magnifyingglass")
                    }
                }
                if allocation != nil {
                    Text("编辑现有分配时不能更换交易；如需更换，请新建分配。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let selectedTransaction, !PromotionCalculator.includes(selectedTransaction, in: promotion) {
                    Text("这笔交易不是自动候选，仍可按条款手动分配。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            TextField("计入活动的金额（\(promotion.progressCurrencyCode)）", text: $amountText)
                .keyboardType(.decimalPad)
            if let selectedTransaction, selectedTransaction.currencyCode != promotion.progressCurrencyCode {
                Text("交易币种为 \(selectedTransaction.currencyCode)，请填写银行认可的合格金额。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let suggestionHint {
                Text(suggestionHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func selectedTransactionRow(_ transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(transaction.kind == .refund ? "退款" : "消费")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(transaction.kind == .refund ? .orange : .secondary)
            }
            Text("\(CardPilotUI.dateText(transaction.transactionOn)) · \(transactionCardText(transaction))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("已选择 \(transactionLabel(transaction))")
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(CardPilotUI.dateText(transaction.transactionOn)) · \(transactionCardText(transaction))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))
                    .font(.caption.monospacedDigit())
                Text(PromotionCalculator.includes(transaction, in: promotion) ? "推荐" : "手动")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(PromotionCalculator.includes(transaction, in: promotion) ? Color.accentColor : Color.orange)
            }
            if transaction.id == transactionID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transactionLabel(transaction))
    }

    private var suggestionHint: String? {
        guard allocation == nil, let transaction = selectedTransaction,
              transaction.kind == .purchase,
              transaction.currencyCode == promotion.progressCurrencyCode,
              let progress = try? PromotionCalculator.progress(for: promotion) else { return nil }
        if allocation == nil,
           let cap = promotion.benefitTransactionCap,
           progress.usedTransactionCount >= cap {
            return "优惠笔数已达到 \(cap) 笔；如需记录第 \(progress.usedTransactionCount + 1) 笔，请确认后仍可保存。"
        }
        if let threshold = promotion.perTransactionThreshold, transaction.amount < threshold {
            return "这笔交易低于单笔计入门槛；如银行条款另有说明，可手动填写正数。"
        }
        if let cap = promotion.qualifyingCap, progress.qualifiedAmount >= cap {
            return "活动已达到累计计入上限；如需修正可手动填写正数。"
        }
        if let cap = promotion.qualifyingCap,
           let suggested = PromotionCalculator.suggestedQualifyingAmount(
               transactionAmount: transaction.amount,
               transactionCurrencyCode: transaction.currencyCode,
               promotionCurrencyCode: promotion.progressCurrencyCode,
               perTransactionThreshold: promotion.perTransactionThreshold,
               currentQualifiedAmount: progress.qualifiedAmount,
               qualifyingCap: cap
           ), suggested < transaction.amount {
            return "已按剩余可计入上限建议金额；最终以银行认可金额为准。"
        }
        return nil
    }

    private var overRefundWarningPresented: Binding<Bool> {
        Binding(
            get: { overRefundWarningMessage != nil },
            set: { if !$0 { overRefundWarningMessage = nil } }
        )
    }

    private func transactionLabel(_ transaction: Transaction) -> String {
        let merchant = transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant
        return "\(CardPilotUI.dateText(transaction.transactionOn)) · \(merchant) · \(transactionCardText(transaction)) · \(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
    }

    private func transactionCardText(_ transaction: Transaction) -> String {
        let cardName = transaction.card.nickname.isEmpty ? transaction.card.productName : transaction.card.nickname
        return "\(transaction.card.account.bank.name) \(cardName)，末四位 \(transaction.card.lastFour)"
    }

    private func setInitialAmount() {
        let transaction = selectedTransaction ?? candidateTransactions.first ?? transactions.first
        if selectedTransaction == nil, let transaction {
            transactionID = transaction.id
        }
        guard amountText.isEmpty, let transaction else { return }
        if transaction.kind == .refund {
            amountText = transaction.currencyCode == promotion.progressCurrencyCode
                ? CardPilotUI.editableAmountText(transaction.amount)
                : ""
            return
        }
        guard let progress = try? PromotionCalculator.progress(for: promotion) else { return }
        guard let suggestedAmount = PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: transaction.amount,
            transactionCurrencyCode: transaction.currencyCode,
            promotionCurrencyCode: promotion.progressCurrencyCode,
            perTransactionThreshold: promotion.perTransactionThreshold,
            currentQualifiedAmount: progress.qualifiedAmount,
            qualifyingCap: promotion.qualifyingCap
        ), suggestedAmount > .zero else {
            amountText = ""
            return
        }
        amountText = CardPilotUI.editableAmountText(suggestedAmount)
    }

    private func setInitialAmountIfBlank() {
        guard allocation == nil else { return }
        amountText = ""
        setInitialAmount()
    }

    private func save(allowingOverRefund: Bool = false) {
        guard let transaction = selectedTransaction else { errorMessage = "请选择交易。"; return }
        guard let amount = CardPilotUI.decimal(amountText), amount > .zero else {
            errorMessage = "合格金额应为大于 0 的数字。"
            return
        }
        if allocation == nil && promotion.allocations.contains(where: { $0.transaction.id == transaction.id }) {
            errorMessage = "这笔交易已经分配给该促销。"
            return
        }
        if !allowingOverRefund,
           transaction.kind == .refund,
           transaction.status == .active,
           let original = transaction.originalTransaction,
           transaction.currencyCode == original.currencyCode,
           PromotionCalculator.overRefundedPromotionIDs(
               originalAllocations: original.allocations.map {
                   (promotionID: $0.promotion.id, qualifyingAmount: $0.qualifyingAmount)
               },
               refundAllocations: [(promotionID: promotion.id, qualifyingAmount: amount)],
               otherRefundAllocations: original.refunds.flatMap { refund in
                   refund.allocations.filter { $0.id != allocation?.id }.map {
                       (
                           transactionID: refund.id,
                           promotionID: $0.promotion.id,
                           qualifyingAmount: $0.qualifyingAmount,
                           status: refund.status
                       )
                   }
               },
               excludingTransactionID: transaction.id
           ).contains(promotion.id) {
            overRefundWarningMessage = "该促销的退款分配将超过原消费的可退余额。"
            return
        }
        if !allowingOverRefund,
           transaction.kind == .purchase,
           PromotionCalculator.overRefundedPromotionIDs(
               originalAllocations: transaction.allocations
                   .filter { $0.id != allocation?.id }
                   .map { (promotionID: $0.promotion.id, qualifyingAmount: $0.qualifyingAmount) }
                   + [(promotionID: promotion.id, qualifyingAmount: amount)],
               refundAllocations: transaction.refunds
                   .filter { $0.status == .active && $0.currencyCode == transaction.currencyCode }
                   .flatMap { refund in
                       refund.allocations.map {
                           (promotionID: $0.promotion.id, qualifyingAmount: $0.qualifyingAmount)
                       }
                   },
               otherRefundAllocations: [],
               excludingTransactionID: nil
           ).contains(promotion.id) {
            overRefundWarningMessage = "该促销的退款分配将超过修改后的原消费分配。"
            return
        }
        let target = allocation ?? PromotionAllocation(transaction: transaction, promotion: promotion, qualifyingAmount: amount, currencyCode: promotion.progressCurrencyCode)
        target.transaction = transaction
        target.promotion = promotion
        target.qualifyingAmount = amount
        target.currencyCode = promotion.progressCurrencyCode
        do {
            try target.validate()
            if allocation == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "分配未保存：\(error.localizedDescription)"
        }
    }
}
