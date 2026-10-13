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
    var initialRefundOriginal: Transaction? = nil

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
                                      initialCard: initialCard, initialRefundOriginal: initialRefundOriginal,
                                      draft: resumedDraft, draftStore: store)
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            Image(systemName: "square.and.pencil").font(.largeTitle)
                            Text(loadFailed ? "草稿暂时无法读取" : "有一笔未完成的交易").font(.headline)
                            Text(loadFailed ? "可以重试，或丢弃草稿后重新填写。" : "草稿尚未记账，也未计入促销进度。")
                                .foregroundStyle(.secondary)
                            if let pendingDraft, !loadFailed {
                                draftSummary(pendingDraft)
                                Button("继续草稿") {
                                    resumedDraft = pendingDraft
                                    ready = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
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
                        .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("交易草稿")
                    .navigationBarTitleDisplayMode(.inline)
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

    private func draftSummary(_ draft: TransactionDraft) -> some View {
        let card = cards.first { $0.id == draft.cardID }
        let cardText = card.map {
            "\($0.account.bank.name) · \($0.nickname.isEmpty ? $0.productName : $0.nickname) · 尾号 \($0.lastFour)"
        } ?? "原卡片已不可用，可恢复后重新选择"
        let amountText = CardPilotUI.decimal(draft.amountText, format: draft.inputFormat).map {
            CardPilotUI.amountText($0, currencyCode: draft.currencyCode)
        } ?? (draft.amountText.isEmpty ? "尚未填写金额" : "未完成金额：\(draft.amountText) \(draft.currencyCode)")
        return Text([
            "\(draft.kind == .refund ? "退款" : "消费") · \(amountText)",
            cardText,
            CardPilotUI.dateText(draft.transactionOn),
            draft.merchant
        ].filter { !$0.isEmpty }.joined(separator: "\n"))
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("transactionDraftSummary")
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
