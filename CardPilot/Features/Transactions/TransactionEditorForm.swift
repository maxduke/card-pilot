import SwiftData
import SwiftUI
import UIKit

struct TransactionEditorForm: View {
    private enum InputField: Hashable {
        case amount
        case allocation(UUID)
        case promotionSearch
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction?
    let cards: [Card]
    let promotions: [Promotion]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedInput: InputField?
    @ScaledMetric(relativeTo: .caption) private var stepIndicatorSize = 28

    @AppStorage("cardPilot.lastUsedCardID") private var lastUsedCardID = ""
    @State private var cardID: UUID
    @State private var kind: TransactionKind
    @State private var transactionDate: Date
    @State private var postingDate: Date
    @State private var hasPostingDate: Bool
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var hasSelectedCurrency = false
    @State private var merchant: String
    @State private var category: String
    @State private var notes: String
    @State private var status: TransactionStatus
    @State private var originalTransactionID: UUID
    @State private var selectedPromotionIDs: Set<UUID>
    @State private var allocationAmounts: [UUID: String]
    @State private var automaticallySelectedPromotionIDs: Set<UUID> = []
    @State private var manuallyDeselectedPromotionIDs: Set<UUID> = []
    @State private var promotionSearchText = ""
    @State private var manuallyEditedAllocationIDs: Set<UUID> = []
    @State private var didInitializePromotions = false
    @State private var editorStep = 0
    @State private var showingInactiveCards: Bool
    @State private var showingOtherFields: Bool
    @State private var showingCardPicker = false
    @State private var showingOriginalPicker = false
    @State private var errorMessage: String?
    @State private var showingAllocationErrors = false
    @State private var overRefundWarningMessage: String?

    let draftStore: TransactionDraftStore
    let isResumedDraft: Bool
    @State private var amountFormat: AmountInput.Format
    @Environment(\.scenePhase) private var scenePhase
    @State private var draftID: UUID
    @State private var hasPersistedDraft: Bool
    @State private var draftFinished = false
    @State private var draftWriteError = false
    @State private var showingDraftClose = false
    @State private var initialDraftSnapshot: TransactionDraft?
    @State private var savedPromotionCurrencies: [UUID: String]

