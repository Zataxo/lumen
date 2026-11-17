import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Lumen

private func testPNG(width: Int, height: Int) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

private let doneLine = #"{"message":{"role":"assistant","content":""},"done":true}"# + "\n"

@Suite("Vision requests")
struct VisionRequestTests {
    @Test func ollamaSendsBase64ImagesAndThinkFlag() async throws {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, _, _ in .init(status: 200, body: Data(doneLine.utf8)) }
        let image = Data([0xFF, 0xD8, 0xFF, 0x01, 0x02])
        let request = ChatRequest(
            model: "gemma3:12b",
            messages: [ChatRequestMessage(role: .user, content: "What is this?", images: [image])],
            enableThinking: true
        )
        for try await _ in provider.streamChat(request) {}

        let recorded = try #require(StubURLProtocol.requests(for: host).first)
        #expect(recorded.path == "/api/chat")
        let body = try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["images"] as? [String] == [image.base64EncodedString()])
        #expect(body["think"] as? Bool == true)
    }

    @Test func ollamaOmitsEmptyImagesAndThink() async throws {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, _, _ in .init(status: 200, body: Data(doneLine.utf8)) }
        let request = ChatRequest(model: "llama3.2:3b", messages: [ChatRequestMessage(role: .user, content: "Hi")])
        for try await _ in provider.streamChat(request) {}

        let recorded = try #require(StubURLProtocol.requests(for: host).first)
        let body = try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.first?["images"] == nil)
        #expect(body["think"] == nil)
    }

    @Test func openAISendsImageContentParts() async throws {
        let host = uniqueHost()
        StubURLProtocol.register(host: host) { _, _, _ in .init(status: 200, body: Data("data: [DONE]\n\n".utf8)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let provider = OpenAICompatibleProvider(
            connection: ServerConnection(serverID: UUID(), kind: .openAICompatible, baseURL: URL(string: "http://\(host)/v1")!, secrets: ServerSecrets(), timeout: 10),
            configuration: configuration
        )
        let image = Data([1, 2, 3])
        let request = ChatRequest(model: "llava", messages: [ChatRequestMessage(role: .user, content: "Describe", images: [image])])
        for try await _ in provider.streamChat(request) {}

        let recorded = try #require(StubURLProtocol.requests(for: host).first)
        #expect(recorded.path == "/v1/chat/completions")
        let body = try #require(try JSONSerialization.jsonObject(with: recorded.body) as? [String: Any])
        let content = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "text")
        #expect(content.first?["text"] as? String == "Describe")
        let imageURL = (content.last?["image_url"] as? [String: Any])?["url"] as? String
        #expect(imageURL == "data:image/jpeg;base64,\(image.base64EncodedString())")
    }

    @Test func preparesLargeImagesWithinLimit() throws {
        let prepared = try #require(PendingImage.prepare(testPNG(width: 4000, height: 3000)))
        #expect(prepared.pixelWidth == PendingImage.maxPixelSize)
        #expect(prepared.pixelHeight == 1176)
        // Re-encoded as JPEG.
        #expect(prepared.data.starts(with: [0xFF, 0xD8]))
    }

    @Test func keepsSmallImagesAtOriginalSize() throws {
        let prepared = try #require(PendingImage.prepare(testPNG(width: 300, height: 200)))
        #expect(prepared.pixelWidth == 300)
        #expect(prepared.pixelHeight == 200)
    }

    @Test func rejectsNonImages() {
        #expect(PendingImage.prepare(Data("hello".utf8)) == nil)
    }
}

@Suite("Thinking timing")
struct ThinkingTimingTests {
    @Test func measuresThinkingUntilFirstAnswerToken() async throws {
        let accumulator = StreamAccumulator()
        accumulator.apply(.thinking("Let me think"))
        try await Task.sleep(for: .milliseconds(120))
        accumulator.apply(.thinking(" more"))
        accumulator.apply(.content("Answer"))
        try await Task.sleep(for: .milliseconds(80))

        let snapshot = accumulator.snapshot()
        let duration = try #require(snapshot.thinkingDuration(end: .now)).seconds
        #expect(duration >= 0.1)
        #expect(duration < 0.19) // stops at the first answer token, not "now"
        #expect(snapshot.thinking == "Let me think more")
    }

    @Test func noThinkingMeansNoDuration() {
        let accumulator = StreamAccumulator()
        accumulator.apply(.content("Just an answer"))
        #expect(accumulator.snapshot().thinkingDuration(end: .now) == nil)
    }

    @Test func thinkTagsInContentAreTimedToo() async {
        let accumulator = StreamAccumulator()
        let stream = AsyncThrowingStream<ChatChunk, any Error> { continuation in
            continuation.yield(.content("<think>plan</think>Done"))
            continuation.yield(.done(nil))
            continuation.finish()
        }
        _ = await accumulator.consume(stream)
        let snapshot = accumulator.snapshot()
        #expect(snapshot.thinkingStartedAt != nil)
        #expect(snapshot.contentStartedAt != nil)
        #expect(snapshot.thinkingDuration(end: .now) != nil)
    }

    @Test(arguments: [(0.4, "a moment"), (3.2, "3s"), (59.6, "1m 0s"), (75, "1m 15s")])
    func formatsDurations(seconds: Double, expected: String) {
        #expect(ThinkingFormat.duration(seconds) == expected)
    }
}

@Suite("Reply stats")
struct ReplyStatsTests {
    @Test func fullSummary() {
        let input = ReplyStatsFormatter.Input(
            modelID: "qwen3:8b", tokensPerSecond: 42.37, completionTokens: 512,
            promptTokens: 30, timeToFirstToken: 0.354, totalSeconds: 12.4
        )
        #expect(ReplyStatsFormatter.summary(input) == "qwen3:8b · 42 tok/s · 512 tokens · 0.35 s to first token")
        let details = ReplyStatsFormatter.details(input)
        #expect(details.contains("Prompt: 30 tokens"))
        #expect(details.contains("Total: 542 tokens"))
        #expect(details.contains("Total time: 12 s"))
    }

    @Test func slowModelShowsDecimalAndFallsBackToTime() {
        let input = ReplyStatsFormatter.Input(modelID: nil, tokensPerSecond: 4.25, completionTokens: nil, timeToFirstToken: 2.5, totalSeconds: 8.04)
        #expect(ReplyStatsFormatter.summary(input) == "4.2 tok/s · 8.0 s · 2.5 s to first token")
    }

    @Test func emptyWhenNothingKnown() {
        #expect(ReplyStatsFormatter.summary(.init()).isEmpty)
    }
}
