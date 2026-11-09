import SwiftData
import SwiftUI

struct AllocationEditorView: View {
    private enum Field: Hashable { case search, amount }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let promotion: Promotion
    let allocation: PromotionAllocation?
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]

    @State private var transactionID: UUID
    @State private var amountText: String
    @State private var transactionSearchText = ""
    @State private var showingTransactionChoices = false
    @State private var didInitialize = false
    @State private var errorMessage: String?
    @State private var overRefundWarningMessage: String?
    @State private var showingAmountError = false
    @FocusState private var focusedField: Field?

    init(promotion: Promotion, allocation: PromotionAllocation?) {
        self.promotion = promotion
        self.allocation = allocation
        _transactionID = State(initialValue: allocation?.transaction.id ?? UUID())
        _amountText = State(initialValue: allocation.map { CardPilotUI.editableAmountText($0.qualifyingAmount) } ?? "")
    }

    private func filteredTransactions(in availableTransactions: [Transaction]) -> [Transaction] {
        let query = transactionSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return availableTransactions }
        return availableTransactions.filter { transaction in
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
        let availableTransactions = PromotionAllocationSelection.availableTransactions(transactions, for: promotion, editing: allocation)
        let matches = filteredTransactions(in: availableTransactions)
        NavigationStack {
            ScrollViewReader { scrollProxy in
                editorForm(availableTransactions: availableTransactions, matches: matches)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                focusedField = nil
                                errorMessage = nil
                                showingAmountError = true
                                if positiveAmount == nil {
                                    Task { @MainActor in
                                        await Task.yield()
                                        guard showingAmountError, positiveAmount == nil else { return }
                                        scrollProxy.scrollTo(Field.amount, anchor: .top)
                                    }
                                } else {
                                    save()
                                }
                            }
                            .disabled(selectedTransaction == nil)
                            .accessibilityIdentifier("allocation.editor.save")
                        }
                        if focusedField == .amount {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("收起键盘") { focusedField = nil }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .accessibilityIdentifier("allocation.editor.keyboard.dismiss")
                            }
                        }
                    }
            }
            .onAppear {
                guard !didInitialize else { return }
                setInitialAmount()
                showingTransactionChoices = selectedTransaction == nil
                didInitialize = true
            }
            .onChange(of: transactionID) { _, _ in setInitialAmountIfBlank() }
            .onChange(of: transactionSearchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    showingTransactionChoices = true
                }
            }
            .navigationTitle(allocation == nil ? "添加促销分配" : "编辑促销分配")
            .alert("退款分配超出可退范围", isPresented: overRefundWarningPresented) {
                Button("取消", role: .cancel) {}
                Button("仍然保存", role: .destructive) { save(allowingOverRefund: true) }
            } message: {
                Text(overRefundWarningMessage ?? "")
            }
        }
        .protectEdits(snapshot: editSnapshot, isReady: didInitialize)
    }

    private func editorForm(availableTransactions: [Transaction], matches: [Transaction]) -> some View {
        Form {
            transactionSection(availableTransactions: availableTransactions, matches: matches)
            if let errorMessage {
                InlineErrorView(message: errorMessage)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("allocation.editor.form")
    }

    private func transactionSection(availableTransactions: [Transaction], matches: [Transaction]) -> some View {
        Section("交易") {
            if transactions.isEmpty {
                Text("请先添加交易。")
                    .foregroundStyle(.secondary)
            } else {
                if let selectedTransaction {
                    selectedTransactionRow(selectedTransaction)
                } else {
                    Text(availableTransactions.isEmpty
                         ? "已有交易均已计入本活动。请返回编辑现有分配，或记录新交易。"
                         : "没有可自动推荐的交易，请按活动条款手动选择。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if allocation == nil {
                    DisclosureGroup(isExpanded: $showingTransactionChoices) {
                        TextField("搜索商户、日期、卡片或末四位", text: $transactionSearchText)
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .search)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                        if matches.isEmpty {
                            Text("没有匹配的交易。")
                                .foregroundStyle(.secondary)
                        } else {
                            transactionChoices(matches.filter { PromotionCalculator.includes($0, in: promotion) }, title: "推荐交易")
                            transactionChoices(matches.filter { !PromotionCalculator.includes($0, in: promotion) }, title: "其他交易（手动核对）")
                        }
                    } label: {
                        Label("\(selectedTransaction == nil ? "选择交易" : "更换交易")（\(matches.count) 笔）", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("allocation.editor.transactions")
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
            VStack(alignment: .leading, spacing: 7) {
                Text("计入活动的金额（\(promotion.progressCurrencyCode)）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("金额", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .amount)
                    .accessibilityLabel("计入活动的金额（\(promotion.progressCurrencyCode)）")
                    .accessibilityIdentifier("allocation.editor.amount")
                if showingAmountError && positiveAmount == nil {
                    InlineErrorView(message: "计入金额应为大于 0 的数字。")
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("allocation.editor.amountError")
                }
            }
            .id(Field.amount)
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

    @ViewBuilder
    private func transactionChoices(_ transactions: [Transaction], title: String) -> some View {
        if !transactions.isEmpty {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(transactions, id: \.id) { transaction in
                Button {
                    focusedField = nil
                    transactionID = transaction.id
                    showingTransactionChoices = false
                } label: {
                    transactionRow(transaction)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("allocation.editor.transaction.\(transaction.id)")
            }
        }
    }

    private var positiveAmount: Decimal? {
        guard let amount = CardPilotUI.decimal(amountText), amount > .zero else { return nil }
        return amount
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
        let recommended = PromotionCalculator.includes(transaction, in: promotion)
        return HStack(spacing: 10) {
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
                Text(recommended ? "推荐" : "手动")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(recommended ? Color.accentColor : Color.orange)
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
        let transaction = selectedTransaction ?? PromotionAllocationSelection.initialTransaction(
            in: transactions, for: promotion, editing: allocation
        )
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
        showingAmountError = false
        amountText = ""
        setInitialAmount()
    }

    private func save(allowingOverRefund: Bool = false) {
        errorMessage = nil
        guard let transaction = selectedTransaction else { errorMessage = "请选择交易。"; return }
        guard let amount = positiveAmount else {
            showingAmountError = true
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
        do {
            try PromotionAllocationActions.save(amount, transaction: transaction, promotion: promotion,
                                                allocation: allocation, context: modelContext)
            dismiss()
        } catch {
            errorMessage = "分配未保存：\(error.localizedDescription)"
        }
    }
}
