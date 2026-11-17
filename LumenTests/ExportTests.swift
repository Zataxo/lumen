import Foundation
import Testing
@testable import Lumen

@Suite("Chat export")
struct ChatExporterTests {
    private let chat = ExportedChat(
        id: UUID(),
        title: "Sorting in Swift",
        createdAt: Date(timeIntervalSince1970: 1_763_200_000),
        updatedAt: Date(timeIntervalSince1970: 1_763_200_100),
        isPinned: true,
        modelID: "llama3.2:3b",
        messages: [
            .init(role: .system, content: "be brief", createdAt: .distantPast),
            .init(role: .user, content: "How do I sort?\n", createdAt: .distantPast),
            .init(role: .assistant, content: "Use `sorted()`.", thinking: "simple question", modelID: "llama3.2:3b", createdAt: .distantPast),
        ]
    )

    @Test func markdownHasTitleRolesAndContent() {
        let markdown = ChatExporter.markdown(chat)
        #expect(markdown.hasPrefix("# Sorting in Swift\n"))
        #expect(markdown.contains("Model: `llama3.2:3b`"))
        #expect(markdown.contains("### You\n\nHow do I sort?"))
        #expect(markdown.contains("### Assistant (llama3.2:3b)"))
        #expect(markdown.contains("Use `sorted()`."))
        #expect(markdown.contains("<details><summary>Thinking</summary>"))
        #expect(!markdown.contains("be brief")) // system prompt omitted
    }

    @Test func exportedMarkdownParsesBack() {
        let blocks = MarkdownParser.parse(ChatExporter.markdown(chat)).blocks
        guard case .heading(1, let title) = blocks.first else { Issue.record("No title heading"); return }
        #expect(String(title.characters) == "Sorting in Swift")
    }

    @Test func jsonRoundTrips() throws {
        let data = try ChatExporter.json([chat])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ExportedChat].self, from: data)
        #expect(decoded == [chat])
    }

    @Test func multipleChatsAreSeparated() {
        let combined = ChatExporter.markdown([chat, chat])
        #expect(combined.components(separatedBy: "# Sorting in Swift\n").count == 3)
    }

    @Test(arguments: [
        ("What's 2/3?", "What's 2 3"),
        ("  ..hidden. ", "hidden"),
        ("a:b*c?\"d<e>f|g", "a b c d e f g"),
        ("", "Chat"),
    ])
    func safeFileNames(title: String, expected: String) {
        #expect(ChatExporter.fileName(for: title) == expected)
    }
}
