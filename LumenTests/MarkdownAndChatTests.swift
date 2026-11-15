import Foundation
import Testing
@testable import llm_app

@Suite("Markdown parser")
struct MarkdownParserTests {
    private func plain(_ text: AttributedString) -> String { String(text.characters) }

    @Test func paragraphsAndHeadings() {
        let blocks = MarkdownParser.parse("# Title\n\nHello **bold** and *it* `code`.").blocks
        #expect(blocks.count == 2)
        guard case .heading(1, let title) = blocks[0], case .paragraph(let body) = blocks[1] else {
            Issue.record("Unexpected blocks: \(blocks)"); return
        }
        #expect(plain(title) == "Title")
        #expect(plain(body) == "Hello bold and it code.")
        let boldRun = body.runs.first { plain(AttributedString(body[$0.range])) == "bold" }
        #expect(boldRun?.inlinePresentationIntent == .stronglyEmphasized)
        let codeRun = body.runs.first { plain(AttributedString(body[$0.range])) == "code" }
        #expect(codeRun?.inlinePresentationIntent == .code)
    }

    @Test func fencedCodeBlockKeepsLanguageAndCode() {
        let blocks = MarkdownParser.parse("```Swift\nlet x = 1\nprint(x)\n```").blocks
        guard case .code(let code) = blocks.first else { Issue.record("No code block"); return }
        #expect(code.language == "swift")
        #expect(code.code == "let x = 1\nprint(x)")
        #expect(plain(code.highlighted) == code.code)
    }

    @Test func unterminatedFenceWhileStreamingIsStillCode() {
        let blocks = MarkdownParser.parse("Here:\n\n```python\ndef f():\n    return 1").blocks
        #expect(blocks.count == 2)
        guard case .code(let code) = blocks.last else { Issue.record("No code block"); return }
        #expect(code.code.hasPrefix("def f():"))
    }

    @Test func tables() {
        let source = """
        | Name | Size |
        |:-----|-----:|
        | llama | 3B |
        | qwen | 8B |
        """
        guard case .table(let table) = MarkdownParser.parse(source).blocks.first else { Issue.record("No table"); return }
        #expect(table.header.map(plain) == ["Name", "Size"])
        #expect(table.rows.map { $0.map(plain) } == [["llama", "3B"], ["qwen", "8B"]])
        #expect(table.alignments == [.leading, .trailing])
    }

    @Test func nestedAndOrderedListsWithTasks() {
        let source = """
        3. first
        4. second
           - nested
        - [x] done
        - [ ] todo
        """
        let blocks = MarkdownParser.parse(source).blocks
        guard case .list(let ordered) = blocks.first else { Issue.record("No list"); return }
        #expect(ordered.isOrdered)
        #expect(ordered.startIndex == 3)
        #expect(ordered.items.count == 2)
        guard case .list(let nested) = ordered.items[1].blocks.last else { Issue.record("No nested list"); return }
        #expect(!nested.isOrdered)
        guard case .list(let tasks) = blocks.last else { Issue.record("No task list"); return }
        #expect(tasks.items.map(\.checkbox) == [.checked, .unchecked])
    }

    @Test func linksQuotesAndRules() {
        let blocks = MarkdownParser.parse("> quoted [site](https://example.com)\n\n---").blocks
        guard case .quote(let inner) = blocks.first, case .paragraph(let text) = inner.first else {
            Issue.record("No quote"); return
        }
        #expect(text.runs.contains { $0.link == URL(string: "https://example.com") })
        #expect(blocks.last == .rule)
    }

    @Test func emptyInput() {
        #expect(MarkdownParser.parse("").blocks.isEmpty)
    }

    @Test func appendingTextKeepsEarlierBlocksStable() {
        // Streaming relies on earlier blocks comparing equal so they skip re-rendering.
        let first = MarkdownParser.parse("Para one.\n\nPara tw").blocks
        let second = MarkdownParser.parse("Para one.\n\nPara two is longer").blocks
        #expect(first[0] == second[0])
        #expect(first[1] != second[1])
    }
}

