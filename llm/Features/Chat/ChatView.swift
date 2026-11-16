import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A conversation: message list, composer and the model picker in the toolbar.
struct ChatView: View {
    @Bindable var session: ChatSession
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @Environment(ModelCatalog.self) private var catalog
    @Environment(PullManager.self) private var pullManager
    @Environment(ServerStatusMonitor.self) private var statusMonitor
    @Environment(SettingsRouter.self) private var settingsRouter
    @Environment(AuthStore.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.windowActions) private var windowActions
    @Environment(\.openAppSettings) private var openAppSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDropTargeted = false
    @State private var isPalettePresented = false
    @State private var isExplorerPresented = false
    @State private var isChatSettingsPresented = false

    var body: some View {
        let selection = session.resolvedSelection(servers: servers)
        let capabilities = session.capabilities(server: selection.server, modelID: selection.modelID)
        let supportsVision = capabilities.map { $0.contains(.vision) }
        Group {
            if let chat = session.chat {
                MessageListView(chatID: chat.id, session: session)
                    .id(chat.id)
            } else {
                WelcomeView(session: session, server: selection.server, modelID: selection.modelID)
                    .id(session.chat == nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(
                session: session,
                canSend: selection.server != nil && selection.modelID != nil,
                supportsVision: supportsVision,
                modelName: selection.modelID
            )
        }
        .overlay {
            if isDropTargeted { DropTargetOverlay() }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            guard supportsVision != false else {
                session.notice = .other("\(selection.modelID ?? "This model") can't read images. Choose a model with Vision.")
                return false
            }
            Task { session.addImages(await ImageIntake.load(providers)) }
            return true
        }
        .task(id: selection.server?.id) {
            session.modelCatalog = catalog
            if let server = selection.server { await catalog.load(server) }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ModelPickerButton(
                    session: session,
                    server: selection.server,
                    modelID: selection.modelID,
                    environment: forwardedEnvironment
                ) {
                    isExplorerPresented = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isChatSettingsPresented = true
                } label: {
                    Label("Chat Settings", systemImage: session.overrides.isEmpty ? "slider.horizontal.3" : "slider.horizontal.below.square.filled.and.square")
                }
                .help("Chat Settings (⌥⌘I)")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let server = selection.server, case .failed(let error) = catalog.state(for: server.id) {
                ConnectionBanner(serverName: server.name, error: error) {
                    Task { await catalog.load(server, force: true) }
                } onOpenSettings: {
                    openAppSettings()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selection.server.map { catalog.state(for: $0.id) })
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app is a natural moment to retry an unreachable server.
            if phase == .active, let server = selection.server, case .failed = catalog.state(for: server.id) {
                Task { await catalog.load(server, force: true) }
            }
        }
        .overlay {
            CommandPaletteOverlay(session: session, isPresented: $isPalettePresented, onAction: perform)
        }
        .sheet(isPresented: $isExplorerPresented) {
            if let server = selection.server {
                ChatModelExplorerSheet(session: session, serverID: server.id)
            }
        }
        .sheet(isPresented: $isChatSettingsPresented) {
            ChatSettingsView(session: session)
        }
        #if DEBUG
        .onAppear {
            // UI testing aid: simulators can't send ⌘K.
            if ProcessInfo.processInfo.arguments.contains("-LumenOpenPalette") { isPalettePresented = true }
        }
        #endif
        .focusedSceneValue(\.chatCommands, ChatCommands(
            isStreaming: session.isStreaming,
            canRegenerate: session.chat != nil && !session.isStreaming,
            stop: session.stop,
            regenerate: session.regenerate,
            showPalette: { isPalettePresented.toggle() },
            showChatSettings: { isChatSettingsPresented = true }
        ))
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: session.sendCount)
        .sensoryFeedback(.success, trigger: session.finishCount)
        #endif
    }
}

extension ChatView {
    private var forwardedEnvironment: ForwardedEnvironment {
        ForwardedEnvironment(
            modelContainer: modelContext.container,
            modelCatalog: catalog,
            pullManager: pullManager,
            statusMonitor: statusMonitor,
            settingsRouter: settingsRouter,
            auth: auth,
            openAppSettings: openAppSettings
        )
    }

    private func perform(_ action: CommandPaletteAction) {
        switch action {
        case .newChat: windowActions?.newChat()
        case .chatSettings: isChatSettingsPresented = true
        case .browseModels: isExplorerPresented = true
        case .settings: openAppSettings()
        }
    }
}

/// Non-observed flag so scroll-position tracking doesn't re-render the list.
final class ScrollPin {
    var isAtBottom = true
}

struct MessageListView: View {
    let session: ChatSession
    @Query private var messages: [Message]
    @Environment(\.messageTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pin = ScrollPin()
    /// Observed copy of `pin.isAtBottom`; changes only when crossing the threshold.
    @State private var showsJumpButton = false
    @State private var editingMessageID: UUID?
    private static let bottomID = "bottom"

    init(chatID: UUID, session: ChatSession) {
        self.session = session
        _messages = Query(filter: #Predicate<Message> { $0.chatID == chatID }, sort: \Message.position)
    }

    var body: some View {
        let liveID = session.live?.messageID
        let lastAssistantID = messages.last(where: { $0.role == .assistant })?.id

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: typography.messageSpacing) {
                    ForEach(messages) { message in
                        Group {
                            if message.id == liveID, let live = session.live {
                                LiveReplyRow(live: live) {
                                    if pin.isAtBottom { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                                }
                            } else {
                                MessageRow(
                                    message: message,
                                    isLastAssistant: message.id == lastAssistantID,
                                    isBusy: liveID != nil,
                                    isEditing: editingMessageID == message.id,
                                    actions: actions
                                )
                            }
                        }
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, Spacing.large)
                .padding(.vertical, Spacing.xLarge)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9), value: messages.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Generous threshold: the action bar and stats line appear after a reply finishes
                // and shouldn't count as "scrolled away".
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 150
            } action: { _, isAtBottom in
                pin.isAtBottom = isAtBottom
                withAnimation(.snappy) { showsJumpButton = !isAtBottom }
            }
            .overlay(alignment: .bottom) {
                if showsJumpButton {
                    Button {
                        pin.isAtBottom = true
                        withAnimation(Motion.spring(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(Self.bottomID, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .glassSurface(in: Circle())
                            .overlay { Circle().strokeBorder(.primary.opacity(0.1), lineWidth: 1) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, Spacing.medium)
                    .help("Jump to latest")
                    .accessibilityLabel("Jump to latest message")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .onChange(of: session.isStreaming) { _, isStreaming in
                // Keep the finished reply's action bar in view.
                if !isStreaming, pin.isAtBottom {
                    withAnimation(.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }
            .onChange(of: session.sendCount) { _, _ in
                pin.isAtBottom = true
                withAnimation(.snappy) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
    }

    private var actions: MessageRow.Actions {
        MessageRow.Actions(
            regenerate: { session.regenerate() },
            beginEdit: { editingMessageID = $0 },
            endEdit: { editingMessageID = nil },
            resend: { message, text in
                editingMessageID = nil
                session.editAndResend(message, newText: text)
            }
        )
    }
}

/// Shown above the chat when the current server can't be reached.
struct ConnectionBanner: View {
    let serverName: String
    let error: ProviderError
    var onRetry: () -> Void
    var onOpenSettings: () -> Void
    @State private var isRetrying = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach \(serverName)")
                    .font(.callout.weight(.semibold))
                Text([error.title, error.hint].compactMap { $0 }.joined(separator: " — "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.small)
            VStack(alignment: .trailing, spacing: Spacing.xSmall) {
                Button {
                    isRetrying = true
                    onRetry()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Retry")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption)
            }
        }
        .padding(Spacing.medium)
        .glassSurface(in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.small)
        .accessibilityElement(children: .contain)
    }
}
