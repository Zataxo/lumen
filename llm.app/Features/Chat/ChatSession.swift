import Foundation
import Observation
import SwiftData

/// The in-progress reply. Only the streaming row observes it, so token updates never
/// re-render the rest of the message list.
@Observable
final class LiveReply {
    let messageID: UUID
    let startedAt = ContinuousClock.now
    var content = ""
    var thinking = ""
    var hasFirstToken = false
    /// When reasoning began; drives the live "Thinking… 4s" label.
    var thinkingStartedAt: ContinuousClock.Instant?
    var thinkingDuration: Duration?

    init(messageID: UUID) {
        self.messageID = messageID
    }
}

/// Owns one chat's generation lifecycle: send, stream, stop, regenerate, edit-and-resend.
/// Networking and parsing stay in providers; persistence goes through SwiftData.
@Observable
final class ChatSession {
    private(set) var chat: Chat?
    /// Server / model chosen before the chat exists (a new chat). Once the chat exists, its
    /// own `serverID` / `modelID` are the source of truth.
    private(set) var pendingServerID: UUID?
    private(set) var pendingModelID: String?

    private(set) var live: LiveReply?
    /// The composer's text (lives here so the welcome screen can fill it).
    var draft = ""
    /// Overrides chosen before the chat exists; applied when it's created.
    private var pendingOverrides = ChatOverrides()

    /// This chat's system prompt / parameter overrides.
    var overrides: ChatOverrides {
        get { chat?.overrides ?? pendingOverrides }
        set {
            if let chat { chat.overrides = newValue } else { pendingOverrides = newValue }
        }
    }

    /// Images waiting to be sent with the next message.
    private(set) var pendingImages: [PendingImage] = []
    private(set) var isPreparingImages = false

    /// Set by the owning view; used to look up model capabilities (vision, thinking).
    /// Observed, so views re-read capabilities once the catalog is attached and loaded.
    var modelCatalog: ModelCatalog?
    /// Problems that prevent sending (no server, no model). Stream errors are stored on the message.
    var notice: ProviderError?

    /// Haptic triggers.
    private(set) var sendCount = 0
    private(set) var finishCount = 0

    var isStreaming: Bool { live != nil }

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private let onChatCreated: (UUID) -> Void

    init(chat: Chat?, modelContext: ModelContext, onChatCreated: @escaping (UUID) -> Void) {
        self.chat = chat
        self.modelContext = modelContext
        self.onChatCreated = onChatCreated
    }

    // MARK: Server / model selection

    /// The server and model this chat will use, falling back to the default server.
    func resolvedSelection(servers: [ServerConfig]) -> (server: ServerConfig?, modelID: String?) {
        let serverID = chat?.serverID ?? pendingServerID
        let server = servers.first { $0.id == serverID } ?? servers.first(where: \.isDefault) ?? servers.first
        let modelID: String?
        if let chat, chat.serverID == server?.id, let chatModel = chat.modelID {
            modelID = chatModel
        } else if pendingServerID == server?.id, let pendingModelID {
            modelID = pendingModelID
        } else {
            modelID = server?.defaultModelID
        }
        return (server, modelID)
    }

    func select(server: ServerConfig, modelID: String) {
        if let chat {
            chat.serverID = server.id
            chat.modelID = modelID
        } else {
            pendingServerID = server.id
            pendingModelID = modelID
        }
        notice = nil
    }

    /// Known capabilities of a model, or nil when the server doesn't report them
    /// (OpenAI-compatible servers) or the list hasn't loaded yet.
    func capabilities(server: ServerConfig?, modelID: String?) -> Set<ModelCapability>? {
        guard let server, server.kind == .ollama,
              let info = modelCatalog?.model(modelID, on: server.id)
        else { return nil }
        return info.capabilities
    }

    // MARK: Attachments

