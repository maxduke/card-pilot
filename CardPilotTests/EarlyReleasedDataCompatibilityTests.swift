import CryptoKit
import Foundation
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class EarlyReleasedDataCompatibilityTests: XCTestCase {
    private enum InjectedFailure: Error { case diskFull, unexpectedLegacyFallback }

    func testEarlyV3StorePreservesEveryFieldAcrossUpgradeSaveAndReopen() throws {
        let fixture = try copiedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var expected = fixture.records
        XCTAssertTrue(expected.accounts.allSatisfy { $0.customName == nil })
        XCTAssertTrue(expected.promotions.allSatisfy { $0.benefitTransactionCap == nil })
        do {
            let container = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
            XCTAssertEqual(container.configurations.first?.url, fixture.storeURL)
            let context = container.mainContext
            context.autosaveEnabled = false
            XCTAssertEqual(try BackupRecords.capture(context), expected)
            let account = try XCTUnwrap(context.fetch(FetchDescriptor<CreditCardAccount>())
                .first { $0.notes == "共享账户" })
            account.customName = "升级后的历史账户"
            try context.save()
            let index = try XCTUnwrap(expected.accounts.firstIndex { $0.id == account.id })
            expected.accounts[index].customName = account.customName
        }
        let reopened = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        XCTAssertEqual(reopened.configurations.first?.url, fixture.storeURL)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(reopened)), expected)
    }

    func testEarlyV3ZeroAllocationSurvivesExportRestoreAndRelaunch() async throws {
        let fixture = try copiedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        let recovery = fixture.directory.appendingPathComponent("Recovery")
        let store = BackupStore(directory: recovery, openLegacy: { original })
        XCTAssertFalse(store.startupFailed)
        let data = try await store.exportData()
        let archive = try BackupArchive.decode(data)
        XCTAssertEqual(archive.version, 2)
        XCTAssertEqual(archive.records, fixture.records)

        let zero = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<PromotionAllocation>())
            .first { $0.qualifyingAmount == .zero })
        XCTAssertThrowsError(try zero.validate(), "Normal creation/edit validation remains positive-only")
        var negative = archive.records
        let index = try XCTUnwrap(negative.allocations.firstIndex { $0.id == zero.id })
        negative.allocations[index].qualifyingAmount = BackupDecimal(-1)
        XCTAssertThrowsError(try negative.validatedContainer(), "Archived negatives remain invalid")

        let prepared = try await store.prepare(data)
        XCTAssertEqual(prepared.records, fixture.records)
        try await store.restore(prepared)
        let restoredURL = try XCTUnwrap(store.container?.configurations.first?.url)
        XCTAssertNotEqual(restoredURL, fixture.storeURL)
        XCTAssertEqual(try BackupRecords.capture(ModelContext(original)), fixture.records)

        let relaunched = BackupStore(directory: recovery,
                                   openLegacy: { throw InjectedFailure.unexpectedLegacyFallback })
        XCTAssertFalse(relaunched.startupFailed)
        XCTAssertEqual(relaunched.container?.configurations.first?.url, restoredURL)
        let after = try await relaunched.export()
        XCTAssertEqual(after.records, fixture.records)
        XCTAssertEqual(after.records.allocations.first { $0.id == zero.id }?.qualifyingAmount.value, Decimal.zero)
        let retained = try relaunched.retainedBackups()
        XCTAssertEqual(retained.count, 1)
        let retainedURL = try XCTUnwrap(retained.first?.id)
        XCTAssertEqual(try BackupArchive.decode(BackupStore.read(retainedURL)).records, fixture.records)
    }

    func testEarlyV3RestoreSaveFailureRetainsOriginalZeroAllocation() async throws {
        let fixture = try copiedFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let original = try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        let recovery = fixture.directory.appendingPathComponent("Recovery")
        let store = BackupStore(directory: recovery, openLegacy: { original },
                                save: { _ in throw InjectedFailure.diskFull })
        let archive = try await store.export()
        do {
            try await store.restore(archive)
            XCTFail("Injected save failure must prevent restoration")
        } catch BackupError.storageFailure {
            // The complete old ledger, including its zero fact, stays authoritative.
        }
        XCTAssertFalse(store.startupFailed)
        XCTAssertTrue(store.container === original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.appendingPathComponent("active-store.json").path))
        XCTAssertEqual(try BackupRecords.capture(ModelContext(original)), fixture.records)
        let relaunched = BackupStore(directory: recovery, openLegacy: {
            try CardPilotPersistence.makeContainer(at: fixture.storeURL)
        })
        XCTAssertFalse(relaunched.startupFailed)
        let after = try await relaunched.export()
        XCTAssertEqual(after.records, fixture.records)
        let retainedURL = try XCTUnwrap(store.retainedBackups().first?.id)
        XCTAssertEqual(try BackupArchive.decode(BackupStore.read(retainedURL)).records, fixture.records)
    }

    private struct Fixture {
        let directory: URL
        let storeURL: URL
        let records: BackupRecords
    }

    /// Read immutable native inputs; only disposable database copies reach SwiftData.
    private func copiedFixture() throws -> Fixture {
        let prefix = "CardPilot-v0.1.3"
        let bundle = Bundle(for: Self.self)
        func resource(_ name: String) throws -> URL {
            try XCTUnwrap(bundle.url(forResource: name, withExtension: nil), "Missing native fixture: \(name)")
        }
        struct Manifest: Decodable {
            let releaseTag: String
            let releaseRevision: String
            let counts: [String: Int]
            let files: [File]
            struct File: Decodable { let name: String; let bytes: Int; let sha256: String }
        }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: resource(prefix + ".manifest.json")))
        XCTAssertEqual(manifest.releaseTag, "v0.1.3")
        XCTAssertEqual(manifest.releaseRevision, "3553b38c19dbb38004d201bdfa7600648b35e6ee")
        XCTAssertEqual(manifest.counts, ["banks": 1, "networks": 6, "accounts": 2, "cards": 3,
                                       "billingRules": 4, "billingCycles": 2, "promotions": 2,
                                       "transactions": 4, "allocations": 3])
        XCTAssertEqual(Set(manifest.files.map(\.name)), [prefix + ".store", prefix + ".expected-records.json"])
        for entry in manifest.files {
            let data = try Data(contentsOf: resource(entry.name))
            XCTAssertEqual(data.count, entry.bytes)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), entry.sha256)
        }
        let records = try JSONDecoder().decode(BackupRecords.self,
            from: Data(contentsOf: resource(prefix + ".expected-records.json")))
        XCTAssertEqual(records.count, 27)
        XCTAssertEqual(records.allocations.filter { $0.qualifyingAmount.value == .zero }.count, 1)
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let storeURL = directory.appendingPathComponent("ledger.store")
        try FileManager.default.copyItem(at: resource(prefix + ".store"), to: storeURL)
        return Fixture(directory: directory, storeURL: storeURL, records: records)
    }
}
