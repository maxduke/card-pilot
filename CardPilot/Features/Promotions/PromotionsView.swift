import SwiftData
import SwiftUI

struct PromotionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query private var cards: [Card]

    @State private var showingEditor = false
    @State private var editingPromotion: Promotion?
    @State private var showingArchived = false
    @State private var errorMessage: String?
    @State private var promotionPendingDeletion: Promotion?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if visiblePromotions.isEmpty {
                    EmptyStateView(
                        title: "还没有促销活动",
                        systemImage: "gift",
                        message: "把银行或卡组织活动记录下来，就能手动追踪累计消费进度。"
                    )
                } else {
                    List {
                        ForEach(visiblePromotions, id: \.id) { promotion in
                            NavigationLink {
                                PromotionDetailView(promotion: promotion)
                            } label: {
                                PromotionRow(promotion: promotion)
                            }
                            .contextMenu {
                                Button {
                                    editingPromotion = promotion
                                    showingEditor = true
                                } label: {
                                    Label("编辑促销", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    requestDelete(promotion)
                                } label: {
                                    Label("删除促销", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            if let promotion = offsets.map({ visiblePromotions[$0] }).first {
                                requestDelete(promotion)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("促销")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showingArchived ? "隐藏归档" : "显示归档") {
                        showingArchived.toggle()
                    }
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

    private var visiblePromotions: [Promotion] {
        promotions.filter { showingArchived || $0.archivedAt == nil }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func requestDelete(_ promotion: Promotion) {
        guard promotion.allocations.isEmpty else {
            delete(promotion)
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
    let promotion: Promotion
    private var progress: PromotionProgress? { try? PromotionCalculator.progress(for: promotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(promotion.title)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Text(CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let progress {
                PromotionProgressSummary(promotion: promotion, progress: progress, compact: true)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("促销 \(promotion.title)")
    }

    private var statusText: String {
        let today = CardPilotUI.rawDate(Date())
        if promotion.archivedAt != nil { return "已归档" }
        if promotion.startOn > today { return "即将开始" }
        return promotion.endOn >= today ? "进行中" : "已结束"
    }

    private var statusColor: Color {
        statusText == "进行中" ? .green : .secondary
    }
}

private struct PromotionProgressSummary: View {
    let promotion: Promotion
    let progress: PromotionProgress
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            if let threshold = progress.qualificationThreshold {
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
    @State private var qualificationThresholdText: String
    @State private var qualifyingCapText: String
    @State private var perTransactionThresholdText: String
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
        _qualificationThresholdText = State(initialValue: promotion.flatMap { $0.qualificationThreshold.map(CardPilotUI.editableAmountText) } ?? "")
        _qualifyingCapText = State(initialValue: promotion.flatMap { $0.qualifyingCap.map(CardPilotUI.editableAmountText) } ?? "")
        _perTransactionThresholdText = State(initialValue: promotion.flatMap { $0.perTransactionThreshold.map(CardPilotUI.editableAmountText) } ?? "")
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

    var body: some View {
        NavigationStack {
            Form {
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
                    TextField("累计达标门槛（可选）", text: $qualificationThresholdText)
                        .keyboardType(.decimalPad)
                    TextField("累计计入上限（前 N 元/最高计算金额，可选）", text: $qualifyingCapText)
                        .keyboardType(.decimalPad)
                    TextField("单笔计入门槛（可选）", text: $perTransactionThresholdText)
                        .keyboardType(.decimalPad)
                    CurrencyPickerView(selection: $currencyCode, title: "进度币种")
                        .disabled(promotion?.allocations.isEmpty == false)
                    if promotion?.allocations.isEmpty == false {
                        Text("已有促销分配，进度币种已锁定。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("不适用的规则留空；填写的金额必须大于 0。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("允许与其他活动叠加", isOn: $stackingAllowed)
                    Toggle("归档", isOn: $archived)
                }

                Section("主办方") {
                    if banks.isEmpty && networks.isEmpty {
                        Text("可稍后补充银行或卡组织主办方")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(banks.filter { $0.archivedAt == nil || selectedBankIDs.contains($0.id) }, id: \.id) { bank in
                        Toggle(isOn: binding(for: bank.id, in: $selectedBankIDs)) {
                            HStack(spacing: 10) {
                                BankBadge(bank: bank)
                                Text(bank.name)
                            }
                        }
                    }
                    ForEach(organizerNetworks, id: \.id) { network in
                        Toggle(isOn: binding(for: network.id, in: $selectedNetworkIDs)) {
                            HStack(spacing: 10) {
                                CardNetworkBadge(network: network)
                                Text(network.displayName)
                            }
                        }
                    }
                    Text("只选择活动主办的实际卡组织；双标卡组合请在适用卡中明确勾选。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("推荐适用卡") {
                    if recommendedCards.isEmpty {
                        Text(selectedBankIDs.isEmpty && selectedNetworkIDs.isEmpty
                             ? "选择银行或卡组织后显示启用卡推荐"
                             : "没有找到同时匹配这些主办方的启用卡")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("根据已选主办方匹配")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("全选推荐") {
                                selectedCardIDs.formUnion(recommendedCards.map(\.card.id))
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        ForEach(recommendedCards) { recommendation in
                            Toggle(isOn: binding(for: recommendation.card.id, in: $selectedCardIDs)) {
                                cardRow(recommendation.card, reasons: recommendation.reasons)
                            }
                        }
                    }
                    Text("推荐仅供确认，不会自动成为适用卡。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("其他卡片") {
                    if cards.isEmpty {
                        Text("请先添加卡片")
                            .foregroundStyle(.secondary)
                    } else if otherCards.isEmpty {
                        Text("所有可选卡片均已显示在推荐列表中")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(otherCards, id: \.id) { card in
                            Toggle(isOn: binding(for: card.id, in: $selectedCardIDs)) {
                                cardRow(card)
                            }
                        }
                    }
                    Text("未在推荐中的卡片也可以逐张确认；主办方变化不会移除已确认的适用卡。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                Section("规则说明") {
                    TextField("规则（首版仅自动计算累计消费）", text: $rules, axis: .vertical)
                    TextField("排除项", text: $exclusions, axis: .vertical)
                    TextField("奖励说明", text: $rewardDescription, axis: .vertical)
                    TextField("备注", text: $notes, axis: .vertical)
                }

                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .navigationTitle(promotion == nil ? "添加促销" : "编辑促销")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
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
        let threshold = parseOptionalAmount(qualificationThresholdText, label: "累计达标门槛")
        guard threshold.isValid else { return }
        let cap = parseOptionalAmount(qualifyingCapText, label: "累计计入上限")
        guard cap.isValid else { return }
        let perTransactionThreshold = parseOptionalAmount(perTransactionThresholdText, label: "单笔计入门槛")
        guard perTransactionThreshold.isValid else { return }

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
}

struct PromotionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let promotion: Promotion
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query private var cards: [Card]
    @State private var showingAllocationEditor = false
    @State private var editingAllocation: PromotionAllocation?
    @State private var showingPromotionEditor = false
    @State private var errorMessage: String?

    private var progress: PromotionProgress? { try? PromotionCalculator.progress(for: promotion) }

    var body: some View {
        List {
            Section("进度") {
                if let progress {
                    PromotionProgressSummary(promotion: promotion, progress: progress, compact: false)
                } else {
                    Text("暂时无法计算进度。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("促销分配") {
                if promotion.allocations.isEmpty {
                    Text("还没有分配交易。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(promotion.allocations.sorted { $0.transaction.transactionOn > $1.transaction.transactionOn }, id: \.id) { allocation in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(allocation.transaction.merchant.isEmpty ? "未填写商户" : allocation.transaction.merchant)
                                Text(CardPilotUI.dateText(allocation.transaction.transactionOn))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(allocation.transaction.kind == .refund ? "−" : "+")\(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                                .foregroundStyle(allocation.transaction.kind == .refund ? .orange : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingAllocation = allocation
                            showingAllocationEditor = true
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        offsets.map { promotion.allocations.sorted { $0.transaction.transactionOn > $1.transaction.transactionOn }[$0] }.forEach { allocation in
                            modelContext.delete(allocation)
                        }
                        do {
                            try modelContext.save()
                        } catch {
                            modelContext.rollback()
                            errorMessage = "分配未删除：\(error.localizedDescription)"
                        }
                    }
                }
            }
            Section("活动信息") {
                LabeledContent("有效期", value: CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
                LabeledContent("叠加", value: promotion.stackingAllowed ? "允许" : "不允许")
                if !promotion.organizingBanks.isEmpty {
                    LabeledContent("银行主办方", value: promotion.organizingBanks.map(\.name).joined(separator: "、"))
                }
                if !promotion.organizingNetworks.isEmpty {
                    LabeledContent("卡组织主办方") {
                        HStack(spacing: 5) {
                            ForEach(promotion.organizingNetworks, id: \.id) { network in
                                CardNetworkBadge(network: network)
                            }
                        }
                    }
                }
                if let threshold = promotion.qualificationThreshold {
                    LabeledContent("累计达标门槛", value: CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))
                }
                if let cap = promotion.qualifyingCap {
                    LabeledContent("累计计入上限", value: CardPilotUI.amountText(cap, currencyCode: promotion.progressCurrencyCode))
                }
                if let perTransactionThreshold = promotion.perTransactionThreshold {
                    LabeledContent("单笔计入门槛", value: CardPilotUI.amountText(perTransactionThreshold, currencyCode: promotion.progressCurrencyCode))
                }
            }
            if !promotion.eligibleCards.isEmpty {
                Section("适用卡") {
                    ForEach(promotion.eligibleCards.sorted { cardName($0) < cardName($1) }, id: \.id) { card in
                        HStack(spacing: 10) {
                            BankBadge(bank: card.account.bank)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cardName(card))
                                HStack(spacing: 6) {
                                    CardNetworksBadges(networks: card.networks)
                                    Text("•••• \(card.lastFour)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(promotion.title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingPromotionEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("编辑促销")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if promotion.seriesID == nil {
                        Button {
                            copyToNextMonth()
                        } label: {
                            Label("复制到下个月", systemImage: "doc.on.doc")
                        }
                    }
                    Button {
                        editingAllocation = nil
                        showingAllocationEditor = true
                    } label: {
                        Label("添加促销分配", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("促销操作")
            }
        }
        .sheet(isPresented: $showingPromotionEditor) {
            PromotionEditorView(promotion: promotion, banks: banks, networks: networks, cards: cards)
        }
        .sheet(isPresented: $showingAllocationEditor) {
            AllocationEditorView(promotion: promotion, allocation: editingAllocation)
        }
        .alert("无法完成操作", isPresented: errorPresented) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func copyToNextMonth() {
        guard let copy = promotion.copiedToNextMonth() else {
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
    @State private var errorMessage: String?
    @State private var overRefundWarningMessage: String?

    init(promotion: Promotion, allocation: PromotionAllocation?) {
        self.promotion = promotion
        self.allocation = allocation
        _transactionID = State(initialValue: allocation?.transaction.id ?? UUID())
        _amountText = State(initialValue: allocation.map { CardPilotUI.editableAmountText($0.qualifyingAmount) } ?? "")
    }

    private var candidateTransactions: [Transaction] {
        transactions.filter { transaction in
            PromotionCalculator.includes(transaction, in: promotion)
                || allocation?.transaction.id == transaction.id
        }
    }

    private var selectedTransaction: Transaction? {
        transactions.first { $0.id == transactionID }
    }

    var body: some View {
        NavigationStack {
            editorForm
            .onAppear(perform: setInitialAmount)
            .onChange(of: transactionID) { _, _ in setInitialAmountIfBlank() }
            .navigationTitle(allocation == nil ? "添加促销分配" : "编辑促销分配")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .alert("退款分配超出可退范围", isPresented: overRefundWarningPresented) {
                Button("取消", role: .cancel) {}
                Button("仍然保存", role: .destructive) { save(allowingOverRefund: true) }
            } message: {
                Text(overRefundWarningMessage ?? "")
            }
        }
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
                Picker("选择交易", selection: $transactionID) {
                    ForEach(candidateTransactions, id: \.id) { transaction in
                        Text(transactionLabel(transaction)).tag(transaction.id)
                    }
                    ForEach(transactions.filter { transaction in
                        !candidateTransactions.contains(where: { $0.id == transaction.id })
                    }, id: \.id) { transaction in
                        Text("手动：\(transactionLabel(transaction))").tag(transaction.id)
                    }
                }
                .disabled(allocation != nil)
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

    private var suggestionHint: String? {
        guard allocation == nil, let transaction = selectedTransaction,
              transaction.kind == .purchase,
              transaction.currencyCode == promotion.progressCurrencyCode,
              let progress = try? PromotionCalculator.progress(for: promotion) else { return nil }
        if let threshold = promotion.perTransactionThreshold, transaction.amount < threshold {
            return "这笔交易低于单笔计入门槛，已默认填 0；如银行条款另有说明，可手动修改。"
        }
        if let cap = promotion.qualifyingCap, progress.qualifiedAmount >= cap {
            return "活动已达到累计计入上限，已默认填 0；如需修正可手动修改。"
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
        return "\(CardPilotUI.dateText(transaction.transactionOn)) · \(merchant) · \(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
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
        ) else {
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
        guard let amount = CardPilotUI.decimal(amountText), amount >= .zero else {
            errorMessage = "合格金额应为不小于 0 的数字。"
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
