import SwiftData
import SwiftUI

@MainActor
enum BillingCycleActions {
    static func resolve(_ target: BillingCycleTarget, accounts: [CreditCardAccount], today: LocalDate,
                        timeZone: TimeZone = CardPilotUI.homeTimeZone) throws -> (CreditCardAccount, BillingCycle) {
        guard let account = accounts.first(where: { $0.id == target.accountID }),
              target.cycleKey >= account.trackingStartCycleKey
                || account.billingCycles.contains(where: { $0.cycleKey == target.cycleKey }) else {
            throw ActionError.missingTarget
        }
        let cycle = try BillingCalculator.calculate(account: account, cycleKey: target.cycleKey,
            record: account.billingCycles.first { $0.cycleKey == target.cycleKey }, today: today, timeZone: timeZone)
        return (account, cycle)
    }

    enum Change {
        case repayment(Date?)
        case dates(statement: Int?, repayment: Int?)
    }

    static func save(_ change: Change, account: CreditCardAccount, cycleKey: Int, context: ModelContext,
                     today: LocalDate, timeZone: TimeZone = CardPilotUI.homeTimeZone,
                     persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        _ = try resolve(.init(accountID: account.id, cycleKey: cycleKey), accounts: [account], today: today, timeZone: timeZone)
        // Query before writing as well as validating the inverse relationship's uniqueness.
        let accountID = account.id
        let matches = try context.fetch(FetchDescriptor<BillingCycleRecord>(predicate: #Predicate {
            $0.account?.id == accountID && $0.cycleKey == cycleKey
        }))
        guard matches.count <= 1 else { throw ModelValidationError.duplicateBillingCycle }
        let existing = matches.first
        let previousStatement = existing?.statementDateOverride
        let previousRepayment = existing?.repaymentDateOverride
        let previousRepaidAt = existing?.repaidAt
        var statement = previousStatement
        var repayment = previousRepayment
        var repaidAt = previousRepaidAt
        switch change {
        case .repayment(let date): repaidAt = date
        case .dates(let newStatement, let newRepayment):
            statement = newStatement
            repayment = newRepayment
        }

        // Reject invalid input as values, before creating a SwiftData object or touching
        // its inverse. rollback() alone can leave a newly inserted record in that array.
        _ = try BillingCalculator.calculate(
            accountStatus: account.status,
            closedOn: try account.closedOn.map { try LocalDate(rawValue: $0) },
            cycleKey: cycleKey,
            rules: account.billingRuleVersions.map {
                BillingRuleInput(effectiveCycleKey: $0.effectiveCycleKey, statementDay: $0.statementDay,
                                 repaymentKind: $0.repaymentKind, repaymentValue: $0.repaymentValue)
            },
            override: BillingCycleOverride(statementDate: try statement.map { try LocalDate(rawValue: $0) },
                                           repaymentDate: try repayment.map { try LocalDate(rawValue: $0) },
                                           repaidAt: repaidAt),
            today: today, timeZone: timeZone
        )
        guard existing != nil || statement != nil || repayment != nil || repaidAt != nil else { return }
        let previousCycles = account.billingCycles
        let record = existing ?? BillingCycleRecord(account: account, cycleKey: cycleKey)
        if existing == nil { context.insert(record) }
        do {
            record.statementDateOverride = statement
            record.repaymentDateOverride = repayment
            record.repaidAt = repaidAt
            if repaidAt == nil && statement == nil && repayment == nil { context.delete(record) }
            try persist(context)
            let defaults = UserDefaults.standard
            defaults.set(defaults.integer(forKey: "cardPilot.notificationRevision") &+ 1,
                         forKey: "cardPilot.notificationRevision")
        } catch {
            // Restore both sides before rollback, including the failed-insert path.
            record.statementDateOverride = previousStatement
            record.repaymentDateOverride = previousRepayment
            record.repaidAt = previousRepaidAt
            record.account = existing == nil ? nil : account
            account.billingCycles = previousCycles
            context.rollback()
            throw error
        }
    }

    enum ActionError: LocalizedError {
        case missingTarget
        var errorDescription: String? { "该账户或账期已不存在，请返回查看当前账户。" }
    }
}

struct BillingCycleDestination: View {
    let target: BillingCycleTarget
    @Query private var accounts: [CreditCardAccount]

    var body: some View {
        if let (account, _) = try? BillingCycleActions.resolve(target, accounts: accounts,
                                                             today: CardPilotUI.localDate(from: .now)) {
            BillingCycleDetailView(account: account, cycleKey: target.cycleKey)
        } else {
            ContentUnavailableView("无法打开账期", systemImage: "calendar.badge.exclamationmark",
                                   description: Text("账户或账期可能已删除、关闭或被恢复的数据替换。请返回查看当前账户。"))
        }
    }
}

