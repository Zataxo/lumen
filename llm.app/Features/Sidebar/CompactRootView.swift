#if os(iOS)
import SwiftUI

/// iPhone layout: the chat fills the screen and the sidebar slides over it from the leading
/// edge. Open with the toolbar button or an edge swipe; close by tapping the dimmed area,
/// dragging the panel back, or picking a chat.
struct CompactRootView: View {
    @Binding var selectedChatID: UUID?
    @State private var isDrawerOpen = false
    /// Live finger offset while dragging (negative = towards closed).
    @GestureState(resetTransaction: Transaction(animation: Motion.spring(reduceMotion: false)))
    private var dragTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openAppSettings) private var openAppSettings

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(geometry.size.width * 0.84, 340)
            let offset = drawerOffset(width: drawerWidth)
            let progress = 1 - abs(offset) / drawerWidth

            ZStack(alignment: .leading) {
                NavigationStack {
                    DetailView(selectedChatID: $selectedChatID)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    setDrawer(open: true)
                                } label: {
                                    Label("Show Sidebar", systemImage: "sidebar.leading")
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                NewChatToolbarButton(action: newChat)
                            }
                        }
                }
                .overlay(alignment: .leading) { edgeSwipeArea(width: drawerWidth) }
                .accessibilityHidden(isDrawerOpen)

                Color.black
                    .opacity(0.28 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(isDrawerOpen)
                    .onTapGesture { setDrawer(open: false) }
                    .accessibilityLabel("Close sidebar")
                    .accessibilityAddTraits(.isButton)

                SidebarView(selectedChatID: $selectedChatID, onNewChat: newChat)
                    .frame(width: drawerWidth)
                    .background {
                        // Panel fills edge to edge; content stays inside the safe area.
                        UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                            .shadow(color: .black.opacity(0.18 * progress), radius: 18, x: 4)
                            .ignoresSafeArea()
                    }
                    .offset(x: offset)
                    .gesture(closeDragGesture(width: drawerWidth))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onChange(of: selectedChatID) { _, _ in setDrawer(open: false) }
        .focusedSceneValue(\.sceneActions, actions)
        .environment(\.windowActions, actions)
    }

    private var actions: SceneActions {
        SceneActions(newChat: newChat, toggleSidebar: { setDrawer(open: !isDrawerOpen) }, openSettings: { openAppSettings() })
    }

    private func drawerOffset(width: CGFloat) -> CGFloat {
        let base = isDrawerOpen ? 0 : -width
        return min(0, max(-width, base + dragTranslation))
    }

    private func edgeSwipeArea(width: CGFloat) -> some View {
        Color.clear
            .frame(width: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragTranslation) { value, state, _ in
                        state = max(0, value.translation.width)
                    }
                    .onEnded { value in
                        if value.translation.width > width * 0.3 || value.predictedEndTranslation.width > width * 0.5 {
                            setDrawer(open: true)
                        }
                    }
            )
            .allowsHitTesting(!isDrawerOpen)
            .accessibilityHidden(true)
    }

    private func closeDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTranslation) { value, state, _ in
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                if value.translation.width < -width * 0.3 || value.predictedEndTranslation.width < -width * 0.5 {
                    setDrawer(open: false)
                }
            }
    }

    private func setDrawer(open: Bool) {
        guard open != isDrawerOpen else { return }
        withAnimation(Motion.spring(reduceMotion: reduceMotion)) {
            isDrawerOpen = open
        }
    }

    private func newChat() {
        selectedChatID = nil
        setDrawer(open: false)
    }
}
#endif
