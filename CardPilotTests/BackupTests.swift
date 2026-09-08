import Foundation
import SwiftData
import XCTest
@testable import CardPilot

@MainActor
final class BackupTests: XCTestCase {
    private enum InjectedFailure: Error { case diskFull }

    func testCompleteRoundTripRetainsEveryFieldAndRelationship() async throws {
        let source = try fixture()
        let archive = BackupArchive(records: try BackupRecords.capture(source.mainContext))
        let encoded = try archive.encoded()
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("12345678901234567890.123456789"))
        let decoded = try BackupArchive.decode(encoded)
        XCTAssertEqual(decoded, archive)
        let restored = try decoded.records.validatedContainer()
        XCTAssertEqual(try BackupRecords.capture(restored.mainContext), archive.records)
        let context = ModelContext(restored)
        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(Set(cards.map { $0.account.id }).count, 1)
        XCTAssertEqual(cards.first?.account.cards.count, 2)
        XCTAssertEqual(cards.first?.account.billingRuleVersions.count, 3)
        let refund = try XCTUnwrap(context.fetch(FetchDescriptor<Transaction>()).first { $0.kind == .refund })
        XCTAssertEqual(refund.originalTransaction?.refunds.map(\.id), [refund.id])
        XCTAssertEqual(refund.allocations.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Promotion>()).filter { $0.archivedAt != nil }.count, 1)
    }

    func testRestoreReplacesSameIDsAndSurvivesRelaunchWithUndoBackup() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original })
        let before = try await store.export().records
        var replacement = BackupArchive(records: before)
        replacement.records.banks[0].name = "恢复后的名称"
        replacement.records.transactions[0].merchant = "恢复后的商户"
        try await store.restore(replacement)
        await assertEqualAsync(try await store.export().records, replacement.records)
        XCTAssertEqual(try BackupRecords.capture(original.mainContext), before)
        let relaunched = BackupStore(directory: directory, openLegacy: { throw InjectedFailure.diskFull })
        XCTAssertFalse(relaunched.startupFailed)
        await assertEqualAsync(try await relaunched.export().records, replacement.records)
        let retained = try XCTUnwrap(store.retainedBackups().first)
        let undo = try await store.prepare(BackupStore.read(retained.id))
        XCTAssertEqual(undo.records, before)
        try await relaunched.restore(undo)
        await assertEqualAsync(try await relaunched.export().records, before)
        XCTAssertEqual(try relaunched.retainedBackups().count, 2)
    }

    func testEmptyBackupIsExactReplacementAndDoesNotReseedOnRelaunch() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original })
        try await store.restore(BackupArchive(records: BackupRecords()))
        let relaunched = BackupStore(directory: directory, openLegacy: { original })
        await assertEqualAsync(try await relaunched.export().records.count, 0)
        XCTAssertFalse(try BackupRecords.capture(original.mainContext).banks.isEmpty)
    }

    func testInvalidReferencesNeverChangeOriginalData() async throws {
        try await assertRejected { $0.records.cards[0].account = UUID() }
        try await assertRejected { $0.records.cards[0].networks = [UUID()] }
        try await assertRejected { $0.records.billingRules[0].account = UUID() }
        try await assertRejected { $0.records.billingCycles[0].account = UUID() }
        try await assertRejected { $0.records.promotions[0].organizingBanks = [UUID()] }
        try await assertRejected { $0.records.promotions[0].eligibleCards = [UUID()] }
        try await assertRejected { $0.records.transactions[0].originalTransaction = UUID() }
        try await assertRejected { $0.records.allocations[0].promotion = UUID() }
    }

    func testDuplicateIDsIncludingDifferentRecordTypesAreRejected() async throws {
        try await assertRejected { $0.records.banks.append($0.records.banks[0]) }
        try await assertRejected { $0.records.cards[0].id = $0.records.banks[0].id }
        try await assertRejected { $0.records.cards[0].networks.append($0.records.cards[0].networks[0]) }
    }

    func testCompositeConflictsAreRejected() async throws {
        try await assertRejected { archive in
            var record = archive.records.billingRules.first { $0.effectiveCycleKey == nil }!
            record.id = UUID()
            archive.records.billingRules.append(record)
        }
        try await assertRejected { archive in
            var record = archive.records.billingCycles[0]
            record.id = UUID()
            archive.records.billingCycles.append(record)
        }
        try await assertRejected { archive in
            var record = archive.records.allocations[0]
            record.id = UUID()
            archive.records.allocations.append(record)
        }
        try await assertRejected { archive in
            var record = archive.records.promotions[0]
            record.id = UUID()
            archive.records.promotions.append(record)
        }
        try await assertRejected { archive in
            var record = archive.records.banks[0]
            record.id = UUID()
            archive.records.banks.append(record)
        }
        try await assertRejected { archive in
            var record = archive.records.networks[0]
            record.id = UUID()
            archive.records.networks.append(record)
        }
    }

    func testMissingBaselineAndInvalidRawStatusesAreRejected() async throws {
        try await assertRejected { $0.records.billingRules.removeAll { $0.effectiveCycleKey == nil } }
        try await assertRejected { $0.records.cards[0].statusRaw = "unknown" }
        try await assertRejected { $0.records.accounts[0].statusRaw = "unknown" }
        try await assertRejected { $0.records.transactions[0].kindRaw = "unknown" }
        try await assertRejected { $0.records.promotions[0].enrollmentStatusRaw = "unknown" }
        try await assertRejected { $0.records.billingRules[0].repaymentKindRaw = "unknown" }
    }

    func testDomainConstraintsAreValidatedBeforeDiskWrites() async throws {
        try await assertRejected { $0.records.cards[0].lastFour = "abc" }
        try await assertRejected { $0.records.transactions[0].transactionOn = 20260230 }
        try await assertRejected { $0.records.transactions[0].amount = BackupDecimal(.zero) }
        try await assertRejected { $0.records.allocations[0].qualifyingAmount = BackupDecimal(-1) }
        try await assertRejected { $0.records.allocations[0].currencyCode = "USD" }
        try await assertRejected { archive in
            let index = archive.records.promotions.firstIndex { $0.qualificationThreshold != nil }!
            archive.records.promotions[index].benefitTransactionCap = 2
        }
        try await assertRejected { $0.records.accounts[0].statusRaw = "closed"; $0.records.accounts[0].closedOn = nil }
        try await assertRejected { $0.records.billingRules[0].repaymentValue = Int.max }
        try await assertRejected { $0.records.promotions[0].seriesIndex = -1 }
        try await assertRejected { $0.records.promotions[0].seriesIndex = Int.max }
        try await assertRejected { $0.records.billingCycles[0].statementDateOverride = 99991231 }
    }

    func testRefundCannotReferenceRefundOrAnotherCardPurchase() async throws {
        try await assertRejected { archive in
            let index = archive.records.transactions.firstIndex { $0.kindRaw == "refund" }!
            archive.records.transactions[index].originalTransaction = archive.records.transactions[index].id
        }
        try await assertRejected { archive in
            let index = archive.records.transactions.firstIndex { $0.kindRaw == "refund" }!
            let otherCard = archive.records.cards.first { $0.id != archive.records.transactions[index].card }!
            archive.records.transactions[index].card = otherCard.id
        }
    }

    func testUnknownVersionAndMalformedFileLeaveOriginalUnchanged() async throws {
        let original = try fixture()
        let store = BackupStore(directory: try temporaryDirectory(), openLegacy: { original })
        let before = try await store.export().records
        var unsupported = BackupArchive(records: before)
        unsupported.version = 999
        await assertThrowsAsync(try await store.restore(unsupported))
        unsupported.version = 1
        unsupported.format = "OtherApp"
        await assertThrowsAsync(try await store.restore(unsupported))
        for data in [Data("{".utf8), Data("{}".utf8), Data("{\"format\":\"CardPilotBackup\",\"version\":1}".utf8)] {
            await assertThrowsAsync(try await store.prepare(data))
        }
        await assertEqualAsync(try await store.export().records, before)
        XCTAssertTrue(try store.retainedBackups().isEmpty)
    }

    func testDecimalDecoderRejectsRoundingAndNonStringAmounts() async throws {
        for json in ["1.25", "\"NaN\"", "\"1junk\"", "\"1,25\"", "\"0.12345678901234567890123456789012345678901234567890\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(BackupDecimal.self, from: Data(json.utf8)))
        }
        for value in ["0.01", "12345678901234567890.123456789", "0.0000000000000000000000000001"] {
            let data = Data("\"\(value)\"".utf8)
            let decimal = try JSONDecoder().decode(BackupDecimal.self, from: data)
            XCTAssertEqual(try JSONEncoder().encode(decimal), data)
        }
    }

    func testOversizedInputIsRejectedBeforeDecoding() async throws {
        XCTAssertThrowsError(try BackupArchive.decode(Data(repeating: 32, count: BackupArchive.maximumFileSize + 1)))
    }

    func testStagedSaveFailureRetainsOldStoreAndRecoveryBackup() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original }, save: { _ in throw InjectedFailure.diskFull })
        let before = try await store.export().records
        await assertThrowsAsync(try await store.restore(BackupArchive(records: BackupRecords())))
        await assertEqualAsync(try await store.export().records, before)
        XCTAssertEqual(try BackupRecords.capture(original.mainContext), before)
        XCTAssertEqual(try store.retainedBackups().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("active-store.json").path))
    }

    func testBackupWriteFailureDoesNotWriteStagedStore() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original }, save: { _ in XCTFail("Staging must not start after a backup write failure") }, write: { _, _ in throw InjectedFailure.diskFull })
        let before = try await store.export().records
        await assertThrowsAsync(try await store.restore(BackupArchive(records: BackupRecords())))
        await assertEqualAsync(try await store.export().records, before)
    }

    func testSelectionWriteFailurePreservesPreviouslySelectedStoreAcrossRelaunch() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let first = BackupStore(directory: directory, openLegacy: { original })
        let before = try await first.export().records
        try await first.restore(BackupArchive(records: before))
        let selectionURL = directory.appendingPathComponent("active-store.json")
        let selectionBefore = try Data(contentsOf: selectionURL)
        let failing = BackupStore(directory: directory, openLegacy: { original }, write: { data, url in
            if url.lastPathComponent == "active-store.json" { throw InjectedFailure.diskFull }
            try data.write(to: url, options: .atomic)
        })
        await assertThrowsAsync(try await failing.restore(BackupArchive(records: BackupRecords())))
        XCTAssertEqual(try Data(contentsOf: selectionURL), selectionBefore)
        await assertEqualAsync(try await failing.export().records, before)
        let relaunched = BackupStore(directory: directory, openLegacy: { throw InjectedFailure.diskFull })
        await assertEqualAsync(try await relaunched.export().records, before)
    }

    func testFailedReadbackNeverCommitsSelection() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original }, save: { _ in })
        let before = try await store.export().records
        await assertThrowsAsync(try await store.restore(BackupArchive(records: before)))
        await assertEqualAsync(try await store.export().records, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("active-store.json").path))
    }

    func testStartupFailureCanRestoreWithoutDeletingUnreadableOriginal() async throws {
        let directory = try temporaryDirectory()
        let originalURL = directory.appendingPathComponent("unreadable.store")
        let originalBytes = Data("unreadable-original".utf8)
        try originalBytes.write(to: originalURL)
        let store = BackupStore(directory: directory, openLegacy: { throw InjectedFailure.diskFull })
        XCTAssertTrue(store.startupFailed)
        XCTAssertNil(store.container)
        let fixture = try fixture()
        let archive = BackupArchive(records: try BackupRecords.capture(fixture.mainContext))
        try await store.restore(archive)
        XCTAssertFalse(store.startupFailed)
        await assertEqualAsync(try await store.export().records, archive.records)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)
        XCTAssertTrue(try store.retainedBackups().isEmpty)
    }

    func testMissingOrCorruptSelectionNeverFallsBackToEmptyStore() async throws {
        for bytes in [Data("corrupt".utf8), Data("{\"storeID\":\"\(UUID().uuidString)\"}".utf8)] {
            let directory = try temporaryDirectory()
            let url = directory.appendingPathComponent("active-store.json")
            try bytes.write(to: url)
            var legacyOpened = false
            let store = BackupStore(directory: directory, openLegacy: { legacyOpened = true; return try self.fixture() })
            store.retryStartup()
            XCTAssertTrue(store.startupFailed)
            XCTAssertNil(store.container)
            XCTAssertFalse(legacyOpened)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }

    func testUnsavedEditsPreventExportAndRestore() async throws {
        let original = try fixture()
        let store = BackupStore(directory: try temporaryDirectory(), openLegacy: { original })
        let card = try XCTUnwrap(original.mainContext.fetch(FetchDescriptor<Card>()).first)
        card.notes = "未保存的编辑"
        await assertThrowsAsync(try await store.export())
        await assertThrowsAsync(try await store.restore(BackupArchive(records: BackupRecords())))
        XCTAssertEqual(card.notes, "未保存的编辑")
        XCTAssertTrue(original.mainContext.hasChanges)
    }

    func testInputOrderIsIrrelevantAndDevicePreferencesAreExcluded() async throws {
        let fixture = try fixture()
        let store = BackupStore(directory: try temporaryDirectory(), openLegacy: { fixture })
        let before = try await store.export()
        var shuffled = before
        shuffled.records.cards.reverse()
        shuffled.records.transactions.reverse()
        shuffled.records.billingRules.reverse()
        let prepared = try await store.prepare(shuffled.encoded())
        XCTAssertEqual(prepared.records, before.records)
        let text = String(decoding: try prepared.encoded(), as: UTF8.self)
        for key in ["homeTimeZone", "appLockEnabled", "reminderTime", "notificationRevision"] {
            XCTAssertFalse(text.contains(key))
        }
    }

    func testRestoreKeepsMainActorResponsiveAndRejectsConcurrentOperations() async throws {
        let original = try fixture()
        let enteredSave = expectation(description: "Background staging reached save")
        let releaseSave = DispatchSemaphore(value: 0)
        let store = BackupStore(directory: try temporaryDirectory(), openLegacy: { original }, save: { context in
            XCTAssertFalse(Thread.isMainThread)
            enteredSave.fulfill()
            guard releaseSave.wait(timeout: .now() + 5) == .success else {
                throw InjectedFailure.diskFull
            }
            try context.save()
        })
        let session = store.sessionID
        let restoring = Task { try await store.restore(BackupArchive(records: BackupRecords())) }
        await fulfillment(of: [enteredSave], timeout: 3)
        XCTAssertTrue(store.isBusy)
        XCTAssertEqual(store.sessionID, session)
        await assertThrowsAsync(try await store.export())
        await assertThrowsAsync(try await store.prepare(Data()))
        await assertThrowsAsync(try await store.restore(BackupArchive(records: BackupRecords())))
        releaseSave.signal()
        try await restoring.value
        XCTAssertFalse(store.isBusy)
        XCTAssertNotEqual(store.sessionID, session)
        await assertEqualAsync(try await store.export().records.count, 0)
    }

    func testAsyncFileImportAndExportRetainRecordsAndReleaseBusyAfterFailure() async throws {
        let original = try fixture()
        let directory = try temporaryDirectory()
        let store = BackupStore(directory: directory, openLegacy: { original })
        let data = try await store.exportData()
        let url = directory.appendingPathComponent("export.json")
        try data.write(to: url)
        let prepared = try await store.prepareFile(url)
        XCTAssertEqual(prepared.records, try BackupRecords.capture(original.mainContext))
        await assertThrowsAsync(try await store.prepareFile(directory.appendingPathComponent("missing.json")))
        XCTAssertFalse(store.isBusy)
        await assertEqualAsync(try await store.export().records, prepared.records)
    }

    private func assertRejected(_ mutate: (inout BackupArchive) -> Void, file: StaticString = #filePath, line: UInt = #line) async throws {
        let original = try fixture()
        let store = BackupStore(directory: try temporaryDirectory(), openLegacy: { original }, write: { _, _ in XCTFail("Rejected input must not write to disk") })
        let before = try await store.export().records
        var archive = BackupArchive(records: before)
        mutate(&archive)
        await assertThrowsAsync(try await store.prepare(archive.encoded()), file: file, line: line)
        await assertThrowsAsync(try await store.restore(archive), file: file, line: line)
        await assertEqualAsync(try await store.export().records, before, file: file, line: line)
    }

    private func assertThrowsAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected an error", file: file, line: line)
        } catch {}
    }

    private func assertEqualAsync<T: Equatable>(
        _ expression: @autoclosure () async throws -> T, _ expected: T,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let actual = try await expression()
            XCTAssertEqual(actual, expected, file: file, line: line)
        } catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func fixture() throws -> ModelContainer {
        let container = try CardPilotPersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        context.autosaveEnabled = false
        let event = Date(timeIntervalSince1970: 1_788_888_888.123456)
        let bank = Bank(name: "历史银行", notes: "银行备注", archivedAt: event, presetCode: "cn.icbc")
        context.insert(bank)
        let networks = CardNetwork.makeBuiltIns()
        networks.forEach(context.insert)
        context.insert(CardNetwork(code: "custom", displayName: "自定义组织"))
        let account = CreditCardAccount(bank: bank, trackingStartCycleKey: 202401, creditLimit: Decimal(string: "12345678901234567890.123456789")!, limitCurrencyCode: "HKD", notes: "共享账户")
        context.insert(account)
        let closed = CreditCardAccount(bank: bank, trackingStartCycleKey: 202401, status: .closed, closedOn: 20250830, notes: "已关闭")
        context.insert(closed)
        let card = Card(account: account, productName: "双标历史卡", nickname: "旧卡", networks: [networks[0], networks[1]], lastFour: "1234", status: .inactive, notes: "卡备注")
        context.insert(card)
        context.insert(Card(account: account, productName: "共享卡", networks: [networks[2]], lastFour: "5678"))
        for (owner, effective, day) in [(account, nil as Int?, 5), (account, 202501, 8), (account, 202701, 10), (closed, nil, 20)] {
            context.insert(BillingRuleVersion(account: owner, effectiveCycleKey: effective, statementDay: day, repaymentKind: .daysAfterStatement, repaymentValue: 20))
        }
        context.insert(BillingCycleRecord(account: account, cycleKey: 202508, statementDateOverride: 20250809, repaymentDateOverride: 20250901, repaidAt: event))
        context.insert(BillingCycleRecord(account: closed, cycleKey: 202507))
        let series = UUID()
        let promotion = Promotion(seriesID: series, seriesIndex: 0, title: "历史促销", startOn: 20250801, endOn: 20250831, organizingBanks: [bank], organizingNetworks: [networks[0]], eligibleCards: [card], enrollmentStatus: .enrolled, enrolledOn: 20250802, enrollmentDeadline: 20250810, qualificationDateBasis: .postingDate, stackingAllowed: false, qualificationThreshold: 100, qualifyingCap: 200, perTransactionThreshold: 10, progressCurrencyCode: "HKD", rules: "规则", exclusions: "排除", rewardDescription: "奖励", notes: "活动备注", archivedAt: event)
        context.insert(promotion)
        context.insert(Promotion(seriesID: series, seriesIndex: 1, title: "下一期", startOn: 20250901, endOn: 20250930, benefitTransactionCap: 3, progressCurrencyCode: "HKD"))
        let purchase = Transaction(card: card, transactionOn: 20250803, postingOn: 20250804, amount: Decimal(string: "12345678901234567890.123456789")!, currencyCode: "HKD", merchant: "商户", category: "分类", notes: "交易备注", status: .reversed)
        context.insert(purchase)
        let refund = Transaction(card: card, kind: .refund, transactionOn: 20250902, amount: Decimal(string: "0.0000000000000000000000000001")!, currencyCode: "USD", merchant: "退款商户", originalTransaction: purchase)
        context.insert(refund)
        context.insert(PromotionAllocation(transaction: purchase, promotion: promotion, qualifyingAmount: Decimal(string: "50.123456789")!, currencyCode: "HKD"))
        context.insert(PromotionAllocation(transaction: refund, promotion: promotion, qualifyingAmount: Decimal(string: "0.01")!, currencyCode: "HKD"))
        try context.save()
        return container
    }
}
