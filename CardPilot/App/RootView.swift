import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \CreditCardAccount.id) private var accounts: [CreditCardAccount]
    @Query(sort: \Card.id) private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]
    @AppStorage("cardPilot.statementReminderOffsets") private var statementOffsets = "7,3,1,0"
    @AppStorage("cardPilot.repaymentReminderOffsets") private var repaymentOffsets = "7,3,1,0"
    @AppStorage("cardPilot.statementRemindersEnabled") private var statementRemindersEnabled = true
    @AppStorage("cardPilot.repaymentRemindersEnabled") private var repaymentRemindersEnabled = true
    @AppStorage("cardPilot.reminderTime") private var reminderTime = "09:00"
    @AppStorage("cardPilot.homeTimeZone") private var homeTimeZone = TimeZone.current.identifier
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false
    @AppStorage("cardPilot.notificationWarning") private var notificationWarning = ""
    @AppStorage("cardPilot.notificationRevision") private var notificationRevision = 0

    @StateObject private var appLock = AppLockController()
    @ObservedObject private var quickActionRouter = CardPilotQuickActionRouter.shared
    @State private var selectedTab = Tab.dashboard
    @State private var showingSettings = false
    @State private var showingTransactionEditor = false
    @State private var showingCardOnboarding = false
    @State private var isAuthenticating = false
    @State private var authenticationAttempt = 0

    @State private var notificationScheduler = LocalNotificationScheduler()
    @State private var notificationRequestRevision = 0

    init() {
        _appLock = StateObject(wrappedValue: AppLockController(
            enabled: UserDefaults.standard.bool(forKey: "cardPilot.appLockEnabled")
        ))
    }

    enum Tab: Hashable {
        case dashboard
        case cards
        case addTransaction
        case promotions
        case transactions
    }

    var body: some View {
        TabView(selection: tabSelection) {
            DashboardView(showingSettings: $showingSettings, onAddCard: addCard)
                .tabItem { Label("首页", systemImage: "rectangle.grid.2x2") }
                .tag(Tab.dashboard)

            CardsView(showingCardOnboarding: $showingCardOnboarding)
                .tabItem { Label("卡片", systemImage: "creditcard") }
                .tag(Tab.cards)

            Color.clear
                .tabItem {
                    Label("记一笔", systemImage: "plus.circle.fill")
                        .accessibilityIdentifier("quickAddTransaction")
                }
                .tag(Tab.addTransaction)

            PromotionsView()
                .tabItem { Label("促销", systemImage: "gift") }
                .tag(Tab.promotions)

            TransactionsView(onAddCard: addCard)
                .tabItem { Label("交易", systemImage: "list.bullet.rectangle") }
                .tag(Tab.transactions)
        }
        .privacySensitive()
        .allowsHitTesting(!appLock.isLocked)
        .accessibilityHidden(appLock.isLocked)
        .sheet(isPresented: $showingSettings, onDismiss: handlePendingQuickActions) {
            SettingsView().environmentObject(appLock)
        }
        .sheet(isPresented: $showingTransactionEditor, onDismiss: handlePendingQuickActions) {
            TransactionEditorView(transaction: nil, cards: cards, promotions: promotions, transactions: transactions)
        }
        // A separate window also covers presented sheets without destroying their edit state.
        .background(AppLockShieldWindow(lock: appLock, isAuthenticating: isAuthenticating, unlock: authenticate))
        .environment(\.timeZone, TimeZone(identifier: homeTimeZone) ?? .current)
        .onAppear {
            if !appLock.setEnabled(appLockEnabled) { appLockEnabled = false }
            authenticate()
            handlePendingQuickActions()
        }
        .onChange(of: showingCardOnboarding) { _, showing in if !showing { handlePendingQuickActions() } }
        .onChange(of: quickActionRouter.pendingActions) { _, _ in handlePendingQuickActions() }
        .onChange(of: appLock.isLocked) { _, locked in
            if !locked { handlePendingQuickActions() }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if !appLock.setEnabled(enabled) { appLockEnabled = false }
            if enabled { authenticate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if !isAuthenticating { relock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                authenticate()
                Task { await rebuildNotifications() }
            } else if Self.shouldRelock(when: phase, isAuthenticating: isAuthenticating) {
                relock()
            }
        }
        .task(id: notificationConfigurationKey) { await rebuildNotifications() }
    }

    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .addTransaction {
                    addTransaction()
                } else {
                    selectedTab = tab
                }
            }
        )
    }

    private func addCard() {
        selectedTab = .cards
        showingCardOnboarding = true
    }

    private func addTransaction() {
        if cards.isEmpty { addCard() }
        else { showingTransactionEditor = true }
    }

    private func relock() {
        authenticationAttempt += 1
        isAuthenticating = false
        appLock.applicationDidEnterBackground()
    }

    private var notificationConfigurationKey: String {
        let accountKey = accounts.map { account in
            let rules = account.billingRuleVersions.map {
                "\($0.effectiveCycleKey ?? 0)-\($0.statementDay)-\($0.repaymentKindRaw)-\($0.repaymentValue)"
            }.sorted().joined(separator: ",")
            let cycles = account.billingCycles.map {
                "\($0.cycleKey)-\($0.statementDateOverride ?? 0)-\($0.repaymentDateOverride ?? 0)-\($0.repaidAt?.timeIntervalSince1970 ?? 0)"
            }.sorted().joined(separator: ",")
            return "\(account.id)-\(CardPilotUI.accountName(account))-\(account.statusRaw)-\(account.closedOn ?? 0)-\(rules)-\(cycles)"
        }.joined(separator: "|")
        return "\(statementRemindersEnabled)|\(repaymentRemindersEnabled)|\(statementOffsets)|\(repaymentOffsets)|\(reminderTime)|\(homeTimeZone)|\(notificationRevision)|\(accountKey)"
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

    private func handlePendingQuickActions() {
        // Ordinary unlocks must never dismiss an editor. Defer shortcuts while a root sheet is open.
        guard !appLock.isLocked, !quickActionRouter.pendingActions.isEmpty,
              !showingSettings, !showingTransactionEditor, !showingCardOnboarding else { return }
        if let action = quickActionRouter.takeNext() {
            switch action {
            case .addTransaction: addTransaction()
            case .promotionProgress:
                selectedTab = .promotions
            }
        }
    }

    private func rebuildNotifications() async {
        notificationRequestRevision += 1
        let requestRevision = notificationRequestRevision
        let parsedTime = CardPilotUI.parseReminderTime(reminderTime)
        let hour = parsedTime?.hour ?? 9
        let minute = parsedTime?.minute ?? 0
        let timeZone = TimeZone(identifier: homeTimeZone) ?? .current
        let today = LocalDate(date: .now, timeZone: timeZone)
        let statementDays = statementRemindersEnabled ? parseOffsets(statementOffsets) : []
        let repaymentDays = repaymentRemindersEnabled ? parseOffsets(repaymentOffsets) : []
        let maxReminderOffset = (statementDays + repaymentDays).max() ?? 0
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
                    accountName: CardPilotUI.accountName(account),
                    cycle: cycle
                )
            }
        }
        do {
            let result = try await notificationScheduler.rebuild(
                cycles: reminderCycles,
                statementOffsets: statementDays,
                repaymentOffsets: repaymentDays,
                reminderHour: hour,
                reminderMinute: minute,
                timeZone: timeZone
            )
            let status = await notificationScheduler.authorizationStatus()
            guard requestRevision == notificationRequestRevision, !Task.isCancelled else { return }
            notificationWarning = notificationWarningMessage(status: status, result: result, timeZone: timeZone)
            UserDefaults.standard.set(result.nextScheduledDate?.timeIntervalSince1970 ?? 0, forKey: "cardPilot.nextReminderDate")
            UserDefaults.standard.set(result.firstOmittedDate?.timeIntervalSince1970 ?? 0, forKey: "cardPilot.firstOmittedReminderDate")
            UserDefaults.standard.set(result.scheduledCount, forKey: "cardPilot.scheduledReminderCount")
        } catch is CancellationError {
            // A newer configuration owns the schedule and its status.
        } catch {
            guard requestRevision == notificationRequestRevision else { return }
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

    static func shouldRelock(when phase: ScenePhase, isAuthenticating: Bool) -> Bool {
        phase == .background || (phase == .inactive && !isAuthenticating)
    }
}
