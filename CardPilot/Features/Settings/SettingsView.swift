import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appLock: AppLockController
    @AppStorage("cardPilot.statementReminderOffsets") private var storedStatementOffsets = "7,3,1,0"
    @AppStorage("cardPilot.repaymentReminderOffsets") private var storedRepaymentOffsets = "7,3,1,0"
    @AppStorage("cardPilot.reminderTime") private var storedReminderTime = "09:00"
    @AppStorage("cardPilot.homeTimeZone") private var storedHomeTimeZone = TimeZone.current.identifier
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false

    @State private var statementReminderOffsets: String
    @State private var repaymentReminderOffsets: String
    @State private var reminderTime: String
    @State private var homeTimeZone: String
    @State private var notificationStatus = "正在检查…"
    @State private var errorMessage: String?

    init() {
        let defaults = UserDefaults.standard
        _statementReminderOffsets = State(initialValue: defaults.string(forKey: "cardPilot.statementReminderOffsets") ?? "7,3,1,0")
        _repaymentReminderOffsets = State(initialValue: defaults.string(forKey: "cardPilot.repaymentReminderOffsets") ?? "7,3,1,0")
        _reminderTime = State(initialValue: defaults.string(forKey: "cardPilot.reminderTime") ?? "09:00")
        _homeTimeZone = State(initialValue: defaults.string(forKey: "cardPilot.homeTimeZone") ?? TimeZone.current.identifier)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账单日提醒") {
                    TextField("提前天数", text: $statementReminderOffsets)
                        .keyboardType(.numbersAndPunctuation)
                    Text("用逗号分隔，例如 7,3,1,0；0 表示当天。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("还款日提醒") {
                    TextField("提前天数", text: $repaymentReminderOffsets)
                        .keyboardType(.numbersAndPunctuation)
                    Text("用逗号分隔，例如 7,3,1,0；0 表示当天。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("提醒设置") {
                    TextField("提醒时刻（HH:mm）", text: $reminderTime)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("常用时区", text: $homeTimeZone)
                        .textInputAutocapitalization(.never)
                    LabeledContent("通知权限", value: notificationStatus)
                    Button("请求通知权限") {
                        Task { await requestNotifications() }
                    }
                    Button("打开系统通知设置") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section("安全与隐私") {
                    Toggle("使用生物识别或设备密码锁定", isOn: appLockBinding)
                    Label("CardPilot 不需要完整卡号或 CVV。", systemImage: "lock.shield")
                    Text("数据保存在本机。请只记录末四位，不要在备注中主动保存敏感认证信息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: finish)
                }
            }
            .task { await refreshNotificationStatus() }
            .alert("无法完成设置", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLockEnabled },
            set: { enabled in
                if appLock.setEnabled(enabled) {
                    appLockEnabled = enabled
                } else {
                    errorMessage = "此设备尚未设置可用的生物识别或设备密码。"
                }
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func requestNotifications() async {
        do {
            _ = try await LocalNotificationScheduler().requestAuthorization()
            await refreshNotificationStatus()
        } catch {
            errorMessage = "无法请求通知权限：\(error.localizedDescription)"
        }
    }

    private func finish() {
        guard CardPilotUI.parseReminderOffsets(statementReminderOffsets) != nil,
              CardPilotUI.parseReminderOffsets(repaymentReminderOffsets) != nil else {
            errorMessage = "提醒提前天数应为逗号分隔的 0...\(CardPilotUI.maximumReminderOffset) 整数。"
            return
        }
        guard CardPilotUI.parseReminderTime(reminderTime) != nil else {
            errorMessage = "提醒时刻应使用 HH:mm 格式。"
            return
        }
        guard TimeZone(identifier: homeTimeZone) != nil else {
            errorMessage = "请输入有效的 IANA 时区，例如 Asia/Shanghai。"
            return
        }
        storedStatementOffsets = statementReminderOffsets
        storedRepaymentOffsets = repaymentReminderOffsets
        storedReminderTime = reminderTime
        storedHomeTimeZone = homeTimeZone
        dismiss()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "已允许"
        case .denied:
            notificationStatus = "已拒绝"
        case .notDetermined:
            notificationStatus = "尚未请求"
        @unknown default:
            notificationStatus = "未知"
        }
    }
}
