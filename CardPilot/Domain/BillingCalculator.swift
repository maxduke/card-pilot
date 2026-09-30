import Foundation

struct BillingRuleInput: Equatable {
    let effectiveCycleKey: Int?
    let statementDay: Int
    let repaymentKind: RepaymentRuleKind
    let repaymentValue: Int

    func hasSameSchedule(as other: BillingRuleInput) -> Bool {
        statementDay == other.statementDay
            && repaymentKind == other.repaymentKind
            && repaymentValue == other.repaymentValue
    }

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

    func requiresRecord(cycleKey: Int, trackingStartCycleKey: Int) -> Bool {
        // An earlier cycle needs its identity retained even after repayment is undone.
        cycleKey < trackingStartCycleKey || statementDate != nil || repaymentDate != nil || repaidAt != nil
    }
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
    /// Include an earlier bill that is still due, without inventing pre-onboarding overdue history.
    static func initialCycle(
        rule: BillingRuleInput,
        today: LocalDate,
        timeZone: TimeZone = .current
    ) throws -> BillingCycle {
        try rule.validate()
        guard rule.effectiveCycleKey == nil else { throw BillingCalculationError.invalidRule }
        let current = try calculate(accountStatus: .active, closedOn: nil, cycleKey: today.monthKey,
                                    rules: [rule], today: today, timeZone: timeZone)
        let availableMonths = (today.year - 1) * 12 + today.month - 1
        let lookback = min(availableMonths, rule.repaymentKind == .fixedDay ? 1
            : rule.repaymentValue / 28 + (rule.repaymentValue % 28 == 0 ? 0 : 1))
        for offset in stride(from: lookback, through: 1, by: -1) {
            guard let month = today.addingMonthsIfPossible(-offset, timeZone: timeZone) else { continue }
            let cycle = try calculate(accountStatus: .active, closedOn: nil, cycleKey: month.monthKey,
                                      rules: [rule], today: today, timeZone: timeZone)
            if cycle.repaymentDate >= today { return cycle }
        }
        return current
    }

    /// Only explicit rule edits can schedule or correct a future version; unrelated edits are a no-op.
    static func futureRuleChange(
        initial: BillingRuleInput,
        requested: BillingRuleInput,
        rules: [BillingRuleInput],
        currentMonthKey: Int
    ) throws -> BillingRuleInput? {
        guard initial != requested else { return nil }
        try requested.validate()
        guard LocalDate.isValidMonthKey(currentMonthKey),
              let effectiveCycleKey = requested.effectiveCycleKey else {
            throw ModelValidationError.invalidCycleKey
        }
        guard effectiveCycleKey > currentMonthKey else {
            throw ModelValidationError.effectiveCycleMustBeFuture
        }
        guard let applicable = applicableRule(from: rules, forCycleKey: effectiveCycleKey) else {
            throw BillingCalculationError.noApplicableRule
        }
        return requested.hasSameSchedule(as: applicable) ? nil : requested
    }

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

        guard let rule = applicableRule(from: rules, forCycleKey: cycleKey) else {
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
        guard repaymentDate > statementDate else { throw BillingCalculationError.invalidOverride }
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
        try account.validate()
        try account.validateBillingConfiguration()
        let rules = account.billingRuleVersions.map {
            BillingRuleInput(
                effectiveCycleKey: $0.effectiveCycleKey,
                statementDay: $0.statementDay,
                repaymentKind: $0.repaymentKind,
                repaymentValue: $0.repaymentValue
            )
        }
        let override: BillingCycleOverride?
        if let record {
            guard record.cycleKey == cycleKey else { throw BillingCalculationError.invalidOverride }
            try record.validate()
            override = BillingCycleOverride(
                statementDate: try record.statementDateOverride.map { try LocalDate(rawValue: $0) },
                repaymentDate: try record.repaymentDateOverride.map { try LocalDate(rawValue: $0) },
                repaidAt: record.repaidAt
            )
        } else {
            override = nil
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

    static func applicableRule(
        from rules: [BillingRuleInput],
        forCycleKey cycleKey: Int
    ) -> BillingRuleInput? {
        rules
            .filter {
                guard let effectiveCycleKey = $0.effectiveCycleKey else { return true }
                return effectiveCycleKey <= cycleKey
            }
            .max { effectiveKey($0) < effectiveKey($1) }
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
