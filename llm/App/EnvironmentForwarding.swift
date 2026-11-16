import SwiftData
import SwiftUI

/// The app-wide objects a view tree needs. Content hosted outside the main window tree
/// (toolbar popovers and menus when the iPad app runs on a Mac) doesn't inherit the
/// environment, and SwiftUI aborts when an `@Environment(SomeObservable.self)` is missing —
/// so such content gets these re-applied explicitly.
struct ForwardedEnvironment {
    let modelContainer: ModelContainer
    let modelCatalog: ModelCatalog
    let pullManager: PullManager
    let statusMonitor: ServerStatusMonitor
    let settingsRouter: SettingsRouter
    let auth: AuthStore
    let openAppSettings: OpenAppSettingsAction
}

extension View {
    func forwardingEnvironment(_ environment: ForwardedEnvironment) -> some View {
        self
            .modelContainer(environment.modelContainer)
            .environment(environment.modelCatalog)
            .environment(environment.pullManager)
            .environment(environment.statusMonitor)
            .environment(environment.settingsRouter)
            .environment(environment.auth)
            .environment(\.openAppSettings, environment.openAppSettings)
            .lumenAppearance()
    }
}
