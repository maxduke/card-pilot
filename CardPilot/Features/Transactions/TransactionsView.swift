import SwiftData
import SwiftUI
import UIKit

struct TransactionsView: View {
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @Query private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    private let onAddCard: () -> Void

    init(onAddCard: @escaping () -> Void = {}) {
        self.onAddCard = onAddCard
    }

    var body: some View {
        TransactionListContent(
            transactions: transactions,
            cards: cards,
            promotions: promotions,
            onAddCard: onAddCard
        )
    }
}

private struct TransactionListContent: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.currentDay) private var currentDay
    private let transactions: [Transaction]
    private let cards: [Card]
    private let promotions: [Promotion]

    @State private var isPresentingEditor = false
    private let onAddCard: () -> Void
    @State private var editingTransaction: Transaction?
    @State private var detailTransaction: Transaction?
    @State private var transactionPendingDeletion: Transaction?
    @State private var transactionPendingReversal: Transaction?
    @State private var errorMessage: String?
    @State private var filterCardID: UUID?
    @State private var filterKind: TransactionKind?
    @State private var filterPromotionID: UUID?
    @State private var filterStatus: TransactionStatus?
    @State private var filterDatePeriod: TransactionDatePeriod = .all
    @State private var customDateRange: ClosedRange<LocalDate>?
    @State private var filterCurrencyCode: String?
    @State private var showingFilterSheet = false
    @State private var searchText = ""

    init(
        transactions: [Transaction], cards: [Card], promotions: [Promotion],
        onAddCard: @escaping () -> Void
    ) {
        self.transactions = transactions
        self.cards = cards
        self.promotions = promotions
        self.onAddCard = onAddCard
    }

    var body: some View {
        let filtered = filteredTransactions
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
                                .foregroundStyle(Color(uiColor: .systemBackground))
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
                            .foregroundStyle(Color(uiColor: .systemBackground))
                        }
                    }
                } else if filtered.isEmpty {
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            activeFilterSummary
                        }
                        resultCount(filtered.count)
                        EmptyStateView(
                            title: "没有匹配交易",
                            systemImage: "line.3.horizontal.decrease.circle",
                            message: hasActiveFilters ? "可以调整筛选条件，或点击上方“清除”查看全部交易。" : "可以搜索商户、分类或促销名称。"
                        )
                    }
                } else {
                    let sections = groupedTransactionsByDate(filtered)
                    VStack(spacing: 0) {
                        if hasActiveFilters {
                            activeFilterSummary
                        }
                        resultCount(filtered.count)
                        List {
                            ForEach(sections.indices, id: \.self) { sectionIndex in
                                let section = sections[sectionIndex]
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
                                                    if transactionHasActiveRefunds(transaction) {
                                                        transactionPendingReversal = transaction
                                                    } else {
                                                        transaction.reverse()
                                                        save()
                                                    }
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
                    .accessibilityIdentifier("transactions.filters")
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
            .trackedSheet(isPresented: $isPresentingEditor, onDismiss: { editingTransaction = nil }) {
                TransactionEditorView(
                    transaction: editingTransaction,
                    cards: cards,
                    promotions: promotions
                )
            }
            .trackedSheet(isPresented: Binding(
                get: { detailTransaction != nil },
                set: { if !$0 { detailTransaction = nil } }
            )) {
                if let detailTransaction {
                    TransactionDetailView(
                        transaction: detailTransaction,
                        cards: cards,
                        promotions: promotions
                    )
                }
            }
            .trackedSheet(isPresented: $showingFilterSheet) {
                TransactionFilterSheet(
                    cards: cards,
                    promotions: promotions,
                    currencies: Array(Set(transactions.map(\.currencyCode))).sorted(),
                    today: currentDay.today,
                    cardID: $filterCardID,
                    kind: $filterKind,
                    promotionID: $filterPromotionID,
                    status: $filterStatus,
                    datePeriod: $filterDatePeriod,
                    customDateRange: $customDateRange,
                    currencyCode: $filterCurrencyCode
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
            .confirmationDialog("确认冲正原消费？", isPresented: Binding(
                get: { transactionPendingReversal != nil },
                set: { if !$0 { transactionPendingReversal = nil } }
            ), titleVisibility: .visible) {
                Button("仅冲正原消费", role: .destructive) {
                    transactionPendingReversal?.reverse()
                    save()
                    transactionPendingReversal = nil
                }
                Button("取消", role: .cancel) { transactionPendingReversal = nil }
            } message: {
                Text("这笔消费有关联的有效退款。冲正后原消费不再计入促销，但退款仍会扣减进度，合计可能为负。请根据银行记录单独核对退款；不会自动冲正退款。")
            }
            .searchable(text: $searchText, prompt: "搜索交易")
        }
    }

    private var filteredTransactions: [Transaction] {
        filterTransactions(
            transactions,
            cardID: filterCardID,
            kind: filterKind,
            promotionID: filterPromotionID,
            status: filterStatus,
            searchText: searchText,
            dateRange: dateRange,
            currencyCode: filterCurrencyCode
        )
    }

    private var dateRange: ClosedRange<Int>? {
        filterDatePeriod.range(today: currentDay.today, customRange: customDateRange)
    }

    private func resultCount(_ count: Int) -> some View {
        Text("共 \(count) 笔交易")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .accessibilityIdentifier("transactions.results.count")
    }

    private var activeFilterCount: Int {
        [filterCardID != nil, filterKind != nil, filterPromotionID != nil, filterStatus != nil,
         filterDatePeriod != .all, filterCurrencyCode != nil,
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
                if let dateRange {
                    let label = filterDatePeriod == .custom
                        ? "日期：\(CardPilotUI.dateText(dateRange.lowerBound)) 至 \(CardPilotUI.dateText(dateRange.upperBound))"
                        : "\(filterDatePeriod.title) · \(CardPilotUI.monthKeyText(dateRange.lowerBound / 100))"
                    filterChip(label) {
                        filterDatePeriod = .all
                    }
                    .accessibilityIdentifier("transactions.filters.date.clear")
                }
                if let filterCurrencyCode {
                    filterChip(filterCurrencyCode) { self.filterCurrencyCode = nil }
                        .accessibilityIdentifier("transactions.filters.currency.clear")
                }
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
                Button {
                    clearFilters()
                } label: {
                    Text("清除全部")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("transactions.filters.clear")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(.bar)
    }

    private func filterChip(_ label: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("移除筛选：\(label)")
    }

    private func clearFilters() {
        filterCardID = nil
        filterKind = nil
        filterPromotionID = nil
        filterStatus = nil
        filterDatePeriod = .all
        filterCurrencyCode = nil
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

enum TransactionDatePeriod: String, CaseIterable {
    case all, thisMonth, lastMonth, custom

    var title: String {
        switch self {
        case .all: "全部日期"
        case .thisMonth: "本月"
        case .lastMonth: "上月"
        case .custom: "自定义范围"
        }
    }

    func range(today: LocalDate, customRange: ClosedRange<LocalDate>?) -> ClosedRange<Int>? {
        switch self {
        case .all: return nil
        case .custom:
            if let customRange { return customRange.lowerBound.rawValue...customRange.upperBound.rawValue }
            return (today.monthKey * 100 + 1)...today.rawValue
        case .thisMonth, .lastMonth:
            let monthKey = self == .thisMonth ? today.monthKey
                : (today.month == 1 ? (today.year - 1) * 100 + 12 : today.monthKey - 1)
            // The month before January of year 1 is outside stored dates,
            // so its numeric range matches no supported transaction date.
            let days = monthKey == 12 ? 31 : LocalDate.daysInMonth(year: monthKey / 100, month: monthKey % 100)
            return (monthKey * 100 + 1)...(monthKey * 100 + days)
        }
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
    searchText: String,
    dateRange: ClosedRange<Int>? = nil,
    currencyCode: String? = nil
) -> [Transaction] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return transactions.filter { transaction in
        guard cardID == nil || transaction.card.id == cardID else { return false }
        guard kind == nil || transaction.kind == kind else { return false }
        guard status == nil || transaction.status == status else { return false }
        guard currencyCode == nil || transaction.currencyCode == currencyCode else { return false }
        if let dateRange {
            guard dateRange.contains(transaction.transactionOn) else { return false }
        }
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

struct TransactionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            identity
            amount
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(transactionAccessibilityLabel(transaction))
        .accessibilityHint("查看交易详情")
        .accessibilityIdentifier("transaction.\(transaction.merchant)")
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 12) {
            BankBadge(bank: transaction.card.account.bank)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                    .font(.subheadline.weight(.semibold))
                Text(cardShortLabel(transaction.card))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let tagsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 6))
                tagsLayout {
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
                    } else if transaction.allocations.count > 1 {
                        Text("已计入 \(transaction.allocations.count) 个促销")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var amount: some View {
        Text(signedAmountText(transaction))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(transaction.status == .reversed ? .secondary : .primary)
            .strikethrough(transaction.status == .reversed)
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

func cardLabel(_ card: Card) -> String {
    let name = card.nickname.isEmpty ? card.productName : card.nickname
    return "\(card.account.bank.name) · \(name) · •••• \(card.lastFour) · \(cardNetworkSummary(card.networks))"
}

func cardShortLabel(_ card: Card) -> String {
    let name = card.nickname.isEmpty ? card.productName : card.nickname
    return "\(card.account.bank.name) · \(name) · •••• \(card.lastFour)"
}

func promotionFilterLabel(_ promotion: Promotion) -> String {
    var parts = [promotion.title]
    if let index = promotion.seriesIndex { parts.append("第 \(index + 1) 期") }
    parts.append(CardPilotUI.dateRangeText(start: promotion.startOn, end: promotion.endOn))
    return parts.joined(separator: " · ")
}

func signedAmountText(_ transaction: Transaction) -> String {
    "\(transaction.kind == .refund ? "−" : "")\(CardPilotUI.amountText(transaction.amount, currencyCode: transaction.currencyCode))"
}

func transactionAccessibilityLabel(_ transaction: Transaction) -> String {
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

private struct TransactionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let cards: [Card]
    let promotions: [Promotion]
    let currencies: [String]
    let today: LocalDate
    @Binding var cardID: UUID?
    @Binding var kind: TransactionKind?
    @Binding var promotionID: UUID?
    @Binding var status: TransactionStatus?
    @Binding var datePeriod: TransactionDatePeriod
    @Binding var customDateRange: ClosedRange<LocalDate>?
    @Binding var currencyCode: String?

    private var selectableCurrencies: [String] {
        Array(Set(currencies + [currencyCode].compactMap { $0 })).sorted()
    }

    private var resolvedCustomRange: ClosedRange<LocalDate> {
        customDateRange ?? (try! LocalDate(year: today.year, month: today.month, day: 1))...today
    }

    private var startDate: Binding<Date> {
        Binding(get: { resolvedCustomRange.lowerBound.date(in: CardPilotUI.homeTimeZone) }, set: { value in
            let start = LocalDate(date: value, timeZone: CardPilotUI.homeTimeZone)
            customDateRange = start...max(start, resolvedCustomRange.upperBound)
        })
    }

    private var endDate: Binding<Date> {
        Binding(get: { resolvedCustomRange.upperBound.date(in: CardPilotUI.homeTimeZone) }, set: { value in
            let end = LocalDate(date: value, timeZone: CardPilotUI.homeTimeZone)
            customDateRange = min(resolvedCustomRange.lowerBound, end)...end
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("日期范围", selection: $datePeriod) {
                        ForEach(TransactionDatePeriod.allCases, id: \.self) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("日期范围")
                    .accessibilityIdentifier("transactions.filter.date")
                    .onChange(of: datePeriod) { _, period in
                        if period == .custom && customDateRange == nil { customDateRange = resolvedCustomRange }
                    }
                    if datePeriod == .custom {
                        DatePicker("开始日期", selection: startDate, displayedComponents: .date)
                            .accessibilityIdentifier("transactions.filter.startDate")
                        DatePicker("结束日期", selection: endDate, in: startDate.wrappedValue..., displayedComponents: .date)
                            .accessibilityIdentifier("transactions.filter.endDate")
                    }
                } header: {
                    Text("交易日期")
                } footer: {
                    Text("包含起止两天，按交易日期筛选。")
                }

                Section("币种") {
                    Picker("币种", selection: $currencyCode) {
                        Text("全部币种").tag(nil as String?)
                        ForEach(selectableCurrencies, id: \.self) { code in
                            Text(code).tag(Optional(code))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("币种")
                    .accessibilityIdentifier("transactions.filter.currency")
                }

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
                    .accessibilityIdentifier("transactions.filter.kind")
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
                    .accessibilityIdentifier("transactions.filter.status")
                }
            }
            .environment(\.timeZone, CardPilotUI.homeTimeZone)
            .environment(\.calendar, LocalDate.calendar(timeZone: CardPilotUI.homeTimeZone))
            .navigationTitle("筛选交易")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("清除") {
                        cardID = nil
                        kind = nil
                        promotionID = nil
                        status = nil
                        datePeriod = .all
                        currencyCode = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

func promotionsAwaitingPostingDate(
    _ promotions: [Promotion],
    cardID: UUID?,
    hasPostingDate: Bool,
    transactionOn: Int
) -> [Promotion] {
    guard let cardID, !hasPostingDate else { return [] }
    return promotions.filter {
        $0.archivedAt == nil
            && $0.endOn >= transactionOn
            && $0.qualificationDateBasis == .postingDate
            && $0.eligibleCards.contains(where: { $0.id == cardID })
    }
}

func promotionsMatchingSearch(_ promotions: [Promotion], searchText: String) -> [Promotion] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return [] }
    return promotions.filter { $0.title.localizedCaseInsensitiveContains(query) }
}

func transactionAllocationExceedsAmount(
    transactionAmount: Decimal?, transactionCurrencyCode: String,
    allocationAmount: Decimal?, allocationCurrencyCode: String
) -> Bool {
    guard let transactionAmount, transactionAmount > .zero, let allocationAmount,
          transactionCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == allocationCurrencyCode else {
        return false
    }
    return allocationAmount > transactionAmount
}

func transactionHasActiveRefunds(_ transaction: Transaction) -> Bool {
    transaction.kind == .purchase && transaction.refunds.contains { $0.status == .active }
}

func invalidDraftPromotionIDs(selectedIDs: Set<UUID>, savedCurrencies: [UUID: String],
                              promotions: [Promotion]) -> Set<UUID> {
    Set(selectedIDs.filter { id in
        guard let promotion = promotions.first(where: { $0.id == id }) else { return true }
        return savedCurrencies[id].map { $0 != promotion.progressCurrencyCode } ?? false
    })
}

func suggestedRefundAllocationAmount(
    refundAmount: Decimal, refundCurrencyCode: String, promotion: Promotion,
    original: Transaction?, excludingTransactionID: UUID?
) -> Decimal? {
    guard refundAmount > .zero, refundCurrencyCode == promotion.progressCurrencyCode else { return nil }
    guard let original else { return refundAmount }
    guard original.currencyCode == refundCurrencyCode else { return nil }
    let originalAmount = original.allocations
        .filter { $0.promotion.id == promotion.id }
        .reduce(Decimal.zero) { $0 + $1.qualifyingAmount }
    let refundedAmount = original.refunds
        .filter { $0.status == .active && $0.id != excludingTransactionID }
        .flatMap(\.allocations)
        .filter { $0.promotion.id == promotion.id }
        .reduce(Decimal.zero) { $0 + $1.qualifyingAmount }
    return min(refundAmount, max(.zero, originalAmount - refundedAmount))
}
