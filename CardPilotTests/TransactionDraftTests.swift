import XCTest
@testable import CardPilot

final class TransactionDraftTests: XCTestCase {
    private func withStore(_ body: (TransactionDraftStore, URL) throws -> Void) throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(TransactionDraftStore(databaseURL: directory.appendingPathComponent("first.store")), directory)
    }

    private func draft() -> TransactionDraft {
        let promotion = UUID()
        return TransactionDraft(cardID: UUID(), kind: .refund, transactionOn: 20260228, postingOn: 20260301,
            hasPostingDate: true, amountText: "00125.", currencyCode: "HKD", merchant: "未完成", category: "", notes: "草稿",
            status: .active, originalTransactionID: UUID(), selectedPromotionIDs: [promotion],
            allocationAmounts: [promotion: "99.123456789012345678"], promotionCurrencies: [promotion: "CNY"],
            automaticallySelectedPromotionIDs: [], manuallyDeselectedPromotionIDs: [UUID()],
            manuallyEditedAllocationIDs: [promotion], editorStep: 1, showingInactiveCards: true, showingOtherFields: true)
    }

    func testRelaunchRetainsIncompleteInputManualAllocationsAndNaturalDates() throws {
        try withStore { store, directory in
            let input = draft()
            try store.save(input)
            let reopened = TransactionDraftStore(databaseURL: directory.appendingPathComponent("first.store"))
            XCTAssertEqual(try reopened.load(), input)
            let otherStore = TransactionDraftStore(databaseURL: directory.appendingPathComponent("restored.store"))
            XCTAssertNil(try otherStore.load())
            try reopened.clear()
            XCTAssertNil(try reopened.load())
        }
    }

    func testRevertingFreshDraftClearsFileButResumedDraftRemains() throws {
        try withStore { store, _ in
            var initial = draft()
            initial.amountText = ""
            initial.merchant = ""
            var changed = initial
            changed.amountText = "125"
            XCTAssertTrue(try store.persist(changed, initial: initial, isResumed: false))
            XCTAssertEqual(try store.load(), changed)
            XCTAssertFalse(try store.persist(initial, initial: initial, isResumed: false))
            XCTAssertNil(try store.load())
            XCTAssertTrue(try store.persist(changed, initial: changed, isResumed: true))
            XCTAssertEqual(try store.load(), changed)
        }
    }

    func testCommitBeforeCleanupDoesNotRecoverDuplicate() throws {
        try withStore { store, _ in
            let input = draft()
            try store.save(input)
            XCTAssertEqual(try store.load(isCommitted: { _ in false }), input)
            XCTAssertNil(try store.load(isCommitted: { $0 == input.id }))
            XCTAssertNil(try store.load())
        }
    }

    func testCommittedDraftCleanupFailureDoesNotBlockNewTransaction() throws {
        try withStore { store, directory in
            let input = draft()
            try store.save(input)
            let failingCleanup = TransactionDraftStore(databaseURL: directory.appendingPathComponent("first.store"),
                                                      removeFile: { _ in throw DraftError.unreadable })
            XCTAssertNil(try failingCleanup.load(isCommitted: { $0 == input.id }))
            XCTAssertEqual(try store.load(), input, "Failed cleanup leaves the file, but it must not be offered for recovery.")
            XCTAssertThrowsError(try failingCleanup.clear(), "An explicit discard still reports failure.")
            XCTAssertEqual(try failingCleanup.load(isCommitted: { _ in false }), input)
        }
    }

    func testFailedCommitLookupKeepsRecoverableDraft() throws {
        try withStore { store, _ in
            let input = draft()
            try store.save(input)
            XCTAssertThrowsError(try store.load(isCommitted: { _ in throw DraftError.unreadable }))
            XCTAssertEqual(try store.load(), input)
        }
    }

    func testInvalidOrOversizeWriteRetainsPreviousDraft() throws {
        try withStore { store, _ in
            let input = draft()
            try store.save(input)
            var invalid = input
            invalid.transactionOn = 20260230
            XCTAssertThrowsError(try store.save(invalid))
            invalid = input
            invalid.notes = String(repeating: "x", count: 1_048_577)
            XCTAssertThrowsError(try store.save(invalid))
            XCTAssertEqual(try store.load(), input)
        }
    }

    func testUnknownVersionAndCorruptionRequireExplicitDiscard() throws {
        try withStore { store, _ in
            var input = draft()
            input.version = 2
            let futureData = try JSONEncoder().encode(input)
            try futureData.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), futureData)
            let corrupt = Data("{incomplete".utf8)
            try corrupt.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
            try store.clear()
            XCTAssertNil(try store.load())
        }
    }
}
