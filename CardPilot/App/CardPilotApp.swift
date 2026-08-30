import SwiftData
import SwiftUI

@main
struct CardPilotApp: App {
    private let container: ModelContainer

    init() {
        do {
            let container = try CardPilotPersistence.makeContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<CardNetwork>()
            if (try? context.fetchCount(descriptor)) == 0 {
                CardNetwork.makeBuiltIns().forEach(context.insert)
                try? context.save()
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
