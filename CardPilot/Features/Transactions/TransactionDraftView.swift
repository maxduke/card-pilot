import SwiftData
import SwiftUI

/// All new-transaction entry points share the same recovery decision before opening a form.
struct TransactionEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: Transaction?
    let cards: [Card]
    let promotions: [Promotion]
    let transactions: [Transaction]
    var initialPromotion: Promotion? = nil
    var initialCard: Card? = nil

    @State private var loaded = false
    @State private var pendingDraft: TransactionDraft?
    @State private var resumedDraft: TransactionDraft?
    @State private var ready = false
    @State private var loadFailed = false

    private var store: TransactionDraftStore {
        TransactionDraftStore(databaseURL: modelContext.container.configurations.first!.url)
    }

    var body: some View {
        Group {
            if transaction != nil || ready {
                TransactionEditorForm(transaction: transaction, cards: cards, promotions: promotions,
                                      transactions: transactions, initialPromotion: initialPromotion,
                                      initialCard: initialCard, draft: resumedDraft, draftStore: store)
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "square.and.pencil").font(.largeTitle)
                        Text(loadFailed ? "草稿暂时无法读取" : "有一笔未完成的交易").font(.headline)
                        Text(loadFailed ? "可以重试，或丢弃草稿后重新填写。" : "草稿尚未记账，也未计入促销进度。")
                            .foregroundStyle(.secondary)
                        if let pendingDraft, !loadFailed {
                            Button("继续草稿") {
                                resumedDraft = pendingDraft
                                ready = true
                            }.buttonStyle(.borderedProminent)
                        }
                        if loadFailed { Button("重试") { load() } }
                        Button("丢弃草稿并新建", role: .destructive) {
                            do {
                                try store.clear()
                                pendingDraft = nil
                                loadFailed = false
                                ready = true
                            } catch { loadFailed = true }
                        }
                    }
                    .padding()
                    .navigationTitle("交易草稿")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                }
            }
        }
        .onAppear {
            guard transaction == nil, !loaded else { return }
            loaded = true
            load()
        }
    }

    private func load() {
        do {
            let draft = try store.load { id in
                try modelContext.fetchCount(FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })) > 0
            }
            pendingDraft = draft
            ready = draft == nil
            loadFailed = false
        } catch { loadFailed = true }
    }
}
