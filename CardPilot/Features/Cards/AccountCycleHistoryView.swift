import SwiftUI

struct AccountCycleHistoryView: View {
    let account: CreditCardAccount
    @Environment(\.currentDay) private var currentDay
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var year: Int?
    @State private var month: Int?
    @State private var status: AccountCycleHistoryStatus = .all

    var body: some View {
        let cycles = accountDetailCycles(account, today: currentDay.today, includesTrackedHistory: true)
        let results = filterAccountHistoryCycles(cycles, year: year, month: month, status: status)
        let years = Set(cycles.map { $0.cycleKey / 100 } + [year].compactMap { $0 }).sorted(by: >)
        List {
            Section("查找账期") {
                Picker("年份", selection: $year) {
                    Text("全部年份").tag(nil as Int?)
                    ForEach(years, id: \.self) { year in
                        Text(String(year)).tag(Optional(year))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("account.history.year")
                Picker("月份", selection: $month) {
                    Text("全部月份").tag(nil as Int?)
                    ForEach(1...12, id: \.self) { month in
                        Text("\(month) 月").tag(Optional(month))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("account.history.month")
                if dynamicTypeSize.isAccessibilitySize {
                    statusPicker.pickerStyle(.navigationLink)
                } else {
                    statusPicker.pickerStyle(.menu)
                }
                if year != nil || month != nil || status != .all {
                    Button("清除筛选") {
                        year = nil
                        month = nil
                        status = .all
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("account.history.clear")
                }
            }
            Section {
                if results.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("没有匹配账期")
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "calendar.badge.exclamationmark")
                        }
                    } description: {
                        Text("可调整年份、月份或还款状态。")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    ForEach(results, id: \.cycleKey) { cycle in
                        NavigationLink {
                            BillingCycleDetailView(account: account, cycleKey: cycle.cycleKey)
                        } label: {
                            BillingCycleRow(cycle: cycle, today: currentDay.today)
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("account.history.cycle.\(cycle.cycleKey)")
                    }
                }
            } header: {
                Text("共 \(results.count) 个账期")
                    .accessibilityIdentifier("account.history.count")
            } footer: {
                Text("按账期年月查找，显示追踪范围内的账期及已保存的历史记录；未来账期按现有规则推算。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("全部账期")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusPicker: some View {
        Picker("还款状态", selection: $status) {
            ForEach(AccountCycleHistoryStatus.allCases, id: \.self) { status in
                Text(status.title).tag(status)
            }
        }
        .accessibilityIdentifier("account.history.status")
    }
}

enum AccountCycleHistoryStatus: String, CaseIterable {
    case all, unpaid, paid

    var title: String {
        switch self {
        case .all: "全部状态"
        case .unpaid: "未还款"
        case .paid: "已还款"
        }
    }
}

func filterAccountHistoryCycles(_ cycles: [BillingCycle], year: Int?, month: Int?,
                               status: AccountCycleHistoryStatus) -> [BillingCycle] {
    cycles.filter { cycle in
        (year == nil || cycle.cycleKey / 100 == year)
            && (month == nil || cycle.cycleKey % 100 == month)
            && (status == .all || (status == .paid ? cycle.status == .paid : cycle.status != .paid))
    }
    .sorted { $0.cycleKey > $1.cycleKey }
}
