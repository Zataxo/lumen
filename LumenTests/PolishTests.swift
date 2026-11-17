import Foundation
import SwiftData
import Testing
@testable import Lumen

@Suite("Command palette matching")
struct CommandPaletteMatcherTests {
    @Test func subsequenceMatches() {
        #expect(CommandPaletteMatcher.score("q8", in: "qwen3:8b") != nil)
        #expect(CommandPaletteMatcher.score("gma", in: "gemma3:12b") != nil)
        #expect(CommandPaletteMatcher.score("xyz", in: "llama3.2:3b") == nil)
        #expect(CommandPaletteMatcher.score("ba", in: "ab") == nil) // order matters
    }

    @Test func caseAndSpacesAreIgnored() {
        #expect(CommandPaletteMatcher.score("NEW chat", in: "New Chat") != nil)
    }

    @Test func emptyQueryKeepsOrder() {
        let items = ["b", "a", "c"]
        #expect(CommandPaletteMatcher.rank(items, query: "  ") { [$0] } == items)
    }

    @Test func contiguousAndWordStartRankHigher() {
        let items = ["gemma3:llama-merge", "llama3.2:3b", "codellama:7b"]
        let ranked = CommandPaletteMatcher.rank(items, query: "lla") { [$0] }
        #expect(ranked.first == "llama3.2:3b")
        #expect(Set(ranked) == Set(items))
    }

    @Test func matchesSecondaryFields() {
        struct Row { var title: String; var subtitle: String }
        let rows = [Row(title: "qwen3:8b", subtitle: "Studio"), Row(title: "llama3.2", subtitle: "Laptop")]
        let ranked = CommandPaletteMatcher.rank(rows, query: "studio") { [$0.title, $0.subtitle] }
        #expect(ranked.map(\.title) == ["qwen3:8b"])
    }

    @Test func actionsAreFindable() {
        let titles = CommandPaletteAction.allCases.map(\.title)
        #expect(CommandPaletteMatcher.rank(titles, query: "sett") { [$0] }.first == "Settings…")
    }
}

@Suite("Chat overrides")
struct ChatOverridesTests {
    @Test func mergeTakesOverrideFieldsFirst() {
        let defaults = GenerationParameters(temperature: 0.8, topP: 0.9, contextLength: 8192)
        let override = GenerationParameters(temperature: 0.2)
        #expect(GenerationParameters.merged(override, over: defaults) == GenerationParameters(temperature: 0.2, topP: 0.9, contextLength: 8192))
        #expect(GenerationParameters.merged(nil, over: defaults) == defaults)
    }

    @Test func emptiness() {
        #expect(ChatOverrides().isEmpty)
        #expect(!ChatOverrides(systemPrompt: "").isEmpty) // "send no prompt" is a real override
        #expect(!ChatOverrides(parameters: GenerationParameters(contextLength: 4096)).isEmpty)
    }

    @MainActor
    @Test func roundTripsThroughChat() throws {
        let container = try ModelContainer(
            for: ServerConfig.self, Chat.self, Message.self, Attachment.self, UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let chat = Chat(serverID: nil, modelID: nil)
        container.mainContext.insert(chat)

        let overrides = ChatOverrides(systemPrompt: "Answer in French.", parameters: GenerationParameters(temperature: 0.3, contextLength: 16384))
        chat.overrides = overrides
        #expect(chat.overrides == overrides)
        #expect(chat.parametersOverrideData != nil)

        chat.overrides = ChatOverrides()
        #expect(chat.systemPromptOverride == nil)
        #expect(chat.parametersOverrideData == nil)
    }
}

@Suite("URL digits")
struct URLDigitNormalizationTests {
    @Test func arabicIndicAndPersianDigits() {
        #expect(URLNormalizer.normalizedBaseURL(from: "١٩٢.١٦٨.١.٥٠:١١٤٣٤")?.absoluteString == "http://192.168.1.50:11434")
        #expect(URLNormalizer.normalizedBaseURL(from: "http://studio.local:۱۱۴۳۴")?.absoluteString == "http://studio.local:11434")
        #expect(URLNormalizer.asciiDigits("abc ١٢٣") == "abc 123")
    }
}
