import SwiftData
import SwiftUI
import UIKit

struct CardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query private var accounts: [CreditCardAccount]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]

    @State private var editingBank: Bank?
    @State private var editingAccount: CreditCardAccount?
    @State private var editingCard: Card?
    @State private var showingBankEditor = false
    @State private var showingAccountEditor = false
    @State private var showingCardEditor = false
    @Binding private var showingCardOnboarding: Bool
    @State private var showingArchivedBanks = false
    @State private var showingInactiveCards = false
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var accountPendingDeletion: CreditCardAccount?
    @State private var bankPendingDeletion: Bank?
    @State private var cardPendingDeletion: Card?

    init(showingCardOnboarding: Binding<Bool> = .constant(false)) {
        _showingCardOnboarding = showingCardOnboarding
    }

    var body: some View {
        NavigationStack {
            Group {
                if banks.isEmpty {
                    ContentUnavailableView {
                        Label("还没有信用卡", systemImage: "creditcard.fill")
                    } description: {
                        Text("添加一张卡，几步完成银行、账户和账务日设置。")
                    } actions: {
                        Button("添加信用卡", systemImage: "plus") { showingCardOnboarding = true }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                    }
                } else if visibleBanks.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(visibleBanks, id: \.id) { bank in
                            Section {
                                let bankAccounts = bankAccounts(for: bank)
                                if bankAccounts.isEmpty {
                                    Text("尚未添加信用卡账户")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(bankAccounts, id: \.id) { account in
                                        NavigationLink {
                                            AccountDetailView(account: account)
                                        } label: {
                                            AccountRow(
                                                account: account,
                                                onEdit: { editingAccount = account; showingAccountEditor = true },
                                                onDelete: { requestDeleteAccount(account) }
                                            )
                                        }
                                        ForEach(visibleCards(for: account), id: \.id) { card in
                                            NavigationLink {
                                                CardDetailView(card: card)
                                            } label: {
                                                CardRow(card: card)
                                            }
                                            .contextMenu {
                                                Button {
                                                    editingCard = card
                                                    showingCardEditor = true
                                                } label: {
                                                    Label("编辑卡片", systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    requestDeleteCard(card)
                                                } label: {
                                                    Label("删除卡片", systemImage: "trash")
                                                }
                                            }
                                            .accessibilityIdentifier("card.\(card.productName)")
                                            .padding(.leading, 22)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    BankBadge(bank: bank)
                                    Text(bank.name)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if bank.archivedAt != nil {
                                        Text("已归档")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        editingBank = bank
                                        showingBankEditor = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("编辑银行 \(bank.name)")
                                }
                                .contextMenu {
                                    Button {
                                        editingBank = bank
                                        showingBankEditor = true
                                    } label: {
                                        Label("编辑银行", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        requestDeleteBank(bank)
                                    } label: {
                                        Label("删除银行", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $query, prompt: "搜索银行、账户、卡片或末四位")
            .navigationTitle("卡片")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingCardOnboarding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加信用卡")

                    Menu {
                        Button(showingArchivedBanks ? "隐藏已归档银行" : "显示已归档银行") {
                            showingArchivedBanks.toggle()
                        }
                        Button(showingInactiveCards ? "隐藏停用卡" : "显示停用卡") {
                            showingInactiveCards.toggle()
                        }
                        Button {
                            editingBank = nil
                            showingBankEditor = true
                        } label: {
                            Label("添加银行", systemImage: "building.columns")
                        }
                    } label: {
                        Label("卡片与银行管理", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
            }
            .trackedSheet(isPresented: $showingBankEditor) {
                BankEditorView(bank: editingBank)
            }
            .trackedSheet(isPresented: $showingAccountEditor) {
                AccountEditorView(account: editingAccount, banks: banks)
            }
            .trackedSheet(isPresented: $showingCardEditor) {
                CardEditorView(card: editingCard, accounts: accounts, networks: networks)
            }
            .trackedSheet(isPresented: $showingCardOnboarding) {
                CardOnboardingView(banks: banks, accounts: accounts, networks: networks)
            }
            .confirmationDialog("确认删除账户？", isPresented: accountDeletePresented) {
                Button("永久删除", role: .destructive) {
                    if let accountPendingDeletion {
                        deleteAccount(accountPendingDeletion)
                    }
                    accountPendingDeletion = nil
                }
                Button("取消", role: .cancel) { accountPendingDeletion = nil }
            } message: {
                Text("将永久删除该账户的账务规则和账期记录，此操作无法撤销。")
            }
            .confirmationDialog("确认删除银行？", isPresented: bankDeletePresented) {
                Button("永久删除", role: .destructive) {
                    if let bankPendingDeletion { deleteBank(bankPendingDeletion) }
                    bankPendingDeletion = nil
                }
                Button("取消", role: .cancel) { bankPendingDeletion = nil }
            } message: {
                Text("将永久删除这个未被使用的银行，此操作无法撤销。")
            }
            .confirmationDialog("确认删除卡片？", isPresented: cardDeletePresented) {
                Button("永久删除", role: .destructive) {
                    if let cardPendingDeletion { deleteCard(cardPendingDeletion) }
                    cardPendingDeletion = nil
                }
                Button("取消", role: .cancel) { cardPendingDeletion = nil }
            } message: {
                Text("将永久删除这张未被使用的卡片，此操作无法撤销。")
            }
            .alert("无法完成操作", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var accountDeletePresented: Binding<Bool> {
        Binding(
            get: { accountPendingDeletion != nil },
            set: { if !$0 { accountPendingDeletion = nil } }
        )
    }

    private var bankDeletePresented: Binding<Bool> {
        Binding(get: { bankPendingDeletion != nil }, set: { if !$0 { bankPendingDeletion = nil } })
    }

    private var cardDeletePresented: Binding<Bool> {
        Binding(get: { cardPendingDeletion != nil }, set: { if !$0 { cardPendingDeletion = nil } })
    }

    private var visibleBanks: [Bank] {
        banks.filter { bank in
            (showingArchivedBanks || bank.archivedAt == nil || !bank.accounts.isEmpty)
                && (normalizedQuery.isEmpty || bank.name.localizedCaseInsensitiveContains(normalizedQuery)
                    || !bankAccounts(for: bank).isEmpty)
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bankAccounts(for bank: Bank) -> [CreditCardAccount] {
        let bankAccounts = accounts.filter { $0.bank.id == bank.id }
        guard !normalizedQuery.isEmpty,
              !bank.name.localizedCaseInsensitiveContains(normalizedQuery) else { return bankAccounts }
        return bankAccounts.filter { account in
            account.customName?.localizedCaseInsensitiveContains(normalizedQuery) == true
                || account.notes.localizedCaseInsensitiveContains(normalizedQuery)
                || account.cards.contains { card in
                    (showingInactiveCards || card.status == .active) && cardMatchesQuery(card)
                }
        }
    }

    private func visibleCards(for account: CreditCardAccount) -> [Card] {
        account.cards.filter { card in
            (showingInactiveCards || card.status == .active)
                && (normalizedQuery.isEmpty
                    || account.bank.name.localizedCaseInsensitiveContains(normalizedQuery)
                    || account.customName?.localizedCaseInsensitiveContains(normalizedQuery) == true
                    || account.notes.localizedCaseInsensitiveContains(normalizedQuery)
                    || cardMatchesQuery(card))
        }.sorted { ($0.nickname.isEmpty ? $0.productName : $0.nickname) < ($1.nickname.isEmpty ? $1.productName : $1.nickname) }
    }

    private func cardMatchesQuery(_ card: Card) -> Bool {
        card.productName.localizedCaseInsensitiveContains(normalizedQuery)
            || card.nickname.localizedCaseInsensitiveContains(normalizedQuery)
            || card.lastFour.contains(normalizedQuery)
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            errorMessage = "数据未保存：\(error.localizedDescription)"
        }
    }

    private func deleteBank(_ bank: Bank) {
        guard bank.accounts.isEmpty, bank.organizedPromotions.isEmpty else {
            errorMessage = "该银行仍被账户或促销主办方引用，不能删除。"
            return
        }
        modelContext.delete(bank)
        save()
    }

    private func requestDeleteBank(_ bank: Bank) {
        guard bank.accounts.isEmpty, bank.organizedPromotions.isEmpty else {
            errorMessage = "该银行仍被账户或促销主办方引用，不能删除。"
            return
        }
        bankPendingDeletion = bank
    }

    private func requestDeleteAccount(_ account: CreditCardAccount) {
        guard account.cards.isEmpty else {
            errorMessage = "请先删除该账户下的卡片。"
            return
        }
        accountPendingDeletion = account
    }

    private func deleteAccount(_ account: CreditCardAccount) {
        guard account.cards.isEmpty else {
            errorMessage = "请先删除该账户下的卡片。"
            return
        }
        modelContext.delete(account)
        save()
    }

    private func deleteCard(_ card: Card) {
        guard card.transactions.isEmpty, card.eligiblePromotions.isEmpty else {
            errorMessage = "该卡仍被交易或促销适用卡引用，不能删除。"
            return
        }
        modelContext.delete(card)
        save()
    }

    private func requestDeleteCard(_ card: Card) {
        guard card.transactions.isEmpty, card.eligiblePromotions.isEmpty else {
            errorMessage = "该卡仍被交易或促销适用卡引用，不能删除。"
            return
        }
        cardPendingDeletion = card
    }
}

private struct AccountRow: View {
    @Environment(\.currentDay) private var currentDay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let account: CreditCardAccount
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        layout {
            Image(systemName: account.status == .active ? "rectangle.stack" : "rectangle.stack.badge.minus")
                .foregroundStyle(account.status == .active ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(accountTitle)
                    .font(.subheadline.weight(.semibold))
                Text(accountRelationshipText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            if account.status == .closed {
                Text("已关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accountAccessibilityLabel)
        .accessibilityHint("查看账户详情")
        .contextMenu {
            Button(action: onEdit) { Label("编辑账户", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("删除账户", systemImage: "trash") }
        }
    }

    private var accountTitle: String {
        if account.customName != nil { return CardPilotUI.accountName(account) }
        let lastFours = account.cards.sorted { $0.lastFour < $1.lastFour }.prefix(2).map { "•••• \($0.lastFour)" }
        return lastFours.isEmpty ? "信用卡账户" : "账户 · \(lastFours.joined(separator: " / "))"
    }

    private var accountRelationshipText: String {
        switch account.cards.count {
        case 0: return "尚未添加卡片"
        case 1: return "独立账单账户"
        default: return "\(account.cards.count) 张卡共用账单"
        }
    }

    private var accountAccessibilityLabel: String {
        CardPilotUI.accountAccessibilityLabel(account, summary: billingSummary)
    }

    private var billingSummary: CardAccountBillingSummary {
        accountBillingSummary(account, today: currentDay.today)
    }
}

private struct CardRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: Card

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
        layout {
            Image(systemName: card.status == .active ? "creditcard.fill" : "creditcard")
                .foregroundStyle(card.status == .active ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.nickname.isEmpty ? card.productName : card.nickname)
                    .font(.subheadline)
                HStack(spacing: 5) {
                    CardNetworksBadges(networks: card.networks)
                    Text("•••• \(card.lastFour)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let nextRepaymentDate = billingSummary.nextRepaymentDate {
                    Text("\(billingSummary.nextRepaymentStatus == .overdue ? "已逾期" : CardPilotUI.relativeDateText(nextRepaymentDate, today: today))还款 · \(CardPilotUI.shortDateText(nextRepaymentDate, relativeTo: today))")
                        .font(.caption)
                        .foregroundStyle(billingSummary.nextRepaymentStatus == .overdue ? .orange : .secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            if card.status == .inactive {
                Text("停用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("查看卡片详情")
    }

    @Environment(\.currentDay) private var currentDay
    private var today: LocalDate { currentDay.today }

    private var billingSummary: CardAccountBillingSummary {
        accountBillingSummary(card.account, today: today)
    }

    private var cardAccessibilityLabel: String {
        var parts = [card.account.bank.name, card.nickname.isEmpty ? card.productName : card.nickname,
                     cardNetworkSummary(card.networks), "末四位 \(card.lastFour)"]
        if card.status == .inactive { parts.append("已停用") }
        if let date = billingSummary.nextRepaymentDate {
            parts.append("\(billingSummary.nextRepaymentStatus == .overdue ? "逾期还款" : "下次还款") \(CardPilotUI.dateText(date))")
        }
        return parts.joined(separator: "，")
    }
}

private struct BankEditorView: View {
    private enum Field: Hashable {
        case name
        case notes
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let bank: Bank?
    @State private var name: String
    @State private var notes: String
    @State private var archived: Bool
    @State private var errorMessage: String?
    @State private var showingValidationErrors = false
    @FocusState private var focusedField: Field?

    init(bank: Bank?) {
        self.bank = bank
        _name = State(initialValue: bank?.name ?? "")
        _notes = State(initialValue: bank?.notes ?? "")
        _archived = State(initialValue: bank?.archivedAt != nil)
    }

    private var editSnapshot: String {
        editorSnapshot(name, notes, archived)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section("银行") {
                        TextField("名称", text: $name)
                            .accessibilityLabel("银行名称")
                            .accessibilityIdentifier("bank.name")
                            .focused($focusedField, equals: .name)
                            .id(Field.name)
                        if showingValidationErrors, let message = nameValidationMessage {
                            InlineErrorView(message: message)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("bank.name.error")
                        }
                        TextField("备注（可选）", text: $notes, axis: .vertical)
                            .accessibilityIdentifier("bank.notes")
                            .focused($focusedField, equals: .notes)
                        if bank != nil {
                            Toggle("归档", isOn: $archived)
                        }
                    }
                    if let errorMessage {
                        InlineErrorView(message: errorMessage)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .accessibilityIdentifier("bank.editor.form")
                .navigationTitle(bank == nil ? "添加银行" : "编辑银行")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save(using: scrollProxy) }
                    }
                }
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var nameValidationMessage: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "银行名称不能为空。" : nil
    }

    private func save(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        showingValidationErrors = true
        guard nameValidationMessage == nil else {
            Task { @MainActor in
                await Task.yield()
                guard nameValidationMessage != nil else { return }
                scrollProxy.scrollTo(Field.name, anchor: .top)
            }
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = bank ?? Bank(name: trimmed, notes: notes)
        target.name = trimmed
        target.notes = notes
        target.archivedAt = archived ? (target.archivedAt ?? Date()) : nil
        do {
            try target.validate()
            if bank == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "银行未保存：\(error.localizedDescription)"
        }
    }
}
