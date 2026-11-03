import SwiftData
import SwiftUI

enum PromotionEditorStep: Int, CaseIterable, Hashable, Identifiable {
    case basics
    case eligibility
    case rules

    var id: Int { rawValue }

    var editingTitle: String { self == .basics ? "基本信息" : title }

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

struct PromotionEditorView: View {
    private enum Field: String, Hashable {
        case title, endDate, repeatUntilDate, currency, enrollmentDeadline
        case reward, rules, exclusions, notes
        case qualificationThreshold
        case qualifyingCap
        case perTransactionThreshold
        case benefitTransactionCap

        var isNumeric: Bool {
            switch self {
            case .qualificationThreshold, .qualifyingCap, .perTransactionThreshold, .benefitTransactionCap: true
            default: false
            }
        }

        var section: PromotionEditorStep {
            switch self {
            case .enrollmentDeadline, .reward, .rules, .exclusions, .notes: .rules
            default: .basics
            }
        }
    }

    private enum ValidationAction { case advance, save }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var showingAdditionalAmountRules: Bool
    @State private var showingRuleNotes: Bool
    @State private var step: PromotionEditorStep
    @State private var showingOrganizerPicker = false
    @State private var showingCardPicker = false
    @State private var errorMessage: String?
    @State private var validationAction: ValidationAction?
    @FocusState private var focusedField: Field?
    @Query private var allPromotions: [Promotion]

    init(promotion: Promotion?, banks: [Bank], networks: [CardNetwork], cards: [Card], initialStep: PromotionEditorStep = .basics) {
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
        _showingAdditionalAmountRules = State(initialValue: promotion?.qualifyingCap != nil || promotion?.perTransactionThreshold != nil)
        _showingRuleNotes = State(initialValue: !(promotion?.rules.isEmpty ?? true)
            || !(promotion?.exclusions.isEmpty ?? true) || !(promotion?.notes.isEmpty ?? true))
        _step = State(initialValue: promotion == nil ? .basics : initialStep)
    }

