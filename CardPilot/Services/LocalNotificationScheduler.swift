import Foundation
import UserNotifications

struct BillingReminderCycle: Equatable {
    let accountID: UUID
    let accountName: String
    let cycle: BillingCycle
}

struct NotificationScheduleResult: Equatable {
    let scheduledCount: Int
    let omittedCount: Int
    let lastScheduledDate: Date?
}

@MainActor
final class LocalNotificationScheduler {
    static let identifierPrefix = "cardpilot."
    // ponytail: use a 48-request rolling window; add background refresh only if real usage exhausts it.
    static let requestLimit = 48

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func rebuild(
        cycles: [BillingReminderCycle],
        statementOffsets: [Int],
        repaymentOffsets: [Int],
        reminderHour: Int,
        reminderMinute: Int,
        timeZone: TimeZone,
        now: Date = .now
    ) async throws -> NotificationScheduleResult {
        let plans = try Self.plans(
            cycles: cycles,
            statementOffsets: statementOffsets,
            repaymentOffsets: repaymentOffsets,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            timeZone: timeZone,
            now: now
        )
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: Array(pending.lazy.map(\.identifier).filter(Self.owns))
        )

        for plan in plans.prefix(Self.requestLimit) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            var components = LocalDate.calendar(timeZone: timeZone)
                .dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            components.timeZone = timeZone
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try await center.add(request)
        }

        let scheduled = min(plans.count, Self.requestLimit)
        return NotificationScheduleResult(
            scheduledCount: scheduled,
            omittedCount: max(0, plans.count - scheduled),
            lastScheduledDate: plans.prefix(scheduled).map(\.fireDate).max()
        )
    }

    static func owns(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    static func plans(
        cycles: [BillingReminderCycle],
        statementOffsets: [Int],
        repaymentOffsets: [Int],
        reminderHour: Int,
        reminderMinute: Int,
        timeZone: TimeZone,
        now: Date
    ) throws -> [ReminderPlan] {
        guard (0...23).contains(reminderHour), (0...59).contains(reminderMinute) else {
            throw SchedulingError.invalidTime
        }

        var plans: [ReminderPlan] = []
        for item in cycles {
            for (event, date, offsets) in [
                (ReminderEvent.statement, item.cycle.statementDate, statementOffsets),
                (ReminderEvent.repayment, item.cycle.repaymentDate, repaymentOffsets)
            ] {
                guard event == .statement || item.cycle.status != .paid else { continue }
                for offset in Set(offsets.filter { $0 >= 0 }).sorted() {
                    let reminderDate = date.addingDays(-offset, timeZone: timeZone)
                    var components = DateComponents(
                        timeZone: timeZone,
                        year: reminderDate.year,
                        month: reminderDate.month,
                        day: reminderDate.day,
                        hour: reminderHour,
                        minute: reminderMinute
                    )
                    components.calendar = LocalDate.calendar(timeZone: timeZone)
                    guard let fireDate = components.date, fireDate > now else { continue }
                    plans.append(ReminderPlan(
                        accountID: item.accountID,
                        cycleKey: item.cycle.cycleKey,
                        event: event,
                        identifier: "\(identifierPrefix)\(item.accountID.uuidString).\(item.cycle.cycleKey).\(event.rawValue).\(offset)",
                        title: event == .statement ? "CardPilot 账单日提醒" : "CardPilot 还款日提醒",
                        body: offset == 0
                            ? "\(item.accountName)今天\(event.action)。"
                            : "\(item.accountName)将在 \(offset) 天后\(event.action)（\(date)）。",
                        fireDate: fireDate
                    ))
                }
            }
        }
        var groups = Dictionary(grouping: plans, by: \.accountID).mapValues { plans in
            plans.sorted {
                $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
            }
        }
        let accountIDs = groups.keys.sorted { $0.uuidString < $1.uuidString }
        var priorityPlans: [ReminderPlan] = []
        for accountID in accountIDs {
            guard var group = groups[accountID] else { continue }
            for event in [ReminderEvent.statement, .repayment] {
                guard let index = group.firstIndex(where: { $0.event == event }) else { continue }
                priorityPlans.append(group.remove(at: index))
            }
            groups[accountID] = group
        }
        priorityPlans.sort {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }
        var fairPlans: [ReminderPlan] = []
        while groups.values.contains(where: { !$0.isEmpty }) {
            for accountID in accountIDs {
                guard var group = groups[accountID], !group.isEmpty else { continue }
                fairPlans.append(group.removeFirst())
                groups[accountID] = group
            }
        }
        return priorityPlans + fairPlans
    }

    struct ReminderPlan: Equatable {
        let accountID: UUID
        let cycleKey: Int
        let event: ReminderEvent
        let identifier: String
        let title: String
        let body: String
        let fireDate: Date
    }

    enum SchedulingError: Error, Equatable {
        case invalidTime
    }

    enum ReminderEvent: String, Equatable {
        case statement
        case repayment

        var action: String { self == .statement ? "出账" : "到期还款" }
    }
}

func notificationWarningMessage(
    status: UNAuthorizationStatus,
    result: NotificationScheduleResult,
    timeZone: TimeZone
) -> String {
    switch status {
    case .denied:
        return "通知权限已关闭，请前往系统设置开启。"
    case .notDetermined:
        return "尚未授权通知权限。"
    case .authorized, .provisional, .ephemeral:
        guard result.omittedCount > 0 else { return "" }
        let lastDate = result.lastScheduledDate.map {
            LocalDate(date: $0, timeZone: timeZone).description
        } ?? "未知日期"
        return "通知仅安排至 \(lastDate)，另有 \(result.omittedCount) 条待刷新。"
    @unknown default:
        return result.omittedCount > 0 ? "通知权限状态未知，另有 \(result.omittedCount) 条待刷新。" : "通知权限状态未知。"
    }
}
