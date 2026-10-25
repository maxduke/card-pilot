import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class ReleasedDataCompatibilityTests: XCTestCase {
    private enum InjectedFailure: Error { case diskFull, unexpectedLegacyFallback }

    func testReleasedStoreRetainsEveryFieldAcrossCurrentSaveAndReopen() throws {
        let fixture = try copiedFixture()
        var expected = fixture.archive.records
        do {
            let container = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
            XCTAssertEqual(container.configurations.first?.url, fixture.storeURL)
            let context = container.mainContext
            context.autosaveEnabled = false
            XCTAssertEqual(try BackupRecords.capture(context), expected)

            let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>())
                .first { $0.notes == "共享账户" })
            XCTAssertEqual(Set(account.cards.map(\.id)),
                           Set(expected.cards.filter { $0.account == account.id }.map(\.id)))
            XCTAssertEqual(account.billingRuleVersions.count, 3)
            let refund = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first { $0.kind == .refund })
            XCTAssertEqual(refund.originalTransaction?.refunds.map(\.id), [refund.id])
            XCTAssertEqual(refund.allocations.count, 1)

            let bank = try XCTUnwrap(context.fetch(FetchDescriptor<Bank>()).first)
            bank.name = "当前版本保存后的历史银行"
            account.customName = "原位升级后的共享主账户"
            try context.save()
            let index = try XCTUnwrap(expected.banks.firstIndex { $0.id == bank.id })
            expected.banks[index].name = bank.name
            let accountIndex = try XCTUnwrap(expected.accounts.firstIndex { $0.id == account.id })
            expected.accounts[accountIndex].customName = account.customName
        }
        let reopened = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        XCTAssertEqual(reopened.configurations.first?.url, fixture.storeURL)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(reopened)), expected)
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)
    }

    func testReleasedArchiveRestoresAcrossRelaunchWithoutReusingOldDraft() async throws {
        let fixture = try copiedFixture()
        let original = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        let recovery = fixture.storeURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        let store = BackupStore(directory: recovery, openLegacy: { original })
        XCTAssertFalse(store.startupFailed)
        let sessionBefore = store.sessionID
        let before = try await store.export()
        XCTAssertEqual(before.records, fixture.archive.records)

        let prepared = try await store.prepare(fixture.archiveData)
        XCTAssertEqual(prepared.records, fixture.archive.records)
        try await store.restore(prepared)
        let restoredURL = try XCTUnwrap(store.container?.configurations.first?.url)
        XCTAssertNotEqual(restoredURL, fixture.storeURL)
        XCTAssertNotEqual(store.sessionID, sessionBefore)
        XCTAssertNil(try TransactionDraftStore(databaseURL: restoredURL).load())
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(original)), fixture.archive.records)

        let relaunched = BackupStore(directory: recovery, openLegacy: { throw InjectedFailure.unexpectedLegacyFallback })
        XCTAssertFalse(relaunched.startupFailed)
        XCTAssertEqual(relaunched.container?.configurations.first?.url, restoredURL)
        let after = try await relaunched.export()
        XCTAssertEqual(after.records, fixture.archive.records)
        let retained = try relaunched.retainedBackups()
        XCTAssertEqual(retained.count, 1)
        let retainedURL = try XCTUnwrap(retained.first?.id)
        XCTAssertEqual(try BackupArchive.decode(BackupStore.read(retainedURL)).records, fixture.archive.records)
    }

    func testReleasedDraftPreservesIncompleteInputAndLegacyNumberMeaning() throws {
        let fixture = try copiedFixture()
        let drafts = TransactionDraftStore(databaseURL: fixture.storeURL)
        let draft = try XCTUnwrap(drafts.load())
        XCTAssertEqual(draft.version, 1)
        XCTAssertNil(draft.amountFormat)
        XCTAssertEqual(draft.inputFormat, .legacy)
        XCTAssertEqual(draft.amountText, "1,234.")
        XCTAssertEqual(AmountInput.decimal(draft.amountText, format: draft.inputFormat), Decimal(1234))
        let card = try XCTUnwrap(fixture.archive.records.cards.first { $0.productName == "共享卡" })
        let promotion = try XCTUnwrap(fixture.archive.records.promotions.first { $0.seriesIndex == 1 })
        XCTAssertEqual(draft.cardID, card.id)
        XCTAssertEqual(draft.selectedPromotionIDs, [promotion.id])
        XCTAssertEqual(draft.manuallyEditedAllocationIDs, [promotion.id])
        let allocation = try XCTUnwrap(draft.allocationAmounts[promotion.id])
        XCTAssertEqual(AmountInput.decimal(allocation, format: draft.inputFormat), Decimal(string: "50.125"))
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)
        try drafts.save(draft)
        XCTAssertEqual(try drafts.load(), draft)
    }

    func testReleasedStoreAndDraftRemainUsableAfterRestoreSaveFailure() async throws {
        let fixture = try copiedFixture()
        let original = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        let recovery = fixture.storeURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        let selectionURL = recovery.appendingPathComponent("active-store.json")
        let store = BackupStore(directory: recovery, openLegacy: { original },
                                save: { _ in throw InjectedFailure.diskFull })
        do {
            try await store.restore(fixture.archive)
            XCTFail("Injected save failure must prevent restoration")
        } catch BackupError.storageFailure {
            // The active released database and its draft remain authoritative.
        }
        XCTAssertFalse(store.startupFailed)
        XCTAssertTrue(store.container === original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selectionURL.path))
        XCTAssertEqual(try BackupRecords.capture(ModelContext(original)), fixture.archive.records)
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)
        let retainedURL = try XCTUnwrap(store.retainedBackups().first?.id)
        XCTAssertEqual(try BackupArchive.decode(BackupStore.read(retainedURL)).records, fixture.archive.records)

        let relaunched = BackupStore(directory: recovery, openLegacy: {
            try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        })
        XCTAssertFalse(relaunched.startupFailed)
        XCTAssertEqual(relaunched.container?.configurations.first?.url, fixture.storeURL)
        let after = try await relaunched.export()
        XCTAssertEqual(after.records, fixture.archive.records)
        XCTAssertEqual(try TransactionDraftStore(databaseURL: fixture.storeURL).load(),
                       try JSONDecoder().decode(TransactionDraft.self, from: fixture.draftData))
    }

    func testUnreadableReleasedStoreIsRetainedDuringBackupRecovery() async throws {
        let fixture = try copiedFixture()
        var unreadable = try Data(contentsOf: fixture.storeURL)
        unreadable.replaceSubrange(0..<16, with: Array(repeating: UInt8(0xff), count: 16))
        try unreadable.write(to: fixture.storeURL, options: .atomic)
        let recovery = fixture.storeURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        let store = BackupStore(directory: recovery, openLegacy: {
            try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        })
        XCTAssertTrue(store.startupFailed)
        XCTAssertNil(store.container)
        XCTAssertEqual(try Data(contentsOf: fixture.storeURL), unreadable)
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)

        try await store.restore(fixture.archive)
        XCTAssertFalse(store.startupFailed)
        XCTAssertNotEqual(store.container?.configurations.first?.url, fixture.storeURL)
        XCTAssertEqual(try Data(contentsOf: fixture.storeURL), unreadable)
        XCTAssertEqual(try Data(contentsOf: fixture.draftURL), fixture.draftData)
        let restored = try await store.export()
        XCTAssertEqual(restored.records, fixture.archive.records)
    }

    private struct Fixture {
        let storeURL: URL
        let archiveData: Data
        let archive: BackupArchive
        let draftData: Data
        var draftURL: URL { storeURL.appendingPathExtension("transaction-draft.json") }
    }

    private struct Manifest: Decodable {
        struct File: Decodable {
            let name: String
            let bytes: Int
            let sha256: String
        }
        let releaseRevision: String
        let schemaVersion: String
        let backupVersion: Int
        let draftVersion: Int
        let files: [File]
    }

    /// Open only disposable copies; never pass the bundled released store to SwiftData.
    private func copiedFixture() throws -> Fixture {
        let bundle = Bundle(for: ReleasedDataCompatibilityTests.self)
        func resource(_ name: String) throws -> URL {
            try XCTUnwrap(bundle.url(forResource: name, withExtension: nil), "Missing released fixture: \(name)")
        }
        let prefix = "CardPilot-v0.1.7"
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: resource("\(prefix).manifest.json")))
        XCTAssertEqual(manifest.releaseRevision, "437d303261ec40ed5a7fb7313d2d910da351779f")
        XCTAssertEqual(manifest.schemaVersion, "3.0.0")
        XCTAssertEqual(manifest.backupVersion, 1)
        XCTAssertEqual(manifest.draftVersion, 1)
        XCTAssertEqual(Set(manifest.files.map(\.name)),
                       ["\(prefix).store", "\(prefix).backup.json", "\(prefix).store.transaction-draft.json"])
        for file in manifest.files {
            let data = try Data(contentsOf: resource(file.name))
            XCTAssertEqual(data.count, file.bytes)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), file.sha256)
        }
        let archiveData = try Data(contentsOf: resource("\(prefix).backup.json"))
        let archive = try BackupArchive.decode(archiveData)
        XCTAssertEqual(archive.records.count, 25)
        let draftData = try Data(contentsOf: resource("\(prefix).store.transaction-draft.json"))
        let directory = URL.temporaryDirectory
            .appendingPathComponent("CardPilotReleasedDataTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // SwiftData can retain SQLite connections after ModelContainer leaves scope.
        // Keep these isolated copies until the simulator test process has exited.
        let storeURL = directory.appendingPathComponent("\(prefix).store")
        try FileManager.default.copyItem(at: resource("\(prefix).store"), to: storeURL)
        try FileManager.default.copyItem(at: resource("\(prefix).store.transaction-draft.json"),
                                       to: storeURL.appendingPathExtension("transaction-draft.json"))
        return Fixture(storeURL: storeURL, archiveData: archiveData, archive: archive, draftData: draftData)
    }
}
