import SwiftData
import SwiftUI

struct FutureBillingRuleView: View {
    let account: CreditCardAccount
    let ruleID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.currentDay) private var currentDay
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Bank.name) private var banks: [Bank]
    @State private var showingEditor = false
    @State private var confirmingCancellation = false
    @State private var errorMessage: String?

    private var scheduledRule: BillingRuleVersion? {
        account.billingRuleVersions.first {
            $0.id == ruleID && ($0.effectiveCycleKey ?? Int.min) > currentDay.today.monthKey
        }
    }

    private struct Preview {
        let fallback: BillingRuleVersion
        let next: BillingRuleVersion?
        let before: BillingCycle
        let after: BillingCycle
    }

    var body: some View {
        Group {
            if let rule = scheduledRule {
                let preview = Result { try cancellationPreview(for: rule) }
                let canCancel = if case .success = preview { true } else { false }
                List {
                    Section("规则计划") {
                        BillingRuleRow(rule: rule, title: "\(CardPilotUI.monthKeyText(rule.effectiveCycleKey)) 起生效")
                    }
                    switch preview {
                    case .success(let value):
                        Section("取消后采用") {
                            BillingRuleRow(rule: value.fallback,
                                           title: value.fallback.effectiveCycleKey.map { "\(CardPilotUI.monthKeyText($0)) 起的规则" } ?? "基础规则")
                            if let next = value.next {
                                Text("之后 \(CardPilotUI.monthKeyText(next.effectiveCycleKey)) 起的规则仍按计划生效。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("此后沿用这版规则，直到另行设置新的计划。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section("生效账期日期预览") {
                            previewDates("账单日", before: value.before.statementDate, after: value.after.statementDate)
                            previewDates("还款日", before: value.before.repaymentDate, after: value.after.repaymentDate)
                        }
                    case .failure(let error):
                        Section("取消前需处理") {
                            Label((error as? LocalizedError)?.errorDescription ?? "无法根据剩余规则推算日期，请先检查账户规则与日期覆盖。",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if case FutureBillingRuleCancellation.CancellationError.invalidDates(let cycleKey) = error {
                                NavigationLink("调整相关账期") {
                                    BillingCycleDetailView(account: account, cycleKey: cycleKey)
                                }
                            }
                        }
                    }
                    Section {
                        Button("修正规则计划", systemImage: "pencil") { showingEditor = true }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("account.rule.edit")
                        Button("取消规则计划", role: .destructive) { confirmingCancellation = true }
                            .frame(minHeight: 44)
                            .disabled(!canCancel)
                            .accessibilityIdentifier("account.rule.cancel")
                    } footer: {
                        Text("只取消所选的未来版本。当前与历史规则、已有账期日期覆盖、还款状态及之后的其他计划均保留。日期按规则推算，不代表银行实际账单。")
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("计划已生效或已取消", systemImage: "calendar.badge.clock",
                                       description: Text("请返回账户查看当前规则；已生效的历史规则不能取消。"))
            }
        }
        .navigationTitle("规则计划")
        .navigationBarTitleDisplayMode(.inline)
        .trackedSheet(isPresented: $showingEditor) {
            if let rule = scheduledRule {
                AccountEditorView(account: account, banks: banks, initialScheduledRule: rule)
            }
        }
        .confirmationDialog("确认取消这项未来规则？", isPresented: $confirmingCancellation, titleVisibility: .visible) {
            Button("取消规则计划", role: .destructive) { cancel() }
            Button("保留计划", role: .cancel) {}
        } message: {
            Text("取消后采用页面所示规则。当前与历史账期、日期覆盖和其他计划均保留；还款提醒会重新计算。")
        }
        .alert("未取消规则", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(errorMessage ?? "请返回查看账户规则。") }
    }

    private func previewDates(_ title: String, before: LocalDate, after: LocalDate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text("当前计划：\(CardPilotUI.dateText(before))")
            Text("取消后：\(CardPilotUI.dateText(after))")
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    private func cancellationPreview(for rule: BillingRuleVersion) throws -> Preview {
        try account.validateBillingConfiguration()
        guard let effective = rule.effectiveCycleKey else {
            throw FutureBillingRuleCancellation.CancellationError.alreadyEffective
        }
        let overrides = try Dictionary(uniqueKeysWithValues: account.billingCycles.map { record in
            (record.cycleKey, BillingCycleOverride(
                statementDate: try record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                repaymentDate: try record.repaymentDateOverride.map { try LocalDate(rawValue: $0) },
                repaidAt: record.repaidAt
            ))
        })
        let inputs = account.billingRuleVersions.map(\.billingRuleInput)
        let remaining = try FutureBillingRuleCancellation.remainingRules(removing: effective, rules: inputs,
            overrides: overrides, today: currentDay.today, timeZone: CardPilotUI.homeTimeZone)
        guard let fallback = BillingCalculator.applicableRule(from: remaining, forCycleKey: effective),
              let fallbackModel = account.billingRuleVersions.first(where: { $0.effectiveCycleKey == fallback.effectiveCycleKey }) else {
            throw BillingCalculationError.noApplicableRule
        }
        let next = account.billingRuleVersions.filter { ($0.effectiveCycleKey ?? Int.min) > effective }
            .min { ($0.effectiveCycleKey ?? Int.max) < ($1.effectiveCycleKey ?? Int.max) }
        let before = try BillingCalculator.calculate(accountStatus: .active, closedOn: nil, cycleKey: effective,
            rules: inputs, override: overrides[effective], today: currentDay.today, timeZone: CardPilotUI.homeTimeZone)
        let after = try BillingCalculator.calculate(accountStatus: .active, closedOn: nil, cycleKey: effective,
            rules: remaining, override: overrides[effective], today: currentDay.today, timeZone: CardPilotUI.homeTimeZone)
        return Preview(fallback: fallbackModel, next: next, before: before, after: after)
    }

    private func cancel() {
        do {
            try FutureBillingRuleActions.cancel(ruleID: ruleID, account: account, context: context, today: currentDay.today)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "取消失败，规则与账期未改变。请检查设备空间后重试。"
        }
    }
}
