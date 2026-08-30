import SwiftData
import SwiftUI

struct CardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query private var accounts: [CreditCardAccount]
    @Query private var cards: [Card]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]

    @State private var editingBank: Bank?
    @State private var editingAccount: CreditCardAccount?
    @State private var editingCard: Card?
    @State private var showingBankEditor = false
    @State private var showingAccountEditor = false
    @State private var showingCardEditor = false
    @State private var showingArchivedBanks = false
    @State private var showingInactiveCards = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if banks.isEmpty {
                    EmptyStateView(
                        title: "还没有银行",
                        systemImage: "building.columns",
                        message: "先添加发卡银行，再录入信用卡账户。"
                    )
                } else {
                    List {
                        ForEach(banks.filter { showingArchivedBanks || $0.archivedAt == nil || !$0.accounts.isEmpty }, id: \.id) { bank in
                            Section {
                                let bankAccounts = accounts.filter { $0.bank.id == bank.id }
                                if bankAccounts.isEmpty {
                                    Text("尚未添加信用卡账户")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(bankAccounts, id: \.id) { account in
                                        AccountRow(
                                            account: account,
                                            onEdit: { editingAccount = account; showingAccountEditor = true },
                                            onDelete: { deleteAccount(account) }
                                        )
                                        ForEach(account.cards.filter { showingInactiveCards || $0.status == .active }.sorted { ($0.nickname.isEmpty ? $0.productName : $0.nickname) < ($1.nickname.isEmpty ? $1.productName : $1.nickname) }, id: \.id) { card in
                                            CardRow(card: card) {
                                                editingCard = card
                                                showingCardEditor = true
                                            } onDelete: {
                                                deleteCard(card)
                                            }
                                            .padding(.leading, 22)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(bank.name)
                                    Spacer()
                                    Button {
                                        editingBank = bank
                                        showingBankEditor = true
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("编辑银行 \(bank.name)")
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingBank = bank
                                    showingBankEditor = true
                                } label: {
                                    Label("编辑银行", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleteBank(bank)
                                } label: {
                                    Label("删除银行", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("卡片")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                        Button {
                            editingAccount = nil
                            showingAccountEditor = true
                        } label: {
                            Label("添加信用卡账户", systemImage: "plus.rectangle")
                        }
                        .disabled(banks.isEmpty)
                        Button {
                            editingCard = nil
                            showingCardEditor = true
                        } label: {
                            Label("添加卡片", systemImage: "creditcard")
                        }
                        .disabled(accounts.isEmpty || networks.isEmpty)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加银行、账户或卡片")
                }
            }
            .sheet(isPresented: $showingBankEditor) {
                BankEditorView(bank: editingBank)
            }
            .sheet(isPresented: $showingAccountEditor) {
                AccountEditorView(account: editingAccount, banks: banks)
            }
            .sheet(isPresented: $showingCardEditor) {
                CardEditorView(card: editingCard, accounts: accounts, networks: networks)
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

    private func save() {
        do {
            try modelContext.save()
        } catch {
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

    private func deleteAccount(_ account: CreditCardAccount) {
        guard account.cards.isEmpty, account.billingCycles.isEmpty else {
            errorMessage = "请先删除该账户下的卡片和账期记录。"
            return
        }
        account.billingRuleVersions.forEach { modelContext.delete($0) }
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
}

private struct AccountRow: View {
    let account: CreditCardAccount
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: account.status == .active ? "rectangle.stack" : "rectangle.stack.badge.minus")
                .foregroundStyle(account.status == .active ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.bank.name)
                    .font(.subheadline.weight(.semibold))
                let rule = account.billingRuleVersions.first { $0.effectiveCycleKey == nil }
                if let rule {
                    Text("账单日每月 \(rule.statementDay) 日 · \(repaymentText(rule))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未设置账务规则")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if account.status == .closed {
                Text("已关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("信用卡账户，\(account.bank.name)")
        .contextMenu {
            Button(action: onEdit) { Label("编辑账户", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("删除账户", systemImage: "trash") }
        }
    }

    private func repaymentText(_ rule: BillingRuleVersion) -> String {
        switch rule.repaymentKind {
        case .fixedDay: return "还款日每月 \(rule.repaymentValue) 日"
        case .daysAfterStatement: return "账单日后 \(rule.repaymentValue) 天还款"
        }
    }
}

private struct CardRow: View {
    let card: Card
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: card.status == .active ? "creditcard.fill" : "creditcard")
                .foregroundStyle(card.status == .active ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.nickname.isEmpty ? card.productName : card.nickname)
                    .font(.subheadline)
                Text("\(card.productName) · \(card.network.displayName) · •••• \(card.lastFour)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if card.status == .inactive {
                Text("停用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("卡片，末四位 \(card.lastFour)")
        .contextMenu {
            Button(action: onEdit) { Label("编辑卡片", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("删除卡片", systemImage: "trash") }
        }
    }
}

private struct BankEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let bank: Bank?
    @State private var name: String
    @State private var notes: String
    @State private var archived: Bool
    @State private var errorMessage: String?

    init(bank: Bank?) {
        self.bank = bank
        _name = State(initialValue: bank?.name ?? "")
        _notes = State(initialValue: bank?.notes ?? "")
        _archived = State(initialValue: bank?.archivedAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("银行") {
                    TextField("名称", text: $name)
                        .accessibilityLabel("银行名称")
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                    if bank != nil {
                        Toggle("归档", isOn: $archived)
                    }
                }
                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .navigationTitle(bank == nil ? "添加银行" : "编辑银行")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "银行名称不能为空。"; return }
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
            errorMessage = "银行未保存：\(error.localizedDescription)"
        }
    }
}

private struct AccountEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let account: CreditCardAccount?
    let banks: [Bank]

    @State private var bankID: UUID
    @State private var limitText: String
    @State private var currencyCode: String
    @State private var status: CreditCardAccountStatus
    @State private var closedDate: Date
    @State private var statementDay: Int
    @State private var repaymentKind: RepaymentRuleKind
    @State private var repaymentValue: Int
    @State private var effectiveCycleKeyText: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(account: CreditCardAccount?, banks: [Bank]) {
        self.account = account
        self.banks = banks
        let rule = account?.billingRuleVersions.max {
            ($0.effectiveCycleKey ?? Int.min) < ($1.effectiveCycleKey ?? Int.min)
        }
        _bankID = State(initialValue: account?.bank.id ?? banks.first?.id ?? UUID())
        _limitText = State(initialValue: account.flatMap { $0.creditLimit.map { CardPilotUI.amountText($0) } } ?? "")
        _currencyCode = State(initialValue: account?.limitCurrencyCode ?? "CNY")
        _status = State(initialValue: account?.status ?? .active)
        _closedDate = State(initialValue: account.flatMap { $0.closedOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _statementDay = State(initialValue: rule?.statementDay ?? 1)
        _repaymentKind = State(initialValue: rule?.repaymentKind ?? .fixedDay)
        _repaymentValue = State(initialValue: rule?.repaymentValue ?? 1)
        _effectiveCycleKeyText = State(initialValue: String(CardPilotUI.localDate(from: Date()).monthKey))
        _notes = State(initialValue: account?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    Picker("银行", selection: $bankID) {
                        ForEach(banks.filter { $0.archivedAt == nil || $0.id == account?.bank.id }, id: \.id) { bank in
                            Text(bank.name).tag(bank.id)
                        }
                    }
                    TextField("信用额度（可选）", text: $limitText)
                        .keyboardType(.decimalPad)
                    TextField("额度币种", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                    Picker("状态", selection: $status) {
                        Text("使用中").tag(CreditCardAccountStatus.active)
                        Text("已关闭").tag(CreditCardAccountStatus.closed)
                    }
                    if status == .closed {
                        DatePicker("关闭日期", selection: $closedDate, displayedComponents: .date)
                    }
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                }

                Section("账务规则") {
                    Stepper("账单日：每月 \(statementDay) 日", value: $statementDay, in: 1...31)
                    Picker("还款规则", selection: $repaymentKind) {
                        Text("固定日").tag(RepaymentRuleKind.fixedDay)
                        Text("账单日后 N 天").tag(RepaymentRuleKind.daysAfterStatement)
                    }
                    Stepper(
                        repaymentKind == .fixedDay ? "还款日：每月 \(repaymentValue) 日" : "天数：\(repaymentValue)",
                        value: $repaymentValue,
                        in: repaymentKind == .fixedDay ? 1...31 : 1...90
                    )
                    Text("不存在的日期会按当月最后一天计算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if account != nil {
                        TextField("规则变更生效账期（YYYYMM）", text: $effectiveCycleKeyText)
                            .keyboardType(.numberPad)
                        Text("修改规则会新增版本，不会改写历史账期。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .navigationTitle(account == nil ? "添加信用卡账户" : "编辑信用卡账户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
    }

    private func save() {
        guard let bank = banks.first(where: { $0.id == bankID }) else {
            errorMessage = "请选择银行。"
            return
        }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidCurrencyCode(normalizedCurrency) else {
            errorMessage = "额度币种应为 3 位大写字母。"
            return
        }
        let limit = limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : CardPilotUI.decimal(limitText)
        guard limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || limit != nil else {
            errorMessage = "信用额度格式不正确。"
            return
        }
        let target = account ?? CreditCardAccount(bank: bank, creditLimit: limit, limitCurrencyCode: normalizedCurrency, status: status, closedOn: status == .closed ? CardPilotUI.rawDate(closedDate) : nil, notes: notes)
        target.bank = bank
        target.creditLimit = limit
        target.limitCurrencyCode = normalizedCurrency
        target.status = status
        target.closedOn = status == .closed ? CardPilotUI.rawDate(closedDate) : nil
        target.notes = notes

        if account == nil {
            modelContext.insert(target)
            let newRule = BillingRuleVersion(account: target, statementDay: statementDay, repaymentKind: repaymentKind, repaymentValue: repaymentValue)
            target.billingRuleVersions.append(newRule)
            modelContext.insert(newRule)
        } else {
            let latestRule = target.billingRuleVersions.max {
                ($0.effectiveCycleKey ?? Int.min) < ($1.effectiveCycleKey ?? Int.min)
            }
            if latestRule?.statementDay != statementDay
                || latestRule?.repaymentKind != repaymentKind
                || latestRule?.repaymentValue != repaymentValue {
                guard let effectiveCycleKey = Int(effectiveCycleKeyText),
                      LocalDate.isValidMonthKey(effectiveCycleKey) else {
                    errorMessage = "生效账期应为有效的 YYYYMM。"
                    return
                }
                guard !target.billingRuleVersions.contains(where: { $0.effectiveCycleKey == effectiveCycleKey }) else {
                    errorMessage = "该生效账期已有规则版本。"
                    return
                }
                let newRule = BillingRuleVersion(
                    account: target,
                    effectiveCycleKey: effectiveCycleKey,
                    statementDay: statementDay,
                    repaymentKind: repaymentKind,
                    repaymentValue: repaymentValue
                )
                target.billingRuleVersions.append(newRule)
                modelContext.insert(newRule)
            }
        }
        do {
            try target.validate()
            try target.validateBillingConfiguration()
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "账户未保存：\(error.localizedDescription)"
        }
    }
}

private struct CardEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let card: Card?
    let accounts: [CreditCardAccount]
    let networks: [CardNetwork]

    @State private var accountID: UUID
    @State private var networkID: UUID
    @State private var productName: String
    @State private var nickname: String
    @State private var lastFour: String
    @State private var status: CardStatus
    @State private var notes: String
    @State private var errorMessage: String?

    init(card: Card?, accounts: [CreditCardAccount], networks: [CardNetwork]) {
        self.card = card
        self.accounts = accounts
        self.networks = networks
        _accountID = State(initialValue: card?.account.id ?? accounts.first?.id ?? UUID())
        _networkID = State(initialValue: card?.network.id ?? networks.first?.id ?? UUID())
        _productName = State(initialValue: card?.productName ?? "")
        _nickname = State(initialValue: card?.nickname ?? "")
        _lastFour = State(initialValue: card?.lastFour ?? "")
        _status = State(initialValue: card?.status ?? .active)
        _notes = State(initialValue: card?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("卡片") {
                    Picker("信用卡账户", selection: $accountID) {
                        ForEach(accounts, id: \.id) { account in
                            Text("\(account.bank.name) · 账户").tag(account.id)
                        }
                    }
                    Picker("卡组织", selection: $networkID) {
                        ForEach(networks, id: \.id) { network in
                            Text(network.displayName).tag(network.id)
                        }
                    }
                    TextField("卡产品名称", text: $productName)
                    TextField("昵称（可选）", text: $nickname)
                    TextField("末四位", text: $lastFour)
                        .keyboardType(.numberPad)
                        .textContentType(.none)
                    Picker("状态", selection: $status) {
                        Text("使用中").tag(CardStatus.active)
                        Text("停用").tag(CardStatus.inactive)
                    }
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                }
                Text("不要录入完整卡号或 CVV。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    InlineErrorView(message: errorMessage)
                }
            }
            .navigationTitle(card == nil ? "添加卡片" : "编辑卡片")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }),
              let network = networks.first(where: { $0.id == networkID }) else {
            errorMessage = "请选择账户和卡组织。"
            return
        }
        let target = card ?? Card(account: account, productName: productName, network: network, lastFour: lastFour, status: status, notes: notes)
        target.account = account
        target.network = network
        target.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nickname = nickname
        target.lastFour = lastFour
        target.status = status
        target.notes = notes
        do {
            try target.validate()
            if card == nil { modelContext.insert(target) }
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "卡片未保存：\(error.localizedDescription)"
        }
    }
}
