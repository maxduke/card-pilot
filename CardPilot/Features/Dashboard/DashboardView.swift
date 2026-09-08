import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [CreditCardAccount]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Binding var showingSettings: Bool
    var onAddCard: () -> Void = {}
    @State private var errorMessage: String?
    @State private var recentlyRepaid: DashboardBillingItem?
    @AppStorage("cardPilot.notificationWarning") private var notificationWarning = ""

    private var today: LocalDate { CardPilotUI.localDate(from: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if !accounts.isEmpty && !notificationWarning.isEmpty {
                        Button { showingSettings = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.badge")
                                Text(notificationWarning)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("通知提示：\(notificationWarning)，打开设置")
                    }
                    if actionCounts.total > 0 {
                        DashboardActionOverview(counts: actionCounts)
                    }
                    if billingItems.isEmpty && unfinishedPromotions.isEmpty && enrollmentClosingSoonPromotions.isEmpty {
                        if accounts.isEmpty {
                            ContentUnavailableView {
                                Label("开始使用 CardPilot", systemImage: "creditcard")
                            } description: {
                                Text("先添加一张信用卡，首页会自动整理账单、还款和促销提醒。")
                            } actions: {
                                Button("添加信用卡", systemImage: "plus", action: onAddCard)
                                    .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                        } else {
                            ContentUnavailableView(
                                "目前无需处理",
                                systemImage: "checkmark.circle",
                                description: Text("新的账单、还款或促销节点出现后，会显示在这里。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 260)
                        }
                    }

                    if !actionBillingItems.isEmpty || !enrollmentClosingSoonPromotions.isEmpty {
                        DashboardSection(title: "待处理") {
                            ForEach(actionBillingItems) { item in
                                BillingItemRow(item: item, showsBank: true) {
                                    markRepaid(item)
                                }
                            }
                            ForEach(enrollmentClosingSoonPromotions) { promotion in
                                NavigationLink {
                                    PromotionDetailView(promotion: promotion)
                                } label: {
                                    HStack {
                                        Image(systemName: "person.badge.clock")
                                            .foregroundStyle(.orange)
                                        Text(promotion.title)
                                        Spacer()
                                        if let deadlineValue = promotion.enrollmentDeadline,
                                           let deadline = try? LocalDate(rawValue: deadlineValue) {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text("\(CardPilotUI.relativeDateText(deadline, today: today))截止")
                                                    .font(.subheadline.weight(.semibold))
                                                Text(CardPilotUI.shortDateText(deadline, relativeTo: today))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .monospacedDigit()
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .accessibilityElement(children: .combine)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !unfinishedPromotions.isEmpty {
                        DashboardSection(title: "继续完成") {
                            ForEach(unfinishedPromotions) { promotion in
                                DashboardPromotionRow(
                                    promotion: promotion,
                                    isEndingSoon: isEndingSoon(promotion)
                                )
                            }
                        }
                    }

                    if !accountsWithBillingItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("账户日程")
                                .font(.headline)
                            ForEach(accountsWithBillingItems, id: \.id) { account in
                                AccountScheduleCard(account: account, items: billingItems(for: account)) { item in
                                    markRepaid(item)
                                }
                            }
                        }
                    }

                }
                .padding()
            }
            .navigationTitle("CardPilot")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let recentlyRepaid {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("已标记 \(CardPilotUI.accountName(recentlyRepaid.account)) \(CardPilotUI.monthKeyText(recentlyRepaid.cycleKey)) 已还款")
                            .font(.footnote)
                            .lineLimit(2)
                        Spacer()
                        Button("撤销") { undoRepayment(recentlyRepaid) }
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("打开设置")
                }
            }
            .alert("无法保存", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var activePromotions: [Promotion] {
        promotions.filter { $0.archivedAt == nil && $0.startOn <= today.rawValue && today.rawValue <= $0.endOn }
    }

    private var enrollmentClosingSoonPromotions: [Promotion] {
        promotionsWithEnrollmentDeadlineWithin(promotions, today: today)
    }

    private var unfinishedPromotions: [Promotion] {
        dashboardPromotionsToContinue(
            activePromotions,
            today: today,
            excludingEnrollmentDeadlineIDs: Set(enrollmentClosingSoonPromotions.map(\.id))
        )
    }

    private var actionBillingItems: [DashboardBillingItem] {
        let limit = today.addingDays(7)
        return billingItems.filter {
            $0.kind == .repayment && ($0.status == .overdue || $0.date <= limit)
        }
    }

    private var actionCounts: DashboardActionCounts {
        dashboardActionCounts(
            billingItems: actionBillingItems,
            enrollmentPromotions: enrollmentClosingSoonPromotions,
            today: today
        )
    }

    private var accountsWithBillingItems: [CreditCardAccount] {
        var seen = Set<UUID>()
        return scheduleBillingItems.compactMap { item in
            seen.insert(item.account.id).inserted ? item.account : nil
        }
    }

    private func billingItems(for account: CreditCardAccount) -> [DashboardBillingItem] {
        scheduleBillingItems.filter { $0.account.id == account.id }
    }

    private var scheduleBillingItems: [DashboardBillingItem] {
        let actionIDs = Set(actionBillingItems.map(\.id))
        return billingItems.filter { !actionIDs.contains($0.id) }
    }

    private var billingItems: [DashboardBillingItem] {
        var result: [DashboardBillingItem] = []
        for account in accounts {
            let nearbyCycleKeys = LocalDate.monthKeys(
                from: account.trackingStartCycleKey,
                through: today.addingMonths(2).monthKey
            )
            let savedUnpaidCycleKeys = account.billingCycles.filter { $0.repaidAt == nil }.map(\.cycleKey)
            for cycleKey in Set(nearbyCycleKeys + savedUnpaidCycleKeys) {
                let record = account.billingCycles.first { $0.cycleKey == cycleKey }
                guard let cycle = try? BillingCalculator.calculate(
                    account: account,
                    cycleKey: cycleKey,
                    record: record,
                    today: today,
                    timeZone: CardPilotUI.homeTimeZone
                ) else { continue }

                if account.status == .active && cycle.statementDate >= today {
                    result.append(.init(
                        account: account,
                        cycleKey: cycleKey,
                        kind: .statement,
                        date: cycle.statementDate,
                        status: cycle.status
                    ))
                }
                if cycle.status != .paid && (cycle.repaymentDate >= today || cycle.status == .overdue) {
                    result.append(.init(
                        account: account,
                        cycleKey: cycleKey,
                        kind: .repayment,
                        date: cycle.repaymentDate,
                        status: cycle.status
                    ))
                }
            }
        }
        return selectDashboardBillingItems(result).sorted {
            $0.priority == $1.priority
                ? ($0.date == $1.date ? $0.kind.sortOrder < $1.kind.sortOrder : $0.date < $1.date)
                : $0.priority < $1.priority
        }
    }

    private func isEndingSoon(_ promotion: Promotion) -> Bool {
        let limit = today.addingDays(7)
        return today.rawValue <= promotion.endOn && promotion.endOn <= limit.rawValue
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func markRepaid(_ item: DashboardBillingItem) {
        let record = item.account.billingCycles.first { $0.cycleKey == item.cycleKey }
            ?? BillingCycleRecord(account: item.account, cycleKey: item.cycleKey)
        if !item.account.billingCycles.contains(where: { $0.id == record.id }) {
            modelContext.insert(record)
        }
        record.repaidAt = .now
        do {
            try record.validate()
            try item.account.validateBillingConfiguration()
            try modelContext.save()
            recentlyRepaid = item
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func undoRepayment(_ item: DashboardBillingItem) {
        guard let record = item.account.billingCycles.first(where: { $0.cycleKey == item.cycleKey }) else {
            recentlyRepaid = nil
            return
        }
        record.repaidAt = nil
        if record.statementDateOverride == nil && record.repaymentDateOverride == nil {
            modelContext.delete(record)
        }
        do {
            try modelContext.save()
            recentlyRepaid = nil
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}

func dashboardPromotionsToContinue(
    _ promotions: [Promotion],
    today: LocalDate,
    excludingEnrollmentDeadlineIDs: Set<UUID> = []
) -> [Promotion] {
    promotions
        .filter { promotion in
            guard promotion.archivedAt == nil,
                  promotion.startOn <= today.rawValue,
                  today.rawValue <= promotion.endOn,
                  !excludingEnrollmentDeadlineIDs.contains(promotion.id),
                  promotion.qualificationThreshold != nil || promotion.benefitTransactionCap != nil,
                  let progress = try? PromotionCalculator.progress(for: promotion) else { return false }
            return !progress.isComplete
        }
        .sorted {
            if $0.endOn != $1.endOn { return $0.endOn < $1.endOn }
            let titleOrder = $0.title.localizedCaseInsensitiveCompare($1.title)
            return titleOrder == .orderedSame ? $0.id.uuidString < $1.id.uuidString : titleOrder == .orderedAscending
        }
}

private struct DashboardPromotionRow: View {
    let promotion: Promotion
    let isEndingSoon: Bool

    private var progress: PromotionProgress? {
        try? PromotionCalculator.progress(for: promotion)
    }

    var body: some View {
        NavigationLink {
            PromotionDetailView(promotion: promotion)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(promotion.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text(eligibleCardText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let progress {
                        HStack(spacing: 8) {
                            Text(progressText(progress))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                            Spacer(minLength: 4)
                            Text("结束 \(CardPilotUI.dateText(promotion.endOn))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if isEndingSoon {
                        Label("即将结束", systemImage: "clock.badge.exclamationmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private var eligibleCardText: String {
        let labels = promotion.eligibleCards
            .sorted {
                let lhs = $0.nickname.isEmpty ? $0.productName : $0.nickname
                let rhs = $1.nickname.isEmpty ? $1.productName : $1.nickname
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { card in
                let name = card.nickname.isEmpty ? card.productName : card.nickname
                return "\(card.account.bank.name) \(name)"
            }
        guard !labels.isEmpty else { return "尚未选择适用卡" }
        guard labels.count > 2 else { return labels.joined(separator: "、") }
        return labels.prefix(2).joined(separator: "、") + " 等 \(labels.count) 张卡"
    }

    private func progressText(_ progress: PromotionProgress) -> String {
        if let cap = progress.benefitTransactionCap {
            return "已用 \(progress.usedTransactionCount)/\(cap) 笔"
        }
        guard let remaining = progress.remainingToThreshold else { return "待完成" }
        return "剩余 \(CardPilotUI.amountText(remaining, currencyCode: promotion.progressCurrencyCode))"
    }
}

func selectDashboardBillingItems(_ items: [DashboardBillingItem]) -> [DashboardBillingItem] {
    let statements = Dictionary(
        grouping: items.filter { $0.kind == .statement },
        by: { $0.account.id }
    )
    .values
    .compactMap { items in
        items.min {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
    }
    let repayments = items.filter { $0.kind == .repayment }
    let overdue = repayments.filter { $0.status == .overdue }
    let nearestPending = Dictionary(grouping: repayments.filter { $0.status == .pending }, by: { $0.account.id })
        .values
        .compactMap { items in
            items.min {
                $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
            }
        }
    return statements + overdue + nearestPending
}

func promotionsWithEnrollmentDeadlineWithin(_ promotions: [Promotion], today: LocalDate) -> [Promotion] {
    let lastDate = today.addingDays(7)
    return promotions.filter { promotion in
        guard promotion.archivedAt == nil,
              promotion.enrollmentStatus == .notEnrolled,
              let deadline = promotion.enrollmentDeadline else { return false }
        return today.rawValue <= deadline && deadline <= lastDate.rawValue
    }.sorted {
        let lhs = $0.enrollmentDeadline ?? .max
        let rhs = $1.enrollmentDeadline ?? .max
        return lhs == rhs ? $0.title < $1.title : lhs < rhs
    }
}

struct DashboardBillingItem: Identifiable {
    enum Kind: Equatable {
        case statement
        case repayment

        var title: String { self == .statement ? "账单日" : "还款日" }
        var icon: String { self == .statement ? "doc.text" : "calendar.badge.clock" }
        var sortOrder: Int { self == .statement ? 0 : 1 }
    }

    let account: CreditCardAccount
    let cycleKey: Int
    let kind: Kind
    let date: LocalDate
    let status: BillingCycle.Status

    var id: String { "\(account.id.uuidString)-\(cycleKey)-\(kind.title)" }
    var priority: Int { status == .overdue && kind == .repayment ? 0 : 1 }
}

struct DashboardActionCounts: Equatable {
    let overdue: Int
    let today: Int
    let nextSevenDays: Int

    var total: Int { overdue + today + nextSevenDays }
}

func dashboardActionCounts(
    billingItems: [DashboardBillingItem],
    enrollmentPromotions: [Promotion],
    today: LocalDate
) -> DashboardActionCounts {
    let limit = today.addingDays(7)
    let overdue = billingItems.filter { $0.status == .overdue && $0.date < today }.count
    let dueToday = billingItems.filter { $0.status != .overdue && $0.date == today }.count
    let upcomingBilling = billingItems.filter {
        $0.status != .overdue && today < $0.date && $0.date <= limit
    }.count
    let enrollmentDates = enrollmentPromotions.compactMap {
        $0.enrollmentDeadline.flatMap { try? LocalDate(rawValue: $0) }
    }
    let enrollmentToday = enrollmentDates.filter { $0 == today }.count
    let enrollmentUpcoming = enrollmentDates.filter { today < $0 && $0 <= limit }.count
    return DashboardActionCounts(
        overdue: overdue,
        today: dueToday + enrollmentToday,
        nextSevenDays: upcomingBilling + enrollmentUpcoming
    )
}

private struct DashboardActionOverview: View {
    let counts: DashboardActionCounts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("近期事项")
                .font(.headline)
            HStack(spacing: 0) {
                if counts.overdue > 0 {
                    metric(count: counts.overdue, title: "逾期", color: .red)
                    Divider().frame(height: 34)
                }
                metric(count: counts.today, title: "今天", color: counts.today > 0 ? .orange : .secondary)
                Divider().frame(height: 34)
                metric(count: counts.nextSevenDays, title: "未来 7 天", color: .secondary)
            }
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func metric(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if counts.overdue > 0 { parts.append("逾期 \(counts.overdue) 项") }
        parts.append("今天 \(counts.today) 项")
        parts.append("未来 7 天 \(counts.nextSevenDays) 项")
        return parts.joined(separator: "，")
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

private struct BillingItemRow: View {
    let item: DashboardBillingItem
    let showsBank: Bool
    let markRepaid: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.icon)
                    .foregroundStyle(item.kind == .repayment ? .orange : .blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.kind.title)
                        .font(.subheadline.weight(.medium))
                    Text(showsBank
                         ? "\(CardPilotUI.accountName(item.account)) · \(CardPilotUI.monthKeyText(item.cycleKey))账期"
                         : "\(CardPilotUI.monthKeyText(item.cycleKey))账期")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(CardPilotUI.relativeDateText(item.date, today: CardPilotUI.localDate(from: .now)))
                        .font(.subheadline.weight(.semibold))
                    Text(CardPilotUI.shortDateText(item.date, relativeTo: CardPilotUI.localDate(from: .now)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }

            if item.kind == .repayment {
                HStack {
                    if item.status == .overdue && item.kind == .repayment {
                        Label("已逾期", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("标记已还", action: markRepaid)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .frame(minHeight: 44)
                        .accessibilityLabel("标记 \(CardPilotUI.accountName(item.account)) \(CardPilotUI.monthKeyText(item.cycleKey))账期已还款")
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

private struct AccountScheduleCard: View {
    let account: CreditCardAccount
    let items: [DashboardBillingItem]
    let markRepaid: (DashboardBillingItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BankBadge(bank: account.bank)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CardPilotUI.accountName(account))
                        .font(.headline)
                    Text(accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 12)

            Divider()

            ForEach(items) { item in
                BillingItemRow(item: item, showsBank: false) { markRepaid(item) }
                if item.id != items.last?.id { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
    }

    private var accountSubtitle: String {
        let names = account.cards.map { $0.nickname.isEmpty ? $0.productName : $0.nickname }.sorted()
        let cards = names.isEmpty ? "未添加卡片" : names.count == 1 ? names[0] : "\(names[0]) 等 \(names.count) 张卡"
        return account.status == .closed ? "已关闭 · \(cards)" : cards
    }
}
