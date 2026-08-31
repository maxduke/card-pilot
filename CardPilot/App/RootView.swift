import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \CreditCardAccount.id) private var accounts: [CreditCardAccount]
    @AppStorage("cardPilot.statementReminderOffsets") private var statementOffsets = "7,3,1,0"
    @AppStorage("cardPilot.repaymentReminderOffsets") private var repaymentOffsets = "7,3,1,0"
    @AppStorage("cardPilot.reminderTime") private var reminderTime = "09:00"
    @AppStorage("cardPilot.homeTimeZone") private var homeTimeZone = TimeZone.current.identifier
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false
    @AppStorage("cardPilot.notificationWarning") private var notificationWarning = ""

    @StateObject private var appLock = AppLockController()
    @State private var selectedTab = Tab.dashboard
    @State private var showingSettings = false
    @State private var isAuthenticating = false
    @State private var authenticationAttempt = 0

    private let notificationScheduler = LocalNotificationScheduler()

    init() {
        _appLock = StateObject(wrappedValue: AppLockController(
            enabled: UserDefaults.standard.bool(forKey: "cardPilot.appLockEnabled")
        ))
    }

    enum Tab: Hashable {
        case dashboard
        case cards
        case promotions
        case transactions
    }

    var body: some View {
        Group {
            if appLock.isLocked {
                LockShield(isAuthenticating: isAuthenticating, unlock: authenticate)
            } else {
                TabView(selection: $selectedTab) {
                    DashboardView(showingSettings: $showingSettings)
                        .tabItem { Label("首页", systemImage: "rectangle.grid.2x2") }
                        .tag(Tab.dashboard)

                    CardsView()
                        .tabItem { Label("卡片", systemImage: "creditcard") }
                        .tag(Tab.cards)

                    PromotionsView()
                        .tabItem { Label("促销", systemImage: "gift") }
                        .tag(Tab.promotions)

                    TransactionsView()
                        .tabItem { Label("交易", systemImage: "list.bullet.rectangle") }
                        .tag(Tab.transactions)
                }
                .privacySensitive()
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                        .environmentObject(appLock)
                }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: homeTimeZone) ?? .current)
        .onAppear {
            if !appLock.setEnabled(appLockEnabled) { appLockEnabled = false }
            authenticate()
        }
        .onChange(of: appLock.isLocked) { _, locked in
            if locked { showingSettings = false }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if !appLock.setEnabled(enabled) { appLockEnabled = false }
            if enabled { authenticate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authenticate()
                Task { await rebuildNotifications() }
            } else {
                authenticationAttempt += 1
                isAuthenticating = false
                appLock.applicationDidEnterBackground()
            }
        }
        .task(id: notificationConfigurationKey) {
            await rebuildNotifications()
        }
    }

    private var notificationConfigurationKey: String {
        let accountKey = accounts.map { account in
            let rules = account.billingRuleVersions.map {
                "\($0.effectiveCycleKey ?? 0)-\($0.statementDay)-\($0.repaymentKindRaw)-\($0.repaymentValue)"
            }.sorted().joined(separator: ",")
            let cycles = account.billingCycles.map {
                "\($0.cycleKey)-\($0.statementDateOverride ?? 0)-\($0.repaymentDateOverride ?? 0)-\($0.repaidAt?.timeIntervalSince1970 ?? 0)"
            }.sorted().joined(separator: ",")
            return "\(account.id)-\(account.bank.name)-\(account.statusRaw)-\(account.closedOn ?? 0)-\(rules)-\(cycles)"
        }.joined(separator: "|")
        return "\(statementOffsets)|\(repaymentOffsets)|\(reminderTime)|\(homeTimeZone)|\(accountKey)"
    }

    private func authenticate() {
        guard appLock.isLocked, !isAuthenticating else { return }
        authenticationAttempt += 1
        let attempt = authenticationAttempt
        isAuthenticating = true
        Task {
            _ = await appLock.unlock()
            guard attempt == authenticationAttempt else { return }
            isAuthenticating = false
        }
    }

    private func rebuildNotifications() async {
        let parsedTime = CardPilotUI.parseReminderTime(reminderTime)
        let hour = parsedTime?.hour ?? 9
        let minute = parsedTime?.minute ?? 0
        let timeZone = TimeZone(identifier: homeTimeZone) ?? .current
        let today = LocalDate(date: .now, timeZone: timeZone)
        let maxReminderOffset = (parseOffsets(statementOffsets) + parseOffsets(repaymentOffsets)).max() ?? 0
        let reminderCycles = accounts.flatMap { account -> [BillingReminderCycle] in
            let maxDaysAfterStatement = account.billingRuleVersions
                .filter { $0.repaymentKind == .daysAfterStatement }
                .map(\.repaymentValue)
                .max() ?? 0
            let upcomingCycleKeys = Self.reminderCycleOffsets(
                maxDaysAfterStatement: maxDaysAfterStatement,
                maxReminderOffset: maxReminderOffset
            )
                .map { today.addingMonths($0, timeZone: timeZone).monthKey }
            let savedUnpaidCycleKeys = account.billingCycles.filter { $0.repaidAt == nil }.map(\.cycleKey)
            let cycleKeys = Self.reminderCycleKeys(
                generated: upcomingCycleKeys,
                savedUnpaid: savedUnpaidCycleKeys,
                trackingStartCycleKey: account.trackingStartCycleKey
            )
            return cycleKeys.compactMap { cycleKey in
                let record = account.billingCycles.first { $0.cycleKey == cycleKey }
                guard let cycle = try? BillingCalculator.calculate(
                    account: account,
                    cycleKey: cycleKey,
                    record: record,
                    today: today,
                    timeZone: timeZone
                ) else { return nil }
                return BillingReminderCycle(
                    accountID: account.id,
                    accountName: account.bank.name,
                    cycle: cycle
                )
            }
        }
        do {
            let result = try await notificationScheduler.rebuild(
                cycles: reminderCycles,
                statementOffsets: parseOffsets(statementOffsets),
                repaymentOffsets: parseOffsets(repaymentOffsets),
                reminderHour: hour,
                reminderMinute: minute,
                timeZone: timeZone
            )
            let status = await notificationScheduler.authorizationStatus()
            notificationWarning = notificationWarningMessage(status: status, result: result, timeZone: timeZone)
        } catch {
            notificationWarning = "本地提醒更新失败，请检查设置后重试。"
        }
    }

    private func parseOffsets(_ value: String) -> [Int] {
        CardPilotUI.parseReminderOffsets(value) ?? []
    }

    static func reminderCycleOffsets(maxDaysAfterStatement: Int, maxReminderOffset: Int = 0) -> ClosedRange<Int> {
        let days = max(0, maxDaysAfterStatement)
        let lookbackMonths = max(1, days / 28 + (days % 28 == 0 ? 0 : 1))
        let reminderDays = max(0, maxReminderOffset)
        let futureMonths = max(3, reminderDays / 28 + (reminderDays % 28 == 0 ? 0 : 1))
        return -lookbackMonths...futureMonths
    }

    static func reminderCycleKeys(
        generated: [Int],
        savedUnpaid: [Int],
        trackingStartCycleKey: Int
    ) -> Set<Int> {
        Set(generated.filter { $0 >= trackingStartCycleKey } + savedUnpaid)
    }
}

private struct LockShield: View {
    let isAuthenticating: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("CardPilot 已锁定")
                    .font(.title2.bold())
                Button(isAuthenticating ? "正在验证…" : "解锁", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuthenticating)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
