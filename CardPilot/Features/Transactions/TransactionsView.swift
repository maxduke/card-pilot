import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @Query private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]

    @State private var editingTransaction: Transaction?
    @State private var showingEditor = false
    @State private var errorMessage: String?
    @State private var filterCardID: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    EmptyStateView(
                        title: "还没有交易",
                        systemImage: "list.bullet.rectangle",
                        message: "记录一笔消费后，可以从候选促销中选择要计入的活动。"
                    )
                } else if filteredTransactions.isEmpty {
                    EmptyStateView(
                        title: "没有匹配交易",
                        systemImage: "line.3.horizontal.decrease.circle",
                        message: "可以更换卡片筛选或搜索商户、分类。"
                    )
                } else {
                    List {
                        ForEach(filteredTransactions, id: \.id) { transaction in
                            TransactionRow(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingTransaction = transaction
                                    showingEditor = true
                                }
                                .contextMenu {
                                    Button {
                                        editingTransaction = transaction
                                        showingEditor = true
                                    } label: {
                                        Label("编辑交易", systemImage: "pencil")
                                    }
                                    if transaction.status == .active {
                                        Button {
                                            transaction.reverse()
                                            save()
                                        } label: {
                                            Label("标记为已冲正", systemImage: "arrow.uturn.backward")
                                        }
                                    }
                                    Button(role: .destructive) {
                                        delete(transaction)
                                    } label: {
                                        Label("删除交易", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("交易")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("筛选卡片", selection: $filterCardID) {
                        Text("全部卡片").tag(nil as UUID?)
                        ForEach(cards.sorted { cardLabel($0) < cardLabel($1) }, id: \.id) { card in
                            Text(cardLabel(card)).tag(Optional(card.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("按卡片筛选交易")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTransaction = nil
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加交易")
                    .disabled(cards.isEmpty)
                }
            }
            .sheet(isPresented: $showingEditor) {
                TransactionEditorView(transaction: editingTransaction, cards: cards, promotions: promotions, transactions: transactions)
            }
            .alert("无法完成操作", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .searchable(text: $searchText, prompt: "搜索商户或分类")
        }
    }

    private var filteredTransactions: [Transaction] {
        filterTransactions(transactions, cardID: filterCardID, searchText: searchText)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "数据未保存：\(error.localizedDescription)"
        }
    }

    private func delete(_ transaction: Transaction) {
        guard transaction.refunds.isEmpty, transaction.allocations.isEmpty else {
            errorMessage = "该交易仍被退款或促销分配引用，不能删除。"
            return
        }
        modelContext.delete(transaction)
        save()
    }
}

func filterTransactions(_ transactions: [Transaction], cardID: UUID?, searchText: String) -> [Transaction] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return transactions.filter { transaction in
        guard cardID == nil || transaction.card.id == cardID else { return false }
        guard !query.isEmpty else { return true }
        return transaction.merchant.localizedCaseInsensitiveContains(query)
            || transaction.category.localizedCaseInsensitiveContains(query)
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.kind == .refund ? "arrow.uturn.left.circle" : "cart")
                .foregroundStyle(transaction.kind == .refund ? .orange : .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.subheadline.weight(.medium))
                Text("\(CardPilotUI.dateText(transaction.transactionOn)) · \(cardName(transaction.card))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if transaction.status == .reversed {
                    Text("已冲正")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Text("\(transaction.kind == .refund ? "−" : "")\(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))")
                .foregroundStyle(transaction.status == .reversed ? .secondary : .primary)
                .strikethrough(transaction.status == .reversed)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(transaction.kind == .refund ? "退款" : "消费")，\(transaction.merchant)，\(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))")
    }

    private func cardName(_ card: Card) -> String {
        return cardLabel(card)
    }
}

private func cardLabel(_ card: Card) -> String {
    let name = card.nickname.isEmpty ? card.productName : card.nickname
    return "\(name) · •••• \(card.lastFour)"
}

private struct TransactionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction?
    let cards: [Card]
    let promotions: [Promotion]
    let transactions: [Transaction]

    @State private var cardID: UUID
    @State private var kind: TransactionKind
    @State private var transactionDate: Date
    @State private var postingDate: Date
    @State private var hasPostingDate: Bool
    @State private var amountText: String
    @State private var currencyCode: String
    @State private var merchant: String
    @State private var category: String
    @State private var notes: String
    @State private var status: TransactionStatus
    @State private var originalTransactionID: UUID
    @State private var selectedPromotionIDs: Set<UUID>
    @State private var allocationAmounts: [UUID: String]
    @State private var automaticallySelectedPromotionIDs: Set<UUID> = []
    @State private var manuallyDeselectedPromotionIDs: Set<UUID> = []
    @State private var manuallyEditedAllocationIDs: Set<UUID> = []
    @State private var didInitializePromotions = false
    @State private var showingInactiveCards: Bool
    @State private var errorMessage: String?
    @State private var overRefundWarningMessage: String?

    private static let noOriginalTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    init(transaction: Transaction?, cards: [Card], promotions: [Promotion], transactions: [Transaction]) {
        self.transaction = transaction
        self.cards = cards
        self.promotions = promotions
        self.transactions = transactions
        let initialCard = transaction?.card ?? cards.first(where: { $0.status == .active }) ?? cards.first
        _cardID = State(initialValue: initialCard?.id ?? UUID())
        _kind = State(initialValue: transaction?.kind ?? .purchase)
        _transactionDate = State(initialValue: transaction.flatMap { try? LocalDate(rawValue: $0.transactionOn).date(in: CardPilotUI.homeTimeZone) } ?? Date())
        _postingDate = State(initialValue: transaction.flatMap { $0.postingOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _hasPostingDate = State(initialValue: transaction?.postingOn != nil)
        _amountText = State(initialValue: transaction.map { CardPilotUI.editableAmountText($0.amount) } ?? "")
        _currencyCode = State(initialValue: transaction?.currencyCode ?? initialCard?.account.limitCurrencyCode ?? "CNY")
        _merchant = State(initialValue: transaction?.merchant ?? "")
        _category = State(initialValue: transaction?.category ?? "")
        _notes = State(initialValue: transaction?.notes ?? "")
        _status = State(initialValue: transaction?.status ?? .active)
        _originalTransactionID = State(initialValue: transaction?.originalTransaction?.id ?? Self.noOriginalTransactionID)
        _selectedPromotionIDs = State(initialValue: Set(transaction?.allocations.map { $0.promotion.id } ?? []))
        _allocationAmounts = State(initialValue: Dictionary(uniqueKeysWithValues: (transaction?.allocations ?? []).map { ($0.promotion.id, CardPilotUI.editableAmountText($0.qualifyingAmount)) }))
        _showingInactiveCards = State(initialValue: transaction?.card.status == .inactive)
    }

    private var selectedCard: Card? { cards.first { $0.id == cardID } }
    private var selectableCards: [Card] { cards.filter { showingInactiveCards || $0.status == .active } }

    private var originalTransactions: [Transaction] {
        transactions.filter {
            $0.id != transaction?.id
                && $0.kind == .purchase
                && $0.card.id == cardID
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
        return Set(original.allocations.map(\.promotion.id))
    }

    private var currentAutomaticPromotionIDs: Set<UUID> {
        Set(candidatePromotions.map(\.id)).union(inheritedPromotionIDs)
    }

    private var visiblePromotionIDs: Set<UUID> {
        Set(candidatePromotions.map(\.id)).union(selectedPromotionIDs)
    }

    private var visiblePromotions: [Promotion] {
        promotions.filter { visiblePromotionIDs.contains($0.id) }.sorted { $0.endOn < $1.endOn }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("交易") {
                    Picker("卡片", selection: $cardID) {
                        ForEach(selectableCards, id: \.id) { card in
                            Text(cardLabel(card)).tag(card.id)
                        }
                    }
                    Toggle("显示停用卡", isOn: $showingInactiveCards)
                    Picker("类型", selection: $kind) {
                        Text("消费").tag(TransactionKind.purchase)
                        Text("退款").tag(TransactionKind.refund)
                    }
                    if kind == .refund {
                        Picker("原消费", selection: $originalTransactionID) {
                            Text("不关联原消费（可选）").tag(Self.noOriginalTransactionID)
                            ForEach(originalTransactions, id: \.id) { original in
                                Text(transactionLabel(original)).tag(original.id)
                            }
                        }
                    }
                    DatePicker("交易日期", selection: $transactionDate, displayedComponents: .date)
                    Toggle("记录入账日期", isOn: $hasPostingDate)
                    if hasPostingDate {
                        DatePicker("入账日期", selection: $postingDate, displayedComponents: .date)
                    }
                    TextField("金额", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("币种", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    TextField("商户（可选）", text: $merchant)
                    TextField("分类（可选）", text: $category)
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                    Picker("状态", selection: $status) {
                        Text("有效").tag(TransactionStatus.active)
                        Text("已冲正").tag(TransactionStatus.reversed)
                    }
                }

                Section("促销分配") {
                    if visiblePromotions.isEmpty {
                        Text("没有匹配的候选促销；保存交易后仍可在促销详情中手动分配。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visiblePromotions, id: \.id) { promotion in
                            Toggle(promotion.title, isOn: promotionBinding(promotion.id))
                            if selectedPromotionIDs.contains(promotion.id) {
                                TextField(
                                    "计入金额（\(promotion.progressCurrencyCode)）",
                                    text: amountBinding(promotion.id)
                                )
                                .keyboardType(.decimalPad)
                                .padding(.leading, 24)
                            }
                        }
                        Text("候选活动会默认勾选；可取消或调整计入金额。不同币种请填写银行认可的合格金额。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .onAppear(perform: initializePromotions)
            .onChange(of: cardID) { _, _ in refreshCandidates() }
            .onChange(of: kind) { _, _ in refreshCandidates() }
            .onChange(of: originalTransactionID) { _, _ in refreshCandidates() }
            .onChange(of: transactionDate) { _, _ in refreshCandidates() }
            .onChange(of: postingDate) { _, _ in refreshCandidates() }
            .onChange(of: hasPostingDate) { _, _ in refreshCandidates() }
            .onChange(of: amountText) { _, _ in refreshDefaultAllocationAmounts() }
            .onChange(of: currencyCode) { _, _ in refreshDefaultAllocationAmounts() }
            .navigationTitle(transaction == nil ? "添加交易" : "编辑交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .alert("退款超出可退范围", isPresented: Binding(
                get: { overRefundWarningMessage != nil },
                set: { if !$0 { overRefundWarningMessage = nil } }
            )) {
                Button("取消", role: .cancel) {}
                Button("仍然保存", role: .destructive) { save(allowingOverRefund: true) }
            } message: {
                Text(overRefundWarningMessage ?? "")
            }
        }
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

    private func initializePromotions() {
        guard !didInitializePromotions else { return }
        if transaction == nil {
            let automaticIDs = currentAutomaticPromotionIDs
            selectedPromotionIDs = automaticIDs
            automaticallySelectedPromotionIDs = automaticIDs
            for promotion in promotions where automaticIDs.contains(promotion.id) {
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
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedCurrency == promotion.progressCurrencyCode ? amountText : ""
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

    private func cardLabel(_ card: Card) -> String {
        let name = card.nickname.isEmpty ? card.productName : card.nickname
        return "\(name) · •••• \(card.lastFour)"
    }

    private func transactionLabel(_ transaction: Transaction) -> String {
        let merchant = transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant
        return "\(CardPilotUI.dateText(transaction.transactionOn)) · \(merchant) · \(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
    }

    private func save(allowingOverRefund: Bool = false) {
        guard let card = selectedCard else { errorMessage = "请选择卡片。"; return }
        guard let amount = CardPilotUI.decimal(amountText), amount > .zero else {
            errorMessage = "金额应为大于 0 的数字。"
            return
        }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidCurrencyCode(normalizedCurrency) else {
            errorMessage = "币种应为 3 位大写字母。"
            return
        }
        if let transaction,
           !transaction.refunds.isEmpty,
           (kind != .purchase || card.id != transaction.card.id) {
            errorMessage = "已有退款的原消费不能更换卡片或改为退款。"
            return
        }
        let original = kind == .refund ? originalTransactions.first(where: { $0.id == originalTransactionID }) : nil
        let selectedPromotions = promotions.filter { selectedPromotionIDs.contains($0.id) }
        var parsedAmounts: [UUID: Decimal] = [:]
        for promotion in selectedPromotions {
            guard let amount = CardPilotUI.decimal(allocationAmounts[promotion.id] ?? ""), amount >= .zero else {
                errorMessage = "活动“\(promotion.title)”的计入金额格式不正确。"
                return
            }
            parsedAmounts[promotion.id] = amount
        }
        if !allowingOverRefund,
           kind == .purchase,
           let transaction,
           PromotionCalculator.refundExceedsOriginalAmount(
               originalAmount: amount,
               proposedRefundAmount: .zero,
               otherRefunds: transaction.refunds
                   .filter { $0.currencyCode == normalizedCurrency }
                   .map { (transactionID: $0.id, amount: $0.amount, status: $0.status) },
               excludingTransactionID: nil
           ) {
            overRefundWarningMessage = "关联有效退款合计高于修改后的原消费金额。"
            return
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
                    (promotionID: $0.id, qualifyingAmount: parsedAmounts[$0.id] ?? .zero)
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
        let target = transaction ?? Transaction(
            card: card,
            kind: kind,
            transactionOn: CardPilotUI.rawDate(transactionDate),
            postingOn: hasPostingDate ? CardPilotUI.rawDate(postingDate) : nil,
            amount: amount,
            currencyCode: normalizedCurrency,
            merchant: merchant,
            category: category,
            notes: notes,
            originalTransaction: original,
            status: status
        )
        target.card = card
        target.kind = kind
        target.transactionOn = CardPilotUI.rawDate(transactionDate)
        target.postingOn = hasPostingDate ? CardPilotUI.rawDate(postingDate) : nil
        target.amount = amount
        target.currencyCode = normalizedCurrency
        target.merchant = merchant
        target.category = category
        target.notes = notes
        target.originalTransaction = original
        target.status = status

        do {
            try target.validate()
            let existingAllocations = target.allocations.reduce(into: [UUID: PromotionAllocation]()) {
                if $0[$1.promotion.id] == nil { $0[$1.promotion.id] = $1 }
            }
            if transaction == nil { modelContext.insert(target) }
            for allocation in target.allocations where !selectedPromotionIDs.contains(allocation.promotion.id) {
                modelContext.delete(allocation)
            }
            for promotion in selectedPromotions {
                if let allocation = existingAllocations[promotion.id] {
                    allocation.qualifyingAmount = parsedAmounts[promotion.id] ?? .zero
                    allocation.currencyCode = promotion.progressCurrencyCode
                    try allocation.validate()
                } else {
                    let allocation = PromotionAllocation(
                        transaction: target,
                        promotion: promotion,
                        qualifyingAmount: parsedAmounts[promotion.id] ?? .zero,
                        currencyCode: promotion.progressCurrencyCode
                    )
                    try allocation.validate()
                    modelContext.insert(allocation)
                }
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "交易未保存：\(error.localizedDescription)"
        }
    }
}
