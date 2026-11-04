import SwiftData
import SwiftUI
import UIKit

enum CardNetworkSelection: String, CaseIterable, Identifiable {
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

struct NetworkChoiceTile: View {
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

struct CardOnboardingView: View {
    private enum Field: String, Hashable {
        case bankSearch = "onboarding.bankSearch"
        case bankName = "onboarding.bankName"
        case accountName = "onboarding.accountName"
        case creditLimit = "onboarding.creditLimit"
        case currency = "onboarding.currency"
        case productName = "onboarding.productName"
        case nickname = "onboarding.nickname"
        case lastFour = "onboarding.lastFour"
        case customNetwork = "onboarding.customNetwork"
    }

    @Environment(\.currentDay) private var currentDay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var focusedField: Field?

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
    @State private var accountName = ""
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
    @State private var showingValidationErrors = false
    @State private var savedCard: Card?

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
        editorSnapshot(selectedPresetCode as Any, customBank, customBankName, accountMode, existingAccountID as Any, accountName, limitText, currencyCode, statementDay, repaymentKind, repaymentValue, networkSelection, customNetworkName, productName, nickname, lastFour, currentCycleAlreadyRepaid)
    }

    var body: some View {
        if let savedCard {
            FirstCardReminderView(card: savedCard)
        } else {
            editor
        }
    }

    private var editor: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double((onboardingSteps.firstIndex(of: step) ?? 0) + 1), total: Double(onboardingSteps.count))
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .padding(.top, 4)