    private static let noOriginalTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    init(
        transaction: Transaction?,
        cards: [Card],
        promotions: [Promotion],
        initialPromotion: Promotion? = nil,
        initialCard: Card? = nil,
        initialRefundOriginal: Transaction? = nil,
        draft: TransactionDraft? = nil,
        draftStore: TransactionDraftStore
    ) {
        let amountFormat = draft?.inputFormat ?? AmountInput.Format()
        _amountFormat = State(initialValue: amountFormat)
        _hasPersistedDraft = State(initialValue: draft != nil)
        self.draftStore = draftStore
        self.isResumedDraft = draft != nil
        _draftID = State(initialValue: draft?.id ?? UUID())
        _savedPromotionCurrencies = State(initialValue: draft?.promotionCurrencies ?? [:])
        self.transaction = transaction
        self.cards = cards
        self.promotions = promotions
        let refundOriginal = transaction == nil && draft == nil && initialRefundOriginal?.kind == .purchase
            ? initialRefundOriginal : nil
        let savedCardID = UserDefaults.standard.string(forKey: "cardPilot.lastUsedCardID")
        let resolvedCard = transaction?.card
            ?? refundOriginal?.card
            ?? initialCard
            ?? initialPromotion?.eligibleCards.first(where: { $0.status == .active })
            ?? cards.first(where: { $0.status == .active && $0.id.uuidString == savedCardID })
            ?? cards.first(where: { $0.status == .active })
            ?? cards.first
        _cardID = State(initialValue: resolvedCard?.id ?? UUID())
        _kind = State(initialValue: transaction?.kind ?? (refundOriginal == nil ? .purchase : .refund))
        _transactionDate = State(initialValue: transaction.flatMap { try? LocalDate(rawValue: $0.transactionOn).date(in: CardPilotUI.homeTimeZone) } ?? Date())
        _postingDate = State(initialValue: transaction.flatMap { $0.postingOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _hasPostingDate = State(initialValue: transaction?.postingOn != nil)
        _amountText = State(initialValue: transaction.map { CardPilotUI.editableAmountText($0.amount, format: amountFormat) } ?? "")
        _currencyCode = State(initialValue: transaction?.currencyCode ?? refundOriginal?.currencyCode ?? resolvedCard?.account.limitCurrencyCode ?? "CNY")
        _hasSelectedCurrency = State(initialValue: refundOriginal != nil)
        _merchant = State(initialValue: transaction?.merchant ?? "")
        _category = State(initialValue: transaction?.category ?? "")
        _notes = State(initialValue: transaction?.notes ?? "")
        _status = State(initialValue: transaction?.status ?? .active)
        _originalTransactionID = State(initialValue: transaction?.originalTransaction?.id ?? refundOriginal?.id ?? Self.noOriginalTransactionID)
        let positiveAllocations = (transaction?.allocations ?? []).filter { $0.qualifyingAmount > .zero }
        var initialIDs = Set(positiveAllocations.map { $0.promotion.id })
        var initialAmounts = Dictionary(uniqueKeysWithValues: positiveAllocations.map { ($0.promotion.id, CardPilotUI.editableAmountText($0.qualifyingAmount, format: amountFormat)) })
        if transaction == nil, let initialPromotion {
            initialIDs.insert(initialPromotion.id)
            initialAmounts[initialPromotion.id] = ""
        }
        _selectedPromotionIDs = State(initialValue: initialIDs)
        _allocationAmounts = State(initialValue: initialAmounts)
        _showingInactiveCards = State(initialValue: resolvedCard?.status == .inactive || cards.allSatisfy { $0.status == .inactive })
        _showingOtherFields = State(initialValue: transaction != nil)
        if let draft {
            _cardID = State(initialValue: draft.cardID)
            _kind = State(initialValue: draft.kind)
            _transactionDate = State(initialValue: (try? LocalDate(rawValue: draft.transactionOn).date(in: CardPilotUI.homeTimeZone)) ?? Date())
            _postingDate = State(initialValue: (try? LocalDate(rawValue: draft.postingOn).date(in: CardPilotUI.homeTimeZone)) ?? Date())
            _hasPostingDate = State(initialValue: draft.hasPostingDate)
            _amountText = State(initialValue: draft.amountText)
            _currencyCode = State(initialValue: draft.currencyCode)
            _merchant = State(initialValue: draft.merchant)
            _category = State(initialValue: draft.category)
            _notes = State(initialValue: draft.notes)
            _status = State(initialValue: draft.status)
            _originalTransactionID = State(initialValue: draft.originalTransactionID)
            _selectedPromotionIDs = State(initialValue: draft.selectedPromotionIDs)
            _allocationAmounts = State(initialValue: draft.allocationAmounts)
            _automaticallySelectedPromotionIDs = State(initialValue: draft.automaticallySelectedPromotionIDs)
            _manuallyDeselectedPromotionIDs = State(initialValue: draft.manuallyDeselectedPromotionIDs)
            _manuallyEditedAllocationIDs = State(initialValue: draft.manuallyEditedAllocationIDs)
            _editorStep = State(initialValue: draft.editorStep)
            _showingInactiveCards = State(initialValue: draft.showingInactiveCards)
            _showingOtherFields = State(initialValue: draft.showingOtherFields)
            _didInitializePromotions = State(initialValue: true)
        }
    }

    private var selectedCard: Card? { cards.first { $0.id == cardID } }

    private var selectableCards: [Card] {
        cards.filter { showingInactiveCards || $0.status == .active || $0.id == cardID }
            .sorted { cardLabel($0) < cardLabel($1) }
    }

    private var hasInactiveCards: Bool { cards.contains { $0.status == .inactive } }

    private var originalTransactions: [Transaction] {
        (selectedCard?.transactions ?? []).filter {
            $0.id != transaction?.id
                && $0.kind == .purchase
        }.sorted {
            $0.transactionOn == $1.transactionOn
                ? $0.id.uuidString < $1.id.uuidString
                : $0.transactionOn > $1.transactionOn
        }
    }

    private var candidatePromotions: [Promotion] {
        guard let selectedCard else { return [] }
        let date = CardPilotUI.rawDate(transactionDate)
        return promotions.filter { promotion in
            guard promotion.archivedAt == nil,
                  promotion.eligibleCards.contains(where: { $0.id == selectedCard.id }) else { return false }
            let qualificationDates: [Int]
            switch promotion.qualificationDateBasis {
            case .transactionDate:
                qualificationDates = [date]
            case .postingDate:
                qualificationDates = hasPostingDate ? [CardPilotUI.rawDate(postingDate)] : []
            case .unknown:
                qualificationDates = [date] + (hasPostingDate ? [CardPilotUI.rawDate(postingDate)] : [])
            }
            return qualificationDates.contains { promotion.startOn <= $0 && $0 <= promotion.endOn }
        }
    }

    private var inheritedPromotionIDs: Set<UUID> {
        guard kind == .refund,
              let original = originalTransactions.first(where: { $0.id == originalTransactionID }) else { return [] }
        return Set(original.allocations.filter { $0.qualifyingAmount > .zero }.map(\.promotion.id))
    }

    private var currentAutomaticPromotionIDs: Set<UUID> {
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard kind == .purchase,
              let transactionAmount = CardPilotUI.decimal(amountText, format: amountFormat),
              transactionAmount > .zero else {
            guard kind == .refund, let amount = CardPilotUI.decimal(amountText, format: amountFormat) else {
                return inheritedPromotionIDs
            }
            guard let original = originalTransactions.first(where: { $0.id == originalTransactionID }) else { return [] }
            let inheritedIDs = Set(original.allocations.filter { $0.qualifyingAmount > .zero }.map(\.promotion.id))
            return Set(promotions.filter { promotion in
                guard inheritedIDs.contains(promotion.id) else { return false }
                let suggestion = suggestedRefundAllocationAmount(
                    refundAmount: amount, refundCurrencyCode: normalizedCurrency, promotion: promotion,
                    original: original,
                    excludingTransactionID: transaction?.id)
                return suggestion.map { $0 > .zero } ?? true
            }.map(\.id))
        }
        let automaticCandidates = candidatePromotions.filter { promotion in
            PromotionCalculator.shouldAutomaticallySelect(
                promotion,
                transactionAmount: transactionAmount,
                transactionCurrencyCode: normalizedCurrency
            )
        }
        if automaticCandidates.count > 1 && automaticCandidates.contains(where: { !$0.stackingAllowed }) {
            return []
        }
        return Set(automaticCandidates.map(\.id))
    }

    private var isSearchingPromotions: Bool {
        !promotionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visiblePromotionIDs: Set<UUID> {
        if isSearchingPromotions {
            return selectedPromotionIDs.union(searchedPromotions.map(\.id))
        }
        return Set(candidatePromotions.map(\.id))
            .union(selectedPromotionIDs)
            .union(inheritedPromotionIDs)
            .union(postingDatePendingPromotions.map(\.id))
    }

    private var visiblePromotions: [Promotion] {
        let visibleIDs = visiblePromotionIDs
        return promotions.filter { visibleIDs.contains($0.id) }.sorted { $0.endOn < $1.endOn }
    }

    private var postingDatePendingPromotions: [Promotion] {
        promotionsAwaitingPostingDate(promotions, cardID: selectedCard?.id,
                                      hasPostingDate: hasPostingDate, transactionOn: CardPilotUI.rawDate(transactionDate))
    }

    private var searchedPromotions: [Promotion] {
        promotionsMatchingSearch(promotions, searchText: promotionSearchText)
    }

    private var isAmountPositive: Bool {
        guard let amount = CardPilotUI.decimal(amountText, format: amountFormat) else { return false }
        return amount > .zero
    }

    private var needsPromotionConfirmation: Bool {
        !candidatePromotions.isEmpty || !selectedPromotionIDs.isEmpty || !postingDatePendingPromotions.isEmpty
    }

    private var invalidPromotionIDs: Set<UUID> {
        invalidDraftPromotionIDs(selectedIDs: selectedPromotionIDs, savedCurrencies: savedPromotionCurrencies,
                                 promotions: promotions)
    }

    private var confirmationWarnings: [String] {
        var warnings: [String] = []
        if !invalidPromotionIDs.isEmpty { warnings.append("活动已失效，请移除后重新确认") }
        if promotions.contains(where: { promotion in
            selectedPromotionIDs.contains(promotion.id) && transactionAllocationExceedsAmount(
                transactionAmount: CardPilotUI.decimal(amountText, format: amountFormat),
                transactionCurrencyCode: currencyCode,
                allocationAmount: CardPilotUI.decimal(allocationAmounts[promotion.id] ?? "", format: amountFormat),
                allocationCurrencyCode: promotion.progressCurrencyCode)
        }) { warnings.append("计入金额大于交易金额，请核对") }
        if selectedPromotionIDs.count > 1 && selectedPromotionsContainNonStacking { warnings.append("活动不可叠加") }
        if !selectedPromotionsOutsideCandidates.isEmpty { warnings.append("卡片或日期需核对") }
        if promotions.contains(where: { selectedPromotionIDs.contains($0.id) && $0.enrollmentStatus == .notEnrolled }) {
            warnings.append("活动尚未报名")
        }
        return warnings
    }

    private var editSnapshot: String {
        editorSnapshot(cardID, kind, transactionDate, postingDate, hasPostingDate, amountText, currencyCode, merchant, category, notes, status, originalTransactionID, selectedPromotionIDs.map(\.uuidString).sorted(), allocationAmounts.sorted { $0.key.uuidString < $1.key.uuidString }.map { "\($0.key):\($0.value)" })
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                observedEditorContent(using: scrollProxy)
                .navigationTitle(transaction == nil ? "添加交易" : "编辑交易")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { editorToolbar }
                .confirmationDialog("未完成的交易", isPresented: $showingDraftClose, titleVisibility: .visible) {
                    Button("保留草稿并关闭") {
                        persistDraft(force: true)
                        if !draftWriteError { dismiss() }
                    }
                    Button("丢弃草稿", role: .destructive) {
                        do {
                            try draftStore.clear()
                            draftFinished = true
                            dismiss()
                        } catch { draftWriteError = true }
                    }
                    Button("继续编辑", role: .cancel) {}
                }
                .alert("退款超出可退范围", isPresented: Binding(
                    get: { overRefundWarningMessage != nil },
                    set: { if !$0 { overRefundWarningMessage = nil } }
                )) {
                    Button("取消", role: .cancel) {}
                    Button("仍然保存", role: .destructive) { save(allowingOverRefund: true, scrollProxy: scrollProxy) }
                } message: {
                    Text(overRefundWarningMessage ?? "")
                }
            }
        }
        // Keep the picker presenter outside lazy Form rows so scrolling cannot
        // recreate its presentation registration while the sheet is open.
        .trackedSheet(isPresented: $showingCardPicker) {
            CardSelectionSheet(
                cards: selectableCards,
                selectedCardID: cardID,
                lastUsedCardID: lastUsedCardID,
                onSelect: { selectedID in
                    cardID = selectedID
                    showingCardPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .trackedSheet(isPresented: $showingOriginalPicker) {
            originalTransactionSelection
        }
        .protectEdits(snapshot: editSnapshot, isReady: didInitializePromotions)
    }

    private func observedEditorContent(using scrollProxy: ScrollViewProxy) -> some View {
        editorContent(using: scrollProxy)
        .onAppear {
            initializePromotions()
            if initialDraftSnapshot == nil { initialDraftSnapshot = draftSnapshot }
        }
        .onChange(of: draftSnapshot) { _, _ in persistDraft() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistDraft() }
        }
        .task { if transaction == nil { focusedInput = .amount } }
        .onChange(of: cardID) { _, _ in
            if !originalTransactions.contains(where: { $0.id == originalTransactionID }) {
                originalTransactionID = Self.noOriginalTransactionID
            }
            // A card supplies a default only while a fresh form has no amount or explicit currency.
            // Restored drafts already own their currency, even when the amount is incomplete.
            if transaction == nil, !isResumedDraft, !hasSelectedCurrency,
               amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let selectedCard {
                currencyCode = selectedCard.account.limitCurrencyCode
                refreshDefaultAllocationAmounts()
            }
            refreshCandidates()
        }
        .onChange(of: showingInactiveCards) { _, showing in
            guard !showing, selectedCard?.status == .inactive else { return }
            cardID = cards.first(where: { $0.status == .active })?.id ?? cardID
        }
        .onChange(of: kind) { _, _ in
            refreshCandidates()
            refreshDefaultAllocationAmounts()
        }
        .onChange(of: originalTransactionID) { _, _ in
            refreshCandidates()
            refreshDefaultAllocationAmounts()
        }
        .onChange(of: transactionDate) { _, _ in refreshCandidates() }
        .onChange(of: postingDate) { _, _ in refreshCandidates() }
        .onChange(of: hasPostingDate) { _, _ in refreshCandidates() }
        .onChange(of: amountText) { _, _ in
            refreshCandidates()
            refreshDefaultAllocationAmounts()
        }
        .onChange(of: currencyCode) { _, _ in
            refreshCandidates()
            refreshDefaultAllocationAmounts()
        }
    }

    private func editorContent(using scrollProxy: ScrollViewProxy) -> some View {
        let actionTitle = editorStep == 0 ? (needsPromotionConfirmation ? "继续确认促销" : "保存交易") : "确认并保存"
        return VStack(spacing: 0) {
            if needsPromotionConfirmation || editorStep == 1 { editorStepIndicator }
            Group {
                if editorStep == 0 {
                    Form {
                        basicTransactionSections
                        editorFeedback
                    }
                } else {
                    ScrollView {
                        // Keep the confirmation controls alive as their text
                        // sizes change, including the focused input's anchor.
                        VStack(alignment: .leading, spacing: 20) {
                            promotionConfirmationSections
                            editorFeedback
                        }
                        .padding(20)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .animation(nil, value: dynamicTypeSize)
            .scrollDismissesKeyboard(.immediately)
            .accessibilityIdentifier("transaction.form")
            .onChange(of: focusedInput) { (_: InputField?, field: InputField?) in
                revealFocusedInput(field, using: scrollProxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                revealFocusedInput(focusedInput, using: scrollProxy)
            }
            VStack(spacing: 0) {
                Divider()
                if editorStep == 1 {
                    Button("返回修改交易") { editorStep = 0 }
                        .font(.footnote.weight(.medium))
                        .padding(.top, 8)
                    if !confirmationWarnings.isEmpty {
                        Label(confirmationWarnings.joined(separator: " · "), systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
                Button {
                    focusedInput = nil
                    if editorStep == 0 && needsPromotionConfirmation {
                        continueToPromotionConfirmation()
                    } else {
                        save(scrollProxy: scrollProxy)
                    }
                } label: {
                    Text(dynamicTypeSize.isAccessibilitySize && editorStep == 0 && needsPromotionConfirmation
                         ? "确认促销" : actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .disabled(!isAmountPositive || selectedCard == nil)
                .accessibilityLabel(actionTitle)
                .accessibilityIdentifier("saveTransaction")
                if isNumericInputFocused {
                    HStack {
                        Spacer()
                        Button { focusedInput = nil } label: {
                            Text("收起键盘")
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("transaction.keyboard.dismiss")
                    }
                    .padding(.horizontal, 16)
                }
            }
            .background(.bar, ignoresSafeAreaEdges: .bottom)
        }
    }

    @ViewBuilder
    private var editorFeedback: some View {
        if !invalidPromotionIDs.isEmpty {
            editorFeedbackSection("草稿活动需要重新确认") {
                Text("部分活动已删除或变更币种。移除失效活动后可保留交易内容，仍存在的活动可重新搜索并填写计入金额。")
                Button("移除失效活动，保留交易内容") { removeInvalidPromotions() }
            }
        }
        if draftWriteError {
            editorFeedbackSection {
                Text("草稿未能保存到设备，请保持此页面并重试。")
                Button("重试保存草稿") { persistDraft(force: true) }
            }
        }
        if let errorMessage {
            InlineErrorView(message: errorMessage)
        }
    }

    @ViewBuilder
    private func editorFeedbackSection<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if editorStep == 0 {
            Section {
                content()
            } header: {
                if let title { Text(title) }
            }
        } else {
            confirmationGroup(title, content: content)
        }
    }

    private func confirmationGroup<Content: View>(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 12, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var draftSnapshot: TransactionDraft {
        var snapshot = TransactionDraft(id: draftID, cardID: cardID, kind: kind,
            transactionOn: CardPilotUI.rawDate(transactionDate), postingOn: CardPilotUI.rawDate(postingDate),
            hasPostingDate: hasPostingDate, amountText: amountText, currencyCode: currencyCode,
            merchant: merchant, category: category, notes: notes, status: status,
            originalTransactionID: originalTransactionID, selectedPromotionIDs: selectedPromotionIDs,
            allocationAmounts: allocationAmounts,
            promotionCurrencies: Dictionary(uniqueKeysWithValues: promotions.filter { selectedPromotionIDs.contains($0.id) }
                .map { ($0.id, savedPromotionCurrencies[$0.id] ?? $0.progressCurrencyCode) }),
            automaticallySelectedPromotionIDs: automaticallySelectedPromotionIDs,
            manuallyDeselectedPromotionIDs: manuallyDeselectedPromotionIDs,
            manuallyEditedAllocationIDs: manuallyEditedAllocationIDs, editorStep: editorStep,
            showingInactiveCards: showingInactiveCards, showingOtherFields: showingOtherFields)
        snapshot.amountFormat = amountFormat
        return snapshot
    }

    private func removeInvalidPromotions() {
        for id in invalidPromotionIDs {
            selectedPromotionIDs.remove(id)
            automaticallySelectedPromotionIDs.remove(id)
            manuallyDeselectedPromotionIDs.insert(id)
            manuallyEditedAllocationIDs.remove(id)
            allocationAmounts[id] = nil
            savedPromotionCurrencies[id] = nil
        }
        errorMessage = nil
    }

    private func persistDraft(force: Bool = false) {
        guard transaction == nil, didInitializePromotions, !draftFinished,
              force || hasPersistedDraft || (initialDraftSnapshot != nil && draftSnapshot != initialDraftSnapshot) else { return }
        do {
            guard let initialDraftSnapshot else { return }
            hasPersistedDraft = try draftStore.persist(draftSnapshot, initial: initialDraftSnapshot, isResumed: isResumedDraft)
            draftWriteError = false
        } catch { draftWriteError = true }
    }

    private func closeNewTransaction() {
        guard !isResumedDraft, let initialDraftSnapshot, draftSnapshot == initialDraftSnapshot else {
            showingDraftClose = true
            return
        }
        do {
            try draftStore.clear()
            draftFinished = true
            dismiss()
        } catch { draftWriteError = true }
    }

    private var editorStepIndicator: some View {
        let summary = "第 \(editorStep + 1) 步，共 2 步：\(editorStep == 0 ? "交易信息" : "确认促销")"
        return VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(editorStep + 1)/2 · \(editorStep == 0 ? "交易信息" : "确认促销")")
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    stepIndicatorItem(number: 1, title: "交易信息", isCurrent: editorStep == 0)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 1)
                    stepIndicatorItem(number: 2, title: "确认促销", isCurrent: editorStep == 1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize && isNumericInputFocused ? 0 : 10)
        // Keep this header's background below the navigation bar, within the
        // same safe-area bounds as its content and accessibility element.
        .background(.bar, ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("transaction.steps")
    }

    private func stepIndicatorItem(number: Int, title: String, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(isCurrent ? Color("ActionForeground") : Color.secondary)
                .frame(width: stepIndicatorSize, height: stepIndicatorSize)
                .background(isCurrent ? Color("ActionBackground") : Color.secondary.opacity(0.15), in: Circle())
            Text(title)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private var basicTransactionSections: some View {
        Section {
            cardSelector
            if hasInactiveCards {
                Toggle("显示停用卡", isOn: $showingInactiveCards)
            }
        } header: {
            Text("选择卡片")
        } footer: {
            if let selectedCard {
                Text("账户额度币种：\(selectedCard.account.limitCurrencyCode)")
            } else {
                Text("请选择一张卡片后继续。")
            }
        }

        Section("金额") {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                TextField("0.00", text: $amountText)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .keyboardType(amountFormat.decimalSeparator == Locale.current.decimalSeparator ? .decimalPad : .numbersAndPunctuation)
                    .environment(\.locale, amountFormat.locale)
                    .focused($focusedInput, equals: .amount)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("交易金额")
                    .accessibilityIdentifier("transactionAmount")
                CurrencyPickerView(selection: Binding(
                    get: { currencyCode },
                    set: { currencyCode = $0; hasSelectedCurrency = true }
                ), title: "币种")
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("transactionCurrency")
            }
            if amountFormat.decimalSeparator != Locale.current.decimalSeparator {
                Text("此草稿沿用原地区的金额格式，小数分隔符为“\(amountFormat.decimalSeparator)”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !amountText.isEmpty && !isAmountPositive {
                Text("请输入大于 0 的金额。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Section("交易类型") {
            Picker("交易类型", selection: $kind) {
                Text("消费").tag(TransactionKind.purchase)
                Text("退款").tag(TransactionKind.refund)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("交易类型")
            if let transaction, transaction.kind != kind, !transaction.allocations.isEmpty {
                Text("更改消费／退款类型会改变现有促销分配的正负贡献；计入金额仍保留，请在下一步逐项核对。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if kind == .refund {
                let original = originalTransactions.first { $0.id == originalTransactionID }
                Button {
                    focusedInput = nil
                    showingOriginalPicker = true
                } label: {
                    HStack {
                        Text(original == nil ? "选择原消费（可选）" : "更改原消费")
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .accessibilityHidden(true)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityValue(original.map(transactionLabel) ?? "不关联原消费（可选）")
                .accessibilityIdentifier("transaction.original")
                if let original {
                    Text("原消费：\(transactionLabel(original)) · 状态：\(original.status == .reversed ? "已冲正" : "有效")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("transaction.original.summary")
                    if original.status == .reversed {
                        Text("原消费已冲正；退款仍是独立记录，请按银行记录确认退款及促销分配。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if originalTransactions.isEmpty {
                    Text("当前卡片暂无可关联的原消费，可稍后在详情中补充。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("交易信息") {
            TextField("商户（可选）", text: $merchant)
                .textContentType(.organizationName)
            DatePicker("交易日期", selection: $transactionDate, displayedComponents: .date)
            Toggle("记录入账日期", isOn: $hasPostingDate)
            if hasPostingDate {
                DatePicker("入账日期", selection: $postingDate, displayedComponents: .date)
            }
        }

        Section {
            DisclosureGroup("其他字段", isExpanded: $showingOtherFields) {
                TextField("分类（可选）", text: $category)
                TextField("备注（可选）", text: $notes, axis: .vertical)
                if transaction != nil {
                    Picker("交易状态", selection: $status) {
                        Text("有效").tag(TransactionStatus.active)
                        Text("已冲正").tag(TransactionStatus.reversed)
                    }
                    .pickerStyle(.segmented)
                    if status == .reversed, let transaction, transactionHasActiveRefunds(transaction) {
                        Text("冲正原消费不会冲正关联退款：原消费贡献归零，退款仍扣减促销进度，合计可能为负。请单独核对退款。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !needsPromotionConfirmation {
            Section {
                Label("本笔不计入活动", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
                Button("手动选择活动") {
                    focusedInput = nil
                    continueToPromotionConfirmation()
                }
                .disabled(!isAmountPositive)
            }
        }
    }

    @ViewBuilder
    private var promotionConfirmationSections: some View {
        confirmationGroup("本笔交易") {
            if let selectedCard { Text(cardLabel(selectedCard)).font(.subheadline) }
            if amountFormat.decimalSeparator != Locale.current.decimalSeparator {
                Text("计入金额沿用草稿格式，小数分隔符为“\(amountFormat.decimalSeparator)”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(CardPilotUI.amountText(CardPilotUI.decimal(amountText, format: amountFormat) ?? .zero, currencyCode: currencyCode))
                .font(.title2.bold())
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .refund ? "退款日期" : "消费日期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CardPilotUI.dateText(CardPilotUI.rawDate(transactionDate)))
            }
            .accessibilityElement(children: .combine)
            if !merchant.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("商户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(merchant)
                }
                .accessibilityElement(children: .combine)
            }
        }
        confirmationGroup("确认促销") {
            Label(
                selectedPromotionIDs.isEmpty ? "本笔未计入促销" : "已选择 \(selectedPromotionIDs.count) 个促销",
                systemImage: selectedPromotionIDs.isEmpty ? "tag.slash" : "checkmark.circle"
            )
            .foregroundStyle(selectedPromotionIDs.isEmpty ? Color.secondary : Color.accentColor)
            Text("请检查候选活动与计入金额；点击“确认并保存”后才会写入这笔交易。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        promotionSection
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if transaction == nil {
                Button("关闭", action: closeNewTransaction)
            } else {
                EditorCancelButton()
            }
        }
    }

    private var isNumericInputFocused: Bool {
        switch focusedInput {
        case .amount?, .allocation?:
            true
        case .promotionSearch?, nil:
            false
        }
    }

    private func revealFocusedInput(_ field: InputField?, using scrollProxy: ScrollViewProxy) {
        guard let field, field != .amount else { return }
        Task { @MainActor in
            await Task.yield()
            guard focusedInput == field else { return }
            switch field {
            case .promotionSearch:
                scrollProxy.scrollTo(InputField.promotionSearch, anchor: .top)
            case let .allocation(id):
                // The input begins at its validation anchor, leaving room
                // above the fixed footer when the keyboard opens.
                scrollProxy.scrollTo(InputField.allocation(id), anchor: .top)
            case .amount:
                break
            }
        }
    }

    private func continueToPromotionConfirmation() {
        guard selectedCard != nil else {
            errorMessage = "请选择卡片。"
            return
        }
        guard isAmountPositive else {
            errorMessage = "金额应为大于 0 的数字。"
            return
        }
        errorMessage = nil
        initializePromotions()
        refreshDefaultAllocationAmounts()
        editorStep = 1
    }

    private var cardSelector: some View {
        Group {
            if selectableCards.isEmpty {
                Label("请先在“卡片”页添加信用卡", systemImage: "creditcard")
                    .foregroundStyle(.secondary)
            } else if let selectedCard {
                Button {
                    focusedInput = nil
                    showingCardPicker = true
                } label: {
                    HStack(spacing: 12) {
                        BankBadge(bank: selectedCard.account.bank)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCard.nickname.isEmpty ? selectedCard.productName : selectedCard.nickname)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("•••• \(selectedCard.lastFour)")
                                    .font(.caption.monospaced())
                                CardNetworksBadges(networks: selectedCard.networks)
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("当前卡片，\(cardLabel(selectedCard))")
                .accessibilityHint("打开卡片选择")
                .accessibilityIdentifier("transactionCardPicker")
            } else {
                Button("选择其他卡片", systemImage: "creditcard") {
                    focusedInput = nil
                    showingCardPicker = true
                }
                .accessibilityHint("草稿中的卡片已不可用，请重新选择")
            }
        }
    }

    private var originalTransactionSelection: some View {
        NavigationStack {
            List {
                originalTransactionOption("不关联原消费（可选）", id: Self.noOriginalTransactionID)
                ForEach(originalTransactions, id: \.id) { original in
                    originalTransactionOption(transactionLabel(original), id: original.id)
                }
            }
            .navigationTitle("选择原消费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingOriginalPicker = false }
                }
            }
        }
    }

    private func originalTransactionOption(_ title: String, id: UUID) -> some View {
        Button {
            originalTransactionID = id
            showingOriginalPicker = false
        } label: {
            HStack {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if originalTransactionID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(originalTransactionID == id ? .isSelected : [])
    }

    @ViewBuilder
    private var promotionSection: some View {
        let visible = visiblePromotions
        let pendingPostingIDs = Set(postingDatePendingPromotions.map(\.id))
        confirmationGroup("促销分配") {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("搜索")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                TextField("", text: $promotionSearchText)
                    .focused($focusedInput, equals: .promotionSearch)
                    .accessibilityLabel("搜索其他促销")
                    .accessibilityIdentifier("allocation.search")
            }
            .id(InputField.promotionSearch)
            if visible.isEmpty && !isSearchingPromotions {
                Label("本笔未计入促销", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
                Text("当前卡片和日期没有匹配的活动；仍可搜索全部促销并手动选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if visible.isEmpty {
                Text("没有匹配的促销。可修改搜索词，或返回上一步检查卡片和日期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if isSearchingPromotions {
                    let selected = visible.filter { selectedPromotionIDs.contains($0.id) }
                    let results = visible.filter { !selectedPromotionIDs.contains($0.id) }
                    if !selected.isEmpty {
                        Text("已选活动")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(selected, id: \.id) { promotion in
                            promotionChoice(promotion, awaitingPostingDate: pendingPostingIDs.contains(promotion.id))
                        }
                    }
                    Text("搜索结果")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if results.isEmpty {
                        Text("没有其他匹配活动。已选活动和计入金额会保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results, id: \.id) { promotion in
                        promotionChoice(promotion, awaitingPostingDate: pendingPostingIDs.contains(promotion.id))
                    }
                } else {
                    ForEach(visible, id: \.id) { promotion in
                        promotionChoice(promotion, awaitingPostingDate: pendingPostingIDs.contains(promotion.id))
                    }
                }
                Text("已报名或无需报名、金额符合条件的累计活动会预选。不可叠加的多个活动及逐笔优惠活动，请逐项确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !inheritedPromotionIDs.isEmpty {
                    Text("已带入原消费已有的促销分配，即使活动已结束也会保留。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if selectedPromotionIDs.count > 1,
                   selectedPromotionsContainNonStacking {
                    Text("所选活动中包含“不允许叠加”的活动，请按活动条款确认。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !selectedPromotionsOutsideCandidates.isEmpty {
                    Text("所选活动当前不再符合卡片或日期候选条件，请确认后再保存。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if selectedPromotionIDs.contains(where: { id in
                    promotions.first(where: { $0.id == id })?.enrollmentStatus == .notEnrolled
                }) {
                    Text("所选活动中有尚未报名的活动，请确认报名状态。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func promotionChoice(_ promotion: Promotion, awaitingPostingDate: Bool) -> some View {
        Toggle(isOn: promotionBinding(promotion.id)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(promotion.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(promotionSummary(promotion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("allocation.toggle.\(promotion.title)")
        if dynamicTypeSize.isAccessibilitySize {
            // A long title and summary need separate space at
            // accessibility sizes so the title can scroll fully.
            Text(promotionSummary(promotion))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if selectedPromotionIDs.contains(promotion.id) {
            let warning = qualificationWarning(for: promotion)
            Text("计入金额（\(promotion.progressCurrencyCode)）")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 24)
            // The caption can exceed the keyboard viewport, so
            // keep the input at the beginning of its scroll anchor.
            VStack(alignment: .leading, spacing: 7) {
                TextField(
                    "0\(amountFormat.decimalSeparator)00",
                    text: amountBinding(promotion.id)
                )
                .keyboardType(amountFormat.decimalSeparator == Locale.current.decimalSeparator ? .decimalPad : .numbersAndPunctuation)
                .environment(\.locale, amountFormat.locale)
                .focused($focusedInput, equals: .allocation(promotion.id))
                .textFieldStyle(.plain)
                .accessibilityLabel("\(promotion.title)计入金额（\(promotion.progressCurrencyCode)）")
                .accessibilityIdentifier("allocation.amount.\(promotion.title)")
                if showingAllocationErrors && positiveAllocationAmount(for: promotion.id) == nil {
                    InlineErrorView(message: "计入金额应为大于 0 的数字。")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("allocation.error.\(promotion.title)")
                }
            }
            .padding(.leading, 24)
            .id(InputField.allocation(promotion.id))
            if let warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
        }
        if awaitingPostingDate {
            Text("需补入账日期，不会自动勾选。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        Divider()
    }

    private func promotionSummary(_ promotion: Promotion) -> String {
        var parts = [promotion.progressCurrencyCode]
        if let benefitTransactionCap = promotion.benefitTransactionCap {
            parts.append("最多 \(benefitTransactionCap) 笔")
        }
        if let threshold = promotion.qualificationThreshold {
            parts.append("达标 \(CardPilotUI.amountText(threshold))")
        }
        if let perTransactionThreshold = promotion.perTransactionThreshold {
            parts.append("单笔 ≥ \(CardPilotUI.amountText(perTransactionThreshold))")
        }
        if let cap = promotion.qualifyingCap {
            parts.append("封顶 \(CardPilotUI.amountText(cap))")
        }
        return parts.joined(separator: " · ")
    }

    private func qualificationWarning(for promotion: Promotion) -> String? {
        if transactionAllocationExceedsAmount(
            transactionAmount: CardPilotUI.decimal(amountText, format: amountFormat),
            transactionCurrencyCode: currencyCode,
            allocationAmount: CardPilotUI.decimal(allocationAmounts[promotion.id] ?? "", format: amountFormat),
            allocationCurrencyCode: promotion.progressCurrencyCode
        ) {
            return "计入金额大于本笔交易金额。已确认的分配不会随交易修改自动更改，请核对银行认可金额；仍可手动保存。"
        }
        guard kind != .refund,
              let transactionAmount = CardPilotUI.decimal(amountText, format: amountFormat),
              transactionAmount > .zero else { return nil }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency == promotion.progressCurrencyCode else {
            return "币种不同，无法自动换算；请手动填写合格金额。"
        }
        let alreadyCounted = transaction.map { transaction in
            transaction.kind == .purchase
                && transaction.status == .active
                && transaction.allocations.contains {
                    $0.promotion.id == promotion.id && $0.qualifyingAmount > .zero
                }
        } ?? false
        if !alreadyCounted,
           let cap = promotion.benefitTransactionCap,
           let progress = try? PromotionCalculator.progress(for: promotion),
           progress.usedTransactionCount >= cap {
            return "本活动优惠笔数已用完；如需修正仍可手动记录本笔。"
        }
        if let cap = promotion.qualifyingCap,
           let progress = try? PromotionCalculator.progress(for: promotion),
           progress.qualifiedAmount >= cap {
            return "本活动累计计入上限已用完；如需修正请手动填写正数。"
        }
        guard let threshold = promotion.perTransactionThreshold,
              transactionAmount < threshold else { return nil }
        return "本活动单笔至少 \(CardPilotUI.amountText(threshold, currencyCode: promotion.progressCurrencyCode))，请确认是否符合条款后填写正数。"
    }

    private func promotionBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedPromotionIDs.contains(id) },
            set: { selected in
                if selected {
                    selectedPromotionIDs.insert(id)
                    if allocationAmounts[id] == nil, let promotion = promotions.first(where: { $0.id == id }) {
                        allocationAmounts[id] = defaultAmount(for: promotion)
                    }
                    automaticallySelectedPromotionIDs.remove(id)
                    manuallyDeselectedPromotionIDs.remove(id)
                } else {
                    selectedPromotionIDs.remove(id)
                    automaticallySelectedPromotionIDs.remove(id)
                    manuallyDeselectedPromotionIDs.insert(id)
                    if let savedCurrency = savedPromotionCurrencies[id],
                       savedCurrency != promotions.first(where: { $0.id == id })?.progressCurrencyCode {
                        allocationAmounts[id] = nil
                        manuallyEditedAllocationIDs.remove(id)
                    }
                    savedPromotionCurrencies[id] = nil
                }
            }
        )
    }

    private func amountBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { allocationAmounts[id] ?? "" },
            set: {
                allocationAmounts[id] = $0
                automaticallySelectedPromotionIDs.remove(id)
                manuallyEditedAllocationIDs.insert(id)
            }
        )
    }

    private func positiveAllocationAmount(for id: UUID) -> Decimal? {
        guard let amount = CardPilotUI.decimal(allocationAmounts[id] ?? "", format: amountFormat),
              amount > .zero else { return nil }
        return amount
    }

    private func initializePromotions() {
        guard !didInitializePromotions else { return }
        if transaction == nil {
            let automaticIDs = currentAutomaticPromotionIDs
            selectedPromotionIDs.formUnion(automaticIDs)
            automaticallySelectedPromotionIDs = automaticIDs
            for promotion in promotions where selectedPromotionIDs.contains(promotion.id) {
                allocationAmounts[promotion.id] = defaultAmount(for: promotion)
            }
        }
        didInitializePromotions = true
    }

    private func refreshCandidates() {
        guard didInitializePromotions, transaction == nil else { return }
        let ids = currentAutomaticPromotionIDs
        let staleAutomaticIDs = automaticallySelectedPromotionIDs.subtracting(ids)
        automaticallySelectedPromotionIDs.subtract(staleAutomaticIDs)
        selectedPromotionIDs.subtract(staleAutomaticIDs)

        let newAutomaticIDs = ids
            .subtracting(selectedPromotionIDs)
            .subtracting(manuallyDeselectedPromotionIDs)
        selectedPromotionIDs.formUnion(newAutomaticIDs)
        automaticallySelectedPromotionIDs.formUnion(newAutomaticIDs)
        for promotion in promotions where newAutomaticIDs.contains(promotion.id) {
            allocationAmounts[promotion.id] = defaultAmount(for: promotion)
        }
    }

    private func refreshDefaultAllocationAmounts() {
        guard transaction == nil else { return }
        for id in selectedPromotionIDs where !manuallyEditedAllocationIDs.contains(id) {
            guard let promotion = promotions.first(where: { $0.id == id }) else { continue }
            allocationAmounts[id] = defaultAmount(for: promotion)
        }
    }

    private func defaultAmount(for promotion: Promotion) -> String {
        guard let amount = CardPilotUI.decimal(amountText, format: amountFormat), amount > .zero else { return "" }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency == promotion.progressCurrencyCode else { return "" }
        if kind == .refund {
            let suggestion = suggestedRefundAllocationAmount(
                refundAmount: amount, refundCurrencyCode: normalizedCurrency, promotion: promotion,
                original: originalTransactions.first { $0.id == originalTransactionID },
                excludingTransactionID: transaction?.id)
            guard let suggestion, suggestion > .zero else { return "" }
            return CardPilotUI.editableAmountText(suggestion, format: amountFormat)
        }
        let currentQualifiedAmount = (try? PromotionCalculator.progress(for: promotion))?.qualifiedAmount ?? .zero
        let suggestion = PromotionCalculator.suggestedQualifyingAmount(
            transactionAmount: amount,
            transactionCurrencyCode: normalizedCurrency,
            promotionCurrencyCode: promotion.progressCurrencyCode,
            perTransactionThreshold: promotion.perTransactionThreshold,
            currentQualifiedAmount: currentQualifiedAmount,
            qualifyingCap: promotion.qualifyingCap
        )
        guard let suggestion, suggestion > .zero else { return "" }
        return CardPilotUI.editableAmountText(suggestion, format: amountFormat)
    }

    private var selectedPromotionsContainNonStacking: Bool {
        promotions.contains { selectedPromotionIDs.contains($0.id) && !$0.stackingAllowed }
    }

    private var selectedPromotionsOutsideCandidates: [Promotion] {
        let candidateIDs = Set(candidatePromotions.map(\.id))
        return promotions.filter {
            selectedPromotionIDs.contains($0.id)
                && !candidateIDs.contains($0.id)
                && !inheritedPromotionIDs.contains($0.id)
        }
    }

    private func transactionLabel(_ transaction: Transaction) -> String {
        let merchant = transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant
        return "\(CardPilotUI.dateText(transaction.transactionOn)) · \(merchant) · \(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
    }

    private func save(allowingOverRefund: Bool = false, scrollProxy: ScrollViewProxy) {
        guard !draftFinished else { return }
        errorMessage = nil
        if transaction == nil {
            do {
                let id = draftID
                if try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })) > 0 {
                    draftFinished = true
                    try? draftStore.clear()
                    dismiss()
                    return
                }
            } catch {
                errorMessage = "无法检查交易是否已保存，请重试。"
                return
            }
        }
        guard selectedPromotionIDs.isSubset(of: Set(promotions.map(\.id))) else {
            errorMessage = "草稿中的活动已不存在，请先移除失效活动；其余交易内容会保留。"
            return
        }
        for promotion in promotions where selectedPromotionIDs.contains(promotion.id) {
            if let savedCurrency = savedPromotionCurrencies[promotion.id], savedCurrency != promotion.progressCurrencyCode {
                errorMessage = "活动币种已改变，请取消选择该活动后重新选择并填写计入金额，或移除失效活动。"
                return
            }
        }
        if kind == .refund, originalTransactionID != Self.noOriginalTransactionID,
           !originalTransactions.contains(where: { $0.id == originalTransactionID }) {
            errorMessage = "关联的原消费已不可用，请重新选择原消费。"
            return
        }
        guard let card = selectedCard else { errorMessage = "请选择卡片。"; return }
        guard let amount = CardPilotUI.decimal(amountText, format: amountFormat), amount > .zero else {
            errorMessage = "金额应为大于 0 的数字。"
            return
        }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidCurrencyCode(normalizedCurrency) else {
            errorMessage = "币种应为有效的 ISO 4217 代码。"
            return
        }
        if let transaction,
           !transaction.refunds.isEmpty,
           (kind != .purchase || card.id != transaction.card.id) {
            errorMessage = "已有退款的原消费不能更换卡片或改为退款。"
            return
        }
        let original = kind == .refund ? originalTransactions.first(where: { $0.id == originalTransactionID }) : nil
        let selectedPromotions = visiblePromotions.filter { selectedPromotionIDs.contains($0.id) }
        var parsedAmounts: [UUID: Decimal] = [:]
        for promotion in selectedPromotions {
            guard let amount = positiveAllocationAmount(for: promotion.id) else {
                showingAllocationErrors = true
                // Give SwiftUI a chance to lay out the new error before scrolling.
                let field = InputField.allocation(promotion.id)
                Task { @MainActor in
                    await Task.yield()
                    scrollProxy.scrollTo(field, anchor: .top)
                }
                return
            }
            parsedAmounts[promotion.id] = amount
        }
        if !allowingOverRefund, kind == .purchase, let transaction {
            var warnings: [String] = []
            if PromotionCalculator.refundExceedsOriginalAmount(
                originalAmount: amount,
                proposedRefundAmount: .zero,
                otherRefunds: transaction.refunds
                    .filter { $0.currencyCode == normalizedCurrency }
                    .map { (transactionID: $0.id, amount: $0.amount, status: $0.status) },
                excludingTransactionID: nil
            ) {
                warnings.append("关联有效退款合计高于修改后的原消费金额。")
            }
            let overRefundedPromotionIDs = PromotionCalculator.overRefundedPromotionIDs(
                originalAllocations: selectedPromotions.map {
                    (promotionID: $0.id, qualifyingAmount: parsedAmounts[$0.id] ?? .zero)
                },
                refundAllocations: transaction.refunds
                    .filter { $0.status == .active && $0.currencyCode == normalizedCurrency }
                    .flatMap { refund in
                        refund.allocations.map {
                            (promotionID: $0.promotion.id, qualifyingAmount: $0.qualifyingAmount)
                        }
                    },
                otherRefundAllocations: [],
                excludingTransactionID: nil
            )
            let overRefundedPromotionNames = promotions
                .filter { overRefundedPromotionIDs.contains($0.id) }
                .map(\.title)
            if !overRefundedPromotionNames.isEmpty {
                warnings.append("促销分配高于修改后的原消费分配：" + overRefundedPromotionNames.joined(separator: "、") + "。")
            }
            if !warnings.isEmpty {
                overRefundWarningMessage = warnings.joined(separator: "\n")
                return
            }
        }
        if !allowingOverRefund,
           let original,
           original.currencyCode == normalizedCurrency {
            var warnings: [String] = []
            if PromotionCalculator.refundExceedsOriginalAmount(
                originalAmount: original.amount,
                proposedRefundAmount: status == .active ? amount : .zero,
                otherRefunds: original.refunds.map {
                    (transactionID: $0.id, amount: $0.amount, status: $0.status)
                },
                excludingTransactionID: transaction?.id
            ) {
                warnings.append("关联有效退款合计高于原消费金额。")
            }
            let overRefundedPromotionIDs = PromotionCalculator.overRefundedPromotionIDs(
                originalAllocations: original.allocations.map {
                    (promotionID: $0.promotion.id, qualifyingAmount: $0.qualifyingAmount)
                },
                refundAllocations: selectedPromotions.map {
                    (
                        promotionID: $0.id,
                        qualifyingAmount: status == .active ? (parsedAmounts[$0.id] ?? .zero) : .zero
                    )
                },
                otherRefundAllocations: original.refunds.flatMap { refund in
                    refund.allocations.map {
                        (
                            transactionID: refund.id,
                            promotionID: $0.promotion.id,
                            qualifyingAmount: $0.qualifyingAmount,
                            status: refund.status
                        )
                    }
                },
                excludingTransactionID: transaction?.id
            )
            let overRefundedPromotionNames = selectedPromotions
                .filter { overRefundedPromotionIDs.contains($0.id) }
                .map(\.title)
            if !overRefundedPromotionNames.isEmpty {
                warnings.append("促销分配超出原消费的可退余额：" + overRefundedPromotionNames.joined(separator: "、") + "。")
            }
            if !warnings.isEmpty {
                overRefundWarningMessage = warnings.joined(separator: "\n")
                return
            }
        }
        do {
            try TransactionEditActions.save(
                values: TransactionEditValues(kind: kind, transactionOn: CardPilotUI.rawDate(transactionDate),
                    postingOn: hasPostingDate ? CardPilotUI.rawDate(postingDate) : nil,
                    amount: amount, currencyCode: normalizedCurrency, merchant: merchant,
                    category: category, notes: notes, status: status),
                transaction: transaction, newID: draftID, card: card, original: original,
                allocations: selectedPromotions.map { ($0, parsedAmounts[$0.id] ?? .zero) },
                context: modelContext)
            if transaction == nil {
                draftFinished = true
                // If cleanup fails, the saved UUID makes the draft obsolete on next open.
                try? draftStore.clear()
            }
            lastUsedCardID = card.id.uuidString
            let feedback = TransactionSaveFeedback.make(
                kind: kind,
                amount: amount,
                currencyCode: normalizedCurrency,
                allocationCount: selectedPromotions.count,
                isNew: transaction == nil
            )
            NotificationCenter.default.post(
                name: .transactionDidSave,
                object: nil,
                userInfo: ["message": feedback.message]
            )
            dismiss()
        } catch {
            errorMessage = "交易未保存：\(error.localizedDescription)"
        }
    }
}

private struct CardSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [Card]
    let selectedCardID: UUID
    let lastUsedCardID: String
    let onSelect: (UUID) -> Void

    @State private var searchText = ""

    private var filteredCards: [Card] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return cards }
        return cards.filter { card in
            card.account.bank.name.localizedCaseInsensitiveContains(query)
                || card.nickname.localizedCaseInsensitiveContains(query)
                || card.productName.localizedCaseInsensitiveContains(query)
                || card.lastFour.localizedCaseInsensitiveContains(query)
        }
    }

    private var currentCard: Card? {
        filteredCards.first { $0.id == selectedCardID }
    }

    private var recentCard: Card? {
        guard let recentID = UUID(uuidString: lastUsedCardID), recentID != selectedCardID else { return nil }
        return filteredCards.first { $0.id == recentID }
    }

    private var featuredCardIDs: Set<UUID> {
        Set([currentCard?.id, recentCard?.id].compactMap { $0 })
    }

    private var bankNames: [String] {
        Set(filteredCards
            .filter { !featuredCardIDs.contains($0.id) }
            .map { $0.account.bank.name })
            .sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredCards.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配卡片", systemImage: "creditcard.trianglebadge.exclamationmark")
                    } description: {
                        Text("请更换银行、卡片名称或末四位搜索词。")
                    }
                } else if let currentCard {
                    Section("当前卡片") {
                        cardRow(currentCard)
                    }
                }
                if let recentCard {
                    Section("最近使用") {
                        cardRow(recentCard)
                    }
                }
                ForEach(bankNames, id: \.self) { bankName in
                    Section(bankName) {
                        ForEach(filteredCards.filter {
                            $0.account.bank.name == bankName && !featuredCardIDs.contains($0.id)
                        }, id: \.id) { card in
                            cardRow(card)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .searchable(text: $searchText, prompt: "搜索银行、卡片或末四位")
        }
    }

    private func cardRow(_ card: Card) -> some View {
        Button {
            onSelect(card.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                BankBadge(bank: card.account.bank)
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.nickname.isEmpty ? card.productName : card.nickname)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(card.account.bank.name) · •••• \(card.lastFour)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    CardNetworksBadges(networks: card.networks)
                }
                Spacer(minLength: 8)
                if card.id == selectedCardID {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(cardLabel(card))\(card.id == selectedCardID ? "，已选择" : "")")
    }
}
