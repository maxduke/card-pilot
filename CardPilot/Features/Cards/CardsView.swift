import SwiftData
import SwiftUI

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
                                                CardRow(card: card) {
                                                    editingCard = card
                                                    showingCardEditor = true
                                                } onDelete: {
                                                    requestDeleteCard(card)
                                                }
                                            }
                                            .padding(.leading, 22)
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    BankBadge(bank: bank)
                                    Text(bank.name)
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
                                    requestDeleteBank(bank)
                                } label: {
                                    Label("删除银行", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $query, prompt: "搜索银行、卡片或末四位")
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
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("卡片与银行管理")
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
            .sheet(isPresented: $showingCardOnboarding) {
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
            account.notes.localizedCaseInsensitiveContains(normalizedQuery)
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

private enum CardNetworkSelection: String, CaseIterable, Identifiable {
    case unionpay
    case visa
    case mastercard
    case amex
    case jcb
    case unionpayVisa
    case unionpayMastercard
    case unionpayJCB
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unionpay: return "银联"
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .jcb: return "JCB"
        case .unionpayVisa: return "银联 + Visa"
        case .unionpayMastercard: return "银联 + Mastercard"
        case .unionpayJCB: return "银联 + JCB"
        case .other: return "其他"
        }
    }

    var codes: [String] {
        switch self {
        case .unionpay: return ["unionpay"]
        case .visa: return ["visa"]
        case .mastercard: return ["mastercard"]
        case .amex: return ["amex"]
        case .jcb: return ["jcb"]
        case .unionpayVisa: return ["unionpay", "visa"]
        case .unionpayMastercard: return ["unionpay", "mastercard"]
        case .unionpayJCB: return ["unionpay", "jcb"]
        case .other: return []
        }
    }

    static var singleChoices: [Self] { [.unionpay, .visa, .mastercard, .amex, .jcb] }
    static var dualChoices: [Self] { [.unionpayVisa, .unionpayMastercard, .unionpayJCB] }

    static func matching(_ networks: [CardNetwork]) -> Self {
        let codes = Set(networks.map(\.code))
        return allCases.first { !$0.codes.isEmpty && Set($0.codes) == codes } ?? .other
    }
}

private struct NetworkChoiceTile: View {
    let choice: CardNetworkSelection
    @Binding var selection: CardNetworkSelection
    let customName: String

    var body: some View {
        Button {
            selection = choice
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if choice.codes.isEmpty {
                        CardNetworkBadge(displayName: customName.isEmpty ? "其他" : customName)
                    } else {
                        ForEach(choice.codes, id: \.self) { code in
                            CardNetworkBadge(displayName: networkName(for: code), code: code)
                        }
                    }
                }
                Spacer(minLength: 0)
                if selection == choice {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selection == choice ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selection == choice ? Color.accentColor.opacity(0.45) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.title)\(selection == choice ? "，已选择" : "")")
    }

    private func networkName(for code: String) -> String {
        switch code {
        case "unionpay": return "银联"
        case "visa": return "Visa"
        case "mastercard": return "Mastercard"
        case "jcb": return "JCB"
        case "amex": return "American Express"
        default: return code
        }
    }
}

