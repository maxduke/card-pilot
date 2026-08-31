import Combine
import LocalAuthentication

/// Owns transient lock state; persistence of the user's preference belongs to the caller.
@MainActor
final class AppLockController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    private var authenticationGeneration = 0
    private let authenticateDeviceOwner: () async -> Bool

    init(
        enabled: Bool = false,
        authenticateDeviceOwner: @escaping () async -> Bool = AppLockController.authenticateDeviceOwner
    ) {
        isEnabled = enabled
        isLocked = enabled
        self.authenticateDeviceOwner = authenticateDeviceOwner
    }

    func canUseDeviceAuthentication() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard !enabled || canUseDeviceAuthentication() else { return false }
        authenticationGeneration += 1
        isEnabled = enabled
        isLocked = enabled
        return true
    }

    func lockIfNeeded() {
        if isEnabled {
            authenticationGeneration += 1
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

        let generation = authenticationGeneration
        let authenticated = await authenticateDeviceOwner()
        guard generation == authenticationGeneration else { return false }
        isLocked = !authenticated
        return authenticated
    }

    private static func authenticateDeviceOwner() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "解锁 CardPilot"
        )) == true
    }
}
