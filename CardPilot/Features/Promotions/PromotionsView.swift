import SwiftData
import SwiftUI

struct PromotionsView: View {
    @Environment(\.currentDay) private var currentDay
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
        let groups = self.groups
        let activeGroups = groups.filter { $0.status == .active }
        let upcomingGroups = groups.filter { $0.status == .upcoming }
        let historyGroups = groups.filter { $0.status == .history }
        NavigationStack {
            Group {
                if groups.isEmpty {
                    let archivedOnly = trimmedSearchText.isEmpty && !promotions.isEmpty && !showingArchived
                    ContentUnavailableView {
                        Label(trimmedSearchText.isEmpty ? (archivedOnly ? "活动均已归档" : "还没有促销活动") : "没有匹配的促销", systemImage: trimmedSearchText.isEmpty ? "gift" : "magnifyingglass")
                    } description: {
                        Text(trimmedSearchText.isEmpty ? (archivedOnly ? "活动仍保存在归档中，可以随时查看。" : "记录一个活动，随时查看还差多少、还能用几次。") : "试试活动标题、银行、卡组织或卡片末四位。")
                    } actions: {
                        if archivedOnly {
                            Button("查看已归档活动", systemImage: "archivebox") {
                                showingArchived = true
                                showingHistory = true
                            }
                        } else if trimmedSearchText.isEmpty {
                            Button("添加活动", systemImage: "plus") {
                                editingPromotion = nil
                                showingEditor = true
                            }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Color(uiColor: .systemBackground))
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
            .trackedSheet(isPresented: $showingEditor) {
                PromotionEditorView(promotion: editingPromotion, banks: banks, networks: networks, cards: cards)
            }
            .confirmationDialog(promotionPendingDeletion?.seriesID == nil ? "确认删除活动？" : "确认删除此期？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button(promotionPendingDeletion?.seriesID == nil ? "永久删除" : "仅删除此期", role: .destructive) {
                    if let promotionPendingDeletion {
                        delete(promotionPendingDeletion)
                    }
                    promotionPendingDeletion = nil
                }
                Button("取消", role: .cancel) {
                    promotionPendingDeletion = nil
                }
            } message: {
                if let target = promotionPendingDeletion {
                    Text("将永久删除“\(target.title)” · \(promotionPeriodDescription(target))。"
                         + (target.seriesID == nil ? "" : "其他期及其进度会保留。"))
                }
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
            today: currentDay.today.rawValue,
            includeArchived: showingArchived,
            searchText: searchText
        )
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
                Label("编辑此期", systemImage: "pencil")
            }
            Button(role: .destructive) {
                requestDelete(group.representative)
            } label: {
                Label("删除此期", systemImage: "trash")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.currentDay) private var currentDay
    let group: PromotionSeriesGroup
    private var promotion: Promotion { group.representative }
    private var progress: PromotionProgress? { try? PromotionCalculator.progress(for: promotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 7))
                : AnyLayout(HStackLayout())
            headerLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(promotion.title)
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    if group.isSeries {
                        Text("系列 · \(periodText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                statusBadge
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !promotion.rewardDescription.isEmpty {
                Text(promotion.rewardDescription)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(organizerText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                enrollmentBadge
                if promotion.archivedAt != nil {
                    Label("已归档", systemImage: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            if promotion.enrollmentStatus == .notEnrolled, let deadline = promotion.enrollmentDeadline {
                Label("报名截止 \(CardPilotUI.dateText(deadline))", systemImage: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        promotionEnrollmentText(promotion, today: currentDay.today.rawValue)
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
        var values = [promotion.title, statusText]
        if promotion.archivedAt != nil { values.append("已归档") }
        if !promotion.rewardDescription.isEmpty { values.append("奖励：\(promotion.rewardDescription)") }
        values += [organizerText, periodText, CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn), enrollmentText]
        if promotion.enrollmentStatus == .notEnrolled, let deadline = promotion.enrollmentDeadline {
            values.append("报名截止 \(CardPilotUI.dateText(deadline))")
        }
        if let progress {
            if let cap = progress.benefitTransactionCap {
                let remaining = progress.remainingTransactionCount ?? cap
                values.append("已用 \(progress.usedTransactionCount)/\(cap) 次，\(remaining == 0 ? "优惠次数已用完" : "剩余可用 \(remaining) 次")")
            } else if let threshold = progress.qualificationThreshold {
                values.append("进度 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))，目标 \(CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))")
            } else {
                values.append("已计入 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
            }
        }
        return values.joined(separator: "，")
    }
}

struct PromotionProgressSummary: View {
    let promotion: Promotion
    let progress: PromotionProgress
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            if let cap = progress.benefitTransactionCap {
                Text(progress.isComplete ? "优惠次数已用完" : "剩余可用 \(progress.remainingTransactionCount ?? cap) 次")
                    .font(compact ? .caption : .headline)
                    .foregroundStyle(progress.isComplete ? Color.secondary : Color.primary)
                    .accessibilityIdentifier("promotion.remaining.\(promotion.title)")
                Text("已用 \(progress.usedTransactionCount) / \(cap) 次")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            } else if let threshold = progress.qualificationThreshold {
                Text(progress.isComplete ? "已达标" : "还需 \(CardPilotUI.amountText(progress.remainingToThreshold ?? threshold, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .headline)
                    .foregroundStyle(progress.isComplete ? Color.green : Color.primary)
                    .accessibilityIdentifier("promotion.remaining.\(promotion.title)")
                Text("\(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode)) / \(CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))")
                    .accessibilityIdentifier("promotion.progress.\(promotion.title)")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
                ProgressView(
                    value: decimalDouble(min(max(.zero, progress.qualifiedAmount), threshold)),
                    total: decimalDouble(threshold)
                )
                .tint(progress.isComplete ? .green : .accentColor)
                if let cap = progress.qualifyingCap {
                    Text("计入上限剩余 \(CardPilotUI.amountText(progress.remainingCap ?? cap, currencyCode: promotion.progressCurrencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let cap = progress.qualifyingCap {
                Text("剩余可计入 \(CardPilotUI.amountText(progress.remainingCap ?? cap, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .headline)
                    .accessibilityIdentifier("promotion.remaining.\(promotion.title)")
                Text("已计入 \(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            } else {
                Text("已计入净额：\(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode))")
                    .font(compact ? .caption : .body)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
