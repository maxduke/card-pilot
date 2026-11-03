import SwiftData
import SwiftUI
import UIKit

struct AccountEditorView: View {
    private enum Field: String, CaseIterable, Hashable {
        case bank = "account.bank"
        case name = "account.name"
        case limit = "account.limit"
        case currency = "account.currency"
        case closedDate = "account.closedDate"
        case notes = "account.notes"
        case effectiveCycle = "account.effectiveCycle"
        case overrideCycle = "account.overrideCycle"
        case statementOverride = "account.statementOverride"
        case repaymentOverride = "account.repaymentOverride"
    }

    private struct BillingChanges {
        let rule: BillingRuleInput?
        let trackingStart: Int
        let cycles: [Int: BillingCycleOverride]
    }

    private struct BillingInputIssue: Error {
        let field: Field
        let message: String
    }

    @Environment(\.currentDay) private var currentDay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let account: CreditCardAccount?
    let banks: [Bank]

    @FocusState private var focusedField: Field?
    @State private var bankID: UUID
    @State private var accountName: String
    @State private var limitText: String
    @State private var currencyCode: String
    @State private var status: CreditCardAccountStatus
    @State private var closedDate: Date
    @State private var statementDay: Int
    @State private var repaymentKind: RepaymentRuleKind
    @State private var repaymentValue: Int
    @State private var effectiveCycleKeyText: String
    @State private var initialRule: BillingRuleInput
    @State private var overrideCycleKeyText: String
    @State private var pendingOverrideCycleKey: String?
    @State private var hasStatementOverride: Bool
    @State private var statementOverrideDate: Date
    @State private var hasRepaymentOverride: Bool
    @State private var repaymentOverrideDate: Date
    @State private var selectedCycleIsRepaid: Bool
    @State private var pendingUnpaidCycleKeys: Set<Int> = []
    @State private var notes: String
    @State private var errorMessage: String?
    @State private var showingValidationErrors = false