private struct CardOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let banks: [Bank]
    let accounts: [CreditCardAccount]
    let networks: [CardNetwork]

    private enum Step: Int, CaseIterable {
        case bank
        case account
        case billing
        case card

        var title: String {
            switch self {
            case .bank: return "选择发卡银行"
            case .account: return "设置信用卡账户"
            case .billing: return "设置账务规则"
            case .card: return "录入卡片"
            }
        }
    }

    private enum AccountMode: String, CaseIterable, Identifiable {
        case new
        case existing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .new: return "创建独立账户"
            case .existing: return "共用已有账户"
            }
        }
    }

    @State private var currentCycleAlreadyRepaid = false
    @State private var step: Step = .bank
    @State private var region: BankPresetRegion = .mainland
    @State private var bankQuery = ""
    @State private var selectedPresetCode: String?
    @State private var customBank = false
    @State private var customBankName = ""
    @State private var accountMode: AccountMode = .new
    @State private var existingAccountID: UUID?
    @State private var limitText = ""
    @State private var currencyCode = "CNY"
    @State private var statementDay = 1
    @State private var repaymentKind: RepaymentRuleKind = .fixedDay
    @State private var repaymentValue = 1
    @State private var networkSelection: CardNetworkSelection = .unionpay
    @State private var customNetworkName = ""
    @State private var productName = ""
    @State private var nickname = ""
    @State private var lastFour = ""
    @State private var errorMessage: String?

    private var selectedPreset: BankPreset? {
        selectedPresetCode.flatMap { code in BankPreset.catalog.first { $0.code == code } }
    }

    private var filteredPresets: [BankPreset] {
        BankPreset.catalog.filter { $0.region == region && $0.matches(bankQuery) }
    }

    private var selectedBankName: String {
        if customBank { return customBankName.trimmingCharacters(in: .whitespacesAndNewlines) }
        return selectedPreset?.displayName ?? ""
    }

    private var matchingBanks: [Bank] {
        if let selectedPreset {
            return matchingPresetBanks(banks, preset: selectedPreset)
        }
        let name = selectedBankName
        return name.isEmpty ? [] : banks.filter {
            $0.presetCode == nil && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private var matchingAccounts: [CreditCardAccount] {
        guard let bank = matchingBanks.first else { return [] }
        return accounts.filter { $0.bank.id == bank.id && $0.status == .active }
    }

    private var selectedExistingAccount: CreditCardAccount? {
        existingAccountID.flatMap { id in matchingAccounts.first { $0.id == id } }
    }

    private var editSnapshot: String {
        editorSnapshot(selectedPresetCode as Any, customBank, customBankName, accountMode, existingAccountID as Any, limitText, currencyCode, statementDay, repaymentKind, repaymentValue, networkSelection, customNetworkName, productName, nickname, lastFour, currentCycleAlreadyRepaid)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double((onboardingSteps.firstIndex(of: step) ?? 0) + 1), total: Double(onboardingSteps.count))
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(step.title)
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        switch step {
                        case .bank: bankStep
                        case .account: accountStep
                        case .billing: billingStep
                        case .card: cardStep
                        }

                        if let errorMessage {
                            InlineErrorView(message: errorMessage)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("添加信用卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton()
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    if step != .bank {
                        Button("上一步") { previousStep() }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(step == .card ? "完成" : "继续") { advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == .bank && !bankIsReady)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .onChange(of: selectedPresetCode) { _, _ in
                if let selectedPreset { currencyCode = selectedPreset.defaultCurrencyCode }
                accountMode = matchingAccounts.isEmpty ? .new : accountMode
                existingAccountID = matchingAccounts.first?.id
            }
            .onChange(of: region) { _, _ in
                selectedPresetCode = nil
                customBank = false
                currencyCode = region == .mainland ? "CNY" : "HKD"
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var onboardingSteps: [Step] {
        var steps: [Step] = [.bank]
        if !matchingAccounts.isEmpty { steps.append(.account) }
        if accountMode == .new { steps.append(.billing) }
        steps.append(.card)
        return steps
    }

    private var previewCycle: BillingCycle? {
        try? BillingCalculator.calculate(
            accountStatus: .active,
            closedOn: nil,
            cycleKey: CardPilotUI.localDate(from: .now).monthKey,
            rules: [BillingRuleInput(effectiveCycleKey: nil, statementDay: statementDay, repaymentKind: repaymentKind, repaymentValue: repaymentValue)],
            today: CardPilotUI.localDate(from: .now),
            timeZone: CardPilotUI.homeTimeZone
        )
    }

    private var bankIsReady: Bool {
        customBank ? !customBankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selectedPreset != nil
    }

    @ViewBuilder
    private var bankStep: some View {
        TextField("搜索银行、英文名或代码", text: $bankQuery)
            .textFieldStyle(.roundedBorder)
            .textContentType(.organizationName)
            .accessibilityLabel("搜索银行")

        Picker("地区", selection: $region) {
            Text("中国大陆").tag(BankPresetRegion.mainland)
            Text("香港").tag(BankPresetRegion.hongKong)
        }
        .pickerStyle(.segmented)

        if !filteredPresets.isEmpty {
            VStack(spacing: 0) {
                ForEach(filteredPresets) { preset in
                    Button {
                        selectedPresetCode = preset.code
                        customBank = false
                        withAnimation { step = matchingAccounts.isEmpty ? .billing : .account }
                    } label: {
                        HStack(spacing: 12) {
                            BankBadge(preset: preset)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .foregroundStyle(.primary)
                                Text("默认额度币种：\(preset.defaultCurrencyCode) · \(preset.englishName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if !customBank && selectedPresetCode == preset.code {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("选择并继续")
                    if preset.id != filteredPresets.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            ContentUnavailableView("没有匹配银行", systemImage: "magnifyingglass", description: Text("可以使用下方的自定义银行。"))
        }

        VStack(alignment: .leading, spacing: 10) {
            Button {
                customBank = true
                selectedPresetCode = nil
            } label: {
                Label("使用自定义银行", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            if customBank {
                TextField("银行名称", text: $customBankName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    @ViewBuilder
    private var accountStep: some View {
        selectedBankAccountSummary

        if matchingAccounts.isEmpty {
            Label("该银行还没有账户，将创建一个新的信用卡账户。", systemImage: "plus.rectangle.on.rectangle")
                .foregroundStyle(.secondary)
        } else {
            existingAccountPicker
        }
    }

    @ViewBuilder
    private var selectedBankAccountSummary: some View {
        if let selectedPreset {
            HStack(spacing: 12) {
                BankBadge(preset: selectedPreset)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPreset.displayName).font(.headline)
                    Text("新卡将归入此发卡银行").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                BankBadge(name: selectedBankName)
                Text(selectedBankName).font(.headline)
            }
        }
    }

    @ViewBuilder
    private var existingAccountPicker: some View {
        accountModeControl

        if accountMode == .existing {
            existingAccountChoices
        }
    }

    private var accountModeControl: some View {
        Picker("账户关系", selection: $accountMode) {
            ForEach(AccountMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)

    }

    private var existingAccountChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择要共用的账户")
                .font(.subheadline.weight(.semibold))
            ForEach(matchingAccounts, id: \.id) { account in
                existingAccountChoice(account)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func existingAccountChoice(_ account: CreditCardAccount) -> some View {
        let isSelected = existingAccountID == account.id
        return Button {
            existingAccountID = account.id
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardAccountDisplayName(account))
                    Text(creditLimitText(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("账单与还款规则沿用此账户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func creditLimitText(for account: CreditCardAccount) -> String {
        guard let creditLimit = account.creditLimit else { return "未设置额度" }
        return "额度 \(CardPilotUI.amountText(creditLimit, currencyCode: account.limitCurrencyCode))"
    }

    @ViewBuilder
    private var billingStep: some View {
        if accountMode == .existing, let selectedExistingAccount {
            VStack(alignment: .leading, spacing: 8) {
                Label("共用已有账户", systemImage: "rectangle.stack.fill")
                    .font(.headline)
                Text(creditLimitText(for: selectedExistingAccount))
                    .foregroundStyle(.secondary)
                Text("本张卡会沿用该账户的额度、账单日和还款日。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("新账户信息")
                    .font(.headline)
                TextField("信用额度（可选）", text: $limitText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                CurrencyPickerView(selection: $currencyCode)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                BillingDayPicker(title: "账单日", value: $statementDay)
                Picker("还款规则", selection: $repaymentKind) {
                    Text("固定日").tag(RepaymentRuleKind.fixedDay)
                    Text("账单日后 N 天").tag(RepaymentRuleKind.daysAfterStatement)
                }
                BillingDayPicker(title: repaymentKind == .fixedDay ? "还款日" : "账单日后", value: $repaymentValue, isDayOfMonth: repaymentKind == .fixedDay)
                .onChange(of: repaymentKind) { _, kind in
                    if kind == .fixedDay { repaymentValue = min(31, repaymentValue) }
                }
                Text("不存在的日期会按当月最后一天计算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cycle = previewCycle {
                    Divider()
                    LabeledContent("本期账单", value: CardPilotUI.dateText(cycle.statementDate))
                    LabeledContent("本期还款", value: CardPilotUI.dateText(cycle.repaymentDate))
                    Toggle("本期已经还款", isOn: $currentCycleAlreadyRepaid)
                    Text("请核对银行账单。已处理本期还款时打开此选项，避免重复提醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var cardStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("卡片身份")
                .font(.headline)
            TextField("卡产品名称", text: $productName)
                .textFieldStyle(.roundedBorder)
            TextField("昵称（可选）", text: $nickname)
                .textFieldStyle(.roundedBorder)
            TextField("末四位", text: $lastFour)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .textContentType(.none)
            Text("卡组织组合")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CardNetworkSelection.singleChoices) { choice in
                    NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                }
            }
            Text("双标卡")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CardNetworkSelection.dualChoices) { choice in
                    NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                }
            }
            NetworkChoiceTile(choice: .other, selection: $networkSelection, customName: customNetworkName)
            if networkSelection == .other {
                TextField("卡组织名称", text: $customNetworkName)
                    .textFieldStyle(.roundedBorder)
            }
            Text("不要录入完整卡号或 CVV。双标卡只保存实际的两个卡组织，不会自动扩大促销适用范围。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func advance() {
        errorMessage = nil
        switch step {
        case .bank:
            guard bankIsReady else {
                errorMessage = "请选择银行，或填写自定义银行名称。"
                return
            }
            if matchingAccounts.isEmpty { accountMode = .new }
            existingAccountID = matchingAccounts.first?.id
            step = matchingAccounts.isEmpty ? .billing : .account
        case .account:
            if accountMode == .existing && selectedExistingAccount == nil {
                errorMessage = "请选择要共用的账户。"
                return
            }
            step = accountMode == .existing ? .card : .billing
        case .billing:
            guard validateBillingInput() else { return }
            step = .card
        case .card:
            save()
        }
    }

    private func previousStep() {
        errorMessage = nil
        guard let index = onboardingSteps.firstIndex(of: step), index > 0 else { return }
        step = onboardingSteps[index - 1]
    }

    private func validateBillingInput() -> Bool {
        guard accountMode == .existing || isValidCurrencyCode(currencyCode.uppercased()) else {
            errorMessage = "请选择有效的额度币种。"
            return false
        }
        guard accountMode == .existing || limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || CardPilotUI.decimal(limitText).map({ $0 > .zero }) == true else {
            errorMessage = "信用额度应为空，或填写大于 0 的数字。"
            return false
        }
        return true
    }

    private func save() {
        guard !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "卡产品名称不能为空。"
            return
        }
        let normalizedLastFour = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedLastFour.utf8.count == 4,
              normalizedLastFour.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            errorMessage = "末四位必须是 4 位数字。"
            return
        }
        let existingBank = matchingBanks.first
        guard let bank = existingBank ?? makeBank() else {
            errorMessage = "银行信息无效，请重新选择。"
            return
        }
        let creatingBank = existingBank == nil
        let account: CreditCardAccount
        let creatingAccount: Bool
        if accountMode == .existing, let selectedExistingAccount {
            account = selectedExistingAccount
            creatingAccount = false
        } else {
            let normalizedCurrency = currencyCode.uppercased()
            guard isValidCurrencyCode(normalizedCurrency) else {
                errorMessage = "请选择有效的额度币种。"
                return
            }
            account = CreditCardAccount(
                bank: bank,
                trackingStartCycleKey: CardPilotUI.localDate(from: Date()).monthKey,
                creditLimit: limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : CardPilotUI.decimal(limitText),
                limitCurrencyCode: normalizedCurrency
            )
            creatingAccount = true
        }
        guard let cardNetworks = resolveNetworks() else { return }
        let card = Card(
            account: account,
            productName: productName.trimmingCharacters(in: .whitespacesAndNewlines),
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            networks: cardNetworks,
            lastFour: normalizedLastFour,
            status: .active
        )

        do {
            bank.archivedAt = nil
            if let selectedPreset { bank.presetCode = selectedPreset.code }
            try bank.validate()
            if creatingAccount {
                let rule = BillingRuleVersion(
                    account: account,
                    statementDay: statementDay,
                    repaymentKind: repaymentKind,
                    repaymentValue: repaymentValue
                )
                account.billingRuleVersions.append(rule)
                try account.validate()
                try account.validateBillingConfiguration()
                modelContext.insert(account)
                modelContext.insert(rule)
                if currentCycleAlreadyRepaid {
                    let record = BillingCycleRecord(account: account, cycleKey: account.trackingStartCycleKey)
                    record.repaidAt = .now
                    account.billingCycles.append(record)
                    modelContext.insert(record)
                }
            }
            try cardNetworks.forEach { try $0.validate() }
            try card.validate()
            if creatingBank { modelContext.insert(bank) }
            card.account.cards.append(card)
            modelContext.insert(card)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "信用卡未保存：\(error.localizedDescription)"
        }
    }

    private func makeBank() -> Bank? {
        let name = selectedBankName
        guard !name.isEmpty else { return nil }
        return Bank(name: name, presetCode: selectedPreset?.code)
    }

    private func resolveNetworks() -> [CardNetwork]? {
        if networkSelection == .other {
            let name = customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                errorMessage = "请填写卡组织名称。"
                return nil
            }
            if let existing = networks.first(where: { !$0.isBuiltIn && $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
                return [existing]
            }
            let custom = CardNetwork(code: "custom.\(UUID().uuidString.lowercased())", displayName: name)
            modelContext.insert(custom)
            return [custom]
        }
        let selected = networkSelection.codes.compactMap { code in networks.first { $0.code == code } }
        guard selected.count == networkSelection.codes.count else {
            errorMessage = "内置卡组织尚未准备好，请重启应用后再试。"
            return nil
        }
        return selected
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
                Text(accountTitle)
                    .font(.subheadline.weight(.semibold))
                Text(accountRelationshipText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
        accountBillingSummary(account)
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
            Spacer()
            if card.status == .inactive {
                Text("停用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("查看卡片详情")
        .contextMenu {
            Button(action: onEdit) { Label("编辑卡片", systemImage: "pencil") }
            Button(role: .destructive, action: onDelete) { Label("删除卡片", systemImage: "trash") }
        }
    }

    private var today: LocalDate { CardPilotUI.localDate(from: Date()) }

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

    private var editSnapshot: String {
        editorSnapshot(name, notes, archived)
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
                ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
        .protectEdits(snapshot: editSnapshot)
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

struct AccountEditorView: View {
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
    @State private var pendingUnpaidCycleKeys: Set<Int> = []
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
        let defaultCurrency = availableBanks.first?.presetCode
            .flatMap { code in BankPreset.catalog.first { $0.code == code }?.defaultCurrencyCode }
            ?? "CNY"
        _currencyCode = State(initialValue: account?.limitCurrencyCode ?? defaultCurrency)
        _status = State(initialValue: account?.status ?? .active)
        _closedDate = State(initialValue: account.flatMap { $0.closedOn.flatMap { try? LocalDate(rawValue: $0).date(in: CardPilotUI.homeTimeZone) } } ?? Date())
        _statementDay = State(initialValue: rule?.statementDay ?? 1)
        _repaymentKind = State(initialValue: rule?.repaymentKind ?? .fixedDay)
        _repaymentValue = State(initialValue: rule?.repaymentValue ?? 1)
        let currentDate = CardPilotUI.localDate(from: Date())
        let currentRecord = account?.billingCycles.first { $0.cycleKey == currentDate.monthKey }
        _effectiveCycleKeyText = State(initialValue: String(nextBillingRuleCycleKey(
            currentMonthKey: currentDate.monthKey,
            existingEffectiveCycleKeys: account?.billingRuleVersions.compactMap(\.effectiveCycleKey) ?? [],
            timeZone: CardPilotUI.homeTimeZone
        )))
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

    private var editSnapshot: String {
        editorSnapshot(bankID, limitText, currencyCode, status, closedDate, statementDay, repaymentKind, repaymentValue, effectiveCycleKeyText, overrideCycleKeyText, hasStatementOverride, statementOverrideDate, hasRepaymentOverride, repaymentOverrideDate, notes, pendingUnpaidCycleKeys.sorted())
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
                    CurrencyPickerView(selection: $currencyCode)
                    Picker("状态", selection: $status) {
                        Text("使用中").tag(CreditCardAccountStatus.active)
                        Text("已关闭").tag(CreditCardAccountStatus.closed)
                    }
                    if status == .closed {
                        DatePicker("关闭日期", selection: $closedDate, displayedComponents: .date)
                    }
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                }

                Section(account == nil ? "账务规则" : "修改以后的账单规则") {
                    if let latestScheduledRuleText {
                        Label(latestScheduledRuleText, systemImage: "calendar.badge.clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    BillingDayPicker(title: "账单日", value: $statementDay)
                    Picker("还款规则", selection: $repaymentKind) {
                        Text("固定日").tag(RepaymentRuleKind.fixedDay)
                        Text("账单日后 N 天").tag(RepaymentRuleKind.daysAfterStatement)
                    }
                    BillingDayPicker(title: repaymentKind == .fixedDay ? "还款日" : "账单日后", value: $repaymentValue, isDayOfMonth: repaymentKind == .fixedDay)
                    .onChange(of: repaymentKind) { _, kind in
                        if kind == .fixedDay { repaymentValue = min(31, repaymentValue) }
                    }
                    Text("不存在的日期会按当月最后一天计算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if account != nil {
                        MonthKeyPicker(
                            title: "新规则生效账期",
                            selection: $effectiveCycleKeyText,
                            offsets: 1...60
                        )
                        Text("保存修改会新增一个未来版本，不会改写当前与历史账期。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if account != nil {
                    Section("调整本期日期") {
                        MonthKeyPicker(
                            title: "账期",
                            selection: $overrideCycleKeyText,
                            offsets: -60...24
                        )
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
                        if let cycleKey = Int(overrideCycleKeyText), pendingUnpaidCycleKeys.contains(cycleKey) {
                            Label("保存后将恢复该账期的待还款状态", systemImage: "clock.arrow.circlepath")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("保留已还款状态") {
                                pendingUnpaidCycleKeys.remove(cycleKey)
                                selectedCycleIsRepaid = true
                            }
                        }
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
                ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
        .protectEdits(snapshot: editSnapshot)
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
                    errorMessage = "请选择有效的生效账期。"
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
                errorMessage = "请选择有效的覆盖账期。"
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
            for record in target.billingCycles where pendingUnpaidCycleKeys.contains(record.cycleKey) {
                record.repaidAt = nil
            }
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
        selectedCycleIsRepaid = record?.repaidAt != nil && !pendingUnpaidCycleKeys.contains(cycleKey)
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
              account.billingCycles.contains(where: { $0.cycleKey == cycleKey && $0.repaidAt != nil }) else {
            errorMessage = "找不到要撤销的已还账期。"
            return
        }
        pendingUnpaidCycleKeys.insert(cycleKey)
        selectedCycleIsRepaid = false
    }

    private var latestScheduledRuleText: String? {
        let currentMonthKey = CardPilotUI.localDate(from: Date()).monthKey
        guard let effectiveCycleKey = account?.billingRuleVersions.compactMap(\.effectiveCycleKey).max(),
              effectiveCycleKey > currentMonthKey else { return nil }
        return "表单当前显示已排定于 \(CardPilotUI.monthKeyText(effectiveCycleKey)) 起生效的规则。"
    }

}

private struct MonthKeyPicker: View {
    // ponytail: a focused rolling window keeps the menu usable; switch to an unbounded month sheet if long-range edits become common.
    let title: String
    @Binding var selection: String
    let offsets: ClosedRange<Int>

    private var monthKeys: [Int] {
        let today = CardPilotUI.localDate(from: Date())
        var keys = Set(offsets.map { today.addingMonths($0, timeZone: CardPilotUI.homeTimeZone).monthKey })
        if let selected = Int(selection), LocalDate.isValidMonthKey(selected) { keys.insert(selected) }
        return keys.sorted()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(monthKeys, id: \.self) { monthKey in
                Text(CardPilotUI.monthKeyText(monthKey)).tag(String(monthKey))
            }
        }
        .pickerStyle(.menu)
        .accessibilityValue(CardPilotUI.monthKeyText(Int(selection)))
    }
}

func selectableAccountBanks(_ banks: [Bank], currentBankID: UUID?) -> [Bank] {
    banks.filter { $0.archivedAt == nil || $0.id == currentBankID }
}

func matchingPresetBanks(_ banks: [Bank], preset: BankPreset) -> [Bank] {
    let tagged = banks.filter { $0.presetCode == preset.code }
    guard tagged.isEmpty else { return tagged }
    return banks.filter {
        $0.presetCode == nil
            && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(preset.displayName) == .orderedSame
    }
}

func nextBillingRuleCycleKey(
    currentMonthKey: Int,
    existingEffectiveCycleKeys: [Int],
    timeZone: TimeZone
) -> Int {
    let currentNext = (try? LocalDate.firstDay(ofMonthKey: currentMonthKey)
        .addingMonths(1, timeZone: timeZone).monthKey) ?? currentMonthKey
    guard let latest = existingEffectiveCycleKeys.filter({ LocalDate.isValidMonthKey($0) }).max(),
          let nextAfterLatest = try? LocalDate.firstDay(ofMonthKey: latest)
            .addingMonths(1, timeZone: timeZone).monthKey else {
        return currentNext
    }
    return max(currentNext, nextAfterLatest)
}

private func cardAccountDisplayName(_ account: CreditCardAccount) -> String {
    CardPilotUI.accountName(account)
}

struct CardEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let card: Card?
    let accounts: [CreditCardAccount]
    let networks: [CardNetwork]

    @State private var accountID: UUID
    @State private var networkSelection: CardNetworkSelection
    @State private var customNetworkName: String
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
        _networkSelection = State(initialValue: CardNetworkSelection.matching(card?.networks ?? []))
        _customNetworkName = State(initialValue: card?.networks.first(where: { !$0.isBuiltIn })?.displayName ?? "")
        _productName = State(initialValue: card?.productName ?? "")
        _nickname = State(initialValue: card?.nickname ?? "")
        _lastFour = State(initialValue: card?.lastFour ?? "")
        _status = State(initialValue: card?.status ?? .active)
        _notes = State(initialValue: card?.notes ?? "")
    }

    private var editSnapshot: String {
        editorSnapshot(accountID, networkSelection, customNetworkName, productName, nickname, lastFour, status, notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("卡片") {
                    Picker("信用卡账户", selection: $accountID) {
                        ForEach(accounts, id: \.id) { account in
                            Text(cardAccountDisplayName(account)).tag(account.id)
                        }
                    }
                    Text("卡组织组合")
                        .font(.subheadline.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CardNetworkSelection.singleChoices) { choice in
                            NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                        }
                    }
                    Text("双标卡")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CardNetworkSelection.dualChoices) { choice in
                            NetworkChoiceTile(choice: choice, selection: $networkSelection, customName: customNetworkName)
                        }
                    }
                    NetworkChoiceTile(choice: .other, selection: $networkSelection, customName: customNetworkName)
                    if networkSelection == .other {
                        TextField("卡组织名称", text: $customNetworkName)
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
                ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountID }) else {
            errorMessage = "请选择账户。"
            return
        }
        guard !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "卡产品名称不能为空。"
            return
        }
        let normalizedLastFour = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedLastFour.utf8.count == 4,
              normalizedLastFour.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            errorMessage = "末四位必须是 4 位数字。"
            return
        }
        guard let selectedNetworks = resolveNetworks() else { return }
        let target = card ?? Card(
            account: account,
            productName: productName,
            networks: selectedNetworks,
            lastFour: normalizedLastFour,
            status: status,
            notes: notes
        )
        target.account = account
        target.networks = selectedNetworks
        target.productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        target.lastFour = normalizedLastFour
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

    private func resolveNetworks() -> [CardNetwork]? {
        if networkSelection == .other {
            let name = customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                errorMessage = "请填写卡组织名称。"
                return nil
            }
            if let existing = networks.first(where: { !$0.isBuiltIn && $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
                return [existing]
            }
            let custom = CardNetwork(code: "custom.\(UUID().uuidString.lowercased())", displayName: name)
            modelContext.insert(custom)
            return [custom]
        }
        let selected = networkSelection.codes.compactMap { code in networks.first { $0.code == code } }
        guard selected.count == networkSelection.codes.count else {
            errorMessage = "内置卡组织尚未准备好，请重启应用后再试。"
            return nil
        }
        return selected
    }
}
