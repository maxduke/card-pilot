import SwiftUI

struct FirstCardReminderView: View {
    @Environment(\.currentDay) private var currentDay
    @Environment(\.dismiss) private var dismiss
    let card: Card
    @State private var hasOpenedSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("卡片已保存", systemImage: "checkmark.circle")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(CardPilotUI.accountName(card.account))
                    Text("接下来可以设置账单日和还款日提醒。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    let summary = accountBillingSummary(card.account, today: currentDay.today, timeZone: currentDay.timeZone)
                    if let date = summary.nextRepaymentDate {
                        LabeledContent(summary.nextRepaymentStatus == .overdue ? "逾期还款日" : "下次还款日",
                                       value: CardPilotUI.dateText(date))
                    }
                    if let date = summary.nextStatementDate {
                        LabeledContent("下次账单日", value: CardPilotUI.dateText(date))
                    }
                } header: {
                    Text("账户日程")
                } footer: {
                    Text("账务日期与通知时间不同，已安排的通知请在提醒设置中查看。")
                }
                Section {
                    NavigationLink {
                        ReminderSettingsView()
                            .onAppear { hasOpenedSettings = true }
                    } label: {
                        Label("设置提醒", systemImage: "bell.badge")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("onboarding.reminders.configure")
                } footer: {
                    Text("也可以稍后从首页的设置进入，不影响已保存的卡片。")
                }
            }
            .navigationTitle("设置还款提醒")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button(hasOpenedSettings ? "完成" : "稍后设置") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("onboarding.reminders.finish")
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}
