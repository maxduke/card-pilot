import Foundation

/// Unsaved input, separate from business facts. Amount strings retain incomplete user input.
struct TransactionDraft: Codable, Equatable {
    var version = 1
    var id = UUID()
    var cardID: UUID
    var kind: TransactionKind
    var transactionOn: Int
    var postingOn: Int
    var hasPostingDate: Bool
    var amountText: String
    var currencyCode: String
    var merchant: String
    var category: String
    var notes: String
    var status: TransactionStatus
    var originalTransactionID: UUID
    var selectedPromotionIDs: Set<UUID>
    var allocationAmounts: [UUID: String]
    var promotionCurrencies: [UUID: String]
    var automaticallySelectedPromotionIDs: Set<UUID>
    var manuallyDeselectedPromotionIDs: Set<UUID>
    var manuallyEditedAllocationIDs: Set<UUID>
    var editorStep: Int
    var showingInactiveCards: Bool
    var showingOtherFields: Bool

    func validate() throws {
        guard version == 1, (0...1).contains(editorStep) else { throw DraftError.unreadable }
        _ = try LocalDate(rawValue: transactionOn)
        _ = try LocalDate(rawValue: postingOn)
    }
}

enum DraftError: Error { case unreadable }

struct TransactionDraftStore {
    let url: URL

    /// The database path survives relaunch, and changes on whole-store backup restoration.
    init(databaseURL: URL) {
        url = databaseURL.appendingPathExtension("transaction-draft.json")
    }

    func load(isCommitted: (UUID) throws -> Bool = { _ in false }) throws -> TransactionDraft? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw DraftError.unreadable }
        let data = try Data(contentsOf: url)
        let draft = try JSONDecoder().decode(TransactionDraft.self, from: data)
        try draft.validate()
        if try isCommitted(draft.id) {
            try clear()
            return nil
        }
        return draft
    }

    func save(_ draft: TransactionDraft) throws {
        try draft.validate()
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 1_048_576 else { throw DraftError.unreadable }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
