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
        let savedCycleKeys = overrides.keys.filter { $0 >= trackingStartCycleKey }
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
