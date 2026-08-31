import Foundation
import SwiftData
import SwiftUI

@main
struct CardPilotApp: App {
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
