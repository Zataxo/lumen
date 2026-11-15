import Foundation
import Testing
@testable import llm_app

/// Splits `text` into chunks at the given byte offsets, simulating arbitrary network packets.
private func chunks(_ text: String, splitAt offsets: [Int]) -> [[UInt8]] {
    let bytes = Array(text.utf8)
    var result: [[UInt8]] = []
    var start = 0
    for offset in offsets.sorted() where offset > start && offset < bytes.count {
        result.append(Array(bytes[start..<offset]))
        start = offset
    }
    result.append(Array(bytes[start...]))
    return result
}

@Suite("LineSplitter")
struct LineSplitterTests {
    @Test func splitsCompleteLines() {
        var splitter = LineSplitter()
        #expect(splitter.feed("one\ntwo\n") == ["one", "two"])
        #expect(splitter.finish() == nil)
    }

    @Test func joinsLinesSplitMidway() {
        var splitter = LineSplitter()
        #expect(splitter.feed("{\"a\":") == [])
        #expect(splitter.feed("1}\n{\"b\"") == ["{\"a\":1}"])
        #expect(splitter.feed(":2}\n") == ["{\"b\":2}"])
    }

    @Test func stripsCRLF() {
        var splitter = LineSplitter()
        #expect(splitter.feed("data: x\r\n\r\n") == ["data: x", ""])
    }

    @Test func returnsUnterminatedTailOnFinish() {
        var splitter = LineSplitter()
        #expect(splitter.feed("partial") == [])
        #expect(splitter.finish() == "partial")
    }

    @Test func multiByteCharacterSplitAcrossChunks() {
        let text = "héllo 👋🏽 世界\n"
        // Split inside the "é" (2 bytes) and inside the emoji (4+4 bytes).
        for parts in [chunks(text, splitAt: [2]), chunks(text, splitAt: [8, 10, 13])] {
            var splitter = LineSplitter()
            let lines = parts.flatMap { splitter.feed($0) }
            #expect(lines == ["héllo 👋🏽 世界"])
        }
    }
}

@Suite("Ollama NDJSON")
struct OllamaNDJSONTests {
    static let stream = """
    {"model":"llama3.2","created_at":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":"Hel"},"done":false}
    {"model":"llama3.2","created_at":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":"lo"},"done":false}
    {"model":"llama3.2","created_at":"2025-01-01T00:00:00Z","message":{"role":"assistant","content":"","thinking":"hmm"},"done":false}
    {"model":"llama3.2","message":{"role":"assistant","content":""},"done":true,"done_reason":"stop","prompt_eval_count":12,"eval_count":40,"eval_duration":2000000000}

    """

    private func decodeAll(_ parts: [[UInt8]]) throws -> [ChatChunk] {
        var splitter = LineSplitter()
        var output: [ChatChunk] = []
        for part in parts {
            for line in splitter.feed(part) { output += try OllamaStreamDecoder.chunks(fromLine: line) }
        }
        if let line = splitter.finish() { output += try OllamaStreamDecoder.chunks(fromLine: line) }
        return output
    }

    private var expected: [ChatChunk] {
        [
            .content("Hel"),
            .content("lo"),
            .thinking("hmm"),
            .done(GenerationStats(promptTokens: 12, completionTokens: 40, generationSeconds: 2)),
        ]
    }

    @Test func decodesWholeStream() throws {
        #expect(try decodeAll([Array(Self.stream.utf8)]) == expected)
    }

    @Test(arguments: [[5], [40, 41, 42], [120, 121], [100, 200, 300, 400]])
    func decodesStreamSplitMidLine(offsets: [Int]) throws {
        #expect(try decodeAll(chunks(Self.stream, splitAt: offsets)) == expected)
    }

    @Test func decodesByteByByte() throws {
        let parts = Array(Self.stream.utf8).map { [$0] }
        #expect(try decodeAll(parts) == expected)
    }

    @Test func tokensPerSecond() {
        #expect(GenerationStats(completionTokens: 40, generationSeconds: 2).tokensPerSecond == 20)
    }

    @Test func surfacesServerError() {
        #expect(throws: ProviderError.server("model 'nope' not found")) {
            try OllamaStreamDecoder.chunks(fromLine: #"{"error":"model 'nope' not found"}"#)
        }
    }

    @Test func ignoresBlankLines() throws {
        #expect(try OllamaStreamDecoder.chunks(fromLine: "   ").isEmpty)
    }
}

@Suite("SSE")
struct SSEParserTests {
    private func events(_ parts: [[UInt8]]) -> [SSEEvent] {
        var splitter = LineSplitter()
        var parser = SSEParser()
        var output: [SSEEvent] = []
        for part in parts {
            for line in splitter.feed(part) {
                if let event = parser.consume(line: line) { output.append(event) }
            }
        }
        if let line = splitter.finish(), let event = parser.consume(line: line) { output.append(event) }
        if let event = parser.finish() { output.append(event) }
        return output
    }

    static let stream = """
    : keep-alive

    data: {"choices":[{"delta":{"role":"assistant","content":""}}]}

    data: {"choices":[{"delta":{"content":"Hi"}}]}

    data: {"choices":[{"delta":{"reasoning_content":"thinking…"}}]}

    data: {"choices":[{"delta":{"content":" there"},"finish_reason":"stop"}]}

    data: {"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":3}}

    data: [DONE]


    """

