import Combine
import Foundation
import SwiftData

/// Changes the active store only after a separate store has been saved and read back.
/// Retained stores are never opened for mutation by this service.
@MainActor
final class BackupStore: ObservableObject {
    @Published private(set) var container: ModelContainer?
    @Published private(set) var sessionID = UUID()
    @Published private(set) var startupFailed = false
    @Published var restoreCompleted = false
    @Published private(set) var isBusy = false

    private let directory: URL
    private let openLegacy: () throws -> ModelContainer
    private let save: @Sendable (ModelContext) throws -> Void
    private let write: @Sendable (Data, URL) throws -> Void
    private var selectionURL: URL { directory.appendingPathComponent("active-store.json") }
    private var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    private struct Selection: Codable { let storeID: UUID }

    struct RetainedBackup: Identifiable {
        let id: URL
        let createdAt: Date
    }

    init(
        directory: URL = URL.applicationSupportDirectory.appendingPathComponent("CardPilotRecovery", isDirectory: true),
        openLegacy: @escaping () throws -> ModelContainer = { try CardPilotPersistence.makeContainer() },
        save: @escaping @Sendable (ModelContext) throws -> Void = { try $0.save() },
        write: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: [.atomic, .completeFileProtection])
        }
    ) {
        self.directory = directory
        self.openLegacy = openLegacy
        self.save = save
        self.write = write
        retryStartup()
    }

    func retryStartup() {
        guard container == nil, !isBusy else { return }
        do {
            let opened: ModelContainer
            if FileManager.default.fileExists(atPath: selectionURL.path) {
                let selection = try JSONDecoder().decode(Selection.self, from: Self.read(selectionURL))
                let url = storeURL(selection.storeID)
                // A missing selected store is an error, never permission to create an empty one.
                guard FileManager.default.fileExists(atPath: url.path) else { throw BackupError.storageFailure }
                opened = try CardPilotPersistence.makeContainer(at: url)
            } else {
                opened = try openLegacy()
                let context = opened.mainContext
                context.autosaveEnabled = false
                if try context.fetchCount(FetchDescriptor<CardNetwork>()) == 0 {
                    CardNetwork.makeBuiltIns().forEach(context.insert)
                    try context.save()
                }
            }
            opened.mainContext.autosaveEnabled = false
            container = opened
            startupFailed = false
        } catch {
            // Do not print the underlying storage error: it can contain financial field values.
            startupFailed = true
        }
    }

    private func beginOperation() throws {
        guard !isBusy else { throw BackupError.operationInProgress }
        guard container?.mainContext.hasChanges != true else { throw BackupError.unsavedChanges }
        isBusy = true
    }

    func export() async throws -> BackupArchive {
        try beginOperation()
        defer { isBusy = false }
        guard let container else { throw BackupError.storageFailure }
        return try await Task.detached {
            try Self.captureArchive(container)
        }.value
    }

    func exportData() async throws -> Data {
        try beginOperation()
        defer { isBusy = false }
        guard let container else { throw BackupError.storageFailure }
        return try await Task.detached {
            try Self.captureArchive(container).encoded()
        }.value
    }

    func prepare(_ data: Data) async throws -> BackupArchive {
        try beginOperation()
        defer { isBusy = false }
        return try await Task.detached { try Self.prepareArchive(data) }.value
    }

    func prepareFile(_ url: URL) async throws -> BackupArchive {
        try beginOperation()
        defer { isBusy = false }
        return try await Task.detached {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try Self.prepareArchive(Self.read(url))
        }.value
    }

    nonisolated private static func captureArchive(_ container: ModelContainer) throws -> BackupArchive {
        // Contexts and all fetched models stay inside the worker that creates them.
        let records = try BackupRecords.capture(ModelContext(container))
        _ = try records.validatedContainer()
        return BackupArchive(records: records)
    }

    nonisolated private static func prepareArchive(_ data: Data) throws -> BackupArchive {
        let archive = try BackupArchive.decode(data)
        let validated = try archive.records.validatedContainer()
        return BackupArchive(exportedAt: archive.exportedAt, records: try BackupRecords.capture(ModelContext(validated)))
    }

    func restore(_ archive: BackupArchive) async throws {
        try beginOperation()
        defer { isBusy = false }
        let active = container
        let directory = directory
        let backupsDirectory = backupsDirectory
        let selectionURL = selectionURL
        let save = save
        let write = write
        let staged = try await Task.detached {
            // Revalidate at the commit boundary, even without the preview UI.
            let prepared = try Self.prepareArchive(archive.encoded())
            let before = try active.map { try Self.captureArchive($0).encoded() }
            do {
                try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                if let before {
                    let backupURL = backupsDirectory.appendingPathComponent("\(UUID().uuidString).json")
                    try write(before, backupURL)
                    guard try Self.read(backupURL) == before else { throw BackupError.verificationFailed }
                }
                let id = UUID()
                let staged = try CardPilotPersistence.makeContainer(at: directory.appendingPathComponent("\(id.uuidString).store"))
                let context = ModelContext(staged)
                context.autosaveEnabled = false
                try prepared.records.insertIntoEmptyStore(context)
                try save(context)
                let readback = try BackupRecords.capture(ModelContext(staged))
                guard readback == prepared.records else { throw BackupError.verificationFailed }
                let selection = try JSONEncoder().encode(Selection(storeID: id))
                // Last fallible operation. Atomic replacement is the durable commit point.
                try write(selection, selectionURL)
                return staged
            } catch let error as BackupError { throw error }
            catch { throw BackupError.storageFailure }
        }.value
        staged.mainContext.autosaveEnabled = false
        container = staged
        startupFailed = false
        sessionID = UUID()
        restoreCompleted = true
    }

    func retainedBackups() throws -> [RetainedBackup] {
        guard FileManager.default.fileExists(atPath: backupsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.map {
            RetainedBackup(id: $0, createdAt: try $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    nonisolated static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: BackupArchive.maximumFileSize + 1) ?? Data()
        guard data.count <= BackupArchive.maximumFileSize else { throw BackupError.tooLarge }
        return data
    }

    private func storeURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).store")
    }
}