@Suite("Syntax highlighter")
struct SyntaxHighlighterTests {
    private func kinds(_ code: String, _ language: String) -> [(String, SyntaxHighlighter.TokenKind)] {
        let characters = Array(code)
        return SyntaxHighlighter.tokenize(code, language: language).map { (String(characters[$0.range]), $0.kind) }
    }

    @Test func swiftTokens() {
        let tokens = kinds(#"@MainActor func greet() -> String { return "hi" } // done"#, "swift")
        #expect(tokens.contains { $0 == ("@MainActor", .attribute) })
        #expect(tokens.contains { $0 == ("func", .keyword) })
        #expect(tokens.contains { $0 == ("String", .type) })
        #expect(tokens.contains { $0 == (#""hi""#, .string) })
        #expect(tokens.contains { $0 == ("// done", .comment) })
    }

    @Test func pythonHashInsideStringIsNotAComment() {
        let tokens = kinds(#"x = "a # b"  # real comment"#, "python")
        #expect(tokens.contains { $0 == (#""a # b""#, .string) })
        #expect(tokens.contains { $0 == ("# real comment", .comment) })
    }

    @Test func numbersAndUnknownLanguage() {
        #expect(kinds("let n = 42", "swift").contains { $0 == ("42", .number) })
        #expect(SyntaxHighlighter.tokenize("anything", language: "klingon").isEmpty)
    }

    @Test func highlightingPreservesText() {
        let code = "const s = `multi\nline`; /* c */ let 🙂 = 1"
        #expect(String(SyntaxHighlighter.highlight(code, language: "js").characters) == code)
    }
}

@Suite("Chat titles")
struct ChatTitlerTests {
    @Test func usesFirstNonEmptyLine() {
        #expect(ChatTitler.title(from: "\n\n  How do I sort an array?\nThanks") == "How do I sort an array?")
    }

    @Test func stripsMarkdownMarkers() {
        #expect(ChatTitler.title(from: "## Explain `async let`") == "Explain async let")
    }

    @Test func truncatesAtWordBoundary() {
        let title = ChatTitler.title(from: "Write a detailed comparison between SwiftUI and UIKit for building large apps")
        #expect(title.hasSuffix("…"))
        #expect(title.count <= 49)
        #expect(!title.dropLast().hasSuffix(" "))
    }

    @Test func fallsBackForEmpty() {
        #expect(ChatTitler.title(from: "   \n ") == "New Chat")
    }
}

@Suite("Stream accumulator")
struct StreamAccumulatorTests {
    @Test func coalescesChunksAndSplitsThinkTags() async {
        let accumulator = StreamAccumulator()
        let stream = AsyncThrowingStream<ChatChunk, any Error> { continuation in
            for piece in ["<thi", "nk>plan</think>", "\n\nHel", "lo"] {
                continuation.yield(.content(piece))
            }
            continuation.yield(.done(GenerationStats(promptTokens: 5, completionTokens: 2, generationSeconds: 1)))
            continuation.finish()
        }
        let outcome = await accumulator.consume(stream)
        #expect(outcome.error == nil)
        #expect(!outcome.wasCancelled)
        #expect(outcome.stats?.completionTokens == 2)

        let snapshot = accumulator.takeSnapshotIfChanged()
        #expect(snapshot?.content == "Hello")
        #expect(snapshot?.thinking == "plan")
        #expect(snapshot?.firstTokenAt != nil)
        // Nothing new since the last pull.
        #expect(accumulator.takeSnapshotIfChanged() == nil)
    }

    @Test func keepsPartialTextOnError() async {
        let accumulator = StreamAccumulator()
        let stream = AsyncThrowingStream<ChatChunk, any Error> { continuation in
            continuation.yield(.content("partial"))
            continuation.finish(throwing: ProviderError.server("boom"))
        }
        let outcome = await accumulator.consume(stream)
        #expect(outcome.error == .server("boom"))
        #expect(accumulator.snapshot().content == "partial")
    }
}
