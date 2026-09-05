import SwiftData
import SwiftUI

struct CardDetailView: View {
    let card: Card

    @Query(sort: \CreditCardAccount.id) private var accounts: [CreditCardAccount]
    @Query(sort: \CardNetwork.displayName) private var networks: [CardNetwork]
    @Query(sort: \Card.id) private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var transactions: [Transaction]

    @State private var showingCardEditor = false
    @State private var showingTransactionEditor = false

    private var today: LocalDate { CardPilotUI.localDate(from: Date()) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        BankBadge(bank: card.account.bank)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cardName)
                                .font(.title2.bold())
                            Text("\(cardNetworkSummary(card.networks)) · •••• \(card.lastFour)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if card.status == .inactive {
                            StatusPill(title: "已停用", color: .secondary)
                        }
                    }

                    if let repaymentDate = summary.nextRepaymentDate {
                        HStack(spacing: 8) {
                            Image(systemName: summary.nextRepaymentStatus == .overdue
                                  ? "exclamationmark.circle.fill" : "calendar.badge.clock")
                                .foregroundStyle(summary.nextRepaymentStatus == .overdue ? .red : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.nextRepaymentStatus == .overdue ? "还款已逾期" : "下次还款")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(CardPilotUI.relativeDateText(repaymentDate, today: today)) · \(CardPilotUI.shortDateText(repaymentDate, relativeTo: today))")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section("快捷操作") {
                Button {
                    showingTransactionEditor = true
                } label: {
                    DetailActionLabel(
                        title: "记一笔",
                        subtitle: card.status == .active ? "使用这张卡记录消费或退款" : "停用卡仍可补录历史交易",
                        systemImage: "plus.circle.fill",
                        tint: .accentColor
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CardTransactionHistoryView(card: card)
                } label: {
                    DetailActionLabel(
                        title: "查看交易",
                        subtitle: transactionCountText,
                        systemImage: "list.bullet.rectangle",
                        tint: .blue,
                        showsChevron: false
                    )
                }
            }

            Section("账单日程") {
                if upcomingCycles.isEmpty {
                    Text("暂无可显示的账期")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(upcomingCycles, id: \.cycleKey) { cycle in
                        BillingCycleRow(cycle: cycle, today: today)
                    }
                }

                NavigationLink {
                    AccountDetailView(account: card.account)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.account.cards.count > 1 ? "查看共享账户" : "查看信用卡账户")
                            .font(.subheadline.weight(.medium))
                        Text(card.account.cards.count > 1
                             ? "与另外 \(card.account.cards.count - 1) 张卡共用账单和还款状态"
                             : "查看账单规则和已处理账期")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }

            Section("适用活动") {
                if applicablePromotions.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("暂无进行中或即将开始的活动")
                            .foregroundStyle(.secondary)
                        Text("只有明确选择这张卡的活动会显示在这里。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ForEach(applicablePromotions, id: \.id) { promotion in
                        NavigationLink {
                            PromotionDetailView(promotion: promotion)
                        } label: {
                            CardPromotionRow(promotion: promotion, today: today)
                        }
                    }
                }
            }

            Section("卡片信息") {
                LabeledContent("银行", value: card.account.bank.name)
                LabeledContent("卡组织", value: cardNetworkSummary(card.networks))
                LabeledContent("末四位", value: card.lastFour)
                LabeledContent("状态", value: card.status == .active ? "使用中" : "已停用")
                if !card.productName.isEmpty, card.productName != cardName {
                    LabeledContent("产品名称", value: card.productName)
                }
                if !card.notes.isEmpty {
                    LabeledContent("备注", value: card.notes)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("卡片详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingCardEditor = true }
            }
        }
        .sheet(isPresented: $showingCardEditor) {
            CardEditorView(card: card, accounts: accounts, networks: networks)
        }
        .sheet(isPresented: $showingTransactionEditor) {
            TransactionEditorView(
                transaction: nil,
                cards: cards,
                promotions: promotions,
                transactions: transactions,
                initialCard: card
            )
        }
    }

    private var cardName: String {
        card.nickname.isEmpty ? card.productName : card.nickname
    }

    private var summary: CardAccountBillingSummary {
        accountBillingSummary(card.account, today: today)
    }

    private var upcomingCycles: [BillingCycle] {
        accountDetailCycles(card.account, today: today, includesTrackedHistory: false)
            .filter { $0.status != .paid }
            .prefix(2)
            .map { $0 }
    }

    private var applicablePromotions: [Promotion] {
        applicablePromotionsForCard(promotions, cardID: card.id, today: today)
    }

    private var transactionCountText: String {
        let activeCount = card.transactions.filter { $0.status == .active }.count
        guard activeCount != card.transactions.count else { return "共 \(activeCount) 笔" }
        return "\(activeCount) 笔有效 · \(card.transactions.count - activeCount) 笔已冲正"
    }
}

