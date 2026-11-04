import SwiftData
import SwiftUI
import UIKit

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction
    let cards: [Card]
    let promotions: [Promotion]

    var body: some View {
        NavigationStack {
            TransactionDetailContent(transaction: transaction, cards: cards,
                                     promotions: promotions,
                                     onDone: { dismiss() })
        }
        .accessibilityElement(children: .contain)
        .transactionSaveFeedback()
    }
}

private struct TransactionDetailContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let transaction: Transaction
    let cards: [Card]
    let promotions: [Promotion]
    var onDone: (() -> Void)? = nil

    private enum EditorDestination: String, Identifiable {
        case edit, refund
        var id: String { rawValue }
    }

    @State private var editorDestination: EditorDestination?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(transaction.merchant.isEmpty ? "未填写商户" : transaction.merchant)
                        .font(.title3.weight(.semibold))
                    Text(signedAmountText(transaction))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .foregroundStyle(transaction.status == .reversed ? .secondary : .primary)
                        .strikethrough(transaction.status == .reversed)
                    HStack(spacing: 8) {
                        detailTag(transaction.kind == .refund ? "退款" : "消费", color: transaction.kind == .refund ? .orange : .blue)
                        if transaction.status == .reversed {
                            detailTag("已冲正", color: .red)
                        } else {
                            detailTag("有效", color: .green)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("交易信息") {
                LabeledContent("卡片", value: cardLabel(transaction.card))
                LabeledContent("交易日期", value: CardPilotUI.dateText(transaction.transactionOn))
                LabeledContent("入账日期", value: CardPilotUI.dateText(transaction.postingOn))
                LabeledContent("币种", value: transaction.currencyCode)
                LabeledContent("分类", value: transaction.category.isEmpty ? "未分类" : transaction.category)
                LabeledContent("备注", value: transaction.notes.isEmpty ? "无" : transaction.notes)
            }

            Section("促销分配") {
                if transaction.allocations.isEmpty {
                    Label("本笔未计入促销", systemImage: "tag.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transaction.allocations.sorted { $0.promotion.title.localizedCaseInsensitiveCompare($1.promotion.title) == .orderedAscending }, id: \.id) { allocation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(allocation.promotion.title)
                                .font(.subheadline.weight(.medium))
                            Text("计入 \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("促销 \(allocation.promotion.title)，计入 \(CardPilotUI.amountText(allocation.qualifyingAmount, currencyCode: allocation.currencyCode))")
                    }
                }
            }

            if transaction.kind == .refund {
                Section("关联原消费") {
                    if let originalTransaction = transaction.originalTransaction {
                        relatedTransactionRow(originalTransaction)
                    } else {
                        Label("未关联原消费", systemImage: "link.badge.plus")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("关联退款") {
                    Button {
                        editorDestination = .refund
                    } label: {
                        Label("记录退款", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("transaction.recordRefund")
                    if transaction.refunds.isEmpty {
                        Text("暂无关联退款")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transaction.refunds.sorted {
                            $0.transactionOn == $1.transactionOn ? $0.id.uuidString < $1.id.uuidString : $0.transactionOn > $1.transactionOn
                        }, id: \.id) { refund in
                            relatedTransactionRow(refund)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成", action: onDone)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") {
                    editorDestination = .edit
                }
            }
        }
        .trackedSheet(item: $editorDestination) { destination in
            TransactionEditorView(
                transaction: destination == .edit ? transaction : nil,
                cards: cards,
                promotions: promotions,
                initialRefundOriginal: destination == .refund ? transaction : nil
            )
        }
    }

    private func detailTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func relatedTransactionRow(_ related: Transaction) -> some View {
        NavigationLink {
            TransactionDetailContent(transaction: related, cards: cards,
                                     promotions: promotions)
        } label: {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(related.merchant.isEmpty ? "未填写商户" : related.merchant)
                        .font(.subheadline.weight(.medium))
                    Text("\(CardPilotUI.dateText(related.transactionOn)) · \(related.status == .reversed ? "已冲正" : "有效")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text(signedAmountText(related))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(transactionAccessibilityLabel(related))
        }
        .accessibilityIdentifier("transaction.related.\(related.id)")
    }
}
