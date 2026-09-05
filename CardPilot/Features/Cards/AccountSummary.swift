import Foundation

struct CardAccountBillingSummary: Equatable {
    let nextStatementDate: LocalDate?
    let nextRepaymentDate: LocalDate?
    let nextRepaymentStatus: BillingCycle.Status?
}

enum CardAccountBillingSummaryCalculator {
    static func calculate(
        status: CreditCardAccountStatus,
        closedOn: LocalDate?,
        trackingStartCycleKey: Int,
        rules: [BillingRuleInput],
        overrides: [Int: BillingCycleOverride] = [:],
        today: LocalDate,
        timeZone: TimeZone
    ) -> CardAccountBillingSummary {
        guard LocalDate.isValidMonthKey(trackingStartCycleKey) else {
            return CardAccountBillingSummary(nextStatementDate: nil, nextRepaymentDate: nil, nextRepaymentStatus: nil)
        }

        let nearbyEnd = today.addingMonths(2, timeZone: timeZone).monthKey
        let nearbyCycleKeys = LocalDate.monthKeys(from: trackingStartCycleKey, through: nearbyEnd)
        let savedCycleKeys = overrides.compactMap { cycleKey, override in
            override.repaidAt == nil ? cycleKey : nil
        }
        let cycleKeys = Set(nearbyCycleKeys + savedCycleKeys).sorted()

        var nextStatement: LocalDate?
        var nextRepayment: BillingCycle?
        for cycleKey in cycleKeys {
            guard let cycle = try? BillingCalculator.calculate(
                accountStatus: status,
                closedOn: closedOn,
                cycleKey: cycleKey,
                rules: rules,
                override: overrides[cycleKey],
                today: today,
                timeZone: timeZone
            ) else { continue }

            if status == .active, cycle.statementDate >= today,
               nextStatement == nil || cycle.statementDate < nextStatement! {
                nextStatement = cycle.statementDate
            }

            guard cycle.status != .paid,
                  cycle.repaymentDate >= today || cycle.status == .overdue else { continue }
            if nextRepayment == nil || isEarlier(cycle, than: nextRepayment!) {
                nextRepayment = cycle
            }
        }

        return CardAccountBillingSummary(
            nextStatementDate: nextStatement,
            nextRepaymentDate: nextRepayment?.repaymentDate,
            nextRepaymentStatus: nextRepayment?.status
        )
    }

    private static func isEarlier(_ lhs: BillingCycle, than rhs: BillingCycle) -> Bool {
        lhs.repaymentDate == rhs.repaymentDate ? lhs.cycleKey < rhs.cycleKey : lhs.repaymentDate < rhs.repaymentDate
    }
}

func accountBillingSummary(
    _ account: CreditCardAccount,
    today: LocalDate = CardPilotUI.localDate(from: Date()),
    timeZone: TimeZone = CardPilotUI.homeTimeZone
) -> CardAccountBillingSummary {
    let overrides = account.billingCycles.reduce(into: [Int: BillingCycleOverride]()) { result, record in
        guard result[record.cycleKey] == nil else { return }
        result[record.cycleKey] = BillingCycleOverride(
            statementDate: record.statementDateOverride.flatMap { try? LocalDate(rawValue: $0) },
            repaymentDate: record.repaymentDateOverride.flatMap { try? LocalDate(rawValue: $0) },
            repaidAt: record.repaidAt
        )
    }
    return CardAccountBillingSummaryCalculator.calculate(
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
        overrides: overrides,
        today: today,
        timeZone: timeZone
    )
}
