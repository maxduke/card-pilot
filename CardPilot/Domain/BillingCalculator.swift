import Foundation

struct BillingRuleInput: Equatable {
    let effectiveCycleKey: Int?
    let statementDay: Int
    let repaymentKind: RepaymentRuleKind
    let repaymentValue: Int

    func validate() throws {
        guard (1...31).contains(statementDay) else { throw BillingCalculationError.invalidRule }
        switch repaymentKind {
        case .fixedDay:
            guard (1...31).contains(repaymentValue) else { throw BillingCalculationError.invalidRule }
        case .daysAfterStatement:
            guard repaymentValue >= 1 else { throw BillingCalculationError.invalidRule }
        }
        if let effectiveCycleKey, !LocalDate.isValidMonthKey(effectiveCycleKey) {
            throw BillingCalculationError.invalidRule
        }
    }
}

struct BillingCycleOverride: Equatable {
    let statementDate: LocalDate?
    let repaymentDate: LocalDate?
    let repaidAt: Date?
}

struct BillingCycle: Equatable {
    enum Status: Equatable {
        case pending
        case overdue
        case paid
    }

    let cycleKey: Int
    let statementDate: LocalDate
    let repaymentDate: LocalDate
    let status: Status
    let repaidAt: Date?
}

enum BillingCalculationError: Error, Equatable {
    case invalidCycleKey
    case missingBaselineRule
    case duplicateBaselineRule
    case duplicateEffectiveRule
    case noApplicableRule
    case invalidRule
    case invalidAccountState
    case invalidOverride
    case accountClosed
}

enum BillingCalculator {
    static func calculate(
        accountStatus: CreditCardAccountStatus,
        closedOn: LocalDate?,
        cycleKey: Int,
        rules: [BillingRuleInput],
        override: BillingCycleOverride? = nil,
        today: LocalDate,
        timeZone: TimeZone = .current
    ) throws -> BillingCycle {
        guard LocalDate.isValidMonthKey(cycleKey) else { throw BillingCalculationError.invalidCycleKey }
        switch accountStatus {
        case .active:
            guard closedOn == nil else { throw BillingCalculationError.invalidAccountState }
        case .closed:
            guard closedOn != nil else { throw BillingCalculationError.invalidAccountState }
        }

        let baselineRules = rules.filter { $0.effectiveCycleKey == nil }
        guard !baselineRules.isEmpty else { throw BillingCalculationError.missingBaselineRule }
        guard baselineRules.count == 1 else { throw BillingCalculationError.duplicateBaselineRule }

        var seenEffectiveKeys = Set<Int>()
        for rule in rules {
            try rule.validate()
            if let effectiveCycleKey = rule.effectiveCycleKey,
               !seenEffectiveKeys.insert(effectiveCycleKey).inserted {
                throw BillingCalculationError.duplicateEffectiveRule
            }
        }

        let applicableRules = rules.filter {
            guard let effectiveCycleKey = $0.effectiveCycleKey else { return true }
            return effectiveCycleKey <= cycleKey
        }
        guard let rule = applicableRules.max(by: { effectiveKey($0) < effectiveKey($1) }) else {
            throw BillingCalculationError.noApplicableRule
        }

        let cycleStart = try LocalDate.firstDay(ofMonthKey: cycleKey)
        let calculatedStatementDate = try date(
            year: cycleStart.year,
            month: cycleStart.month,
            day: rule.statementDay,
            timeZone: timeZone
        )
        let statementDate = override?.statementDate ?? calculatedStatementDate

        if let closedOn, statementDate > closedOn {
            throw BillingCalculationError.accountClosed
        }

        let calculatedRepaymentDate: LocalDate
        switch rule.repaymentKind {
        case .daysAfterStatement:
            calculatedRepaymentDate = statementDate.addingDays(rule.repaymentValue, timeZone: timeZone)
        case .fixedDay:
            let sameMonth = try date(
                year: statementDate.year,
                month: statementDate.month,
                day: rule.repaymentValue,
                timeZone: timeZone
            )
            if sameMonth > statementDate {
                calculatedRepaymentDate = sameMonth
            } else {
                let nextMonth = statementDate.addingMonths(1, timeZone: timeZone)
                calculatedRepaymentDate = try date(
                    year: nextMonth.year,
                    month: nextMonth.month,
                    day: rule.repaymentValue,
                    timeZone: timeZone
                )
            }
        }

        let repaymentDate = override?.repaymentDate ?? calculatedRepaymentDate
        let repaidAt = override?.repaidAt
        let status: BillingCycle.Status
        if repaidAt != nil {
            status = .paid
        } else if today > repaymentDate {
            status = .overdue
        } else {
            status = .pending
        }
        return BillingCycle(
            cycleKey: cycleKey,
            statementDate: statementDate,
            repaymentDate: repaymentDate,
            status: status,
            repaidAt: repaidAt
        )
    }

    static func calculate(
        account: CreditCardAccount,
        cycleKey: Int,
        record: BillingCycleRecord? = nil,
        today: LocalDate,
        timeZone: TimeZone = .current
    ) throws -> BillingCycle {
        let rules = account.billingRuleVersions.map {
            BillingRuleInput(
                effectiveCycleKey: $0.effectiveCycleKey,
                statementDay: $0.statementDay,
                repaymentKind: $0.repaymentKind,
                repaymentValue: $0.repaymentValue
            )
        }
        let override = record.map {
            BillingCycleOverride(
                statementDate: $0.statementDateOverride.flatMap { try? LocalDate(rawValue: $0) },
                repaymentDate: $0.repaymentDateOverride.flatMap { try? LocalDate(rawValue: $0) },
                repaidAt: $0.repaidAt
            )
        }
        if let record, record.cycleKey != cycleKey {
            throw BillingCalculationError.invalidOverride
        }
        return try calculate(
            accountStatus: account.status,
            closedOn: account.closedOn.flatMap { try? LocalDate(rawValue: $0) },
            cycleKey: cycleKey,
            rules: rules,
            override: override,
            today: today,
            timeZone: timeZone
        )
    }

    private static func effectiveKey(_ rule: BillingRuleInput) -> Int {
        rule.effectiveCycleKey ?? Int.min
    }

    private static func date(year: Int, month: Int, day: Int, timeZone: TimeZone) throws -> LocalDate {
        let validDay = min(day, LocalDate.daysInMonth(year: year, month: month, timeZone: timeZone))
        guard validDay > 0 else { throw BillingCalculationError.invalidRule }
        return try LocalDate(year: year, month: month, day: validDay)
    }
}
