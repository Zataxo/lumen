import Observation
import SwiftUI

/// Something a caller wants Settings to do once it's open (e.g. jump straight into "Add Server").
enum SettingsRequest: Equatable {
    case addServer
    case addLocalOllama
}

/// Shared between windows and the macOS Settings scene so any window can open Settings
/// with a pending request.
@Observable
final class SettingsRouter {
    var pendingRequest: SettingsRequest?

    /// Announced just before chats are deleted so every window showing one can stop its stream
    /// and leave the chat first. `nil` ids means "all chats".
    private(set) var deletionEvent: ChatDeletionEvent?

    /// Announces the deletion, then runs `perform` once windows have had a frame to react.
    func deleteChats(_ ids: Set<UUID>?, perform: @escaping @MainActor () -> Void) {
        deletionEvent = ChatDeletionEvent(ids: ids)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            perform()
        }
    }
}

struct ChatDeletionEvent: Equatable {
    let token = UUID()
    let ids: Set<UUID>?

    func affects(_ chatID: UUID) -> Bool { ids?.contains(chatID) ?? true }
}

/// Opens Settings: the Settings window on macOS, a sheet on iOS. Installed by `RootView`.
struct OpenAppSettingsAction {
    var handler: (SettingsRequest?) -> Void = { _ in }

    func callAsFunction(_ request: SettingsRequest? = nil) { handler(request) }
}

/// Per-window actions exposed to menu commands.
struct SceneActions {
    var newChat: () -> Void
    var toggleSidebar: () -> Void
    var openSettings: () -> Void = {}
}

/// Actions on the focused chat, for the Chat menu and keyboard shortcuts.
struct ChatCommands {
    var isStreaming: Bool
    var canRegenerate: Bool
    var stop: () -> Void
    var regenerate: () -> Void
    var showPalette: () -> Void
    var showChatSettings: () -> Void
}

extension EnvironmentValues {
    @Entry var openAppSettings = OpenAppSettingsAction()
    /// The window's actions, for views (the command palette) that trigger them.
    @Entry var windowActions: SceneActions?
}

extension FocusedValues {
    @Entry var sceneActions: SceneActions?
    @Entry var chatCommands: ChatCommands?
}