struct AccountDetailView: View {
    let account: CreditCardAccount

    @Query(sort: \Bank.name) private var banks: [Bank]
    @State private var showingAccountEditor = false

    private var today: LocalDate { CardPilotUI.localDate(from: Date()) }
    private var currentCycleKey: Int { today.monthKey }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        BankBadge(bank: account.bank)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.bank.name)
                                .font(.title2.bold())
                            Text(accountRelationshipText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if account.status == .closed {
                            StatusPill(title: "已关闭", color: .secondary)
                        }
                    }
                    if let creditLimit = account.creditLimit {
                        LabeledContent("信用额度") {
                            Text(CardPilotUI.amountText(creditLimit, currencyCode: account.limitCurrencyCode))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Section("近期账期") {
                if recentCycles.isEmpty {
                    Text("暂无可显示的账期")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentCycles, id: \.cycleKey) { cycle in
                        BillingCycleRow(cycle: cycle, today: today)
                    }
                }
            }

            if !paidCycles.isEmpty {
                Section("已处理账期") {
                    ForEach(paidCycles, id: \.cycleKey) { cycle in
                        BillingCycleRow(cycle: cycle, today: today)
                    }
                }
            }

            Section("账单规则") {
                if let currentRule {
                    BillingRuleRow(rule: currentRule, title: "当前生效")
                } else {
                    Label("当前账期没有可用规则", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                ForEach(scheduledRules, id: \.id) { rule in
                    BillingRuleRow(
                        rule: rule,
                        title: "\(CardPilotUI.monthKeyText(rule.effectiveCycleKey)) 起生效"
                    )
                }

                if !scheduledRules.isEmpty {
                    Text("未来规则会在标注的账期开始使用，当前账期仍按“当前生效”规则计算。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("关联卡片") {
                if sortedCards.isEmpty {
                    Text("尚未添加卡片")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedCards, id: \.id) { card in
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: card.status == .active ? "creditcard.fill" : "creditcard")
                                    .foregroundStyle(card.status == .active ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(card.nickname.isEmpty ? card.productName : card.nickname)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(cardNetworkSummary(card.networks)) · •••• \(card.lastFour)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            if !account.notes.isEmpty || account.closedOn != nil {
                Section("账户信息") {
                    if let closedOn = account.closedOn {
                        LabeledContent("关闭日期", value: CardPilotUI.dateText(closedOn))
                    }
                    if !account.notes.isEmpty {
                        LabeledContent("备注", value: account.notes)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("账户详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingAccountEditor = true }
            }
        }
        .sheet(isPresented: $showingAccountEditor) {
            AccountEditorView(account: account, banks: banks)
        }
    }

    private var sortedCards: [Card] {
        account.cards.sorted {
            let lhs = $0.nickname.isEmpty ? $0.productName : $0.nickname
            let rhs = $1.nickname.isEmpty ? $1.productName : $1.nickname
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var accountRelationshipText: String {
        switch account.cards.count {
        case 0: return "尚未关联卡片"
        case 1: return "1 张卡的独立账单账户"
        default: return "\(account.cards.count) 张卡共用账单与还款状态"
        }
    }

    private var currentRule: BillingRuleVersion? {
        let inputs = account.billingRuleVersions.map(\.billingRuleInput)
        guard let selected = BillingCalculator.applicableRule(from: inputs, forCycleKey: currentCycleKey) else {
            return nil
        }
        return account.billingRuleVersions.first { $0.effectiveCycleKey == selected.effectiveCycleKey }
    }

    private var scheduledRules: [BillingRuleVersion] {
        account.billingRuleVersions
            .filter { ($0.effectiveCycleKey ?? Int.min) > currentCycleKey }
            .sorted { ($0.effectiveCycleKey ?? Int.max) < ($1.effectiveCycleKey ?? Int.max) }
    }

    private var allDetailCycles: [BillingCycle] {
        accountDetailCycles(account, today: today, includesTrackedHistory: true)
    }

    private var recentCycles: [BillingCycle] {
        allDetailCycles.filter { $0.status != .paid }.prefix(4).map { $0 }
    }

    private var paidCycles: [BillingCycle] {
        allDetailCycles.filter { $0.status == .paid }.sorted { $0.cycleKey > $1.cycleKey }.prefix(6).map { $0 }
    }
}

private struct CardTransactionHistoryView: View {
    let card: Card

    @Query(sort: \Card.id) private var cards: [Card]
    @Query(sort: \Promotion.endOn) private var promotions: [Promotion]
    @Query(sort: \Transaction.transactionOn, order: .reverse) private var allTransactions: [Transaction]
    @State private var detailTransaction: Transaction?
    @State private var showingEditor = false

    private var transactions: [Transaction] {
        allTransactions.filter { $0.card.id == card.id }
    }

    private var transactionSections: [(date: Int, transactions: [Transaction])] {
        groupedTransactionsByDate(transactions)
    }

    var body: some View {
        Group {
            if transactions.isEmpty {
                ContentUnavailableView {
                    Label("这张卡还没有交易", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("记录第一笔消费或退款后，会显示在这里。")
                } actions: {
                    Button("记一笔", systemImage: "plus") { showingEditor = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(transactionSections.indices, id: \.self) { index in
                        let section = transactionSections[index]
                        Section(CardPilotUI.dateText(section.date)) {
                            ForEach(section.transactions, id: \.id) { transaction in
                                Button {
                                    detailTransaction = transaction
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(card.nickname.isEmpty ? card.productName : card.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingEditor = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("使用这张卡添加交易")
            }
        }
        .sheet(isPresented: $showingEditor) {
            TransactionEditorView(
                transaction: nil,
                cards: cards,
                promotions: promotions,
                transactions: allTransactions,
                initialCard: card
            )
        }
        .sheet(isPresented: Binding(
            get: { detailTransaction != nil },
            set: { if !$0 { detailTransaction = nil } }
        )) {
            if let detailTransaction {
                TransactionDetailView(
                    transaction: detailTransaction,
                    cards: cards,
                    promotions: promotions,
                    transactions: allTransactions
                )
            }
        }
    }
}

private struct DetailActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct CardPromotionRow: View {
    let promotion: Promotion
    let today: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(promotion.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if !promotion.rewardDescription.isEmpty {
                Text(promotion.rewardDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("\(promotion.startOn > today.rawValue ? "即将开始" : "进行中") · \(endDateText)")
                .font(.caption)
                .foregroundStyle(promotion.endOn <= today.addingDays(7).rawValue ? .orange : .secondary)
        }
        .padding(.vertical, 4)
    }

    private var endDateText: String {
        guard let end = try? LocalDate(rawValue: promotion.endOn) else { return "日期待核对" }
        let dateText = CardPilotUI.shortDateText(end, relativeTo: today)
        guard end <= today.addingDays(7) else { return "结束 \(dateText)" }
        return "\(CardPilotUI.relativeDateText(end, today: today))结束 · \(dateText)"
    }
}

private struct BillingRuleRow: View {
    let rule: BillingRuleVersion
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text("每月 \(rule.statementDay) 日出账 · \(repaymentText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var repaymentText: String {
        switch rule.repaymentKind {
        case .fixedDay: return "每月 \(rule.repaymentValue) 日还款"
        case .daysAfterStatement: return "出账后 \(rule.repaymentValue) 天还款"
        }
    }
}

private struct BillingCycleRow: View {
    let cycle: BillingCycle
    let today: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(CardPilotUI.monthKeyText(cycle.cycleKey))账期")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill(title: statusTitle, color: statusColor)
            }
            HStack {
                Label("账单 \(CardPilotUI.shortDateText(cycle.statementDate, relativeTo: today))", systemImage: "doc.text")
                Spacer()
                Label("还款 \(CardPilotUI.shortDateText(cycle.repaymentDate, relativeTo: today))", systemImage: "calendar.badge.clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(CardPilotUI.monthKeyText(cycle.cycleKey))账期，账单日 \(CardPilotUI.dateText(cycle.statementDate))，还款日 \(CardPilotUI.dateText(cycle.repaymentDate))，\(statusTitle)")
    }

    private var statusTitle: String {
        switch cycle.status {
        case .paid: return "已还款"
        case .overdue: return "已逾期"
        case .pending:
            return cycle.repaymentDate == today ? "今天还款" : "待还款"
        }
    }

    private var statusColor: Color {
        switch cycle.status {
        case .paid: return .green
        case .overdue: return .red
        case .pending: return .secondary
        }
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

func applicablePromotionsForCard(
    _ promotions: [Promotion],
    cardID: UUID,
    today: LocalDate
) -> [Promotion] {
    promotions.filter { promotion in
        promotion.archivedAt == nil
            && promotion.endOn >= today.rawValue
            && promotion.eligibleCards.contains { $0.id == cardID }
    }
    .sorted { lhs, rhs in
        let lhsIsActive = lhs.startOn <= today.rawValue
        let rhsIsActive = rhs.startOn <= today.rawValue
        if lhsIsActive != rhsIsActive { return lhsIsActive }
        if lhs.endOn != rhs.endOn { return lhs.endOn < rhs.endOn }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

func accountDetailCycles(
    _ account: CreditCardAccount,
    today: LocalDate,
    includesTrackedHistory: Bool,
    timeZone: TimeZone = CardPilotUI.homeTimeZone
) -> [BillingCycle] {
    let generatedStart = includesTrackedHistory
        ? account.trackingStartCycleKey
        : max(account.trackingStartCycleKey, today.monthKey)
    let generatedEnd = today.addingMonths(2, timeZone: timeZone).monthKey
    let generatedKeys = LocalDate.monthKeys(from: generatedStart, through: generatedEnd)
    let savedKeys = account.billingCycles.map(\.cycleKey)
    let savedKeySet = Set(savedKeys)
    return Set(generatedKeys + savedKeys)
        .filter { $0 >= account.trackingStartCycleKey || savedKeySet.contains($0) }
        .compactMap { cycleKey in
            try? BillingCalculator.calculate(
                account: account,
                cycleKey: cycleKey,
                record: account.billingCycles.first { $0.cycleKey == cycleKey },
                today: today,
                timeZone: timeZone
            )
        }
        .sorted {
            if $0.status == .overdue, $1.status != .overdue { return true }
            if $0.status != .overdue, $1.status == .overdue { return false }
            return $0.cycleKey < $1.cycleKey
        }
}

private extension BillingRuleVersion {
    var billingRuleInput: BillingRuleInput {
        BillingRuleInput(
            effectiveCycleKey: effectiveCycleKey,
            statementDay: statementDay,
            repaymentKind: repaymentKind,
            repaymentValue: repaymentValue
        )
    }
}
