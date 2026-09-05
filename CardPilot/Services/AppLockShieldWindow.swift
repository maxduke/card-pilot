import Combine
import SwiftUI
import UIKit

/// Keeps the app's navigation and sheets mounted while protecting every presentation in the scene.
struct AppLockShieldWindow: UIViewRepresentable {
    let lock: AppLockController
    let isAuthenticating: Bool
    let unlock: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(lock: lock, isAuthenticating: isAuthenticating, unlock: unlock)
    }

    func makeUIView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.isUserInteractionEnabled = false
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowProbe, context: Context) {
        context.coordinator.isAuthenticating = isAuthenticating
        context.coordinator.unlock = unlock
        context.coordinator.refresh()
    }

    static func dismantleUIView(_ uiView: WindowProbe, coordinator: Coordinator) {
        uiView.onWindowChanged = nil
        coordinator.detach()
    }

    final class WindowProbe: UIView {
        var onWindowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChanged?(window)
        }
    }

    @MainActor
    final class Coordinator {
        var isAuthenticating: Bool
        var unlock: () -> Void
        private var isLocked: Bool
        private var subscription: AnyCancellable?
        private weak var contentWindow: UIWindow?
        private weak var previousKeyWindow: UIWindow?
        private var shieldWindow: UIWindow?
        private var hostingController: UIHostingController<LockShield>?
        private var previousInteractionEnabled = true
        private var previousAccessibilityHidden = false

        init(lock: AppLockController, isAuthenticating: Bool, unlock: @escaping () -> Void) {
            self.isLocked = lock.isLocked
            self.isAuthenticating = isAuthenticating
            self.unlock = unlock
            subscription = lock.$isLocked.sink { [weak self] locked in
                self?.isLocked = locked
                self?.refresh()
            }
        }

        func attach(to window: UIWindow?) {
            guard contentWindow !== window else { return }
            hide()
            contentWindow = window
            refresh()
        }

        func refresh() {
            guard isLocked else { hide(); return }
            guard let contentWindow, let scene = contentWindow.windowScene else { return }
            let content = LockShield(isAuthenticating: isAuthenticating, unlock: unlock)
            if let hostingController {
                hostingController.rootView = content
                return
            }

            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            previousInteractionEnabled = contentWindow.isUserInteractionEnabled
            previousAccessibilityHidden = contentWindow.accessibilityElementsHidden
            contentWindow.endEditing(true)
            contentWindow.isUserInteractionEnabled = false
            contentWindow.accessibilityElementsHidden = true

            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .systemBackground
            host.view.accessibilityViewIsModal = true
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
            window.rootViewController = host
            hostingController = host
            shieldWindow = window
            window.makeKeyAndVisible()
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
        }

        func detach() {
            subscription?.cancel()
            hide()
            contentWindow = nil
        }

        private func hide() {
            guard let shieldWindow else { return }
            let wasKey = shieldWindow.isKeyWindow
            shieldWindow.isHidden = true
            shieldWindow.rootViewController = nil
            self.shieldWindow = nil
            hostingController = nil
            contentWindow?.isUserInteractionEnabled = previousInteractionEnabled
            contentWindow?.accessibilityElementsHidden = previousAccessibilityHidden
            if wasKey { (previousKeyWindow ?? contentWindow)?.makeKey() }
            previousKeyWindow = nil
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}

private struct LockShield: View {
    let isAuthenticating: Bool
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("CardPilot 已锁定").font(.title2.bold())
                Text("解锁后继续刚才的操作")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(isAuthenticating ? "正在验证…" : "解锁", action: unlock)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isAuthenticating)
                    .accessibilityIdentifier("unlockApp")
            }
            .padding(24)
        }
    }
}