    init(account: CreditCardAccount?, banks: [Bank], initialScheduledRule: BillingRuleVersion? = nil) {
        self.account = account
        self.banks = banks
        let currentDate = CardPilotUI.localDate(from: Date())
        let selectedRule = initialScheduledRule.flatMap { rule -> BillingRuleVersion? in
            guard let account, rule.account?.id == account.id,
                  account.billingRuleVersions.contains(where: { $0.id == rule.id }),
                  (rule.effectiveCycleKey ?? Int.min) > currentDate.monthKey else { return nil }
            return rule
        }
        let rule = selectedRule ?? account?.billingRuleVersions.max {
            ($0.effectiveCycleKey ?? Int.min) < ($1.effectiveCycleKey ?? Int.min)
        }
        let availableBanks = selectableAccountBanks(banks, currentBankID: account?.bank.id)
        _bankID = State(initialValue: account?.bank.id ?? availableBanks.first?.id ?? UUID())
        _accountName = State(initialValue: account?.customName ?? "")
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
        let currentRecord = account?.billingCycles.first { $0.cycleKey == currentDate.monthKey }
        let effectiveCycleKey = selectedRule?.effectiveCycleKey ?? nextBillingRuleCycleKey(
            currentMonthKey: currentDate.monthKey,
            existingEffectiveCycleKeys: account?.billingRuleVersions.compactMap(\.effectiveCycleKey) ?? [],
            timeZone: CardPilotUI.homeTimeZone
        )
        _effectiveCycleKeyText = State(initialValue: String(effectiveCycleKey))
        _initialRule = State(initialValue: BillingRuleInput(
            effectiveCycleKey: effectiveCycleKey,
            statementDay: rule?.statementDay ?? 1,
            repaymentKind: rule?.repaymentKind ?? .fixedDay,
            repaymentValue: rule?.repaymentValue ?? 1
        ))
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
        editorSnapshot(bankID, accountName, limitText, currencyCode, status, closedDate, statementDay, repaymentKind, repaymentValue, effectiveCycleKeyText, overrideCycleKeyText, hasStatementOverride, statementOverrideDate, hasRepaymentOverride, repaymentOverrideDate, notes, pendingUnpaidCycleKeys.sorted())
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                let billingIssue = currentBillingIssue
                Form {
                    Section("账户") {
                        AccountBankPicker(selection: $bankID,
                                          banks: selectableAccountBanks(banks, currentBankID: account?.bank.id))
                        .id(Field.bank)
                        fieldError(.bank)
                        TextField("账户名称（可选）", text: $accountName)
                            .focused($focusedField, equals: .name)
                            .id(Field.name)
                            .accessibilityHint("留空时使用银行与卡片信息")
                            .accessibilityIdentifier("account.editor.name")
                        TextField("信用额度（可选）", text: $limitText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .limit)
                            .id(Field.limit)
                        fieldError(.limit)
                        CurrencyPickerView(selection: $currencyCode)
                            .id(Field.currency)
                        fieldError(.currency)
                        if dynamicTypeSize.isAccessibilitySize {
                            statusPicker.pickerStyle(.inline)
                        } else {
                            statusPicker
                        }
                        if status == .closed {
                            BillingDatePicker(title: "关闭日期", selection: $closedDate, identifier: "account.editor.closedDate")
                                .id(Field.closedDate)
                            fieldError(.closedDate, billingIssue: billingIssue)
                        }
                        TextField("备注（可选）", text: $notes, axis: .vertical)
                            .accessibilityIdentifier("account.notes")
                            .focused($focusedField, equals: .notes)
                    }

                    Section(account == nil ? "账务规则" : "修改以后的账单规则") {
                        if let latestScheduledRuleText {
                            Label(latestScheduledRuleText, systemImage: "calendar.badge.clock")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        BillingDayPicker(title: "账单日", value: $statementDay, identifier: "account.editor.rule.statementDay")
                        Picker("还款规则", selection: $repaymentKind) {
                            Text("固定日").tag(RepaymentRuleKind.fixedDay)
                            Text("账单日后 N 天").tag(RepaymentRuleKind.daysAfterStatement)
                        }
                        BillingDayPicker(title: repaymentKind == .fixedDay ? "还款日" : "账单日后", value: $repaymentValue,
                                         isDayOfMonth: repaymentKind == .fixedDay, identifier: "account.editor.rule.repaymentDay")
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
                                offsets: 1...60,
                                identifier: "account.editor.rule.effectiveCycle"
                            )
                            .id(Field.effectiveCycle)
                            fieldError(.effectiveCycle, billingIssue: billingIssue)
                            Text("修改规则或生效账期后保存：所选未来账期已有版本时修正该版本，否则新增版本。不会改写当前与历史账期，后续已排定版本仍然保留。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if account != nil {
                        Section("调整本期日期") {
                            MonthKeyPicker(
                                title: "账期",
                                selection: overrideCycleSelection,
                                offsets: -60...24,
                                identifier: "account.editor.override.cycle"
                            )
                            .id(Field.overrideCycle)
                            fieldError(.overrideCycle, billingIssue: billingIssue)
                            Toggle("覆盖账单日", isOn: $hasStatementOverride)
                                .accessibilityIdentifier("account.editor.override.statement.enabled")
                            if hasStatementOverride {
                                BillingDatePicker(title: "实际账单日", selection: $statementOverrideDate,
                                                  identifier: "account.editor.override.statementDate")
                                    .id(Field.statementOverride)
                                fieldError(.statementOverride, billingIssue: billingIssue)
                            }
                            Toggle("覆盖还款日", isOn: $hasRepaymentOverride)
                                .accessibilityIdentifier("account.editor.override.repayment.enabled")
                            if hasRepaymentOverride {
                                BillingDatePicker(title: "实际还款日", selection: $repaymentOverrideDate,
                                                  identifier: "account.editor.override.repaymentDate")
                                    .id(Field.repaymentOverride)
                                fieldError(.repaymentOverride, billingIssue: billingIssue)
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
                .scrollDismissesKeyboard(.immediately)
                .accessibilityIdentifier("account.editor.form")
                .onChange(of: focusedField) { _, field in
                    guard field == .limit else { return }
                    revealCreditLimit(using: scrollProxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    revealCreditLimit(using: scrollProxy)
                }
                .navigationTitle(account == nil ? "添加信用卡账户" : "编辑信用卡账户")
                .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .automatic)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save(using: scrollProxy) } }
                    if focusedField == .limit {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("收起键盘") { focusedField = nil }
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("account.keyboard.dismiss")
                                .onGeometryChange(for: CGRect.self) { geometry in
                                    geometry.frame(in: .global)
                                } action: { frame in
                                    guard !frame.isEmpty else { return }
                                    revealCreditLimit(using: scrollProxy)
                                }
                        }
                    }
                }
            }
        }
        .confirmationDialog("放弃当前账期的日期修改？", isPresented: Binding(
            get: { pendingOverrideCycleKey != nil },
            set: { if !$0 { pendingOverrideCycleKey = nil } }
        ), titleVisibility: .visible, presenting: pendingOverrideCycleKey) { cycleKey in
            Button("放弃日期修改并切换", role: .destructive) {
                overrideCycleKeyText = cycleKey
                pendingOverrideCycleKey = nil
            }
            Button("继续编辑", role: .cancel) { pendingOverrideCycleKey = nil }
        } message: { _ in
            Text("当前账期的日期修改尚未保存。继续编辑并保存，或放弃这些日期修改后切换账期。")
        }
        .protectEdits(snapshot: editSnapshot)
    }

    private var overrideCycleSelection: Binding<String> {
        Binding(
            get: { overrideCycleKeyText },
            set: { cycleKey in
                guard cycleKey != overrideCycleKeyText else { return }
                if hasUnsavedCycleDates {
                    pendingOverrideCycleKey = cycleKey
                } else {
                    overrideCycleKeyText = cycleKey
                }
            }
        )
    }

    private var hasUnsavedCycleDates: Bool {
        guard let cycleKey = Int(overrideCycleKeyText) else { return false }
        let record = account?.billingCycles.first { $0.cycleKey == cycleKey }
        let statement = hasStatementOverride ? CardPilotUI.rawDate(statementOverrideDate) : nil
        let repayment = hasRepaymentOverride ? CardPilotUI.rawDate(repaymentOverrideDate) : nil
        return statement != record?.statementDateOverride || repayment != record?.repaymentDateOverride
    }

    private func revealCreditLimit(using scrollProxy: ScrollViewProxy) {
        guard focusedField == .limit else { return }
        Task { @MainActor in
            await Task.yield()
            guard focusedField == .limit else { return }
            scrollProxy.scrollTo(Field.limit, anchor: .top)
        }
    }

    private func validationMessage(for field: Field) -> String? {
        switch field {
        case .bank:
            return selectableAccountBanks(banks, currentBankID: account?.bank.id)
                .contains(where: { $0.id == bankID }) ? nil : "请选择银行。"
        case .limit:
            guard !limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            guard let limit = CardPilotUI.decimal(limitText) else { return "信用额度格式不正确。" }
            return limit > .zero ? nil : "信用额度必须大于 0。"
        case .currency:
            let normalized = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return isValidCurrencyCode(normalized) ? nil : "额度币种应为有效的 ISO 4217 代码。"
        case .name, .closedDate, .notes, .effectiveCycle, .overrideCycle, .statementOverride, .repaymentOverride:
            return nil
        }
    }

    @ViewBuilder
    private func fieldError(_ field: Field, billingIssue: BillingInputIssue? = nil) -> some View {
        if showingValidationErrors,
           let message = validationMessage(for: field) ?? (billingIssue?.field == field ? billingIssue?.message : nil) {
            InlineErrorView(message: message)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(field.rawValue).error")
        }
    }

    private var currentBillingIssue: BillingInputIssue? {
        guard showingValidationErrors else { return nil }
        do {
            _ = try proposedBillingChanges()
            return nil
        } catch let issue as BillingInputIssue {
            return issue
        } catch {
            // Configuration and persistence failures retain the overall save message.
            return nil
        }
    }

    private func dateIssue(for cycleKey: Int) -> BillingInputIssue {
        let month = CardPilotUI.monthKeyText(cycleKey)
        guard Int(overrideCycleKeyText) == cycleKey else {
            return BillingInputIssue(field: .effectiveCycle,
                message: "\(month)账期的还款日不晚于账单日。请调整该账期日期，或修改规则。")
        }
        let field: Field = hasRepaymentOverride ? .repaymentOverride : hasStatementOverride ? .statementOverride : .overrideCycle
        return BillingInputIssue(field: field, message: "\(month)账期的还款日必须晚于账单日。")
    }

    private func scrollToError(_ field: Field, using scrollProxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            guard validationMessage(for: field) != nil || currentBillingIssue?.field == field else { return }
            scrollProxy.scrollTo(field, anchor: .top)
        }
    }

    private func proposedBillingChanges() throws -> BillingChanges {
        let today = currentDay.today
        let timeZone = CardPilotUI.homeTimeZone
        let requestedRule = BillingRuleInput(
            effectiveCycleKey: account == nil ? nil : Int(effectiveCycleKeyText),
            statementDay: statementDay, repaymentKind: repaymentKind, repaymentValue: repaymentValue
        )
        let closedOn = status == .closed ? CardPilotUI.localDate(from: closedDate) : nil
        let ruleChange: BillingRuleInput?
        let trackingStart: Int
        var cycleUpdates: [Int: BillingCycleOverride] = [:]
        do {
            try requestedRule.validate()
            if let account {
                try account.validateBillingConfiguration()
                ruleChange = try BillingCalculator.futureRuleChange(
                    initial: initialRule, requested: requestedRule,
                    rules: account.billingRuleVersions.map(\.billingRuleInput),
                    currentMonthKey: today.monthKey
                )
                trackingStart = account.trackingStartCycleKey
                guard let cycleKey = Int(overrideCycleKeyText), LocalDate.isValidMonthKey(cycleKey) else {
                    throw BillingInputIssue(field: .overrideCycle, message: "请选择有效的覆盖账期。")
                }
                let existing = account.billingCycles.first { $0.cycleKey == cycleKey }
                let statement = hasStatementOverride ? CardPilotUI.localDate(from: statementOverrideDate) : nil
                let repayment = hasRepaymentOverride ? CardPilotUI.localDate(from: repaymentOverrideDate) : nil
                if existing?.statementDateOverride != statement?.rawValue
                    || existing?.repaymentDateOverride != repayment?.rawValue {
                    cycleUpdates[cycleKey] = BillingCycleOverride(
                        statementDate: statement, repaymentDate: repayment, repaidAt: existing?.repaidAt
                    )
                }
                for record in account.billingCycles where pendingUnpaidCycleKeys.contains(record.cycleKey) {
                    let dates = try cycleUpdates[record.cycleKey] ?? BillingCycleOverride(
                        statementDate: record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                        repaymentDate: record.repaymentDateOverride.map { try LocalDate(rawValue: $0) },
                        repaidAt: record.repaidAt
                    )
                    cycleUpdates[record.cycleKey] = BillingCycleOverride(
                        statementDate: dates.statementDate, repaymentDate: dates.repaymentDate, repaidAt: nil
                    )
                }
            } else {
                ruleChange = requestedRule
                trackingStart = try BillingCalculator.initialCycle(rule: requestedRule, today: today, timeZone: timeZone).cycleKey
            }
            var proposedRules = account?.billingRuleVersions.map(\.billingRuleInput) ?? []
            if let ruleChange {
                proposedRules.removeAll { $0.effectiveCycleKey == ruleChange.effectiveCycleKey }
                proposedRules.append(ruleChange)
            }
            if ruleChange != nil {
                var proposedOverrides: [Int: BillingCycleOverride] = [:]
                for record in account?.billingCycles ?? [] {
                    proposedOverrides[record.cycleKey] = try BillingCycleOverride(
                        statementDate: record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                        repaymentDate: record.repaymentDateOverride.map { try LocalDate(rawValue: $0) },
                        repaidAt: record.repaidAt
                    )
                }
                proposedOverrides.merge(cycleUpdates) { _, changed in changed }
                if let cycleKey = try BillingCalculator.firstInvalidOverrideCycleKey(
                    affectedBy: ruleChange, rules: proposedRules, overrides: proposedOverrides, today: today, timeZone: timeZone
                ) {
                    throw dateIssue(for: cycleKey)
                }
            }
            // Validate values before mutating models or their inverse relationship arrays.
            for (cycleKey, dates) in cycleUpdates.sorted(by: { $0.key < $1.key }) {
                do {
                    _ = try BillingCalculator.calculate(
                        accountStatus: status, closedOn: closedOn, cycleKey: cycleKey,
                        rules: proposedRules, override: dates, today: today, timeZone: timeZone
                    )
                } catch BillingCalculationError.invalidOverride {
                    throw dateIssue(for: cycleKey)
                } catch BillingCalculationError.accountClosed {
                    let field: Field = Int(overrideCycleKeyText) == cycleKey && hasStatementOverride ? .statementOverride : .closedDate
                    throw BillingInputIssue(field: field,
                        message: "\(CardPilotUI.monthKeyText(cycleKey))账期的账单日晚于账户关闭日期，请调整日期。")
                }
            }
        } catch ModelValidationError.effectiveCycleMustBeFuture {
            throw BillingInputIssue(field: .effectiveCycle, message: "规则变更生效账期必须晚于当前账期。")
        }
        return BillingChanges(rule: ruleChange, trackingStart: trackingStart, cycles: cycleUpdates)
    }

    private func save(using scrollProxy: ScrollViewProxy) {
        focusedField = nil
        errorMessage = nil
        showingValidationErrors = true
        if let field = Field.allCases.first(where: { validationMessage(for: $0) != nil }) {
            scrollToError(field, using: scrollProxy)
            return
        }
        guard let bank = selectableAccountBanks(banks, currentBankID: account?.bank.id)
            .first(where: { $0.id == bankID }) else { return }
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let limit = limitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : CardPilotUI.decimal(limitText)
        let changes: BillingChanges
        do {
            try bank.validate()
            changes = try proposedBillingChanges()
        } catch let issue as BillingInputIssue {
            scrollToError(issue.field, using: scrollProxy)
            return
        } catch {
            errorMessage = "账户未保存：\(error.localizedDescription)"
            return
        }
        let ruleChange = changes.rule
        let trackingStart = changes.trackingStart
        let cycleUpdates = changes.cycles
        let closedOn = status == .closed ? CardPilotUI.localDate(from: closedDate) : nil

        let previousOwnerBank = account?.bank
        let target = account ?? CreditCardAccount(bank: bank, trackingStartCycleKey: trackingStart)
        let previousValues = (target.creditLimit, target.limitCurrencyCode, target.statusRaw, target.closedOn, target.notes)
        let previousName = target.customName
        let previousRules = target.billingRuleVersions
        let ruleValues = previousRules.map { ($0, $0.billingRuleInput) }
        let previousCycles = target.billingCycles
        let cycleValues = previousCycles.map { ($0, $0.statementDateOverride, $0.repaymentDateOverride, $0.repaidAt) }
        var insertedRules: [BillingRuleVersion] = []
        var insertedCycles: [BillingCycleRecord] = []
        do {
            let normalizedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
            target.customName = normalizedName.isEmpty ? nil : normalizedName
            target.bank = bank
            target.creditLimit = limit
            target.limitCurrencyCode = normalizedCurrency
            target.status = status
            target.closedOn = closedOn?.rawValue
            target.notes = notes
            if account == nil { modelContext.insert(target) }
            if let ruleChange {
                let existing = target.billingRuleVersions.first { $0.effectiveCycleKey == ruleChange.effectiveCycleKey }
                let rule = existing ?? BillingRuleVersion(
                    account: target, effectiveCycleKey: ruleChange.effectiveCycleKey,
                    statementDay: ruleChange.statementDay, repaymentKind: ruleChange.repaymentKind,
                    repaymentValue: ruleChange.repaymentValue
                )
                if existing == nil {
                    insertedRules.append(rule)
                    modelContext.insert(rule)
                    if !target.billingRuleVersions.contains(where: { $0.id == rule.id }) {
                        target.billingRuleVersions.append(rule)
                    }
                }
                rule.statementDay = ruleChange.statementDay
                rule.repaymentKind = ruleChange.repaymentKind
                rule.repaymentValue = ruleChange.repaymentValue
            }
            for (cycleKey, dates) in cycleUpdates {
                let existing = target.billingCycles.first { $0.cycleKey == cycleKey }
                let record = existing ?? BillingCycleRecord(account: target, cycleKey: cycleKey)
                if existing == nil {
                    insertedCycles.append(record)
                    modelContext.insert(record)
                    if !target.billingCycles.contains(where: { $0.id == record.id }) { target.billingCycles.append(record) }
                }
                record.statementDateOverride = dates.statementDate?.rawValue
                record.repaymentDateOverride = dates.repaymentDate?.rawValue
                record.repaidAt = dates.repaidAt
                if !dates.requiresRecord(cycleKey: cycleKey, trackingStartCycleKey: target.trackingStartCycleKey) {
                    modelContext.delete(record)
                    target.billingCycles.removeAll { $0.id == record.id }
                }
            }
            try target.validate()
            try target.validateBillingConfiguration()
            try modelContext.save()
            dismiss()
        } catch {
            for rule in insertedRules { rule.account = nil }
            for record in insertedCycles { record.account = nil }
            for (rule, values) in ruleValues {
                rule.statementDay = values.statementDay
                rule.repaymentKind = values.repaymentKind
                rule.repaymentValue = values.repaymentValue
            }
            for (record, statement, repayment, repaidAt) in cycleValues {
                record.account = target
                record.statementDateOverride = statement
                record.repaymentDateOverride = repayment
                record.repaidAt = repaidAt
            }
            target.billingRuleVersions = previousRules
            target.billingCycles = previousCycles
            target.creditLimit = previousValues.0
            target.limitCurrencyCode = previousValues.1
            target.statusRaw = previousValues.2
            target.closedOn = previousValues.3
            target.notes = previousValues.4
            target.customName = previousName
            if let previousOwnerBank { target.bank = previousOwnerBank }
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

    private var statusPicker: some View {
        Picker("状态", selection: $status) {
            Text("使用中").tag(CreditCardAccountStatus.active)
            Text("已关闭").tag(CreditCardAccountStatus.closed)
        }
        .accessibilityIdentifier("account.editor.status")
    }

    private var latestScheduledRuleText: String? {
        let currentMonthKey = currentDay.today.monthKey
        guard let effectiveCycleKey = account?.billingRuleVersions.compactMap(\.effectiveCycleKey).max(),
              effectiveCycleKey > currentMonthKey else { return nil }
        return "已有规则排定于 \(CardPilotUI.monthKeyText(effectiveCycleKey)) 起生效；可选择该未来账期修正规则。"
    }

}

private struct AccountBankPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selection: UUID
    let banks: [Bank]

    private var selectedName: String {
        banks.first { $0.id == selection }?.name ?? "请选择银行"
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                NavigationLink {
                    AccountBankSelection(selection: $selection, banks: banks)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("银行")
                            .foregroundStyle(.primary)
                        Text(selectedName)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel("银行")
            } else {
                Picker("银行", selection: $selection) {
                    ForEach(banks, id: \.id) { bank in
                        Text(bank.name).tag(bank.id)
                    }
                }
            }
        }
        .accessibilityValue(selectedName)
        .accessibilityIdentifier("account.editor.bank")
    }
}

