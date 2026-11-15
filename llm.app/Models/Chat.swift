import Foundation
import SwiftData

/// A conversation. The server and model are stored per chat so history keeps working
/// when the default server changes.
@Model
final class Chat {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var serverID: UUID?
    var modelID: String?
    var systemPromptOverride: String?
    /// JSON-encoded `GenerationParameters`; nil fields inherit the app defaults.
    var parametersOverrideData: Data?
    /// True once the title was derived from the first message (or set by the user),
    /// so it isn't overwritten later.
    var hasTitle: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message] = []

    init(title: String = "New Chat", serverID: UUID?, modelID: String?) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.updatedAt = .now
        self.isPinned = false
        self.serverID = serverID
        self.modelID = modelID
    }
}

extension Chat {
    var overrides: ChatOverrides {
        get {
            ChatOverrides(
                systemPrompt: systemPromptOverride,
                parameters: parametersOverrideData.flatMap { try? JSONDecoder().decode(GenerationParameters.self, from: $0) } ?? GenerationParameters()
            )
        }
        set {
            systemPromptOverride = newValue.systemPrompt
            parametersOverrideData = newValue.parameters.isEmpty ? nil : try? JSONEncoder().encode(newValue.parameters)
        }
    }
}

nonisolated enum MessageRole: String, Codable, Sendable {
    case system, user, assistant
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    /// Denormalised for cheap `#Predicate` filtering of one chat's messages.
    var chatID: UUID = UUID()
    /// Order within the chat (timestamps can tie).
    var position: Int = 0
    var roleRawValue: String
    var content: String
    var thinking: String?
    var createdAt: Date
    /// Model that produced an assistant message.
    var modelID: String?
    /// Set when generation failed; the partial content (if any) is kept.
    var errorText: String?

    /// How long the model reasoned before answering.
    var thinkingSeconds: Double?

    @Relationship(deleteRule: .cascade, inverse: \Attachment.message)
    var attachments: [Attachment] = []

    // Stats shown under each reply.
    var promptTokens: Int?
    var completionTokens: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenSeconds: Double?
    var totalSeconds: Double?

    var chat: Chat?

    init(role: MessageRole, content: String, thinking: String? = nil) {
        self.id = UUID()
        self.roleRawValue = role.rawValue
        self.content = content
        self.thinking = thinking
        self.createdAt = .now
    }

    var role: MessageRole { MessageRole(rawValue: roleRawValue) ?? .user }
}