    /// Downscales images off the main actor and queues them for the next message.
    func addImages(_ datas: [Data]) {
        let room = PendingImage.maxCount - pendingImages.count
        guard room > 0 else {
            notice = .other("You can attach up to \(PendingImage.maxCount) images per message.")
            return
        }
        let batch = Array(datas.prefix(room))
        isPreparingImages = true
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                batch.compactMap(PendingImage.prepare)
            }.value
            isPreparingImages = false
            pendingImages += prepared.prefix(PendingImage.maxCount - pendingImages.count)
            if prepared.count < batch.count {
                notice = .other("Some files couldn't be read as images.")
            } else if datas.count > room {
                notice = .other("Only the first \(PendingImage.maxCount) images were attached.")
            } else {
                notice = nil
            }
        }
    }

    func removePendingImage(_ id: PendingImage.ID) {
        pendingImages.removeAll { $0.id == id }
    }

    // MARK: Actions

    var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty, !isStreaming, !isPreparingImages else { return }
        let (server, modelID) = resolvedSelection(servers: fetchServers())
        guard let server else { notice = .other("Add a server in Settings first."); return }
        guard let modelID else { notice = .other("Choose a model to chat with."); return }
        notice = nil

        let chat: Chat
        if let existing = self.chat {
            chat = existing
        } else {
            chat = Chat(title: text.isEmpty ? "Image" : ChatTitler.title(from: text), serverID: server.id, modelID: modelID)
            // An image-only first message gets a placeholder title; the first text replaces it.
            chat.hasTitle = !text.isEmpty
            chat.overrides = pendingOverrides
            modelContext.insert(chat)
            self.chat = chat
            onChatCreated(chat.id)
        }
        if !chat.hasTitle, !text.isEmpty {
            chat.title = ChatTitler.title(from: text)
            chat.hasTitle = true
        }

        let message = Message(role: .user, content: text)
        append(message, to: chat)
        for (index, image) in images.enumerated() {
            let attachment = Attachment(data: image.data, position: index, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight)
            attachment.message = message
            modelContext.insert(attachment)
        }
        pendingImages = []
        sendCount += 1
        startGeneration(chat: chat, server: server, modelID: modelID)
    }

    func stop() {
        streamTask?.cancel()
    }

    /// Called when the chat is closed or the user switches away: stop streaming, keep partial text.
    func cancel() {
        streamTask?.cancel()
    }

    func regenerate() {
        guard let chat, !isStreaming else { return }
        let messages = fetchMessages(chatID: chat.id)
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        for message in messages where message.position > lastUser.position {
            modelContext.delete(message)
        }
        let (server, modelID) = resolvedSelection(servers: fetchServers())
        guard let server, let modelID else { notice = .other("Choose a model to chat with."); return }
        startGeneration(chat: chat, server: server, modelID: modelID)
    }

    func editAndResend(_ message: Message, newText: String) {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chat, !isStreaming, message.role == .user, !text.isEmpty else { return }
        message.content = text
        for later in fetchMessages(chatID: chat.id) where later.position > message.position {
            modelContext.delete(later)
        }
        let (server, modelID) = resolvedSelection(servers: fetchServers())
        guard let server, let modelID else { notice = .other("Choose a model to chat with."); return }
        sendCount += 1
        startGeneration(chat: chat, server: server, modelID: modelID)
    }

    // MARK: Generation

    private func startGeneration(chat: Chat, server: ServerConfig, modelID: String) {
        guard let connection = ServerConnection(server: server) else {
            notice = .invalidURL
            return
        }
        let history = fetchMessages(chatID: chat.id)
        let defaults = GenerationDefaults.current
        let profile = UserProfile.current(in: modelContext)
        let systemPrompt = SystemPromptBuilder.build(
            base: chat.overrides.systemPrompt ?? defaults.systemPrompt,
            profile: profile.flatMap { $0.includeAboutMeInPrompt ? ProfileContext(name: $0.name, aboutMe: $0.aboutMe) : nil }
        )

        var requestMessages: [ChatRequestMessage] = []
        if !systemPrompt.isEmpty {
            requestMessages.append(ChatRequestMessage(role: .system, content: systemPrompt))
        }
        let capabilities = capabilities(server: server, modelID: modelID)
        // Images go to models that can see, or whose capabilities are unknown.
        let sendImages = capabilities.map { $0.contains(.vision) } ?? true
        requestMessages += history
            .filter { $0.role != .assistant || $0.errorText == nil || !$0.content.isEmpty }
            .map { message in
                ChatRequestMessage(
                    role: message.role,
                    content: message.content,
                    images: sendImages && message.role == .user ? message.sortedAttachments.map(\.data) : []
                )
            }

        let request = ChatRequest(
            model: modelID,
            messages: requestMessages,
            parameters: .merged(chat.overrides.parameters, over: defaults.parameters),
            // Ollama returns reasoning separately when asked; only ask models that support it
            // (others reject the flag).
            enableThinking: capabilities?.contains(.thinking) == true ? true : nil
        )

        let reply = Message(role: .assistant, content: "")
        reply.modelID = modelID
        append(reply, to: chat)
        try? modelContext.save()

        let live = LiveReply(messageID: reply.id)
        self.live = live

        let provider = ProviderFactory.makeProvider(for: connection)
        let accumulator = StreamAccumulator()
        let stream = provider.streamChat(request)
        let producer = Task.detached(priority: .userInitiated) {
            await accumulator.consume(stream)
        }

        streamTask = Task { [weak self] in
            // Pull from the accumulator at ~30 Hz instead of reacting to every token.
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(33))
                    if let snapshot = accumulator.takeSnapshotIfChanged() {
                        Self.apply(snapshot, to: live)
                    }
                }
            }
            let outcome = await withTaskCancellationHandler {
                await producer.value
            } onCancel: {
                producer.cancel()
            }
            ticker.cancel()
            self?.finish(reply: reply, live: live, snapshot: accumulator.snapshot(), outcome: outcome)
        }
    }

    private static func apply(_ snapshot: StreamAccumulator.Snapshot, to live: LiveReply) {
        if live.content != snapshot.content { live.content = snapshot.content }
        if live.thinking != snapshot.thinking { live.thinking = snapshot.thinking }
        if !live.hasFirstToken, snapshot.firstTokenAt != nil { live.hasFirstToken = true }
        if live.thinkingStartedAt == nil, let started = snapshot.thinkingStartedAt { live.thinkingStartedAt = started }
        if live.thinkingDuration == nil, let thinkingStart = snapshot.thinkingStartedAt, let contentStart = snapshot.contentStartedAt {
            live.thinkingDuration = contentStart - thinkingStart
        }
    }

    private func finish(reply: Message, live: LiveReply, snapshot: StreamAccumulator.Snapshot, outcome: StreamAccumulator.Outcome) {
        defer {
            self.live = nil
            streamTask = nil
        }
        // The chat may have been deleted while streaming.
        guard !reply.isDeleted, reply.modelContext != nil, chat.map({ !$0.isDeleted }) ?? true else { return }
        let end = ContinuousClock.now
        reply.content = snapshot.content
        reply.thinking = snapshot.thinking.isEmpty ? nil : snapshot.thinking
        reply.thinkingSeconds = snapshot.thinkingDuration(end: end)?.seconds

        if let firstTokenAt = snapshot.firstTokenAt {
            reply.timeToFirstTokenSeconds = (firstTokenAt - live.startedAt).seconds
            let generation = (end - firstTokenAt).seconds
            reply.totalSeconds = (end - live.startedAt).seconds
            reply.promptTokens = outcome.stats?.promptTokens
            reply.completionTokens = outcome.stats?.completionTokens
            reply.tokensPerSecond = outcome.stats?.tokensPerSecond
                ?? outcome.stats?.completionTokens.map { generation > 0 ? Double($0) / generation : 0 }
        }

        if let error = outcome.error {
            reply.errorText = [error.title, error.hint].compactMap { $0 }.joined(separator: "\n")
        }

        if outcome.wasCancelled, outcome.error == nil, reply.content.isEmpty, reply.thinking == nil {
            // Stopped before anything arrived: drop the empty reply.
            modelContext.delete(reply)
        }
        chat?.updatedAt = .now
        try? modelContext.save()

        if outcome.error == nil, !outcome.wasCancelled { finishCount += 1 }
    }

    // MARK: Persistence helpers

    private func append(_ message: Message, to chat: Chat) {
        let lastPosition = fetchMessages(chatID: chat.id).last?.position ?? -1
        message.chatID = chat.id
        message.position = lastPosition + 1
        message.chat = chat
        modelContext.insert(message)
        chat.updatedAt = .now
    }

    private func fetchMessages(chatID: UUID) -> [Message] {
        let descriptor = FetchDescriptor<Message>(
            predicate: #Predicate { $0.chatID == chatID },
            sortBy: [SortDescriptor(\.position)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchServers() -> [ServerConfig] {
        (try? modelContext.fetch(FetchDescriptor<ServerConfig>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