struct BillingCycleDetailView: View {
    let account: CreditCardAccount
    let cycleKey: Int
    @Environment(\.modelContext) private var context
    @State private var showingDates = false
    @State private var errorMessage: String?
    @State private var feedback: String?
    private var today: LocalDate { CardPilotUI.localDate(from: .now) }
    private var cycle: BillingCycle? {
        try? BillingCalculator.calculate(account: account, cycleKey: cycleKey,
            record: account.billingCycles.first { $0.cycleKey == cycleKey }, today: today, timeZone: CardPilotUI.homeTimeZone)
    }

    var body: some View {
        List {
            Section {
                Text(CardPilotUI.accountName(account)).font(.headline)
                Text("\(CardPilotUI.monthKeyText(cycleKey))账期")
                if account.cards.count > 1 {
                    Text("此账户的 \(account.cards.count) 张卡共用本期还款状态。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let cycle {
                Section("本期日程") {
                    LabeledContent("账单日", value: CardPilotUI.dateText(cycle.statementDate))
                    LabeledContent("还款日", value: CardPilotUI.dateText(cycle.repaymentDate))
                    LabeledContent("状态", value: cycle.status == .paid ? "已还款" : cycle.status == .overdue ? "已逾期" : "待还款")
                    if let date = cycle.repaidAt {
                        LabeledContent("标记时间") { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                    }
                }
                Section {
                    if cycle.status == .paid {
                        Button("撤销已还款") { save(.repayment(nil), feedback: "已撤销，还款提醒将重新计算。") }
                    } else {
                        Button("标记已还", systemImage: "checkmark.circle") {
                            save(.repayment(.now), feedback: "已标记已还款，可在此撤销。")
                        }
                    }
                    Button("调整本期日期", systemImage: "calendar") { showingDates = true }
                    if let feedback { Text(feedback).font(.footnote).foregroundStyle(.secondary) }
                } footer: {
                    Text("确认本期已全部处理后再标记已还；此操作不创建交易记录。日期调整只影响本期。")
                }
                Section {
                    NavigationLink("查看账户") { AccountDetailView(account: account) }
                }
            } else {
                Text("本期日期无法计算，请查看账户规则。")
                NavigationLink("查看账户") { AccountDetailView(account: account) }
            }
        }
        .navigationTitle("账期详情")
        .navigationBarTitleDisplayMode(.inline)
        .trackedSheet(isPresented: $showingDates) {
            if let cycle { BillingCycleDatesEditor(account: account, cycle: cycle) }
        }
        .alert("无法保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "请重试。") }
    }

    private func save(_ change: BillingCycleActions.Change, feedback: String) {
        do {
            try BillingCycleActions.save(change, account: account, cycleKey: cycleKey, context: context, today: today)
            self.feedback = feedback
        } catch { errorMessage = "保存失败，请核对账户规则和本期日期后重试。" }
    }
}

private struct BillingCycleDatesEditor: View {
    let account: CreditCardAccount
    let cycle: BillingCycle
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var overrideStatement: Bool
    @State private var overrideRepayment: Bool
    @State private var statement: Date
    @State private var repayment: Date
    @State private var errorMessage: String?

    init(account: CreditCardAccount, cycle: BillingCycle) {
        self.account = account
        self.cycle = cycle
        let record = account.billingCycles.first { $0.cycleKey == cycle.cycleKey }
        _overrideStatement = State(initialValue: record?.statementDateOverride != nil)
        _overrideRepayment = State(initialValue: record?.repaymentDateOverride != nil)
        _statement = State(initialValue: cycle.statementDate.date(in: CardPilotUI.homeTimeZone))
        _repayment = State(initialValue: cycle.repaymentDate.date(in: CardPilotUI.homeTimeZone))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(CardPilotUI.accountName(account))
                    Text("\(CardPilotUI.monthKeyText(cycle.cycleKey))账期")
                }
                Section {
                    Toggle("调整账单日", isOn: $overrideStatement)
                    if overrideStatement { DatePicker("账单日", selection: $statement, displayedComponents: .date) }
                    Toggle("调整还款日", isOn: $overrideRepayment)
                    if overrideRepayment { DatePicker("还款日", selection: $repayment, displayedComponents: .date) }
                } footer: {
                    Text("关闭调整后恢复规则计算；调整账单日后，未单独调整的还款日会随之重新推算。")
                }
            }
            .navigationTitle("调整本期日期")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditorCancelButton() }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "请重试。") }
        }
        .protectEdits(snapshot: editorSnapshot(overrideStatement, overrideRepayment, statement, repayment))
    }

    private func save() {
        do {
            try BillingCycleActions.save(.dates(statement: overrideStatement ? CardPilotUI.rawDate(statement) : nil,
                                               repayment: overrideRepayment ? CardPilotUI.rawDate(repayment) : nil),
                account: account, cycleKey: cycle.cycleKey, context: context, today: CardPilotUI.localDate(from: .now))
            dismiss()
        } catch { errorMessage = "请确认还款日晚于账单日，且账单日不晚于账户关闭日期。账户规则也必须有效。" }
    }
}
