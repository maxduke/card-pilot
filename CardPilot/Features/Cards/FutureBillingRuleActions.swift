import Foundation
import SwiftData

enum FutureBillingRuleCancellation {
    enum CancellationError: LocalizedError, Equatable {
        case alreadyEffective
        case missingRule
        case invalidDates(Int)

        var errorDescription: String? {
            switch self {
            case .alreadyEffective: "仅可取消尚未生效的规则，当前与历史规则会保留。"
            case .missingRule: "这项规则计划已不存在，请返回查看当前账户。"
            case .invalidDates(let cycleKey): "取消后，\(CardPilotUI.monthKeyText(cycleKey))账期的还款日不晚于账单日。请先调整该账期的日期，再取消规则计划。"
            }
        }
    }

    static func remainingRules(removing effectiveCycleKey: Int?, rules: [BillingRuleInput],
                               overrides: [Int: BillingCycleOverride], today: LocalDate,
                               timeZone: TimeZone) throws -> [BillingRuleInput] {
        guard let effectiveCycleKey, LocalDate.isValidMonthKey(effectiveCycleKey),
              effectiveCycleKey > today.monthKey else { throw CancellationError.alreadyEffective }
        let matches = rules.filter { $0.effectiveCycleKey == effectiveCycleKey }
        guard !matches.isEmpty else { throw CancellationError.missingRule }
        guard matches.count == 1 else { throw BillingCalculationError.duplicateEffectiveRule }
        let remaining = rules.filter { $0.effectiveCycleKey != effectiveCycleKey }
        // Check the remaining rule set before mutating any persisted relationship.
        _ = try BillingCalculator.calculate(accountStatus: .active, closedOn: nil,
                                            cycleKey: effectiveCycleKey, rules: remaining,
                                            today: today, timeZone: timeZone)
        for (cycleKey, dates) in overrides.sorted(by: { $0.key < $1.key }) {
            guard BillingCalculator.applicableRule(from: rules, forCycleKey: cycleKey)?.effectiveCycleKey == effectiveCycleKey else {
                continue
            }
            do {
                // Closure affects visibility, not the consistency of saved dates.
                _ = try BillingCalculator.calculate(accountStatus: .active, closedOn: nil,
                                                    cycleKey: cycleKey, rules: remaining, override: dates,
                                                    today: today, timeZone: timeZone)
            } catch BillingCalculationError.invalidOverride {
                throw CancellationError.invalidDates(cycleKey)
            }
        }
        return remaining
    }
}

@MainActor
enum FutureBillingRuleActions {
    static func cancel(ruleID: UUID, account: CreditCardAccount, context: ModelContext,
                       today: LocalDate, timeZone: TimeZone = CardPilotUI.homeTimeZone,
                       persist: (ModelContext) throws -> Void = { try $0.save() }) throws {
        try account.validate()
        try account.validateBillingConfiguration()
        let matches = try context.fetch(FetchDescriptor<BillingRuleVersion>(predicate: #Predicate { $0.id == ruleID }))
        guard matches.count == 1, let rule = matches.first, rule.account?.id == account.id,
              account.billingRuleVersions.contains(where: { $0.id == ruleID }) else {
            throw FutureBillingRuleCancellation.CancellationError.missingRule
        }
        let overrides = try Dictionary(uniqueKeysWithValues: account.billingCycles.map { record in
            (record.cycleKey, BillingCycleOverride(
                statementDate: try record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                repaymentDate: try record.repaymentDateOverride.map { try LocalDate(rawValue: $0) },
                repaidAt: record.repaidAt
            ))
        })
        _ = try FutureBillingRuleCancellation.remainingRules(
            removing: rule.effectiveCycleKey, rules: account.billingRuleVersions.map(\.billingRuleInput),
            overrides: overrides, today: today, timeZone: timeZone
        )
        let previousRules = account.billingRuleVersions
        do {
            account.billingRuleVersions.removeAll { $0.id == ruleID }
            rule.account = nil
            context.delete(rule)
            try account.validateBillingConfiguration()
            try persist(context)
            let defaults = UserDefaults.standard
            defaults.set(defaults.integer(forKey: "cardPilot.notificationRevision") &+ 1,
                         forKey: "cardPilot.notificationRevision")
        } catch {
            rule.account = account
            account.billingRuleVersions = previousRules
            context.rollback()
            throw error
        }
    }
}