private struct AccountBankSelection: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: UUID
    let banks: [Bank]

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(banks, id: \.id) { bank in
                Button {
                    selection = bank.id
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(bank.name)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if selection == bank.id {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityAddTraits(selection == bank.id ? .isSelected : [])
                .id(bank.id)
            }
            .task {
                await Task.yield()
                scrollProxy.scrollTo(selection, anchor: .center)
            }
        }
        .navigationTitle("银行")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MonthKeyPicker: View {
    @Environment(\.currentDay) private var currentDay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Keep the existing rolling window and include any selected month outside it.
    let title: String
    @Binding var selection: String
    let offsets: ClosedRange<Int>
    let identifier: String

    private var monthKeys: [Int] {
        let today = currentDay.today
        var keys = Set(offsets.map { today.addingMonths($0, timeZone: CardPilotUI.homeTimeZone).monthKey })
        if let selected = Int(selection), LocalDate.isValidMonthKey(selected) { keys.insert(selected) }
        return keys.sorted()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            NavigationLink {
                BillingMonthSelection(title: title, selection: $selection, monthKeys: monthKeys)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(CardPilotUI.monthKeyText(Int(selection)))
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel(title)
            .accessibilityValue(CardPilotUI.monthKeyText(Int(selection)))
            .accessibilityIdentifier(identifier)
        } else {
            picker.pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) {
            ForEach(monthKeys, id: \.self) { monthKey in
                Text(CardPilotUI.monthKeyText(monthKey))
                    .fixedSize(horizontal: false, vertical: true)
                    .tag(String(monthKey))
            }
        }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(CardPilotUI.monthKeyText(Int(selection)))
    }
}

private struct BillingMonthSelection: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selection: String
    let monthKeys: [Int]

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(monthKeys, id: \.self) { monthKey in
                Button {
                    selection = String(monthKey)
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(CardPilotUI.monthKeyText(monthKey))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if selection == String(monthKey) {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityAddTraits(selection == String(monthKey) ? .isSelected : [])
                .id(String(monthKey))
            }
            .task {
                await Task.yield()
                scrollProxy.scrollTo(selection, anchor: .center)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
