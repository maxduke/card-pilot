import Foundation
import SwiftData
import SwiftUI
import UIKit

enum CardPilotQuickAction: String, CaseIterable, Hashable, Sendable {
    case addTransaction = "com.maxduke.CardPilot.quickAction.addTransaction"
    case promotionProgress = "com.maxduke.CardPilot.quickAction.promotionProgress"

    var title: String {
        switch self {
        case .addTransaction: return "记一笔"
        case .promotionProgress: return "查看促销进度"
        }
    }

    var systemImageName: String {
        switch self {
        case .addTransaction: return "plus.circle"
        case .promotionProgress: return "gift"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: nil
        )
    }

    init?(shortcutItem: UIApplicationShortcutItem) {
        self.init(rawValue: shortcutItem.type)
    }
}

@MainActor
final class CardPilotQuickActionRouter: ObservableObject {
    static let shared = CardPilotQuickActionRouter()

    @Published private(set) var pendingActions: [CardPilotQuickAction] = []

    func enqueue(_ action: CardPilotQuickAction) {
        pendingActions.append(action)
    }

    @discardableResult
    func enqueue(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = CardPilotQuickAction(shortcutItem: shortcutItem) else { return false }
        enqueue(action)
        return true
    }

    func takeNext() -> CardPilotQuickAction? {
        guard !pendingActions.isEmpty else { return nil }
        return pendingActions.removeFirst()
    }
}

@MainActor
final class CardPilotAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = CardPilotQuickAction.allCases.map(\.shortcutItem)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = CardPilotSceneDelegate.self
        }
        return configuration
    }
}

@MainActor
final class CardPilotSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = CardPilotQuickActionRouter.shared.enqueue(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(CardPilotQuickActionRouter.shared.enqueue(shortcutItem))
    }
}

@main
struct CardPilotApp: App {
    @UIApplicationDelegateAdaptor(CardPilotAppDelegate.self) private var appDelegate

    private let container: ModelContainer

    init() {
        if UserDefaults.standard.string(forKey: "cardPilot.homeTimeZone") == nil {
            UserDefaults.standard.set(TimeZone.current.identifier, forKey: "cardPilot.homeTimeZone")
        }
        do {
            let container = try CardPilotPersistence.makeContainer()
            container.mainContext.autosaveEnabled = false
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<CardNetwork>()
            if try context.fetchCount(descriptor) == 0 {
                CardNetwork.makeBuiltIns().forEach(context.insert)
                try context.save()
            }
            self.container = container
        } catch {
            fatalError("无法创建本地数据存储：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
