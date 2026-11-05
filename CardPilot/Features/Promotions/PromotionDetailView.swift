import SwiftData
import SwiftUI

struct PromotionDetailView: View {
    @Environment(\.currentDay) private var currentDay
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let promotion: Promotion
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query private var cards: [Card]
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @State private var showingTransactionEditor = false
    @Query private var allPromotions: [Promotion]
    @State private var showingAllocationEditor = false
    @State private var editingAllocation: PromotionAllocation?
    @State private var showingEditOptions = false
    @State private var promotionEditorStep: PromotionEditorStep?
    @State private var selectedPeriodID: UUID
    @State private var allocationPendingDeletion: PromotionAllocation?
    @State private var showingAllocationDeleteConfirmation = false
    @State private var showingCopyConfirmation = false
    @State private var showingCopyCompleted = false
    @State private var copiedPeriod: PromotionPeriod?
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
            progressSection
            Section("更新进度") {
                Button {
                    showingTransactionEditor = true
                } label: {
                    promotionActionLabel(
                        title: "记录新消费",
                        subtitle: "创建交易并自动带入本活动",
                        systemImage: "plus",
                        tint: .accentColor,
                        isEnabled: !cards.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(cards.isEmpty)
                .accessibilityLabel("记录新消费")
                .accessibilityHint("创建交易并预选当前活动")
                .accessibilityIdentifier("recordPromotionTransaction")

                Button {
                    addAllocation()
                } label: {
                    promotionActionLabel(
                        title: "选择已有交易",
                        subtitle: "从交易记录中选择并填写计入金额",
                        systemImage: "list.bullet.rectangle",
                        tint: .secondary,
                        isEnabled: !transactions.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(transactions.isEmpty)
                .accessibilityLabel("选择已有交易")
                .accessibilityHint("从交易记录中选择并计入当前活动")
                .accessibilityIdentifier("allocateExistingTransaction")

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
            enrollmentSection
            Section("活动信息") {
                detailValueRow("本期有效期", value: CardPilotUI.dateRangeText(start: displayedPromotion.startOn, end: displayedPromotion.endOn))
                detailValueRow("系列", value: displayedPromotion.seriesID == nil ? "独立活动" : periodIndexText(displayedPromotion))
                detailValueRow("叠加", value: displayedPromotion.stackingAllowed ? "允许" : "不允许")
                detailValueRow("状态", value: presentationStatusText)
                if displayedPromotion.archivedAt != nil {
                    detailValueRow("归档", value: "已归档")
                }
                if !displayedPromotion.organizingBanks.isEmpty {
                    detailValueRow("银行主办方", value: displayedPromotion.organizingBanks.map(\.name).joined(separator: "、"))
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
                    detailValueRow("累计达标门槛", value: CardPilotUI.amountText(threshold, currencyCode: displayedPromotion.progressCurrencyCode))
                }
                if let cap = displayedPromotion.qualifyingCap {
                    detailValueRow("累计计入上限", value: CardPilotUI.amountText(cap, currencyCode: displayedPromotion.progressCurrencyCode))
                }
                if let perTransactionThreshold = displayedPromotion.perTransactionThreshold {
                    detailValueRow(
                        displayedPromotion.benefitTransactionCap == nil ? "单笔计入门槛" : "单笔满足金额",
                        value: CardPilotUI.amountText(perTransactionThreshold, currencyCode: displayedPromotion.progressCurrencyCode)
                    )
                }
                if let benefitTransactionCap = displayedPromotion.benefitTransactionCap {
                    detailValueRow("优惠笔数上限", value: "\(benefitTransactionCap) 笔")
                }
            }
            if !displayedPromotion.rules.isEmpty
                || !displayedPromotion.exclusions.isEmpty
                || !displayedPromotion.notes.isEmpty {
                Section("规则与说明") {
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
                    showingEditOptions = true
                } label: {
                    Text("编辑")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("编辑促销")
                .accessibilityHint("选择要编辑的内容")
                .accessibilityIdentifier("promotion.edit")
            }
            if displayedPromotion.seriesID == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if nextCopyPeriod == nil {
                            errorMessage = "无法生成下个月的完整日期。"
                        } else {
                            showingCopyConfirmation = true
                        }
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制到下个月")
                }
            }
        }
        .confirmationDialog("编辑促销", isPresented: $showingEditOptions, titleVisibility: .visible) {
            ForEach(PromotionEditorStep.allCases) { item in
                Button("编辑\(item.editingTitle)") {
                    promotionEditorStep = item
                }
            }
            Button("取消", role: .cancel) {}
        }
        .trackedSheet(isPresented: $showingTransactionEditor) {
            TransactionEditorView(transaction: nil, cards: cards, promotions: allPromotions, initialPromotion: displayedPromotion)
        }
        .trackedSheet(item: $promotionEditorStep) { step in
            PromotionEditorView(promotion: displayedPromotion, banks: banks, networks: networks, cards: cards, initialStep: step)
        }
        .trackedSheet(isPresented: $showingAllocationEditor) {
            AllocationEditorView(promotion: displayedPromotion, allocation: editingAllocation)
        }
        .confirmationDialog("复制到下个月？", isPresented: $showingCopyConfirmation, titleVisibility: .visible) {
            Button("复制活动", action: copyToNextMonth)
            Button("取消", role: .cancel) {}
        } message: {
            if let period = nextCopyPeriod {
                Text("将新建 \(CardPilotUI.dateRangeText(start: period.startOn, end: period.endOn)) 的独立活动。进度和已报名记录不会复制。")
            }
        }
        .alert("复制完成", isPresented: $showingCopyCompleted) {
            Button("好", role: .cancel) {}
        } message: {
            if let copiedPeriod {
                Text("已创建 \(CardPilotUI.dateRangeText(start: copiedPeriod.startOn, end: copiedPeriod.endOn)) 的活动，可返回促销列表查看。")
            }
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

    private func promotionActionLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isEnabled ? tint : Color.secondary)
                .frame(width: 36, height: 36)
                .background(
                    (isEnabled ? tint : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var enrollmentSection: some View {
        Section("报名与资格") {
            detailValueRow("报名状态", value: enrollmentText)
                .accessibilityIdentifier("promotion.enrollmentStatus")
            if displayedPromotion.enrollmentStatus == .notEnrolled {
                Button("标记已报名", systemImage: "person.crop.circle.badge.checkmark", action: markEnrolled)
                Text("请先在银行完成报名，再更新这里的记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let enrolledOn = displayedPromotion.enrolledOn {
                detailValueRow("报名日期", value: CardPilotUI.dateText(enrolledOn))
            }
            if let deadline = displayedPromotion.enrollmentDeadline {
                detailValueRow("报名截止", value: CardPilotUI.dateText(deadline))
                if displayedPromotion.enrollmentStatus == .notEnrolled {
                    NavigationLink("报名提醒设置", systemImage: "bell") {
                        ReminderSettingsView()
                    }
                    .accessibilityIdentifier("promotion.enrollment.reminders")
                }
            }
            detailValueRow("资格日期依据", value: qualificationBasisText)
                .accessibilityIdentifier("promotion.qualificationBasis")
        }
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
                if allocation.transaction.status == .reversed {
                    Text("已冲正 · 不计入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(allocation.transaction.kind == .refund ? "−" : "+")\(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                .font(.subheadline.monospacedDigit())
                .strikethrough(allocation.transaction.status == .reversed)
                .foregroundStyle(allocation.transaction.status == .reversed ? Color.secondary
                                 : allocation.transaction.kind == .refund ? Color.orange : Color.primary)
        }
        .contentShape(Rectangle())
    }

    private func allocationAccessibilityText(_ allocation: PromotionAllocation) -> String {
        let merchant = allocation.transaction.merchant.isEmpty ? "未填写商户" : allocation.transaction.merchant
        let sign = allocation.transaction.kind == .refund ? "退款" : "消费"
        let contribution = allocation.transaction.status == .reversed
            ? "已冲正，不计入进度，原分配"
            : allocation.transaction.kind == .refund ? "减少进度" : "计入"
        return "\(merchant)，\(sign)，\(CardPilotUI.dateText(allocation.transaction.transactionOn))，\(transactionCardText(allocation.transaction))，\(contribution) \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))"
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

    private var progressSection: some View {
        Section("进度") {
            if let progress {
                PromotionProgressSummary(promotion: displayedPromotion, progress: progress, compact: false)
            } else {
                Text("暂时无法计算进度。")
                    .foregroundStyle(.secondary)
            }
            detailValueRow("结束日期", value: CardPilotUI.dateText(displayedPromotion.endOn))
                .accessibilityIdentifier("promotion.endDate")
            if !displayedPromotion.rewardDescription.isEmpty {
                detailTextRow(title: "奖励", text: displayedPromotion.rewardDescription)
                    .accessibilityIdentifier("promotion.reward")
            }
        }
    }

    @ViewBuilder
    private func detailValueRow(_ title: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                Text(value).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: value)
        }
    }

    private var enrollmentText: String {
        promotionEnrollmentText(displayedPromotion, today: currentDay.today.rawValue)
    }

    private var qualificationBasisText: String {
        switch displayedPromotion.qualificationDateBasis {
        case .transactionDate: return "交易日期"
        case .postingDate: return "入账日期"
        case .unknown: return "交易日期或入账日期"
        }
    }

    private var presentationStatusText: String {
        switch PromotionPresentation.status(of: displayedPromotion, today: currentDay.today.rawValue) {
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
        switch PromotionPresentation.status(of: period, today: currentDay.today.rawValue) {
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

    private var nextCopyPeriod: PromotionPeriod? {
        guard let start = PromotionSeriesCalculator.shiftedDate(displayedPromotion.startOn, byMonths: 1),
              let end = PromotionSeriesCalculator.shiftedDate(displayedPromotion.endOn, byMonths: 1) else { return nil }
        return PromotionPeriod(startOn: start, endOn: end)
    }

    private func copyToNextMonth() {
        guard let copy = displayedPromotion.copiedToNextMonth() else {
            errorMessage = "无法生成下个月的完整日期。"
            return
        }
        do {
            try PromotionCreationActions.save([copy], context: modelContext)
            copiedPeriod = PromotionPeriod(startOn: copy.startOn, endOn: copy.endOn)
            showingCopyCompleted = true
        } catch {
            errorMessage = "促销未复制：\(error.localizedDescription)"
        }
    }

    private func cardName(_ card: Card) -> String {
        card.nickname.isEmpty ? card.productName : card.nickname
    }
}
