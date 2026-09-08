import SwiftUI
import UIKit

/// Recovery remains available without a ModelContainer, behind the existing device lock policy.
struct StorageRecoveryView: View {
    @EnvironmentObject private var store: BackupStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var lock = AppLockController(enabled: UserDefaults.standard.bool(forKey: "cardPilot.appLockEnabled"))
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false
    @State private var isAuthenticating = false
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
                    Text("原存储文件仍保留，应用没有自动清空数据。请先解锁设备、检查可用空间并重新打开应用；若仍失败，可更新 CardPilot 或使用完整备份恢复。")
                    Button("重试打开原数据") { store.retryStartup() }
                    NavigationLink("从完整备份恢复") { BackupView() }
                } footer: {
                    Text("请勿卸载应用或删除原存储。没有可用备份时，请保留设备数据以便后续修复。")
                }
            }
            .navigationTitle("存储恢复")
        }
        .privacySensitive()
        .allowsHitTesting(!lock.isLocked)
        .accessibilityHidden(lock.isLocked)
        .background(AppLockShieldWindow(lock: lock, isAuthenticating: isAuthenticating, unlock: authenticate))
        .onAppear {
            refreshLockPolicy()
            authenticate()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if !isAuthenticating { relock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshLockPolicy(); authenticate() }
            else if RootView.shouldRelock(when: phase, isAuthenticating: isAuthenticating) { relock() }
        }
    }

    private func refreshLockPolicy() {
        if lock.disableIfAuthenticationUnavailable() { appLockEnabled = false }
    }

    private func relock() {
        attempt += 1
        isAuthenticating = false
        lock.applicationDidEnterBackground()
    }

    private func authenticate() {
        guard lock.isLocked, !isAuthenticating else { return }
        attempt += 1
        let generation = attempt
        isAuthenticating = true
        Task {
            _ = await lock.unlock()
            guard generation == attempt else { return }
            isAuthenticating = false
        }
    }
}