    private var editSnapshot: String {
        editorSnapshot(title, startDate, endDate, repeatsMonthly, repeatUntilDate, progressMode, qualificationThresholdText, qualifyingCapText, perTransactionThresholdText, benefitTransactionCapText, currencyCode, selectedBankIDs.map(\.uuidString).sorted(), selectedNetworkIDs.map(\.uuidString).sorted(), selectedCardIDs.map(\.uuidString).sorted(), enrollmentStatus, hasEnrolledOn, enrolledOn, hasEnrollmentDeadline, enrollmentDeadline, qualificationDateBasis, stackingAllowed, rules, exclusions, rewardDescription, notes, archived, seriesEditScope)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section {
                        if promotion == nil {
                            editorStepIndicator
                        } else {
                            Picker("编辑内容", selection: $step) {
                                ForEach(PromotionEditorStep.allCases) { item in
                                    Text(item.editingTitle).tag(item)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("promotion.editor.section")
                        }
                    }
                    if promotion?.seriesID != nil {
                        Section {
                            Picker("编辑范围", selection: $seriesEditScope) {
                                Text("仅本期").tag(PromotionSeriesEditScope.thisOnly)
                                Text("本期及以后").tag(PromotionSeriesEditScope.thisAndFuture)
                            }
                            Text("规则修改应用到所选范围；报名状态、报名日期和归档操作只修改本期。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        InlineErrorView(message: errorMessage)
                    }
                    switch step {
                    case .basics:
                        basicsStep
                    case .eligibility:
                        eligibilityStep
                    case .rules:
                        rulesStep
                    }
                }
                // Recreate the Form's scroll position, while keeping a proxy
                // that can reveal errors after switching to another section.
                .id(step)
                .accessibilityIdentifier("promotion.editor.form")
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: focusedField) { _, field in
                    guard let field, field.isNumeric else { return }
                    Task { @MainActor in
                        await Task.yield()
                        guard focusedField == field else { return }
                        scrollProxy.scrollTo(field, anchor: .top)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 12) {
                            if promotion == nil && step != .basics {
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
                        if promotion != nil || step == .rules {
                            Button("保存") { save(using: scrollProxy) }
                                .accessibilityIdentifier("promotion.editor.save")
                        } else {
                            Button("下一步") { advance(using: scrollProxy) }
                                .accessibilityIdentifier("promotion.editor.advance")
                        }
                    }
                    if focusedField?.isNumeric == true {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("收起键盘") { focusedField = nil }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("promotion.keyboard.dismiss")
                        }
                    }
                }
            }
            .onChange(of: step) { _, _ in focusedField = nil }
            .onChange(of: progressMode) { _, mode in
                if mode == .cumulative,
                   !qualifyingCapText.isEmpty || !perTransactionThresholdText.isEmpty {
                    showingAdditionalAmountRules = true
                }
            }
            .navigationTitle(promotion == nil ? "添加促销" : "编辑促销")
            .navigationBarTitleDisplayMode(.inline)
            .trackedSheet(isPresented: $showingOrganizerPicker) {
                OrganizerSelectionView(
                    banks: banks,
                    networks: organizerNetworks,
                    selectedBankIDs: $selectedBankIDs,
                    selectedNetworkIDs: $selectedNetworkIDs
                )
            }
            .trackedSheet(isPresented: $showingCardPicker) {
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
                    .focused($focusedField, equals: .title)
                    .accessibilityIdentifier("promotion.title")
                    .id(Field.title)
                fieldError(.title)
                BillingDatePicker(title: "开始日期", selection: $startDate, identifier: "promotion.startDate")
                    .disabled(promotion?.seriesID != nil)
                BillingDatePicker(title: "结束日期", selection: $endDate, identifier: "promotion.endDate")
                    .disabled(promotion?.seriesID != nil)
                    .id(Field.endDate)
                fieldError(.endDate)
                if promotion == nil {
                    Toggle("每月重复", isOn: $repeatsMonthly)
                    if repeatsMonthly {
                        BillingDatePicker(title: "系列结束日期", selection: $repeatUntilDate,
                                          identifier: "promotion.repeatUntilDate")
                            .id(Field.repeatUntilDate)
                        fieldError(.repeatUntilDate)
                        Text("将创建 \(monthlyPeriodPreview.count) 个完整周期")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if promotion?.seriesID != nil {
                    Text("系列日期由首期锚点按月生成，不能单独修改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("金额与进度") {
                if dynamicTypeSize.isAccessibilitySize {
                    progressModePicker.pickerStyle(.inline)
                } else {
                    progressModePicker
                }
                if progressMode == .perTransaction {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("优惠笔数上限")
                            .font(.subheadline)
                        TextField("正整数", text: $benefitTransactionCapText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .benefitTransactionCap)
                            .accessibilityLabel("优惠笔数上限")
                        fieldError(.benefitTransactionCap)
                        ruleExplanation("例如最多优惠 5 笔：这是可用次数上限，不是必须完成的笔数。")
                    }
                    .id(Field.benefitTransactionCap)
                    amountRuleField("单笔满足金额（可选）", text: $perTransactionThresholdText,
                                    field: .perTransactionThreshold,
                                    explanation: "例如每笔至少 \(CardPilotUI.amountText(100, currencyCode: currencyCode)) 才符合金额条件；留空表示不设单笔门槛。")
                    Text("每笔符合条件的消费计 1 笔；这里只记录已用笔数，不计算优惠金额。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    amountRuleField("累计达标门槛（可选）", text: $qualificationThresholdText,
                                    field: .qualificationThreshold,
                                    explanation: "例如累计满 \(CardPilotUI.amountText(3000, currencyCode: currencyCode)) 才达标；留空表示只记录累计金额。")
                    DisclosureGroup(isExpanded: $showingAdditionalAmountRules) {
                        amountRuleField("累计计入上限（可选）", text: $qualifyingCapText,
                                        field: .qualifyingCap,
                                        explanation: "例如仅前 \(CardPilotUI.amountText(5000, currencyCode: currencyCode)) 可计入：这是上限，不是必须达到的金额。")
                        amountRuleField("单笔计入门槛（可选）", text: $perTransactionThresholdText,
                                        field: .perTransactionThreshold,
                                        explanation: "例如每笔至少 \(CardPilotUI.amountText(100, currencyCode: currencyCode)) 才符合金额条件；它不是累计达标门槛。")
                    } label: {
                        Text("其他金额条件（可选）")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                CurrencyPickerView(selection: $currencyCode, title: "进度币种")
                    .disabled(promotion?.allocations.isEmpty == false)
                    .id(Field.currency)
                fieldError(.currency)
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

    private func amountRuleField(_ title: String, text: Binding<String>, field: Field, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
            TextField("金额", text: text)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .accessibilityLabel(title)
            fieldError(field)
            ruleExplanation(explanation)
        }
        .id(field)
    }

    private func ruleExplanation(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                if dynamicTypeSize.isAccessibilitySize {
                    enrollmentPicker.pickerStyle(.inline)
                } else {
                    enrollmentPicker
                }
                if enrollmentStatus == .enrolled {
                    Toggle("记录报名日期", isOn: $hasEnrolledOn)
                    if hasEnrolledOn {
                        BillingDatePicker(title: "报名日期", selection: $enrolledOn, identifier: "promotion.enrolledOn")
                    }
                }
                if enrollmentStatus != .notRequired {
                    Toggle("设置报名截止日", isOn: $hasEnrollmentDeadline)
                    if hasEnrollmentDeadline {
                        BillingDatePicker(title: "报名截止日", selection: $enrollmentDeadline,
                                          identifier: "promotion.enrollmentDeadline")
                            .id(Field.enrollmentDeadline)
                        fieldError(.enrollmentDeadline)
                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    qualificationBasisPicker.pickerStyle(.inline)
                } else {
                    qualificationBasisPicker
                }
                Toggle("允许与其他活动叠加", isOn: $stackingAllowed)
            }
            Section("规则与奖励") {
                textRuleField("奖励说明", text: $rewardDescription, field: .reward, identifier: "promotion.editor.reward")
                DisclosureGroup(isExpanded: $showingRuleNotes) {
                    textRuleField("规则", text: $rules, field: .rules, identifier: "promotion.editor.rules")
                    textRuleField("排除项", text: $exclusions, field: .exclusions, identifier: "promotion.editor.exclusions")
                    textRuleField("备注", text: $notes, field: .notes, identifier: "promotion.editor.notes")
                    ruleExplanation("这些文字用于查阅；计入资格和奖励仍需按银行条款确认。")
                } label: {
                    Text("规则、排除项与备注（可选）")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if promotion != nil {
                Section("管理") {
                    Toggle("归档", isOn: $archived)
                }
            }
            Section("保存前确认") {
                LabeledContent("活动", value: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : title)
                LabeledContent("有效期", value: CardPilotUI.dateRangeText(start: CardPilotUI.rawDate(startDate), end: CardPilotUI.rawDate(endDate)))
                LabeledContent("主办方", value: organizerSummary)
                LabeledContent("适用卡", value: selectedCardIDs.isEmpty ? "尚未选择" : "\(selectedCardIDs.count) 张")
                LabeledContent("进度规则", value: progressSummary)
                LabeledContent("报名", value: enrollmentSummary)
                if promotion == nil && repeatsMonthly {
                    Text("后续各期需要分别报名；首期的已报名状态和日期不会复制到后续期。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if seriesEditScope == .thisAndFuture {
                    Text("规则修改应用到本期及以后；报名状态、报名日期和归档操作只修改本期。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func textRuleField(_ title: String, text: Binding<String>, field: Field, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline)
            TextField("可选", text: text, axis: .vertical)
                .focused($focusedField, equals: field)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private var progressModePicker: some View {
        Picker("进度类型", selection: $progressMode) {
            ForEach(PromotionProgressMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }

    private var enrollmentPicker: some View {
        Picker("报名状态", selection: $enrollmentStatus) {
            Text("不需要报名").tag(EnrollmentStatus.notRequired)
            Text("尚未报名").tag(EnrollmentStatus.notEnrolled)
                .accessibilityIdentifier("promotion.editor.enrollment.pending")
            Text("已报名").tag(EnrollmentStatus.enrolled)
        }
    }

    private var qualificationBasisPicker: some View {
        Picker("资格日期依据", selection: $qualificationDateBasis) {
            Text("交易日期").tag(QualificationDateBasis.transactionDate)
            Text("入账日期").tag(QualificationDateBasis.postingDate)
            Text("未知（交易日或入账日）")
                .fixedSize(horizontal: false, vertical: true)
                .tag(QualificationDateBasis.unknown)
                .accessibilityIdentifier("promotion.editor.basis.unknown")
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

    private var basicsValidationFields: [Field] {
        let progressFields: [Field] = progressMode == .cumulative
            ? [.qualificationThreshold, .qualifyingCap, .perTransactionThreshold]
            : [.benefitTransactionCap, .perTransactionThreshold]
        return [.title, .endDate, .repeatUntilDate] + progressFields + [.currency]
    }

    private func validationMessage(for field: Field) -> String? {
        switch field {
        case .title:
            guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return validationAction == .advance ? "请先填写活动标题。" : "活动标题不能为空。"
        case .endDate:
            return startDate <= endDate ? nil : "结束日期不能早于开始日期。"
        case .repeatUntilDate:
            return promotion == nil && repeatsMonthly && monthlyPeriodPreview.count < 2
                ? "系列结束日期必须容纳至少两个完整周期。" : nil
        case .qualificationThreshold:
            guard progressMode == .cumulative else { return nil }
            return optionalAmountMessage(qualificationThresholdText, label: "累计达标门槛")
        case .qualifyingCap:
            guard progressMode == .cumulative else { return nil }
            return optionalAmountMessage(qualifyingCapText, label: "累计计入上限")
        case .perTransactionThreshold:
            return optionalAmountMessage(perTransactionThresholdText,
                                         label: progressMode == .cumulative ? "单笔计入门槛" : "单笔满足金额")
        case .benefitTransactionCap:
            guard progressMode == .perTransaction else { return nil }
            return parsePositiveInteger(benefitTransactionCapText).isValid
                ? nil : "优惠笔数上限应为大于 0 的整数。"
        case .currency:
            let normalized = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard isValidCurrencyCode(normalized) else {
                return validationAction == .advance ? "请选择有效的进度币种。" : "进度币种应为有效的 ISO 4217 代码。"
            }
            if let promotion {
                if !promotion.allocations.isEmpty, promotion.progressCurrencyCode != normalized {
                    return "已有促销分配后不能修改进度币种。"
                }
                if seriesTargets(for: promotion).contains(where: {
                    !$0.allocations.isEmpty && $0.progressCurrencyCode != normalized
                }) {
                    return "系列中已有促销分配的周期不能修改进度币种。"
                }
            }
            return nil
        case .enrollmentDeadline:
            return enrollmentStatus != .notRequired && hasEnrollmentDeadline
                && CardPilotUI.rawDate(enrollmentDeadline) > CardPilotUI.rawDate(endDate)
                ? "报名截止日不能晚于活动结束日。" : nil
        case .reward, .rules, .exclusions, .notes:
            return nil
        }
    }

    private func optionalAmountMessage(_ text: String, label: String) -> String? {
        parseOptionalAmount(text).isValid ? nil : "\(label)应为大于 0 的数字，或留空。"
    }

    @ViewBuilder
    private func fieldError(_ field: Field) -> some View {
        if let validationAction, validationAction == .save || field.section == .basics,
           let message = validationMessage(for: field) {
            InlineErrorView(message: message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("promotion.error.\(field.rawValue)")
        }
    }

    private func revealError(_ field: Field, using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        if progressMode == .cumulative, field == .qualifyingCap || field == .perTransactionThreshold {
            showingAdditionalAmountRules = true
        }
        step = field.section
        Task { @MainActor in
            await Task.yield()
            guard step == field.section, validationMessage(for: field) != nil else { return }
            scrollProxy.scrollTo(field, anchor: .top)
        }
    }

    private func advance(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        validationAction = .advance
        if step == .basics,
           let field = basicsValidationFields.first(where: { validationMessage(for: $0) != nil }) {
            revealError(field, using: scrollProxy)
            return
        }
        guard let next = PromotionEditorStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = next
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

    private func save(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        validationAction = .save
        if let field = (basicsValidationFields + [.enrollmentDeadline]).first(where: { validationMessage(for: $0) != nil }) {
            revealError(field, using: scrollProxy)
            return
        }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let threshold: (value: Decimal?, isValid: Bool)
        let cap: (value: Decimal?, isValid: Bool)
        let perTransactionThreshold: (value: Decimal?, isValid: Bool)
        let benefitTransactionCap: (value: Int?, isValid: Bool)
        switch progressMode {
        case .cumulative:
            threshold = parseOptionalAmount(qualificationThresholdText)
            cap = parseOptionalAmount(qualifyingCapText)
            perTransactionThreshold = parseOptionalAmount(perTransactionThresholdText)
            benefitTransactionCap = (nil, true)
        case .perTransaction:
            threshold = (nil, true)
            cap = (nil, true)
            perTransactionThreshold = parseOptionalAmount(perTransactionThresholdText)
            benefitTransactionCap = parsePositiveInteger(benefitTransactionCapText)
        }

        let startOn = CardPilotUI.rawDate(startDate)
        let endOn = CardPilotUI.rawDate(endDate)
        let status = enrollmentStatus
        let enrolledValue = status == .enrolled && hasEnrolledOn ? CardPilotUI.rawDate(enrolledOn) : nil
        let deadlineValue = status == .notRequired || !hasEnrollmentDeadline ? nil : CardPilotUI.rawDate(enrollmentDeadline)
        if let deadlineValue, deadlineValue > endOn {
            step = .rules
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
            let targets = Promotion.makeMonthlySeries(startingWith: template, through: CardPilotUI.rawDate(repeatUntilDate))
            do {
                try PromotionCreationActions.save(targets, context: modelContext)
                dismiss()
            } catch {
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
        if promotion == nil {
            do {
                try PromotionCreationActions.save([target], context: modelContext)
                dismiss()
            } catch {
                errorMessage = "促销未保存：\(error.localizedDescription)"
            }
            return
        }
        let targets = seriesTargets(for: target)
        guard !targets.contains(where: { !$0.allocations.isEmpty && $0.progressCurrencyCode != normalizedCurrency }) else {
            step = .basics
            errorMessage = "系列中已有促销分配的周期不能修改进度币种。"
            return
        }
        let previousValues = targets.map(PromotionEditSnapshot.init)
        let previousRelationships = PromotionRelationshipSnapshot(
            promotions: targets, banks: selectedBanks, networks: selectedNetworks, cards: selectedCards
        )
        for candidate in targets {
            let state = PromotionSeriesCalculator.editedPeriodState(
                for: candidate, editing: target, enrollmentStatus: status,
                enrolledOn: enrolledValue, enrollmentDeadline: deadlineValue, archived: archived
            )
            candidate.title = normalizedTitle
            if candidate.id == target.id || candidate.seriesID == nil {
                candidate.startOn = startOn
                candidate.endOn = endOn
            }
            candidate.organizingBanks = selectedBanks
            candidate.organizingNetworks = selectedNetworks
            candidate.eligibleCards = selectedCards
            candidate.enrollmentStatus = state.enrollmentStatus
            candidate.enrolledOn = state.enrolledOn
            candidate.enrollmentDeadline = state.enrollmentDeadline
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
            candidate.archivedAt = state.archivedAt
        }
        do {
            try targets.forEach { candidate in
                if let deadline = candidate.enrollmentDeadline, deadline > candidate.endOn {
                    throw ModelValidationError.invalidEnrollment
                }
                try candidate.validate()
            }
            try modelContext.save()
            dismiss()
        } catch {
            for (candidate, snapshot) in zip(targets, previousValues) { snapshot.restore(candidate) }
            previousRelationships.restore()
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

    private func parseOptionalAmount(_ text: String) -> (value: Decimal?, isValid: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return (nil, true) }
        guard let amount = CardPilotUI.decimal(normalized), amount > .zero else {
            return (nil, false)
        }
        return (amount, true)
    }

    private func parsePositiveInteger(_ text: String) -> (value: Int?, isValid: Bool) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(normalized), value > 0 else {
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
                        Text("尚未选择适用卡时，本活动不会出现在自动推荐中，你仍可手动计入交易。")
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

struct PromotionCardSelectionRow: View {
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