    @Test func parsesEventsAndSkipsComments() {
        let parsed = events([Array(Self.stream.utf8)])
        #expect(parsed.count == 6)
        #expect(parsed.last?.data == "[DONE]")
    }

    @Test(arguments: [[3], [20, 21], [64, 65, 66, 67], [150, 151, 300]])
    func parsesStreamSplitMidLine(offsets: [Int]) {
        #expect(events(chunks(Self.stream, splitAt: offsets)) == events([Array(Self.stream.utf8)]))
    }

    @Test func joinsMultiLineData() {
        let parsed = events([Array("event: message\ndata: first\ndata: second\n\n".utf8)])
        #expect(parsed == [SSEEvent(event: "message", data: "first\nsecond")])
    }

    @Test func dataWithoutSpaceAndCRLF() {
        #expect(events([Array("data:{\"x\":1}\r\n\r\n".utf8)]) == [SSEEvent(data: "{\"x\":1}")])
    }

    @Test func dispatchesFinalEventWithoutTrailingBlankLine() {
        #expect(events([Array("data: last".utf8)]) == [SSEEvent(data: "last")])
    }

    @Test func decodesOpenAIPayloads() throws {
        var content = ""
        var thinking = ""
        var usage: GenerationStats?
        var sawDone = false
        for event in events([Array(Self.stream.utf8)]) {
            switch try OpenAIStreamDecoder.decode(event.data) {
            case .done:
                sawDone = true
            case .chunks(let chunks, let eventUsage):
                if let eventUsage { usage = eventUsage }
                for chunk in chunks {
                    switch chunk {
                    case .content(let text): content += text
                    case .thinking(let text): thinking += text
                    case .done: break
                    }
                }
            }
        }
        #expect(content == "Hi there")
        #expect(thinking == "thinking…")
        #expect(usage == GenerationStats(promptTokens: 9, completionTokens: 3))
        #expect(sawDone)
    }

    @Test func surfacesAPIError() {
        #expect(throws: ProviderError.server("rate limited")) {
            try OpenAIStreamDecoder.decode(#"{"error":{"message":"rate limited"}}"#)
        }
    }
}

@Suite("Think tags")
struct ThinkTagExtractorTests {
    /// Runs the extractor over `parts` and merges adjacent chunks of the same kind.
    private func extract(_ parts: [String]) -> (content: String, thinking: String) {
        var extractor = ThinkTagExtractor()
        var content = ""
        var thinking = ""
        for chunk in parts.flatMap({ extractor.feed($0) }) + extractor.finish() {
            switch chunk {
            case .content(let text): content += text
            case .thinking(let text): thinking += text
            case .done: break
            }
        }
        return (content, thinking)
    }

    @Test func plainContentPassesThrough() {
        #expect(extract(["Hello ", "world"]) == ("Hello world", ""))
    }

    @Test func extractsThinkBlockInOneChunk() {
        #expect(extract(["<think>plan it</think>\n\nAnswer"]) == ("Answer", "plan it"))
    }

    @Test(arguments: [
        ["<thi", "nk>plan", " it</th", "ink>Answer"],
        ["<", "t", "h", "i", "n", "k", ">", "plan it", "<", "/", "think", ">", "\n", "Answer"],
        ["<think>plan it<", "/think>", "\n\n", "Answer"],
    ])
    func extractsTagsSplitAcrossChunks(parts: [String]) {
        #expect(extract(parts) == ("Answer", "plan it"))
    }

    @Test func lessThanThatIsNotATagIsKept() {
        #expect(extract(["if a <", " b then"]) == ("if a < b then", ""))
        #expect(extract(["x <th", "ing>"]) == ("x <thing>", ""))
    }

    @Test func heldBackPrefixIsFlushedAtEnd() {
        #expect(extract(["ends with <thi"]) == ("ends with <thi", ""))
    }

    @Test func unclosedThinkIsReasoning() {
        #expect(extract(["<think>still going"]) == ("", "still going"))
    }

    @Test func emitsChunksIncrementally() {
        var extractor = ThinkTagExtractor()
        #expect(extractor.feed("<think>a") == [.thinking("a")])
        #expect(extractor.feed("b</think>") == [.thinking("b")])
        #expect(extractor.feed("  ") == [])
        #expect(extractor.feed("c") == [.content("c")])
    }
}

@Suite("HTTP error mapping")
struct HTTPErrorMappingTests {
    @Test func ollamaMissingModel() {
        let error = ProviderError.fromHTTP(status: 404, body: Data(#"{"error":"model 'gemma3:12b' not found"}"#.utf8))
        #expect(error == .modelNotFound("model 'gemma3:12b' not found"))
        #expect(error.title == "Model not available")
        #expect(error.hint?.hasPrefix("Model 'gemma3:12b' not found.") == true)
    }

    @Test func openAIMissingModel() {
        let body = Data(#"{"error":{"message":"The model `gpt-x` does not exist","type":"invalid_request_error"}}"#.utf8)
        #expect(ProviderError.fromHTTP(status: 404, body: body) == .modelNotFound("The model `gpt-x` does not exist"))
    }

    @Test func plainNotFoundAndAuth() {
        #expect(ProviderError.fromHTTP(status: 404, body: Data("404 page not found".utf8)) == .notFound)
        #expect(ProviderError.fromHTTP(status: 401, body: Data()) == .unauthorized(status: 401))
        #expect(ProviderError.fromHTTP(status: 500, body: Data(#"{"error":"out of memory"}"#.utf8)) == .http(status: 500, message: "out of memory"))
    }
}
