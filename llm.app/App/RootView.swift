import SwiftData
import SwiftUI

/// Picks the layout for the window: split view on Mac / regular-width iPad, slide-over drawer
/// on iPhone and narrow iPad multitasking. Selection is per window.
struct RootView: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isSettingsPresented = false
    #else
    @Environment(\.openSettings) private var openSettings
    #endif
    @Environment(SettingsRouter.self) private var settingsRouter

    @State private var selectedChatID: UUID?

    var body: some View {
        layout
            .environment(\.openAppSettings, OpenAppSettingsAction { request in
                settingsRouter.pendingRequest = request
                #if os(iOS)
                isSettingsPresented = true
                #else
                openSettings()
                #endif
            })
            #if os(iOS)
            .sheet(isPresented: $isSettingsPresented) {
                SettingsRootView()
            }
            #endif
    }

    @ViewBuilder
    private var layout: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            CompactRootView(selectedChatID: $selectedChatID)
        } else {
            SplitRootView(selectedChatID: $selectedChatID)
        }
        #else
        SplitRootView(selectedChatID: $selectedChatID)
        #endif
    }
}

/// `NavigationSplitView` layout. The sidebar's open/closed state is restored between launches.
struct SplitRootView: View {
    @Binding var selectedChatID: UUID?
    @AppStorage(StorageKeys.sidebarVisible) private var storedSidebarVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openAppSettings) private var openAppSettings

    init(selectedChatID: Binding<UUID?>) {
        _selectedChatID = selectedChatID
        let visible = UserDefaults.standard.object(forKey: StorageKeys.sidebarVisible) as? Bool ?? true
        _columnVisibility = State(initialValue: visible ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedChatID: $selectedChatID, onNewChat: newChat)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            NavigationStack {
                DetailView(selectedChatID: $selectedChatID)
                    .toolbar {
                        if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .navigation) {
                                NewChatToolbarButton(action: newChat)
                            }
                        }
                    }
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            storedSidebarVisible = newValue != .detailOnly
        }
        .focusedSceneValue(\.sceneActions, actions)
        .environment(\.windowActions, actions)
    }

    private var actions: SceneActions {
        SceneActions(newChat: newChat, toggleSidebar: toggleSidebar, openSettings: { openAppSettings() })
    }

    private func newChat() {
        selectedChatID = nil
    }

    private func toggleSidebar() {
        withAnimation(Motion.spring(reduceMotion: reduceMotion)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}

struct NewChatToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Chat", systemImage: "square.and.pencil")
        }
        .help("New Chat (⌘N)")
    }
}

enum StorageKeys {
    static let sidebarVisible = "sidebar.isVisible"
}
