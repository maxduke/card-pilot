import SwiftUI
import UIKit

extension Notification.Name {
    static let transactionDidSave = Notification.Name("CardPilot.transactionDidSave")
    static let transactionSaveFeedbackDidDismiss = Notification.Name("CardPilot.transactionSaveFeedbackDidDismiss")
}

struct TransactionSaveFeedback: Equatable {
    let message: String

    static func make(
        kind: TransactionKind,
        amount: Decimal,
        currencyCode: String,
        allocationCount: Int,
        isNew: Bool
    ) -> TransactionSaveFeedback {
        let amountText = CardPilotUI.amountText(amount, currencyCode: currencyCode)
        let action: String
        if isNew {
            action = kind == .refund ? "已记录退款 \(amountText)" : "已记录 \(amountText)"
        } else {
            action = kind == .refund ? "退款已更新 · \(amountText)" : "交易已更新 · \(amountText)"
        }
        let allocationText = allocationCount == 0 ? "未计入活动" : "计入 \(allocationCount) 个活动"
        return TransactionSaveFeedback(message: "\(action) · \(allocationText)")
    }
}

private struct TransactionSaveFeedbackModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    let producesHaptic: Bool
    let announcesSave: Bool
    @State private var message: String?
    @State private var revision = 0
    @State private var pendingFeedback: PendingFeedback?

    private struct PendingFeedback {
        let message: String
        let presentations: Set<UUID>
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Button {
                        // The root and a presented transaction detail share the
                        // confirmation. Closing either also clears the other.
                        NotificationCenter.default.post(name: .transactionSaveFeedbackDidDismiss, object: nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.footnote.weight(.medium))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.quaternary, lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .privacySensitive()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(message)
                    .accessibilityHint("轻点关闭")
                    .accessibilityIdentifier("transaction.saveFeedback")
                    .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .transactionDidSave)) { notification in
                guard scenePhase == .active,
                      let savedMessage = notification.userInfo?["message"] as? String else { return }
                message = nil
                pendingFeedback = PendingFeedback(message: savedMessage, presentations: notificationRouter.presentations)
                presentPendingFeedback()
            }
            .onChange(of: notificationRouter.presentations) { _, _ in presentPendingFeedback() }
            .onReceive(NotificationCenter.default.publisher(for: .transactionSaveFeedbackDidDismiss)) { _ in
                clearFeedback()
            }
            .task(id: voiceOverEnabled ? nil : revision) {
                guard message != nil, !voiceOverEnabled else { return }
                let displayedRevision = revision
                do { try await Task.sleep(for: .seconds(8)) }
                catch { return }
                // A newer save may be waiting for its editor to close. Its
                // pending confirmation must survive the previous timer.
                guard !Task.isCancelled, !voiceOverEnabled,
                      displayedRevision == revision, message != nil else { return }
                clearFeedback()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { clearFeedback() }
            }
            .onDisappear { clearFeedback() }
            .sensoryFeedback(.success, trigger: producesHaptic ? revision : 0)
    }

    private func presentPendingFeedback() {
        guard scenePhase == .active, let pending = pendingFeedback,
              pending.presentations.isEmpty || !pending.presentations.isSubset(of: notificationRouter.presentations) else { return }
        // trackedSheet releases its registration after UIKit dismissal. Start
        // the visible duration and announcement then, including nested editors.
        pendingFeedback = nil
        revision += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            message = pending.message
        }
        if announcesSave && voiceOverEnabled {
            let announcement = NSAttributedString(string: pending.message, attributes: [
                .accessibilitySpeechQueueAnnouncement: NSNumber(value: true)
            ])
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    private func clearFeedback() {
        pendingFeedback = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { message = nil }
    }
}

extension View {
    func transactionSaveFeedbackOverlay(producesHaptic: Bool = false, announcesSave: Bool = false) -> some View {
        modifier(TransactionSaveFeedbackModifier(producesHaptic: producesHaptic, announcesSave: announcesSave))
    }
}
