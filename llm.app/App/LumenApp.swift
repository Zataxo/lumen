import SwiftData
import SwiftUI

@main
struct LumenApp: App {
    private let modelContainer: ModelContainer
    @State private var statusMonitor = ServerStatusMonitor()
    @State private var settingsRouter = SettingsRouter()
    @State private var modelCatalog = ModelCatalog()
    @State private var pullManager = PullManager()

    init() {
        do {
            modelContainer = try ModelContainer(for: ServerConfig.self, Chat.self, Message.self, Attachment.self, UserProfile.self)
        } catch {
            fatalError("Could not open the Lumen data store: \(error)")
        }
        #if DEBUG
        DebugSeeder.seedIfRequested(into: modelContainer.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .lumenAppearance()
                .environment(pullManager)
                .environment(statusMonitor)
                .environment(settingsRouter)
                .environment(modelCatalog)
        }
        .modelContainer(modelContainer)
        .commands { LumenCommands() }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsRootView()
                .lumenAppearance()
                .environment(pullManager)
                .environment(statusMonitor)
                .environment(settingsRouter)
                .environment(modelCatalog)
        }
        .modelContainer(modelContainer)
        #endif
    }
}
