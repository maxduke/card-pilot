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
    @State private var accountPendingDeletion: CreditCardAccount?

    var body: some View {
        NavigationStack {
            Group {
                if visibleBanks.isEmpty {
                    EmptyStateView(
                        title: "还没有银行",
                        systemImage: "building.columns",
                        message: "先添加发卡银行，再录入信用卡账户。"
                    )
                } else {
                    List {
                        ForEach(visibleBanks, id: \.id) { bank in
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
                                            onDelete: { requestDeleteAccount(account) }
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
                        .disabled(selectableAccountBanks(banks, currentBankID: nil).isEmpty)
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

    private var visibleBanks: [Bank] {
        banks.filter { showingArchivedBanks || $0.archivedAt == nil || !$0.accounts.isEmpty }
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
                if let creditLimit = account.creditLimit {
                    Text("额度 \(CardPilotUI.amountText(creditLimit, currencyCode: account.limitCurrencyCode))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let rule = displayedRule
                if let rule {
                    Text("账单日每月 \(rule.statementDay) 日 · \(repaymentText(rule))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未设置账务规则")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                let summary = billingSummary
                if let nextStatementDate = summary.nextStatementDate {
                    Text("下次账单 \(CardPilotUI.dateText(nextStatementDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let nextRepaymentDate = summary.nextRepaymentDate {
                    Text("\(summary.nextRepaymentStatus == .overdue ? "逾期还款" : "下次还款") \(CardPilotUI.dateText(nextRepaymentDate))")
                        .font(.caption)
                        .foregroundStyle(summary.nextRepaymentStatus == .overdue ? .orange : .secondary)
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

    private var displayedRule: BillingRuleVersion? {
        let currentCycleKey = CardPilotUI.localDate(from: Date()).monthKey
        let inputs = account.billingRuleVersions.map {
            BillingRuleInput(
                effectiveCycleKey: $0.effectiveCycleKey,
                statementDay: $0.statementDay,
                repaymentKind: $0.repaymentKind,
                repaymentValue: $0.repaymentValue
            )
        }
        guard let selected = BillingCalculator.applicableRule(from: inputs, forCycleKey: currentCycleKey) else {
            return nil
        }
        return account.billingRuleVersions.first { $0.effectiveCycleKey == selected.effectiveCycleKey }
    }

    private var billingSummary: CardAccountBillingSummary {
        CardAccountBillingSummaryCalculator.calculate(
            status: account.status,
            closedOn: account.closedOn.flatMap { try? LocalDate(rawValue: $0) },
            trackingStartCycleKey: account.trackingStartCycleKey,
            rules: account.billingRuleVersions.map {
                BillingRuleInput(
                    effectiveCycleKey: $0.effectiveCycleKey,
                    statementDay: $0.statementDay,
                    repaymentKind: $0.repaymentKind,
                    repaymentValue: $0.repaymentValue
                )
            },
            overrides: cycleOverrides,
            today: CardPilotUI.localDate(from: Date()),
            timeZone: CardPilotUI.homeTimeZone
        )
    }

    private var cycleOverrides: [Int: BillingCycleOverride] {
        account.billingCycles.reduce(into: [Int: BillingCycleOverride]()) { result, record in
            guard result[record.cycleKey] == nil else { return }
            result[record.cycleKey] = BillingCycleOverride(
                statementDate: record.statementDateOverride.flatMap { try? LocalDate(rawValue: $0) },
                repaymentDate: record.repaymentDateOverride.flatMap { try? LocalDate(rawValue: $0) },
                repaidAt: record.repaidAt
            )
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
            modelContext.rollback()
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
    @State private var overrideCycleKeyText: String
    @State private var hasStatementOverride: Bool
    @State private var statementOverrideDate: Date
    @State private var hasRepaymentOverride: Bool
    @State private var repaymentOverrideDate: Date
    @State private var selectedCycleIsRepaid: Bool
    @State private var notes: String
    @State private var errorMessage: String?

    init(account: CreditCardAccount?, banks: [Bank]) {
        self.account = account
        self.banks = banks
        let rule = account?.billingRuleVersions.max {
            ($0.effectiveCycleKey ?? Int.min) < ($1.effectiveCycleKey ?? Int.min)
        }
        let availableBanks = selectableAccountBanks(banks, currentBankID: account?.bank.id)
        _bankID = State(initialValue: account?.bank.id ?? availableBanks.first?.id ?? UUID())
        _limitText = State(initialValue: account.flatMap { $0.creditLimit.map { CardPilotUI.editableAmountText($0) } } ?? "")
        _currencyCode = State(initialValue: account?.limitCurrencyCode ?? "CNY")
        _status = State(initialValue: account?.status ?? .active)
        _closedDate = State(initialValue: account.flatMap { $0.closedOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _statementDay = State(initialValue: rule?.statementDay ?? 1)
        _repaymentKind = State(initialValue: rule?.repaymentKind ?? .fixedDay)
        _repaymentValue = State(initialValue: rule?.repaymentValue ?? 1)
        let currentDate = CardPilotUI.localDate(from: Date())
        let currentRecord = account?.billingCycles.first { $0.cycleKey == currentDate.monthKey }
        _effectiveCycleKeyText = State(initialValue: String(currentDate.addingMonths(1, timeZone: CardPilotUI.homeTimeZone).monthKey))
        _overrideCycleKeyText = State(initialValue: String(currentDate.monthKey))
        _hasStatementOverride = State(initialValue: currentRecord?.statementDateOverride != nil)
        _statementOverrideDate = State(initialValue: currentRecord?.statementDateOverride.flatMap {
            try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone)
        } ?? currentDate.date(in: CardPilotUI.homeTimeZone))
        _hasRepaymentOverride = State(initialValue: currentRecord?.repaymentDateOverride != nil)
        _repaymentOverrideDate = State(initialValue: currentRecord?.repaymentDateOverride.flatMap {
            try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone)
        } ?? currentDate.date(in: CardPilotUI.homeTimeZone))
        _selectedCycleIsRepaid = State(initialValue: currentRecord?.repaidAt != nil)
        _notes = State(initialValue: account?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    Picker("银行", selection: $bankID) {
                        ForEach(selectableAccountBanks(banks, currentBankID: account?.bank.id), id: \.id) { bank in
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

                if account != nil {
                    Section("单期日期覆盖") {
                        TextField("账期（YYYYMM）", text: $overrideCycleKeyText)
                            .keyboardType(.numberPad)
                        Toggle("覆盖账单日", isOn: $hasStatementOverride)
                        if hasStatementOverride {
                            DatePicker("实际账单日", selection: $statementOverrideDate, displayedComponents: .date)
                        }
                        Toggle("覆盖还款日", isOn: $hasRepaymentOverride)
                        if hasRepaymentOverride {
                            DatePicker("实际还款日", selection: $repaymentOverrideDate, displayedComponents: .date)
                        }
                        Text("单期覆盖只影响所选账期；还款日必须晚于账单日。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if selectedCycleIsRepaid {
                            Button("撤销已还款", role: .destructive, action: clearSelectedCycleRepaid)
                                .accessibilityLabel("撤销账期 \(overrideCycleKeyText) 的已还款状态")
                        }
                    }
                    .onChange(of: overrideCycleKeyText) { _, _ in loadCycleOverrides() }
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
        guard let bank = selectableAccountBanks(banks, currentBankID: account?.bank.id)
            .first(where: { $0.id == bankID }) else {
            errorMessage = "请选择银行。"
            return
        }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard isValidCurrencyCode(normalizedCurrency) else {
            errorMessage = "额度币种应为有效的 ISO 4217 代码。"
            return
        }
        let limit = limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : CardPilotUI.decimal(limitText)
        guard limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || limit != nil else {
            errorMessage = "信用额度格式不正确。"
            return
        }
        guard limit.map({ $0 > .zero }) != false else {
            errorMessage = "信用额度必须大于 0。"
            return
        }
        var newEffectiveCycleKey: Int?
        var overrideCycleKey: Int?
        if let account {
            let latestRule = account.billingRuleVersions.max {
                ($0.effectiveCycleKey ?? Int.min) < ($1.effectiveCycleKey ?? Int.min)
            }
            let ruleChanged = latestRule?.statementDay != statementDay
                || latestRule?.repaymentKind != repaymentKind
                || latestRule?.repaymentValue != repaymentValue
            if ruleChanged {
                guard let effectiveCycleKey = Int(effectiveCycleKeyText),
                      LocalDate.isValidMonthKey(effectiveCycleKey) else {
                    errorMessage = "生效账期应为有效的 YYYYMM。"
                    return
                }
                guard !account.billingRuleVersions.contains(where: { $0.effectiveCycleKey == effectiveCycleKey }) else {
                    errorMessage = "该生效账期已有规则版本。"
                    return
                }
                do {
                    try account.validateNewBillingRuleEffectiveCycle(
                        effectiveCycleKey,
                        currentMonthKey: CardPilotUI.localDate(from: Date()).monthKey
                    )
                } catch {
                    errorMessage = "规则变更生效账期必须晚于当前账期。"
                    return
                }
                newEffectiveCycleKey = effectiveCycleKey
            }
            guard let parsedCycleKey = Int(overrideCycleKeyText),
                  LocalDate.isValidMonthKey(parsedCycleKey) else {
                errorMessage = "覆盖账期应为有效的 YYYYMM。"
                return
            }
            overrideCycleKey = parsedCycleKey
        }
        let target = account ?? CreditCardAccount(
            bank: bank,
            trackingStartCycleKey: CardPilotUI.localDate(from: Date()).monthKey,
            creditLimit: limit,
            limitCurrencyCode: normalizedCurrency,
            status: status,
            closedOn: status == .closed ? CardPilotUI.rawDate(closedDate) : nil,
            notes: notes
        )
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
        } else if let newEffectiveCycleKey {
                let newRule = BillingRuleVersion(
                    account: target,
                    effectiveCycleKey: newEffectiveCycleKey,
                    statementDay: statementDay,
                    repaymentKind: repaymentKind,
                    repaymentValue: repaymentValue
                )
                target.billingRuleVersions.append(newRule)
                modelContext.insert(newRule)
        }
        var updatedCycleRecord: BillingCycleRecord?
        if let overrideCycleKey,
           hasStatementOverride || hasRepaymentOverride
                || target.billingCycles.contains(where: { $0.cycleKey == overrideCycleKey }) {
            let record = target.billingCycles.first { $0.cycleKey == overrideCycleKey }
                ?? BillingCycleRecord(account: target, cycleKey: overrideCycleKey)
            if !target.billingCycles.contains(where: { $0.id == record.id }) {
                target.billingCycles.append(record)
                modelContext.insert(record)
            }
            record.statementDateOverride = hasStatementOverride ? CardPilotUI.rawDate(statementOverrideDate) : nil
            record.repaymentDateOverride = hasRepaymentOverride ? CardPilotUI.rawDate(repaymentOverrideDate) : nil
            updatedCycleRecord = record
        }
        do {
            try target.validate()
            try target.validateBillingConfiguration()
            if let overrideCycleKey, let updatedCycleRecord {
                _ = try BillingCalculator.calculate(
                    account: target,
                    cycleKey: overrideCycleKey,
                    record: updatedCycleRecord,
                    today: CardPilotUI.localDate(from: Date()),
                    timeZone: CardPilotUI.homeTimeZone
                )
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "账户未保存：\(error.localizedDescription)"
        }
    }

    private func loadCycleOverrides() {
        guard let account,
              let cycleKey = Int(overrideCycleKeyText),
              LocalDate.isValidMonthKey(cycleKey) else {
            selectedCycleIsRepaid = false
            return
        }
        let record = account.billingCycles.first { $0.cycleKey == cycleKey }
        hasStatementOverride = record?.statementDateOverride != nil
        hasRepaymentOverride = record?.repaymentDateOverride != nil
        selectedCycleIsRepaid = record?.repaidAt != nil
        let fallback = (try? LocalDate.firstDay(ofMonthKey: cycleKey).date(in: CardPilotUI.homeTimeZone)) ?? Date()
        statementOverrideDate = record?.statementDateOverride.flatMap {
            try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone)
        } ?? fallback
        repaymentOverrideDate = record?.repaymentDateOverride.flatMap {
            try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone)
        } ?? fallback
    }

    private func clearSelectedCycleRepaid() {
        guard let account,
              let cycleKey = Int(overrideCycleKeyText),
              let record = account.billingCycles.first(where: { $0.cycleKey == cycleKey }) else {
            errorMessage = "找不到要撤销的已还账期。"
            return
        }
        record.repaidAt = nil
        do {
            try record.validate()
            try account.validateBillingConfiguration()
            try modelContext.save()
            selectedCycleIsRepaid = false
        } catch {
            modelContext.rollback()
            selectedCycleIsRepaid = true
            errorMessage = "还款状态未更改：\(error.localizedDescription)"
        }
    }
}

func selectableAccountBanks(_ banks: [Bank], currentBankID: UUID?) -> [Bank] {
    banks.filter { $0.archivedAt == nil || $0.id == currentBankID }
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
        guard !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "卡产品名称不能为空。"
            return
        }
        guard lastFour.count == 4, lastFour.allSatisfy(\.isNumber) else {
            errorMessage = "末四位必须是 4 位数字。"
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
            modelContext.rollback()
            errorMessage = "卡片未保存：\(error.localizedDescription)"
        }
    }
}
