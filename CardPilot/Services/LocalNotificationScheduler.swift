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
    var nextScheduledDate: Date? = nil
    var firstOmittedDate: Date? = nil
}

@MainActor
protocol NotificationClient {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingRequests() async -> [UNNotificationRequest]
    func removeRequests(withIdentifiers identifiers: [String])
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
struct SystemNotificationClient: NotificationClient {
    var center = UNUserNotificationCenter.current()

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func removeRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}

@MainActor
final class LocalNotificationScheduler {
    nonisolated static let identifierPrefix = "cardpilot."
    // Keep a bounded chronological window; a later request must never hide an earlier omission.
    nonisolated static let requestLimit = 48

    private let client: any NotificationClient
    private var revision = 0
    private var rebuildTask: Task<NotificationScheduleResult, Error>?

    init(client: (any NotificationClient)? = nil) {
        self.client = client ?? SystemNotificationClient()
    }

    @discardableResult
    func requestAuthorization() async throws -> Bool {
        try await client.requestAuthorization()
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await client.authorizationStatus()
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
        try Task.checkCancellation()
        revision += 1
        let currentRevision = revision
        let previous = rebuildTask
        let task = Task { @MainActor in
            // Await the preceding writer, even if superseded while an OS add was in flight.
            _ = try? await previous?.value
            guard currentRevision == self.revision else { throw CancellationError() }
            return try await self.apply(plans, revision: currentRevision, timeZone: timeZone)
        }
        rebuildTask = task
        defer { if revision == currentRevision { rebuildTask = nil } }
        let result = try await task.value
        try Task.checkCancellation()
        return result
    }

    private func apply(_ plans: [ReminderPlan], revision: Int, timeZone: TimeZone) async throws -> NotificationScheduleResult {
        let selected = Array(plans.prefix(Self.requestLimit))
        let desiredIDs = Set(selected.map(\.identifier))
        let pending = await client.pendingRequests()
        guard revision == self.revision else { throw CancellationError() }
        // Remove paid/changed reminders immediately, but retain still-valid requests if an add fails.
        client.removeRequests(withIdentifiers: pending.map(\.identifier).filter {
            Self.owns($0) && !desiredIDs.contains($0)
        })

        for plan in selected {
            guard revision == self.revision else { throw CancellationError() }
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["accountID": plan.accountID.uuidString, "cycleKey": plan.cycleKey]
            var components = LocalDate.calendar(timeZone: timeZone)
                .dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            components.timeZone = timeZone
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try await client.add(request)
        }
        guard revision == self.revision else { throw CancellationError() }
        return Self.scheduleResult(for: plans)
    }

    static func scheduleResult(for plans: [ReminderPlan], limit: Int = requestLimit) -> NotificationScheduleResult {
        let scheduled = min(plans.count, max(0, limit))
        return NotificationScheduleResult(
            scheduledCount: scheduled,
            omittedCount: max(0, plans.count - scheduled),
            lastScheduledDate: plans.prefix(scheduled).map(\.fireDate).max(),
            nextScheduledDate: plans.prefix(scheduled).map(\.fireDate).min(),
            firstOmittedDate: plans.dropFirst(scheduled).map(\.fireDate).min()
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
        return plans.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            if $0.event != $1.event { return $0.event == .repayment }
            return $0.identifier < $1.identifier
        }
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
        let firstOmittedDate = result.firstOmittedDate.map {
            LocalDate(date: $0, timeZone: timeZone).description
        } ?? "未知日期"
        return "已安排 \(result.scheduledCount) 条提醒；从 \(firstOmittedDate) 起另有 \(result.omittedCount) 条尚未安排。请减少提醒节点或稍后重新打开应用刷新。"
    @unknown default:
        return result.omittedCount > 0 ? "通知权限状态未知，另有 \(result.omittedCount) 条待刷新。" : "通知权限状态未知。"
    }
}
