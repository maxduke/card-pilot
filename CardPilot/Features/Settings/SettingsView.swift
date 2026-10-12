import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var backupStore: BackupStore
    @EnvironmentObject private var appLock: AppLockController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ReminderSettingsView()
                    } label: {
                        Label("通知与提醒", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings.reminders")
                } footer: {
                    Text("设置通知权限、提醒时间，并查看已安排的提醒。")
                }
                backupSection
                privacySection
            }
            .disabled(backupStore.isBusy)
            .interactiveDismissDisabled(backupStore.isBusy)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.disabled(backupStore.isBusy)
                }
            }
            .alert("无法完成设置", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private var backupSection: some View {
        Section("数据备份") {
            NavigationLink {
                BackupView()
            } label: {
                Label("完整备份与恢复", systemImage: "externaldrive")
            }
            .accessibilityIdentifier("settings.backup")
        }
    }

    private var privacySection: some View {
        Section("安全与隐私") {
            Toggle("使用生物识别或设备密码锁定", isOn: appLockBinding)
            Label("CardPilot 不需要完整卡号或 CVV。", systemImage: "lock.shield")
            Text("数据保存在本机。请只记录末四位，不要在备注中主动保存敏感认证信息。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

}
