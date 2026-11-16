import Foundation
import SwiftData

/// iOS keeps Keychain items when an app is deleted, so a reinstall would otherwise find the
/// old "signed in" session (and API keys for servers that no longer exist). UserDefaults and
/// the database are deleted with the app, which is how a fresh install is recognised.
nonisolated enum FreshInstallGuard {
    static let markerKey = "install.marker"

    /// Call once at launch, before anything reads the Keychain.
    /// - Parameter hasExistingData: whether the database already holds servers or chats.
    ///   Existing users updating to a version with this guard have data, so they stay signed in.
    @discardableResult
    static func run(defaults: UserDefaults = .standard, hasExistingData: Bool, clear: () -> Void) -> Bool {
        guard defaults.object(forKey: markerKey) == nil else { return false }
        defaults.set(Date.now.timeIntervalSince1970, forKey: markerKey)
        guard !hasExistingData else { return false }
        clear()
        return true
    }

    @MainActor
    static func run(container: ModelContainer) {
        let context = container.mainContext
        let hasData = ((try? context.fetchCount(FetchDescriptor<ServerConfig>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<Chat>())) ?? 0) > 0
        run(hasExistingData: hasData) {
            KeychainSessionStorage().save(nil)
            KeychainStore.deleteAllSecrets()
        }
    }
}
