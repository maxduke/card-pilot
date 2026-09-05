import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @Query private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]

    @State private var isPresentingEditor = false
    private let onAddCard: () -> Void
    @State private var editingTransaction: Transaction?
    @State private var detailTransaction: Transaction?
    @State private var transactionPendingDeletion: Transaction?
    @State private var errorMessage: String?
    @State private var filterCardID: UUID?
    @State private var filterKind: TransactionKind?
    @State private var filterPromotionID: UUID?
    @State private var filterStatus: TransactionStatus?
    @State private var showingFilterSheet = false
    @State private var searchText = ""

    init(
        onAddCard: @escaping () -> Void = {}
    ) {
        self.onAddCard = onAddCard
    }

    var body: some View {
        NavigationStack {
            Group {
                if transactions.isEmpty {
                    if cards.isEmpty {
                        ContentUnavailableView {
                            Label("先添加信用卡", systemImage: "creditcard")
                        } description: {
                            Text("添加卡片后才能记录交易和促销进度。")
                        } actions: {
                            Button("添加信用卡", systemImage: "plus", action: onAddCard)
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView {
                            Label("还没有交易", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("记录第一笔消费，开始追踪支出和活动进度。")
                        } actions: {
                            Button("记一笔", systemImage: "plus") {
                                editingTransaction = nil
                                isPresentingEditor = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if filteredTransactions.isEmpty {
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            activeFilterSummary
                        }
                        EmptyStateView(
                            title: "没有匹配交易",
                            systemImage: "line.3.horizontal.decrease.circle",
                            message: hasActiveFilters ? "可以调整筛选条件，或点击上方“清除”查看全部交易。" : "可以搜索商户、分类或促销名称。"
                        )
                    }
                } else {
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            activeFilterSummary
                        }
                        List {
                            ForEach(transactionSections.indices, id: \.self) { sectionIndex in
                                let section = transactionSections[sectionIndex]
                                Section {
                                    ForEach(section.transactions, id: \.id) { transaction in
                                        Button {
                                            detailTransaction = transaction
                                        } label: {
                                            TransactionRow(transaction: transaction)
                                        }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            Button {
                                                editingTransaction = transaction
                                                isPresentingEditor = true
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
                                                transactionPendingDeletion = transaction
                                            } label: {
                                                Label("删除交易", systemImage: "trash")
                                            }
                                        }
                                    }
                                } header: {
                                    Text(CardPilotUI.dateText(section.date))
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("交易")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFilterSheet = true
                    } label: {
                        Label("筛选", systemImage: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(hasActiveFilters ? "筛选，已启用 \(activeFilterCount) 项" : "筛选")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingTransaction = nil
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加交易")
                    .disabled(cards.isEmpty)
                }
            }
            .sheet(isPresented: $isPresentingEditor, onDismiss: { editingTransaction = nil }) {
                TransactionEditorView(
                    transaction: editingTransaction,
                    cards: cards,
                    promotions: promotions,
                    transactions: transactions
                )
            }
            .sheet(isPresented: Binding(
                get: { detailTransaction != nil },
                set: { if !$0 { detailTransaction = nil } }
            )) {
                if let detailTransaction {
                    TransactionDetailView(
                        transaction: detailTransaction,
                        cards: cards,
                        promotions: promotions,
                        transactions: transactions
                    )
                }
            }
            .sheet(isPresented: $showingFilterSheet) {
                TransactionFilterSheet(
                    cards: cards,
                    promotions: promotions,
                    cardID: $filterCardID,
                    kind: $filterKind,
                    promotionID: $filterPromotionID,
                    status: $filterStatus
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("无法完成操作", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .confirmationDialog("确认删除交易？", isPresented: Binding(
                get: { transactionPendingDeletion != nil },
                set: { if !$0 { transactionPendingDeletion = nil } }
            )) {
                Button("永久删除", role: .destructive) {
                    if let transactionPendingDeletion { delete(transactionPendingDeletion) }
                    transactionPendingDeletion = nil
                }
                Button("取消", role: .cancel) { transactionPendingDeletion = nil }
            } message: {
                Text("删除后无法恢复；有关联退款或促销分配的交易仍会受到保护。")
            }
            .searchable(text: $searchText, prompt: "搜索商户、分类或促销")
        }
    }

    private var filteredTransactions: [Transaction] {
        filterTransactions(
            transactions,
            cardID: filterCardID,
            kind: filterKind,
            promotionID: filterPromotionID,
            status: filterStatus,
            searchText: searchText
        )
    }

    private var transactionSections: [(date: Int, transactions: [Transaction])] {
        groupedTransactionsByDate(filteredTransactions)
    }

    private var activeFilterCount: Int {
        [filterCardID != nil, filterKind != nil, filterPromotionID != nil, filterStatus != nil,
         !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty]
            .filter { $0 }
            .count
    }

    private var hasActiveFilters: Bool {
        activeFilterCount > 0 || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var activeFilterSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let filterCardID, let card = cards.first(where: { $0.id == filterCardID }) {
                    filterChip(cardShortLabel(card)) { self.filterCardID = nil }
                }
                if let filterKind {
                    filterChip(filterKind == .refund ? "退款" : "消费") { self.filterKind = nil }
                }
                if let filterPromotionID, let promotion = promotions.first(where: { $0.id == filterPromotionID }) {
                    filterChip(promotionFilterLabel(promotion)) { self.filterPromotionID = nil }
                }
                if let filterStatus {
                    filterChip(filterStatus == .reversed ? "已冲正" : "有效") { self.filterStatus = nil }
                }
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    filterChip("搜索：\(query)") { self.searchText = "" }
                }
                Button("清除全部") {
                    clearFilters()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private func filterChip(_ label: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .accessibilityLabel("移除筛选：\(label)")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.tint)
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1), in: Capsule())
    }

    private func clearFilters() {
        filterCardID = nil
        filterKind = nil
        filterPromotionID = nil
        filterStatus = nil
        searchText = ""
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
    filterTransactions(
        transactions,
        cardID: cardID,
        kind: nil,
        promotionID: nil,
        status: nil,
        searchText: searchText
    )
}

func filterTransactions(
    _ transactions: [Transaction],
    cardID: UUID?,
    kind: TransactionKind?,
    promotionID: UUID?,
    status: TransactionStatus?,
    searchText: String
) -> [Transaction] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return transactions.filter { transaction in
        guard cardID == nil || transaction.card.id == cardID else { return false }
        guard kind == nil || transaction.kind == kind else { return false }
        guard status == nil || transaction.status == status else { return false }
        guard promotionID == nil || transaction.allocations.contains(where: { $0.promotion.id == promotionID }) else { return false }
        guard !query.isEmpty else { return true }
        return transaction.merchant.localizedCaseInsensitiveContains(query)
            || transaction.category.localizedCaseInsensitiveContains(query)
            || transaction.card.account.bank.name.localizedCaseInsensitiveContains(query)
            || cardLabel(transaction.card).localizedCaseInsensitiveContains(query)
            || transaction.allocations.contains { $0.promotion.title.localizedCaseInsensitiveContains(query) }
    }
}

func groupedTransactionsByDate(_ transactions: [Transaction]) -> [(date: Int, transactions: [Transaction])] {
    Dictionary(grouping: transactions, by: \.transactionOn)
        .map { date, values in
            (
                date: date,
                transactions: values.sorted { $0.id.uuidString < $1.id.uuidString }
            )
        }
        .sorted { $0.date > $1.date }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            BankBadge(bank: transaction.card.account.bank)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(cardShortLabel(transaction.card))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if transaction.kind == .refund {
                        transactionTag("退款", color: .orange)
                    }
                    if transaction.status == .reversed {
                        transactionTag("已冲正", color: .red)
                    }
                    if transaction.allocations.count == 1, let promotion = transaction.allocations.first?.promotion {
                        Text("计入：\(promotion.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if transaction.allocations.count > 1 {
                        Text("已计入 \(transaction.allocations.count) 个促销")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(signedAmountText(transaction))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(transaction.status == .reversed ? .secondary : .primary)
                .strikethrough(transaction.status == .reversed)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(transactionAccessibilityLabel(transaction))
        .accessibilityHint("查看交易详情")
    }

    private func transactionTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private func cardLabel(_ card: Card) -> String {
    let name = card.nickname.isEmpty ? card.productName : card.nickname
    return "\(card.account.bank.name) · \(name) · •••• \(card.lastFour) · \(cardNetworkSummary(card.networks))"
}

private func cardShortLabel(_ card: Card) -> String {
    let name = card.nickname.isEmpty ? card.productName : card.nickname
    return "\(card.account.bank.name) · \(name) · •••• \(card.lastFour)"
}

func promotionFilterLabel(_ promotion: Promotion) -> String {
    var parts = [promotion.title]
    if let index = promotion.seriesIndex { parts.append("第 \(index + 1) 期") }
    parts.append(CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
    return parts.joined(separator: " · ")
}

private func signedAmountText(_ transaction: Transaction) -> String {
    "\(transaction.kind == .refund ? "−" : "")\(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
}

private func transactionAccessibilityLabel(_ transaction: Transaction) -> String {
    let merchant = transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant
    let category = transaction.category.isEmpty ? "未分类" : "分类：\(transaction.category)"
    let status = transaction.status == .reversed ? "已冲正" : "有效"
    let promotions: String
    switch transaction.allocations.count {
    case 0: promotions = "本笔未计入促销"
    case 1: promotions = "计入促销：\(transaction.allocations[0].promotion.title)"
    default: promotions = "已计入 \(transaction.allocations.count) 个促销"
    }
    var label = "\(transaction.kind == .refund ? "退款" : "消费")，\(merchant)，\(signedAmountText(transaction))，\(cardLabel(transaction.card))，交易日期 \(CardPilotUI.dateText(transaction.transactionOn))，\(category)，状态：\(status)，\(promotions)"
    if let postingOn = transaction.postingOn {
        label += "，入账日期 \(CardPilotUI.dateText(postingOn))"
    }
    if !transaction.notes.isEmpty {
        label += "，备注：\(transaction.notes)"
    }
    if transaction.kind == .refund {
        label += transaction.originalTransaction == nil ? "，未关联原消费" : "，已关联原消费"
    } else if !transaction.refunds.isEmpty {
        label += "，关联退款 \(transaction.refunds.count) 笔"
    }
    return label
}

private struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction
    let cards: [Card]
    let promotions: [Promotion]
    let transactions: [Transaction]

    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                            .font(.title3.weight(.semibold))
                        Text(signedAmountText(transaction))
                            .font(.largeTitle.bold())
                            .monospacedDigit()
                            .foregroundStyle(transaction.status == .reversed ? .secondary : .primary)
                            .strikethrough(transaction.status == .reversed)
                        HStack(spacing: 8) {
                            detailTag(transaction.kind == .refund ? "退款" : "消费", color: transaction.kind == .refund ? .orange : .blue)
                            if transaction.status == .reversed {
                                detailTag("已冲正", color: .red)
                            } else {
                                detailTag("有效", color: .green)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("交易信息") {
                    LabeledContent("卡片", value: cardLabel(transaction.card))
                    LabeledContent("交易日期", value: CardPilotUI.dateText(transaction.transactionOn))
                    LabeledContent("入账日期", value: CardPilotUI.dateText(transaction.postingOn))
                    LabeledContent("币种", value: transaction.currencyCode)
                    LabeledContent("分类", value: transaction.category.isEmpty ? "未分类" : transaction.category)
                    LabeledContent("备注", value: transaction.notes.isEmpty ? "无" : transaction.notes)
                }

                Section("促销分配") {
                    if transaction.allocations.isEmpty {
                        Label("本笔未计入促销", systemImage: "tag.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transaction.allocations.sorted { $0.promotion.title.localizedCaseInsensitiveCompare($1.promotion.title) == .orderedAscending }, id: \.id) { allocation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(allocation.promotion.title)
                                    .font(.subheadline.weight(.medium))
                                Text("计入 \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("促销 \(allocation.promotion.title)，计入 \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                        }
                    }
                }

                if transaction.kind == .refund {
                    Section("关联原消费") {
                        if let originalTransaction = transaction.originalTransaction {
                            relatedTransactionRow(originalTransaction)
                        } else {
                            Label("未关联原消费", systemImage: "link.badge.plus")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("关联退款") {
                        if transaction.refunds.isEmpty {
                            Text("暂无关联退款")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(transaction.refunds.sorted { $0.id.uuidString < $1.id.uuidString }, id: \.id) { refund in
                                relatedTransactionRow(refund)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("交易详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑") { showingEditor = true }
                }
            }
            .sheet(isPresented: $showingEditor) {
                TransactionEditorView(
                    transaction: transaction,
                    cards: cards,
                    promotions: promotions,
                    transactions: transactions
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func detailTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func relatedTransactionRow(_ related: Transaction) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(related.merchant.isEmpty ? "未填写商户" : related.merchant)
                    .font(.subheadline.weight(.medium))
                Text("\(CardPilotUI.dateText(related.transactionOn)) · \(related.status == .reversed ? "已冲正" : "有效")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(signedAmountText(related))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(transactionAccessibilityLabel(related))
    }
}

private struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [Card]
    let promotions: [Promotion]
    @Binding var cardID: UUID?
    @Binding var kind: TransactionKind?
    @Binding var promotionID: UUID?
    @Binding var status: TransactionStatus?

    var body: some View {
        NavigationStack {
            Form {
                Section("卡片") {
                    Picker("卡片", selection: $cardID) {
                        Text("全部卡片").tag(nil as UUID?)
                        ForEach(cards.sorted { cardShortLabel($0) < cardShortLabel($1) }, id: \.id) { card in
                            Text(cardShortLabel(card)).tag(Optional(card.id))
                        }
                    }
                    .pickerStyle(.menu)
                    if cards.isEmpty {
                        Text("还没有可筛选的卡片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("类型") {
                    Picker("交易类型", selection: $kind) {
                        Text("全部类型").tag(nil as TransactionKind?)
                        Text("消费").tag(Optional(TransactionKind.purchase))
                        Text("退款").tag(Optional(TransactionKind.refund))
                    }
                    .pickerStyle(.menu)
                }

                Section("促销") {
                    Picker("促销", selection: $promotionID) {
                        Text("全部促销").tag(nil as UUID?)
                        ForEach(promotions.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }, id: \.id) { promotion in
                            Text(promotionFilterLabel(promotion)).tag(Optional(promotion.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("状态") {
                    Picker("交易状态", selection: $status) {
                        Text("全部状态").tag(nil as TransactionStatus?)
                        Text("有效").tag(Optional(TransactionStatus.active))
                        Text("已冲正").tag(Optional(TransactionStatus.reversed))
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("筛选交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") {
                        cardID = nil
                        kind = nil
                        promotionID = nil
                        status = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct TransactionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction?
    let cards: [Card]
    let promotions: [Promotion]
    let transactions: [Transaction]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var amountIsFocused: Bool
    @ScaledMetric(relativeTo: .caption) private var stepIndicatorSize = 28

    @AppStorage("cardPilot.lastUsedCardID") private var lastUsedCardID = ""
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
    @State private var promotionSearchText = ""
    @State private var manuallyEditedAllocationIDs: Set<UUID> = []
    @State private var didInitializePromotions = false
    @State private var editorStep = 0
    @State private var showingInactiveCards: Bool
    @State private var showingOtherFields: Bool
    @State private var showingCardPicker = false
    @State private var errorMessage: String?
    @State private var overRefundWarningMessage: String?

    private static let noOriginalTransactionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    init(transaction: Transaction?, cards: [Card], promotions: [Promotion], transactions: [Transaction], initialPromotion: Promotion? = nil) {
        self.transaction = transaction
        self.cards = cards
        self.promotions = promotions
        self.transactions = transactions
        let savedCardID = UserDefaults.standard.string(forKey: "cardPilot.lastUsedCardID")
        let initialCard = transaction?.card
            ?? initialPromotion?.eligibleCards.first(where: { $0.status == .active })
            ?? cards.first(where: { $0.status == .active && $0.id.uuidString == savedCardID })
            ?? cards.first(where: { $0.status == .active })
            ?? cards.first
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
        let positiveAllocations = (transaction?.allocations ?? []).filter { $0.qualifyingAmount > .zero }
        var initialIDs = Set(positiveAllocations.map { $0.promotion.id })
        var initialAmounts = Dictionary(uniqueKeysWithValues: positiveAllocations.map { ($0.promotion.id, CardPilotUI.editableAmountText($0.qualifyingAmount)) })
        if transaction == nil, let initialPromotion {
            initialIDs.insert(initialPromotion.id)
            initialAmounts[initialPromotion.id] = ""
        }
        _selectedPromotionIDs = State(initialValue: initialIDs)
        _allocationAmounts = State(initialValue: initialAmounts)
        _showingInactiveCards = State(initialValue: transaction?.card.status == .inactive || cards.allSatisfy { $0.status == .inactive })
        _showingOtherFields = State(initialValue: transaction != nil)
    }

    private var selectedCard: Card? { cards.first { $0.id == cardID } }

    private var selectableCards: [Card] {
        cards.filter { showingInactiveCards || $0.status == .active || $0.id == cardID }
            .sorted { cardLabel($0) < cardLabel($1) }
    }

    private var hasInactiveCards: Bool { cards.contains { $0.status == .inactive } }

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
        return Set(original.allocations.filter { $0.qualifyingAmount > .zero }.map(\.promotion.id))
    }

    private var currentAutomaticPromotionIDs: Set<UUID> {
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard kind == .purchase,
              let transactionAmount = CardPilotUI.decimal(amountText),
              transactionAmount > .zero else {
            return inheritedPromotionIDs
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

    private var visiblePromotionIDs: Set<UUID> {
        Set(candidatePromotions.map(\.id))
            .union(selectedPromotionIDs)
            .union(postingDatePendingPromotions.map(\.id))
            .union(searchedPromotions.map(\.id))
    }

    private var visiblePromotions: [Promotion] {
        promotions.filter { visiblePromotionIDs.contains($0.id) }.sorted { $0.endOn < $1.endOn }
    }

    private var postingDatePendingPromotions: [Promotion] {
        promotionsAwaitingPostingDate(promotions, cardID: selectedCard?.id, hasPostingDate: hasPostingDate)
    }

    private var searchedPromotions: [Promotion] {
        promotionsMatchingSearch(promotions, searchText: promotionSearchText)
    }

    private var isAmountPositive: Bool {
        guard let amount = CardPilotUI.decimal(amountText) else { return false }
        return amount > .zero
    }

    private var needsPromotionConfirmation: Bool {
        !candidatePromotions.isEmpty || !selectedPromotionIDs.isEmpty || !postingDatePendingPromotions.isEmpty
    }

    private var confirmationWarnings: [String] {
        var warnings: [String] = []
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
            VStack(spacing: 0) {
                if needsPromotionConfirmation || editorStep == 1 { editorStepIndicator }
                Form {
                    if editorStep == 0 {
                        basicTransactionSections
                    } else {
                        promotionConfirmationSections
                    }
                    if let errorMessage {
                        InlineErrorView(message: errorMessage)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
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
                        amountIsFocused = false
                        if editorStep == 0 && needsPromotionConfirmation {
                            continueToPromotionConfirmation()
                        } else {
                            save()
                        }
                    } label: {
                        Text(editorStep == 0 ? (needsPromotionConfirmation ? "继续确认促销" : "保存交易") : "确认并保存")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .disabled(!isAmountPositive || selectedCard == nil)
                    .accessibilityIdentifier("saveTransaction")
                }
                .background(.bar)
            }
            .onAppear(perform: initializePromotions)
            .task { if transaction == nil { amountIsFocused = true } }
            .onChange(of: cardID) { _, _ in
                if transaction == nil, let selectedCard {
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
            .onChange(of: originalTransactionID) { _, _ in refreshCandidates() }
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
            .navigationTitle(transaction == nil ? "添加交易" : "编辑交易")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton()
                }
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
        .protectEdits(snapshot: editSnapshot)
    }

    private var editorStepIndicator: some View {
        HStack(spacing: 8) {
            stepIndicatorItem(number: 1, title: "交易信息", isCurrent: editorStep == 0)
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
            stepIndicatorItem(number: 2, title: "确认促销", isCurrent: editorStep == 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(editorStep + 1) 步，共 2 步：\(editorStep == 0 ? "交易信息" : "确认促销")")
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
                Text("账单币种：\(selectedCard.account.limitCurrencyCode)")
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
                    .keyboardType(.decimalPad)
                    .focused($amountIsFocused)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("交易金额")
                    .accessibilityIdentifier("transactionAmount")
                CurrencyPickerView(selection: $currencyCode, title: "币种")
                    .fixedSize(horizontal: true, vertical: false)
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
            if kind == .refund {
                Picker("原消费", selection: $originalTransactionID) {
                    Text("不关联原消费（可选）").tag(Self.noOriginalTransactionID)
                    ForEach(originalTransactions, id: \.id) { original in
                        Text(transactionLabel(original)).tag(original.id)
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
                }
            }
        }
        if !needsPromotionConfirmation {
            Section {
                Label("本笔不计入活动", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
                Button("手动选择活动") {
                    amountIsFocused = false
                    continueToPromotionConfirmation()
                }
                .disabled(!isAmountPositive)
            }
        }
    }

    @ViewBuilder
    private var promotionConfirmationSections: some View {
        Section("本笔交易") {
            if let selectedCard { Text(cardLabel(selectedCard)).font(.subheadline) }
            Text(CardPilotUI.amountText(CardPilotUI.decimal(amountText) ?? .zero, currencyCode: currencyCode))
                .font(.title2.bold())
                .monospacedDigit()
            LabeledContent(kind == .refund ? "退款日期" : "消费日期", value: CardPilotUI.dateText(CardPilotUI.rawDate(transactionDate)))
            if !merchant.isEmpty { LabeledContent("商户", value: merchant) }
        }
        Section {
            Label(
                selectedPromotionIDs.isEmpty ? "本笔未计入促销" : "已选择 \(selectedPromotionIDs.count) 个促销",
                systemImage: selectedPromotionIDs.isEmpty ? "tag.slash" : "checkmark.circle"
            )
            .foregroundStyle(selectedPromotionIDs.isEmpty ? Color.secondary : Color.accentColor)
            Text("请检查候选活动与计入金额；点击“确认并保存”后才会写入这笔交易。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("确认促销")
        }
        promotionSection
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

    @ViewBuilder
    private var cardSelector: some View {
        if selectableCards.isEmpty {
            Label("请先在“卡片”页添加信用卡", systemImage: "creditcard")
                .foregroundStyle(.secondary)
        } else if let selectedCard {
            Button {
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
            .sheet(isPresented: $showingCardPicker) {
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
        }
    }

    @ViewBuilder
    private var promotionSection: some View {
        Section("促销分配") {
            TextField("搜索其他促销", text: $promotionSearchText)
            if visiblePromotions.isEmpty && candidatePromotions.isEmpty && selectedPromotionIDs.isEmpty && promotionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("本笔未计入促销", systemImage: "tag.slash")
                    .foregroundStyle(.secondary)
                Text("当前卡片和日期没有匹配的活动；仍可搜索全部促销并手动选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if visiblePromotions.isEmpty {
                Text("没有匹配的促销。可修改搜索词，或返回上一步检查卡片和日期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visiblePromotions, id: \.id) { promotion in
                    VStack(alignment: .leading, spacing: 7) {
                        Toggle(isOn: promotionBinding(promotion.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(promotion.title)
                                    .font(.subheadline.weight(.medium))
                                Text(promotionSummary(promotion))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if selectedPromotionIDs.contains(promotion.id) {
                            TextField(
                                "计入金额（\(promotion.progressCurrencyCode)）",
                                text: amountBinding(promotion.id)
                            )
                            .keyboardType(.decimalPad)
                            .padding(.leading, 24)
                            if let warning = qualificationWarning(for: promotion) {
                                Text(warning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(.leading, 24)
                            }
                        }
                        if postingDatePendingPromotions.contains(where: { $0.id == promotion.id }) {
                            Text("需补入账日期，不会自动勾选。")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text("已报名或无需报名、金额符合条件的累计活动会预选。不可叠加的多个活动及逐笔优惠活动，请逐项确认。")
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
        guard kind != .refund,
              let transactionAmount = CardPilotUI.decimal(amountText),
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
        guard let amount = CardPilotUI.decimal(amountText), amount > .zero else { return "" }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency == promotion.progressCurrencyCode else { return "" }
        if kind == .refund { return CardPilotUI.editableAmountText(amount) }
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
        return CardPilotUI.editableAmountText(suggestion)
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

    private func save(allowingOverRefund: Bool = false) {
        guard let card = selectedCard else { errorMessage = "请选择卡片。"; return }
        guard let amount = CardPilotUI.decimal(amountText), amount > .zero else {
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
        let selectedPromotions = promotions.filter { selectedPromotionIDs.contains($0.id) }
        var parsedAmounts: [UUID: Decimal] = [:]
        for promotion in selectedPromotions {
            guard let amount = CardPilotUI.decimal(allocationAmounts[promotion.id] ?? ""), amount > .zero else {
                errorMessage = "活动“\(promotion.title)”的计入金额应为大于 0 的数字。"
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
            lastUsedCardID = card.id.uuidString
            dismiss()
        } catch {
            modelContext.rollback()
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

func promotionsAwaitingPostingDate(
    _ promotions: [Promotion],
    cardID: UUID?,
    hasPostingDate: Bool
) -> [Promotion] {
    guard let cardID, !hasPostingDate else { return [] }
    return promotions.filter {
        $0.archivedAt == nil
            && $0.qualificationDateBasis == .postingDate
            && $0.eligibleCards.contains(where: { $0.id == cardID })
    }
}

func promotionsMatchingSearch(_ promotions: [Promotion], searchText: String) -> [Promotion] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    return promotions.filter { $0.title.localizedCaseInsensitiveContains(query) }
}
