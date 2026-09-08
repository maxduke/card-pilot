import Foundation
import SwiftUI
import UserNotifications

struct BillingCycleTarget: Hashable, Identifiable, Sendable {
    let accountID: UUID
    let cycleKey: Int
    var id: String { "\(accountID).\(cycleKey)" }

    init(accountID: UUID, cycleKey: Int) {
        self.accountID = accountID
        self.cycleKey = cycleKey
    }

    init?(userInfo: [AnyHashable: Any]) {
        guard let account = userInfo["accountID"] as? String,
              let accountID = UUID(uuidString: account),
              let cycleKey = userInfo["cycleKey"] as? Int,
              LocalDate.isValidMonthKey(cycleKey) else { return nil }
        self.init(accountID: accountID, cycleKey: cycleKey)
    }
}

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    @Published private(set) var pendingTarget: BillingCycleTarget?
    @Published private(set) var presentations: Set<UUID> = []

    func receive(_ target: BillingCycleTarget) { pendingTarget = target }
    func presentationOpened(_ id: UUID) { presentations.insert(id) }
    func presentationClosed(_ id: UUID) { presentations.remove(id) }

    func takeTarget(isActive: Bool, isLocked: Bool, isBusy: Bool) -> BillingCycleTarget? {
        guard isActive, !isLocked, !isBusy, presentations.isEmpty else { return nil }
        defer { pendingTarget = nil }
        return pendingTarget
    }
}

// Retained by the app delegate and installed before scenes connect, including cold launch.
final class BillingNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let target = BillingCycleTarget(userInfo: response.notification.request.content.userInfo) else {
            completionHandler()
            return
        }
        Task { @MainActor in
            NotificationRouter.shared.receive(target)
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// Track presentation state rather than visibility: covering a sheet with a nested
// picker must not release the parent's reservation. Release after UIKit dismissal.
@MainActor
private final class SheetRegistration: ObservableObject {
    let id = UUID()
    func begin() { NotificationRouter.shared.presentationOpened(id) }
    func end() { NotificationRouter.shared.presentationClosed(id) }
    deinit {
        let id = id
        Task { @MainActor in NotificationRouter.shared.presentationClosed(id) }
    }
}

private struct TrackedBooleanSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent
    @StateObject private var registration = SheetRegistration()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented { registration.begin() }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                registration.end()
                onDismiss?()
            }) { sheetContent().onAppear { registration.begin() } }
    }
}

private struct TrackedItemSheet<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    let sheetContent: (Item) -> SheetContent
    @StateObject private var registration = SheetRegistration()

    func body(content: Content) -> some View {
        content
            .onChange(of: item != nil, initial: true) { _, presented in
                if presented { registration.begin() }
            }
            .sheet(item: $item, onDismiss: {
                registration.end()
                onDismiss?()
            }) { item in sheetContent(item).onAppear { registration.begin() } }
    }
}

extension View {
    func trackedSheet<Content: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(TrackedBooleanSheet(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    func trackedSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(TrackedItemSheet(item: item, onDismiss: onDismiss, sheetContent: content))
    }
}
