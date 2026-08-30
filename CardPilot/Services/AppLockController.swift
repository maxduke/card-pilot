import Combine
import LocalAuthentication

/// Owns transient lock state; persistence of the user's preference belongs to the caller.
@MainActor
final class AppLockController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool

    init(enabled: Bool = false) {
        isEnabled = enabled
        isLocked = enabled
    }

    func canUseDeviceAuthentication() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || canUseDeviceAuthentication() else { return false }
        isEnabled = enabled
        isLocked = enabled
        return true
    }

    func lockIfNeeded() {
        if isEnabled {
            isLocked = true
        }
    }

    func applicationDidEnterBackground() {
        lockIfNeeded()
    }

    func unlock() async -> Bool {
        guard isEnabled else {
            isLocked = false
            return true
        }

        let context = LAContext()
        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvaluateError) else {
            isLocked = true
            return false
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解锁 CardPilot"
            )
            isLocked = !authenticated
            return authenticated
        } catch {
            isLocked = true
            return false
        }
    }
}
