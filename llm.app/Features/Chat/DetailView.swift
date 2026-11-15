import SwiftData
import SwiftUI

/// The detail column: onboarding when no server exists, otherwise a chat (new or existing).
/// Owns the window's `ChatSession`; switching chats or closing the window cancels its stream.
struct DetailView: View {
    @Binding var selectedChatID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsRouter.self) private var settingsRouter
    @Environment(ModelCatalog.self) private var catalog
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @State private var session: ChatSession?

    var body: some View {
        Group {
            if servers.isEmpty {
                AddFirstServerView()
            } else if let session {
                ChatView(session: session)
            } else {
                // Keeps the modifiers below alive so `onChange(initial:)` creates the session.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.lumenBackground)
        .navigationTitle(session?.chat.flatMap { $0.isDeleted ? nil : $0.title } ?? "New Chat")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: selectedChatID, initial: true) { _, newID in
            syncSession(to: newID)
        }
        .onDisappear { session?.cancel() }
        .onChange(of: settingsRouter.deletionEvent) { _, event in
            guard let event, let chatID = session?.chat?.id, event.affects(chatID) else { return }
            session?.cancel()
            session = nil
            selectedChatID = nil
            syncSession(to: nil)
        }
    }

    private func syncSession(to chatID: UUID?) {
        // The session that just created this chat keeps running (its stream must survive).
        if let session, session.chat?.id == chatID, chatID != nil || session.chat == nil { return }
        session?.cancel()

        var chat: Chat?
        if let chatID {
            let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == chatID })
            chat = try? modelContext.fetch(descriptor).first
        }
        session = ChatSession(chat: chat, modelContext: modelContext) { createdID in
            selectedChatID = createdID
        }
        session?.modelCatalog = catalog
    }
}

/// Shown until the user adds a server.
struct AddFirstServerView: View {
    @Environment(\.openAppSettings) private var openAppSettings
    #if os(macOS)
    @State private var localOllamaFound = false
    #endif

    var body: some View {
        VStack(spacing: Spacing.xLarge) {
            Image(systemName: "server.rack")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 92, height: 92)
                .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            VStack(spacing: Spacing.small) {
                Text("Add your first server")
                    .font(.title2.weight(.semibold))
                Text("Lumen connects to Ollama or any OpenAI-compatible server — on this device, your network, or the internet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: Spacing.small) {
                #if os(macOS)
                if localOllamaFound {
                    Button {
                        openAppSettings(.addLocalOllama)
                    } label: {
                        Label("Use Ollama on This Mac", systemImage: "desktopcomputer")
                            .frame(minWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                #endif
                Button {
                    openAppSettings(.addServer)
                } label: {
                    Label("Add Server…", systemImage: "plus")
                        .frame(minWidth: 220)
                }
                .modifier(PrimaryOrSecondary(isPrimary: !hasLocalSuggestion))
                .controlSize(.large)
            }
        }
        .padding(Spacing.xxLarge)
        #if os(macOS)
        .task { localOllamaFound = await LocalOllamaDetector.isRunning() }
        #endif
    }

    private var hasLocalSuggestion: Bool {
        #if os(macOS)
        localOllamaFound
        #else
        false
        #endif
    }
}

private struct PrimaryOrSecondary: ViewModifier {
    var isPrimary: Bool

    func body(content: Content) -> some View {
        if isPrimary {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension Color {
    /// Main content background: pure system background, slightly warm-neutral in dark mode
    /// via the asset-free system colors.
    static var lumenBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}
