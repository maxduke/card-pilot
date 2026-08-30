import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [CreditCardAccount]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Binding var showingSettings: Bool
    @State private var errorMessage: String?

    private var today: LocalDate { CardPilotUI.localDate(from: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if billingItems.isEmpty && activePromotions.isEmpty {
                        EmptyStateView(
                            title: "开始使用 CardPilot",
                            systemImage: "creditcard",
                            message: "先添加信用卡账户或促销活动，首页会显示需要关注的日期和进度。"
                        )
                        .frame(maxWidth: .infinity, minHeight: 300)
                    }

                    if !billingItems.isEmpty {
                        DashboardSection(title: "近期账务日期") {
                            ForEach(billingItems) { item in
                                BillingItemRow(item: item) {
                                    markRepaid(item)
                                }
                            }
                        }
                    }

                    if !activePromotions.isEmpty {
                        DashboardSection(title: "促销进度") {
                            ForEach(activePromotions) { promotion in
                                PromotionProgressRow(promotion: promotion)
                            }
                        }

                        if !endingSoonPromotions.isEmpty {
                            DashboardSection(title: "即将结束") {
                                ForEach(endingSoonPromotions) { promotion in
                                    HStack {
                                        Image(systemName: "clock.badge.exclamationmark")
                                            .foregroundStyle(.orange)
                                        Text(promotion.title)
                                        Spacer()
                                        Text("结束于 \(CardPilotUI.dateText(promotion.endOn))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("CardPilot")
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

    private var endingSoonPromotions: [Promotion] {
        activePromotions.filter {
            isEndingSoon($0) && (try? PromotionCalculator.progress(for: $0).isComplete) != true
        }
    }

    private var billingItems: [DashboardBillingItem] {
        var result: [DashboardBillingItem] = []
        for account in accounts {
            for offset in -2...2 {
                let cycleDate = today.addingMonths(offset)
                let cycleKey = cycleDate.monthKey
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
        return result.sorted {
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
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DashboardBillingItem: Identifiable {
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
    let markRepaid: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.icon)
                .foregroundStyle(item.kind == .repayment ? .orange : .blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind.title)
                    .font(.subheadline.weight(.medium))
                Text("\(item.account.bank.name) · 账期 \(item.cycleKey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(CardPilotUI.dateText(item.date))
                    .font(.subheadline)
                if item.status == .overdue && item.kind == .repayment {
                    Text("已逾期")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if item.kind == .repayment {
                Button("已还", action: markRepaid)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("标记 \(item.account.bank.name) 账期 \(item.cycleKey) 已还款")
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kind.title)，\(item.account.bank.name)，\(CardPilotUI.dateText(item.date))")
    }
}

private struct PromotionProgressRow: View {
    let promotion: Promotion

    private var progress: PromotionProgress? { try? PromotionCalculator.progress(for: promotion) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(promotion.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let progress {
                    Text("\(CardPilotUI.amountText(progress.qualifiedAmount, currencyCode: promotion.progressCurrencyCode)) / \(CardPilotUI.amountText(progress.targetAmount, currencyCode: promotion.progressCurrencyCode))")
                        .font(.caption)
                        .foregroundStyle(progress.isComplete ? .green : .secondary)
                }
            }
            if let progress {
                ProgressView(value: max(0, decimalDouble(progress.qualifiedAmount)), total: decimalDouble(progress.targetAmount))
                    .tint(progress.isComplete ? .green : .accentColor)
                Text(progress.isComplete ? "已达标" : "还需 \(CardPilotUI.amountText(progress.remainingAmount, currencyCode: promotion.progressCurrencyCode))")
                    .font(.caption)
                    .foregroundStyle(progress.isComplete ? .green : .secondary)
            } else {
                Text("暂时无法计算进度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
