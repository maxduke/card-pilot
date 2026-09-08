import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.invalidFile }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @EnvironmentObject private var store: BackupStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document: BackupDocument?
    @State private var preview: RestorePreview?
    @State private var retained: [BackupStore.RetainedBackup] = []
    @State private var busy = false
    @State private var message: String?

    private struct RestorePreview: Identifiable {
        let id = UUID()
        let archive: BackupArchive
        let current: BackupRecords?
    }

    var body: some View {
        Form {
            Section {
                if store.container != nil {
                    Button("导出完整备份", systemImage: "square.and.arrow.up") {
                        perform {
                            document = BackupDocument(data: try await store.exportData())
                            exporting = true
                        }
                    }
                }
                Button("选择备份恢复", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("包含全部账户、卡片、账务规则、活动、交易与历史关系，包括归档和停用数据。备份为未加密文件，请存放在可信位置。")
            }

            Section("恢复方式") {
                Text("恢复会用备份完整替换当前数据，不进行合并。文件内重复 ID 或冲突会拒绝恢复；备份中的同 ID 记录将整体取代当前版本。")
                Text("提醒、常用时区、应用锁和最近使用偏好保留本机设置。恢复后重新计算页面与提醒。")
                if store.container == nil {
                    Text("当前存储无法读取，不能统计或生成恢复前备份。恢复将保留原存储文件，并在独立存储中启用备份数据。")
                } else {
                    Text("替换前会自动保存一份可恢复的旧数据备份，同时保留原存储文件。成功后关闭当前页面并返回首页。")
                }
            }

            Section {
                ForEach(retained) { backup in
                    Button {
                        load(backup.id)
                    } label: {
                        Label(backup.createdAt.formatted(date: .abbreviated, time: .standard), systemImage: "clock.arrow.circlepath")
                    }
                }
                if retained.isEmpty { Text("尚无恢复前备份").foregroundStyle(.secondary) }
            } header: {
                Text("恢复前备份")
            } footer: {
                Text("点击可预览并恢复旧数据。每次替换均保留独立备份，不自动清理；本机副本无法防止设备丢失或卸载，请定期导出。")
            }
            if busy { ProgressView("正在校验和处理备份…") }
        }
        .navigationTitle("完整备份与恢复")
        .disabled(busy)
        .interactiveDismissDisabled(busy)
        .task { refreshRetained() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure: message = "无法读取所选文件，请确认文件已下载并可访问后重试。"
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "CardPilot-备份") { result in
            switch result {
            case .success: message = "备份已导出。"
            case .failure: message = "备份未导出，请检查目标位置后重试。"
            }
        }
        .trackedSheet(item: $preview, onDismiss: refreshRetained) { item in
            RestorePreviewView(archive: item.archive, current: item.current)
        }
        .alert("备份与恢复", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func load(_ url: URL) {
        perform {
            let archive = try await store.prepareFile(url)
            let current = store.container == nil ? nil : try await store.export().records
            preview = RestorePreview(archive: archive, current: current)
        }
    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task { @MainActor in
            await Task.yield()
            defer { busy = false }
            do { try await action() }
            catch { message = (error as? BackupError)?.errorDescription ?? "无法读取或保存备份，请检查文件访问权限和设备空间后重试。" }
        }
    }

    private func refreshRetained() {
        do { retained = try store.retainedBackups() }
        catch { message = "无法读取恢复前备份列表，请检查设备空间和文件访问权限后重试。" }
    }
}

private struct RestorePreviewView: View {
    @EnvironmentObject private var store: BackupStore
    @Environment(\.dismiss) private var dismiss
    let archive: BackupArchive
    let current: BackupRecords?
    @State private var confirming = false
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("备份信息") {
                    LabeledContent("导出时间", value: archive.exportedAt.formatted(date: .abbreviated, time: .standard))
                    LabeledContent("格式版本", value: "\(archive.version)")
                    Text("文件已通过完整校验。归档与停用数据包含在下列数量中。")
                }
                counts("将恢复", archive.records)
                if let current { counts("将替换的当前数据", current) }
                Section {
                    Text(current == nil
                         ? "原存储无法读取，数量未知。原文件将保留，但无法生成恢复前备份。"
                         : "将完整替换当前数据；恢复前备份及原存储会保留。可以从“恢复前备份”再次恢复旧数据。")
                    Text("本机提醒、时区和应用锁设置保持当前值。")
                    Button("替换并恢复", role: .destructive) { confirming = true }
                    if busy { ProgressView("正在保存和核对…") }
                }
            }
            .navigationTitle("恢复预览")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) } }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .alert("确认替换全部当前数据？", isPresented: $confirming) {
                Button("取消", role: .cancel) {}
                Button("替换并恢复", role: .destructive) { restore() }
            } message: {
                Text(current == nil ? "当前数据无法读取，原存储文件将保留。此操作启用所选备份中的全部数据。" : "当前数据将被所选备份取代。恢复前自动保存旧数据备份；无法保存时不会替换。")
            }
            .alert("恢复未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func counts(_ title: String, _ records: BackupRecords) -> some View {
        Section(title) {
            LabeledContent("银行 / 卡组织", value: "\(records.banks.count) / \(records.networks.count)")
            LabeledContent("账户 / 卡片", value: "\(records.accounts.count) / \(records.cards.count)")
            LabeledContent("规则版本 / 账期记录", value: "\(records.billingRules.count) / \(records.billingCycles.count)")
            LabeledContent("促销期 / 系列", value: "\(records.promotions.count) / \(Set(records.promotions.compactMap(\.seriesID)).count)")
            LabeledContent("交易（含退款）", value: "\(records.transactions.count)")
            LabeledContent("退款", value: "\(records.transactions.filter { $0.kindRaw == "refund" }.count)")
            LabeledContent("促销分配", value: "\(records.allocations.count)")
        }
    }

    private func restore() {
        busy = true
        Task { @MainActor in
            await Task.yield()
            defer { busy = false }
            do { try await store.restore(archive) }
            catch { errorMessage = (error as? BackupError)?.errorDescription ?? "恢复失败，原存储仍保留。请检查设备空间后重试。" }
        }
    }
}