                ScrollViewReader { scrollProxy in
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
                        .contentShape(Rectangle())
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .accessibilityIdentifier("onboarding.form")
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 12) {
                            if step != .bank {
                                Button("上一步") { previousStep() }
                                    .buttonStyle(.bordered)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            Spacer()
                            Button(step == .card ? "完成" : "继续") { advance(using: scrollProxy) }
                                .buttonStyle(.borderedProminent)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .fixedSize(horizontal: true, vertical: false)
                                .disabled(step == .bank && !bankIsReady)
                                .accessibilityIdentifier("onboarding.advance")
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(.bar)
                    }
                }
            }
            .navigationTitle("添加信用卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EditorCancelButton()
                }
                if focusedField == .creditLimit || focusedField == .lastFour {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("收起键盘") { focusedField = nil }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("onboarding.keyboard.dismiss")
                    }
                }
            }
            .onChange(of: step) { _, _ in
                focusedField = nil
                showingValidationErrors = false
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
            .onChange(of: previewCycle) { _, _ in currentCycleAlreadyRepaid = false }
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
        try? BillingCalculator.initialCycle(
            rule: BillingRuleInput(effectiveCycleKey: nil, statementDay: statementDay, repaymentKind: repaymentKind, repaymentValue: repaymentValue),
            today: currentDay.today,
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
            .focused($focusedField, equals: .bankSearch)
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
                    .accessibilityIdentifier("bank.\(preset.code)")
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
                    .focused($focusedField, equals: .bankName)
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
                    Text(CardPilotUI.accountName(account))
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
                TextField("账户名称（可选）", text: $accountName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .accountName)
                    .accessibilityHint("留空时使用银行与卡片信息")
                    .accessibilityIdentifier("onboarding.accountName")
                TextField("信用额度（可选）", text: $limitText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .creditLimit)
                    .id(Field.creditLimit)
                fieldError(.creditLimit)
                CurrencyPickerView(selection: $currencyCode)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .id(Field.currency)
                fieldError(.currency)
                BillingDayPicker(title: "账单日", value: $statementDay, identifier: "onboarding.rule.statementDay")
                Picker("还款规则", selection: $repaymentKind) {
                    Text("固定日").tag(RepaymentRuleKind.fixedDay)
                    Text("账单日后 N 天").tag(RepaymentRuleKind.daysAfterStatement)
                }
                BillingDayPicker(title: repaymentKind == .fixedDay ? "还款日" : "账单日后", value: $repaymentValue,
                                 isDayOfMonth: repaymentKind == .fixedDay, identifier: "onboarding.rule.repaymentDay")
                .onChange(of: repaymentKind) { _, kind in
                    if kind == .fixedDay { repaymentValue = min(31, repaymentValue) }
                }
                Text("不存在的日期会按当月最后一天计算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cycle = previewCycle {
                    Divider()
                    LabeledContent("开始追踪账期", value: CardPilotUI.monthKeyText(cycle.cycleKey))
                    LabeledContent("本期账单", value: CardPilotUI.dateText(cycle.statementDate))
                    LabeledContent("本期还款", value: CardPilotUI.dateText(cycle.repaymentDate))
                    Toggle("本期已经还款", isOn: $currentCycleAlreadyRepaid)
                    Text("请核对 \(CardPilotUI.monthKeyText(cycle.cycleKey))账期的银行账单。只有这期已经还清时才打开此选项；后续账期仍会提醒。")
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
                .focused($focusedField, equals: .productName)
                .id(Field.productName)
            fieldError(.productName)
            TextField("昵称（可选）", text: $nickname)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .nickname)
            TextField("末四位", text: $lastFour)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .lastFour)
                .textContentType(.none)
                .id(Field.lastFour)
            fieldError(.lastFour)
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
                    .focused($focusedField, equals: .customNetwork)
                    .id(Field.customNetwork)
                fieldError(.customNetwork)
            }
            Text("不要录入完整卡号或 CVV。双标卡只保存实际的两个卡组织，不会自动扩大促销适用范围。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var validationFields: [Field] {
        switch step {
        case .billing: [.creditLimit, .currency]
        case .card: [.productName, .lastFour, .customNetwork]
        case .bank, .account: []
        }
    }

    private func validationMessage(for field: Field) -> String? {
        switch field {
        case .creditLimit:
            guard accountMode == .new else { return nil }
            let text = limitText.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || CardPilotUI.decimal(limitText).map({ $0 > .zero }) == true
                ? nil : "信用额度应为空，或填写大于 0 的数字。"
        case .currency:
            return accountMode == .existing || isValidCurrencyCode(currencyCode.uppercased())
                ? nil : "请选择有效的额度币种。"
        case .productName:
            return productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "卡产品名称不能为空。" : nil
        case .lastFour:
            let normalized = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.utf8.count == 4 && normalized.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 })
                ? nil : "末四位必须是 4 位数字。"
        case .customNetwork:
            guard networkSelection == .other else { return nil }
            return customNetworkName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请填写卡组织名称。" : nil
        case .bankSearch, .bankName, .accountName, .nickname:
            return nil
        }
    }

    @ViewBuilder
    private func fieldError(_ field: Field) -> some View {
        if showingValidationErrors, let message = validationMessage(for: field) {
            InlineErrorView(message: message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(field.rawValue).error")
        }
    }

    private func advance(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        showingValidationErrors = true
        if let field = validationFields.first(where: { validationMessage(for: $0) != nil }) {
            let submittedStep = step
            Task { @MainActor in
                await Task.yield()
                guard step == submittedStep, validationMessage(for: field) != nil else { return }
                scrollProxy.scrollTo(field, anchor: .top)
            }
            return
        }
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
        if let message = validationMessage(for: .currency) ?? validationMessage(for: .creditLimit) {
            errorMessage = message
            return false
        }
        return true
    }

    private func save() {
        guard savedCard == nil else { return }
        guard validateBillingInput() else { return }
        if let message = validationMessage(for: .productName) {
            errorMessage = message
            return
        }
        let normalizedLastFour = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = validationMessage(for: .lastFour) {
            errorMessage = message
            return
        }
        let initialCycle = previewCycle
        guard accountMode == .existing || initialCycle != nil else {
            errorMessage = "账务规则无效，请检查账单日和还款规则。"
            return
        }
        guard accountMode != .existing || selectedExistingAccount != nil else {
            errorMessage = "请选择要共用的信用卡账户。"
            return
        }
        // Check before creating relationships, which can insert related models.
        let isFirstCard: Bool
        do {
            isFirstCard = try modelContext.fetchCount(FetchDescriptor<Card>()) == 0
        } catch {
            errorMessage = "无法检查已有卡片，请重试。"
            return
        }
        guard let cardNetworks = resolveNetworks() else { return }
        let previousNetworkCards = cardNetworks.map { ($0, $0.cards) }
        let existingBank = matchingBanks.first
        guard let bank = existingBank ?? makeBank() else {
            errorMessage = "银行信息无效，请重新选择。"
            return
        }
        let creatingBank = existingBank == nil
        let previousArchivedAt = bank.archivedAt
        let previousPresetCode = bank.presetCode
        let account: CreditCardAccount
        let creatingAccount: Bool
        if accountMode == .existing, let selectedExistingAccount {
            account = selectedExistingAccount
            creatingAccount = false
        } else {
            guard let initialCycle else { return }
            let normalizedCurrency = currencyCode.uppercased()
            guard isValidCurrencyCode(normalizedCurrency) else {
                errorMessage = "请选择有效的额度币种。"
                return
            }
            let normalizedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
            account = CreditCardAccount(
                bank: bank,
                customName: normalizedName.isEmpty ? nil : normalizedName,
                trackingStartCycleKey: initialCycle.cycleKey,
                creditLimit: limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : CardPilotUI.decimal(limitText),
                limitCurrencyCode: normalizedCurrency
            )
            creatingAccount = true
        }
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
                if !account.billingRuleVersions.contains(where: { $0.id == rule.id }) {
                    account.billingRuleVersions.append(rule)
                }
                try account.validate()
                try account.validateBillingConfiguration()
                modelContext.insert(account)
                modelContext.insert(rule)
                if currentCycleAlreadyRepaid {
                    let record = BillingCycleRecord(account: account, cycleKey: account.trackingStartCycleKey)
                    record.repaidAt = .now
                    if !account.billingCycles.contains(where: { $0.id == record.id }) {
                        account.billingCycles.append(record)
                    }
                    modelContext.insert(record)
                }
            }
            try cardNetworks.forEach { try $0.validate() }
            try card.validate()
            if creatingBank { modelContext.insert(bank) }
            if !card.account.cards.contains(where: { $0.id == card.id }) { card.account.cards.append(card) }
            modelContext.insert(card)
            try modelContext.save()
            if isFirstCard {
                savedCard = card
            } else {
                dismiss()
            }
        } catch {
            bank.archivedAt = previousArchivedAt
            bank.presetCode = previousPresetCode
            for (network, previousCards) in previousNetworkCards { network.cards = previousCards }
            if creatingAccount {
                for rule in account.billingRuleVersions { rule.account = nil }
                for record in account.billingCycles { record.account = nil }
                account.billingRuleVersions = []
                account.billingCycles = []
            }
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
            if let message = validationMessage(for: .customNetwork) {
                errorMessage = message
                return nil
            }
            if let existing = networks.first(where: { !$0.isBuiltIn && $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
                return [existing]
            }
            return [CardNetwork(code: "custom.\(UUID().uuidString.lowercased())", displayName: name)]
        }
        let selected = networkSelection.codes.compactMap { code in networks.first { $0.code == code } }
        guard selected.count == networkSelection.codes.count else {
            errorMessage = "内置卡组织尚未准备好，请重启应用后再试。"
            return nil
        }
        return selected
    }
}
