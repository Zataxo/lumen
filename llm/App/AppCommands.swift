import SwiftUI

/// Menu bar commands (macOS, and iPad with a hardware keyboard).
struct LumenCommands: Commands {
    @FocusedValue(\.sceneActions) private var sceneActions
    @FocusedValue(\.composerActions) private var composerActions
    @FocusedValue(\.chatCommands) private var chatCommands
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { sceneActions?.newChat() }
                .keyboardShortcut("n")
                .disabled(sceneActions == nil)
            #if os(macOS)
            Button("New Window") { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            #endif
        }
        CommandGroup(after: .pasteboard) {
            Button("Paste Image") { composerActions?.pasteImage() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(composerActions?.canAttach != true)
        }
        #if os(iOS)
        // macOS gets ⌘, from the Settings scene; iPadOS needs it here.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { sceneActions?.openSettings() }
                .keyboardShortcut(",")
                .disabled(sceneActions == nil)
        }
        #endif
        CommandMenu("Chat") {
            Button("Switch Model…") { chatCommands?.showPalette() }
                .keyboardShortcut("k")
                .disabled(chatCommands == nil)
            Button("Chat Settings…") { chatCommands?.showChatSettings() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(chatCommands == nil)
            Divider()
            Button("Regenerate Response") { chatCommands?.regenerate() }
                .keyboardShortcut("r")
                .disabled(chatCommands?.canRegenerate != true)
            Button("Stop Generating") { chatCommands?.stop() }
                .keyboardShortcut(".")
                .disabled(chatCommands?.isStreaming != true)
        }
        CommandGroup(replacing: .sidebar) {
            // ⌃⌘S is the system-standard sidebar shortcut on macOS and iPadOS.
            Button("Toggle Sidebar") { sceneActions?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(sceneActions == nil)
        }
    }
}
