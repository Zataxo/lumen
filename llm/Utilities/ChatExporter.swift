import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Plain value snapshot of a chat for export (decoupled from SwiftData).
nonisolated struct ExportedChat: Codable, Hashable, Sendable {
    struct Message: Codable, Hashable, Sendable {
        var role: MessageRole
        var content: String
        var thinking: String?
        var modelID: String?
        var createdAt: Date
    }

    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var modelID: String?
    var messages: [Message]
}

/// Builds Markdown / JSON exports of chats.
nonisolated enum ChatExporter {
    static func markdown(_ chat: ExportedChat, includeTitle: Bool = true) -> String {
        var lines: [String] = []
        if includeTitle {
            lines.append("# \(chat.title)")
            lines.append("")
        }
        var meta: [String] = []
        if let model = chat.modelID { meta.append("Model: `\(model)`") }
        meta.append("Created: \(chat.createdAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))")
        lines.append("_\(meta.joined(separator: " · "))_")

        for message in chat.messages where message.role != .system {
            lines.append("")
            lines.append("---")
            lines.append("")
            switch message.role {
            case .user:
                lines.append("### You")
            case .assistant:
                lines.append("### Assistant" + (message.modelID.map { " (\($0))" } ?? ""))
            case .system:
                continue
            }
            lines.append("")
            if let thinking = message.thinking, !thinking.isEmpty {
                lines.append("<details><summary>Thinking</summary>")
                lines.append("")
                lines.append(thinking.trimmingCharacters(in: .whitespacesAndNewlines))
                lines.append("")
                lines.append("</details>")
                lines.append("")
            }
            lines.append(message.content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// All chats in one document, newest first, each under a level-1 heading.
    static func markdown(_ chats: [ExportedChat]) -> String {
        chats.map { markdown($0) }.joined(separator: "\n\n")
    }

    static func json(_ chats: [ExportedChat]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(chats)
    }

    /// A filesystem-safe file name derived from a chat title.
    static func fileName(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((cleaned.isEmpty ? "Chat" : cleaned).prefix(80))
    }
}

extension ExportedChat {
    /// Snapshot a SwiftData chat with its messages in order.
    init(chat: Chat, context: ModelContext) {
        let chatID = chat.id
        let descriptor = FetchDescriptor<Lumen.Message>(
            predicate: #Predicate { $0.chatID == chatID },
            sortBy: [SortDescriptor(\.position)]
        )
        let messages = (try? context.fetch(descriptor)) ?? []
        self.init(
            id: chat.id,
            title: chat.title,
            createdAt: chat.createdAt,
            updatedAt: chat.updatedAt,
            isPinned: chat.isPinned,
            modelID: chat.modelID,
            messages: messages.map {
                Message(role: $0.role, content: $0.content, thinking: $0.thinking, modelID: $0.modelID, createdAt: $0.createdAt)
            }
        )
    }
}

extension UTType {
    nonisolated static let markdownText = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText
}

/// In-memory document for `.fileExporter`.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownText, .json, .plainText]

    var data: Data
    var contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
