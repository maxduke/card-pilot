import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appLock: AppLockController
    @AppStorage("cardPilot.statementReminderOffsets") private var storedStatementOffsets = "7,3,1,0"
    @AppStorage("cardPilot.repaymentReminderOffsets") private var storedRepaymentOffsets = "7,3,1,0"
    @AppStorage("cardPilot.reminderTime") private var storedReminderTime = "09:00"
    @AppStorage("cardPilot.homeTimeZone") private var storedHomeTimeZone = TimeZone.current.identifier
    @AppStorage("cardPilot.appLockEnabled") private var appLockEnabled = false
    @AppStorage("cardPilot.notificationRevision") private var notificationAuthorizationRevision = 0
    @AppStorage("cardPilot.statementRemindersEnabled") private var statementRemindersEnabled = true
    @AppStorage("cardPilot.repaymentRemindersEnabled") private var repaymentRemindersEnabled = true
    @AppStorage("cardPilot.nextReminderDate") private var nextReminderDate = 0.0
    @AppStorage("cardPilot.firstOmittedReminderDate") private var firstOmittedReminderDate = 0.0
    @AppStorage("cardPilot.scheduledReminderCount") private var scheduledReminderCount = 0
    @AppStorage("cardPilot.notificationWarning") private var notificationWarning = ""

    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingTimeZonePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("账单日提醒", isOn: $statementRemindersEnabled)
                    NavigationLink {
                        ReminderOffsetsEditor(title: "账单日提醒", storedValue: $storedStatementOffsets)
                    } label: {
                        LabeledContent("提醒提前", value: reminderSummary(storedStatementOffsets))
                    }
                    .accessibilityHint("编辑账单日前的提醒天数")
                    .disabled(!statementRemindersEnabled)
                } header: {
                    Text("账单日提醒")
                } footer: {
                    Text("选择需要的提醒节点，设置会立即生效。")
                }

                Section {
                    Toggle("还款日提醒", isOn: $repaymentRemindersEnabled)
                    NavigationLink {
                        ReminderOffsetsEditor(title: "还款日提醒", storedValue: $storedRepaymentOffsets)
                    } label: {
                        LabeledContent("提醒提前", value: reminderSummary(storedRepaymentOffsets))
                    }
                    .accessibilityHint("编辑还款日前的提醒天数")
                    .disabled(!repaymentRemindersEnabled)
                } header: {
                    Text("还款日提醒")
                } footer: {
                    Text("0 天表示当天提醒。")
                }

                Section {
                    DatePicker(
                        "提醒时刻",
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .environment(\.timeZone, reminderTimeZone)
                    .accessibilityValue(storedReminderTime)

                    Button {
                        showingTimeZonePicker = true
                    } label: {
                        LabeledContent("固定时区", value: timeZoneSummary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("选择固定的提醒时区")

                    LabeledContent("通知权限", value: notificationStatusText)
                    notificationAction
                } header: {
                    Text("提醒设置")
                } footer: {
                    Text("提醒始终按照固定时区触发，不会随设备旅行自动切换。")
                }

                Section {
                    LabeledContent("已安排", value: "\(scheduledReminderCount) 条提醒")
                    if nextReminderDate > 0 {
                        LabeledContent("下一次提醒", value: reminderDateText(nextReminderDate))
                    }
                    if firstOmittedReminderDate > 0 {
                        LabeledContent("最早未安排", value: reminderDateText(firstOmittedReminderDate))
                            .foregroundStyle(.orange)
                    }
                    if !notificationWarning.isEmpty {
                        Text(notificationWarning).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("刷新提醒", systemImage: "arrow.clockwise") {
                        notificationAuthorizationRevision &+= 1
                    }
                } header: {
                    Text("提醒计划")
                } footer: {
                    Text("应用会在打开时补充后续提醒。减少提前提醒节点可以安排更长时间的计划。活动报名和结束日期目前仅显示在首页。")
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
                    Button("完成") { dismiss() }
                }
            }
            .task { await refreshNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refreshNotificationStatus() } }
            }
            .sheet(isPresented: $showingTimeZonePicker) {
                TimeZonePicker(selectedIdentifier: $storedHomeTimeZone)
            }
            .alert("无法完成设置", isPresented: errorPresented) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    private func reminderDateText(_ timestamp: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = reminderTimeZone
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
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

    private var reminderTimeZone: TimeZone {
        TimeZone(identifier: storedHomeTimeZone) ?? .current
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let parsed = CardPilotUI.parseReminderTime(storedReminderTime) ?? .init(hour: 9, minute: 0)
                var components = DateComponents()
                components.calendar = reminderCalendar
                components.timeZone = reminderTimeZone
                components.year = 2001
                components.month = 1
                components.day = 1
                components.hour = parsed.hour
                components.minute = parsed.minute
                return components.date ?? .now
            },
            set: { date in
                let components = reminderCalendar.dateComponents([.hour, .minute], from: date)
                guard let hour = components.hour, let minute = components.minute else { return }
                storedReminderTime = String(format: "%02d:%02d", hour, minute)
            }
        )
    }

    private var reminderCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reminderTimeZone
        return calendar
    }

    private var timeZoneSummary: String {
        "\(settingsTimeZoneName(reminderTimeZone, identifier: storedHomeTimeZone)) · \(settingsUTCOffset(reminderTimeZone))"
    }

    @ViewBuilder
    private var notificationAction: some View {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            Button("允许通知") { Task { await requestNotifications() } }
        case .denied:
            Button("前往系统通知设置") { openNotificationSettings() }
        case .authorized, .provisional, .ephemeral:
            Button("管理系统通知设置") { openNotificationSettings() }
        @unknown default:
            Button("前往系统通知设置") { openNotificationSettings() }
        }
    }

    private var notificationStatusText: String {
        switch notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral: return "已允许"
        case .denied: return "已拒绝"
        case .notDetermined: return "尚未请求"
        @unknown default: return "未知"
        }
    }

    private func requestNotifications() async {
        do {
            let granted = try await LocalNotificationScheduler().requestAuthorization()
            await refreshNotificationStatus()
            if granted { notificationAuthorizationRevision &+= 1 }
        } catch {
            errorMessage = "无法请求通知权限：\(error.localizedDescription)"
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshNotificationStatus() async {
        notificationAuthorizationStatus = await LocalNotificationScheduler().authorizationStatus()
    }

    private func reminderSummary(_ rawValue: String) -> String {
        let offsets = Set(CardPilotUI.parseReminderOffsets(rawValue) ?? []).sorted(by: >)
        guard !offsets.isEmpty else { return "未设置" }
        return offsets.map { $0 == 0 ? "当天" : "提前 \($0) 天" }.joined(separator: "、")
    }
}

private struct ReminderOffsetsEditor: View {
    let title: String
    @Binding var storedValue: String
    @Environment(\.dismiss) private var dismiss
    @State private var offsets: Set<Int>
    @State private var customText = ""
    private let commonOffsets = [7, 3, 1, 0]

    init(title: String, storedValue: Binding<String>) {
        self.title = title
        _storedValue = storedValue
        _offsets = State(initialValue: Set(CardPilotUI.parseReminderOffsets(storedValue.wrappedValue) ?? [7, 3, 1, 0]))
    }

    var body: some View {
        Form {
            Section {
                ForEach(commonOffsets, id: \.self) { offset in
                    Toggle(isOn: toggleBinding(for: offset)) {
                        Text(offset == 0 ? "当天" : "提前 \(offset) 天")
                    }
                    .accessibilityHint(offsets.count == 1 && offsets.contains(offset) ? "至少保留一个提醒节点" : "")
                }
            } header: {
                Text("常用节点")
            }

            Section {
                HStack {
                    TextField("天数（0–365）", text: $customText)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("自定义提前天数")
                    Button("添加", action: addCustomOffset)
                        .disabled(!canAddCustomOffset)
                }

                if customOffsets.isEmpty {
                    Text("还没有自定义节点")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customOffsets, id: \.self) { offset in
                        HStack {
                            Text("提前 \(offset) 天")
                            Spacer()
                            Button("删除", role: .destructive) { remove(offset) }
                                .accessibilityLabel("删除提前 \(offset) 天")
                        }
                    }
                }
            } header: {
                Text("自定义节点")
            } footer: {
                Text("最多提前 365 天；重复天数会自动合并并按降序保存。")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .onAppear { persist(offsets) }
    }

    private var customOffsets: [Int] { offsets.subtracting(commonOffsets).sorted(by: >) }

    private var canAddCustomOffset: Bool {
        guard let value = Int(customText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (0...CardPilotUI.maximumReminderOffset).contains(value) && !offsets.contains(value)
    }

    private func toggleBinding(for offset: Int) -> Binding<Bool> {
        Binding(
            get: { offsets.contains(offset) },
            set: { enabled in
                var updated = offsets
                if enabled { updated.insert(offset) }
                else if updated.count > 1 { updated.remove(offset) }
                persist(updated)
            }
        )
    }

    private func addCustomOffset() {
        guard let value = Int(customText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...CardPilotUI.maximumReminderOffset).contains(value) else { return }
        var updated = offsets
        updated.insert(value)
        customText = ""
        persist(updated)
    }

    private func remove(_ offset: Int) {
        guard offsets.count > 1 else { return }
        var updated = offsets
        updated.remove(offset)
        persist(updated)
    }

    private func persist(_ updated: Set<Int>) {
        offsets = updated
        storedValue = updated.sorted(by: >).map(String.init).joined(separator: ",")
    }
}

private struct TimeZonePicker: View {
    @Binding var selectedIdentifier: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var deviceIdentifier: String { TimeZone.current.identifier }
    private var allIdentifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { identifier in
            searchText.isEmpty || timeZoneSearchText(identifier).localizedCaseInsensitiveContains(searchText)
        }.sorted { lhs, rhs in
            timeZoneSearchText(lhs).localizedCaseInsensitiveCompare(timeZoneSearchText(rhs)) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if allIdentifiers.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    if searchText.isEmpty {
                        Section("当前选择") {
                            timeZoneRow(selectedIdentifier)
                        }
                    }
                    if searchText.isEmpty && deviceIdentifier != selectedIdentifier {
                        Section("当前设备") {
                            timeZoneRow(deviceIdentifier)
                        }
                    }
                    Section(searchText.isEmpty ? "全部时区" : "搜索结果") {
                        ForEach(allIdentifiers.filter {
                            !searchText.isEmpty || ($0 != deviceIdentifier && $0 != selectedIdentifier)
                        }, id: \.self) { identifier in
                            timeZoneRow(identifier)
                        }
                    }
                }
            }
            .navigationTitle("选择固定时区")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索城市或时区")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func timeZoneRow(_ identifier: String) -> some View {
        let timeZone = TimeZone(identifier: identifier) ?? .current
        return Button {
            selectedIdentifier = identifier
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeZoneName(timeZone, identifier: identifier))
                        .foregroundStyle(.primary)
                    Text(identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(utcOffset(timeZone))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if selectedIdentifier == identifier {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(timeZoneName(timeZone, identifier: identifier))，\(utcOffset(timeZone))")
        .accessibilityAddTraits(selectedIdentifier == identifier ? .isSelected : [])
    }

    private func timeZoneSearchText(_ identifier: String) -> String {
        let timeZone = TimeZone(identifier: identifier) ?? .current
        return "\(identifier) \(settingsTimeZoneName(timeZone, identifier: identifier))"
    }

    private func timeZoneName(_ timeZone: TimeZone, identifier: String) -> String {
        settingsTimeZoneName(timeZone, identifier: identifier)
    }

    private func utcOffset(_ timeZone: TimeZone) -> String {
        settingsUTCOffset(timeZone)
    }
}

private func settingsTimeZoneName(_ timeZone: TimeZone, identifier: String) -> String {
    let localized = timeZone.localizedName(for: .generic, locale: Locale(identifier: "zh_CN"))
    guard let localized, !localized.isEmpty else {
        return identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
    }
    return localized
}

private func settingsUTCOffset(_ timeZone: TimeZone) -> String {
    let seconds = timeZone.secondsFromGMT(for: .now)
    let sign = seconds >= 0 ? "+" : "−"
    let absolute = abs(seconds)
    return String(format: "UTC%@%02d:%02d", sign, absolute / 3600, (absolute / 60) % 60)
}
