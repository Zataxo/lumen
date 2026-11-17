import Foundation
import Synchronization
import Testing
@testable import Lumen

// MARK: Stub networking

/// Serves canned responses per host, so parallel tests don't interfere, and records requests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var body: Data 
    }
    struct Recorded: Sendable {
        var method: String
        var path: String
        var body: Data
    }
    typealias Handler = @Sendable (_ method: String, _ path: String, _ body: Data) -> Response

    private static let handlers = Mutex<[String: Handler]>([:])
    private static let recorded = Mutex<[String: [Recorded]]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func requests(for host: String) -> [Recorded] {
        recorded.withLock { $0[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path() ?? ""
        let body = request.httpBody ?? Self.readAll(request.httpBodyStream)
        Self.recorded.withLock { $0[host, default: []].append(Recorded(method: method, path: path, body: body)) }

        let response = Self.handlers.withLock { $0[host] }?(method, path, body) ?? Response(status: 500, body: Data())
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

func makeOllama(host: String, handler: @escaping StubURLProtocol.Handler) -> OllamaProvider {
    StubURLProtocol.register(host: host, handler: handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let connection = ServerConnection(
        serverID: UUID(), kind: .ollama, baseURL: URL(string: "http://\(host):11434")!,
        secrets: ServerSecrets(), timeout: 10
    )
    return OllamaProvider(connection: connection, configuration: configuration)
}

func uniqueHost() -> String { "stub-\(UUID().uuidString.prefix(8).lowercased()).test" }

private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

private let pullStream = """
{"status":"pulling manifest"}
{"status":"pulling aaa","digest":"sha256:aaa","total":1000,"completed":0}
{"status":"pulling aaa","digest":"sha256:aaa","total":1000,"completed":600}
{"status":"pulling bbb","digest":"sha256:bbb","total":200,"completed":200}
{"status":"pulling aaa","digest":"sha256:aaa","total":1000,"completed":1000}
{"status":"verifying sha256 digest"}
{"status":"writing manifest"}
{"status":"success"}

"""

// MARK: Tests

@Suite("Pull progress")
struct PullProgressTrackerTests {
    @Test func aggregatesLayers() throws {
        var tracker = PullProgressTracker()
        var splitter = LineSplitter()
        let progress = try splitter.feed(pullStream).compactMap { try tracker.consume(line: $0) }

        #expect(progress.first?.phase == "Fetching manifest")
        #expect(progress.first?.fraction == nil)
        // After layer aaa at 600/1000 only.
        #expect(progress[2].fraction == 0.6)
        // aaa 600 + bbb 200 of 1200.
        #expect(progress[3].completedBytes == 800)
        #expect(progress[3].totalBytes == 1200)
        #expect(progress[5].phase == "Verifying")
        #expect(progress.last?.isComplete == true)
        #expect(progress.last?.fraction == 1)
        #expect(tracker.isComplete)
    }

    @Test func progressNeverGoesBackwards() throws {
        var tracker = PullProgressTracker()
        _ = try tracker.consume(line: #"{"status":"pulling a","digest":"a","total":100,"completed":80}"#)
        let later = try tracker.consume(line: #"{"status":"pulling a","digest":"a","total":100,"completed":40}"#)
        #expect(later?.completedBytes == 80)
    }

    @Test func surfacesErrors() {
        var tracker = PullProgressTracker()
        #expect(throws: ProviderError.server("pull model manifest: file does not exist")) {
            try tracker.consume(line: #"{"error":"pull model manifest: file does not exist"}"#)
        }
    }

    @Test(arguments: ["llama3.2", "qwen3:8b", "hf.co/bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M", "nomic-embed-text:latest"])
    func validNames(name: String) {
        #expect(ModelNameValidator.isValid(name))
    }

    @Test(arguments: ["", "  ", "llama 3", "qwen3:", ":8b", "a:b:c", "modèle", "rm -rf"])
    func invalidNames(name: String) {
        #expect(!ModelNameValidator.isValid(name))
    }
}

@Suite("Ollama provider (stubbed)")
struct OllamaProviderStubTests {
    @Test func pullStreamsProgressAndSendsModelName() async throws {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, path, _ in
            path == "/api/pull" ? .init(status: 200, body: Data(pullStream.utf8)) : .init(status: 404, body: Data())
        }
        var updates: [PullProgress] = []
        for try await progress in provider.pullModel("qwen3:8b") { updates.append(progress) }

        #expect(updates.last?.isComplete == true)
        #expect(updates.last?.totalBytes == 1200)
        let request = try #require(StubURLProtocol.requests(for: host).first)
        #expect(request.method == "POST")
        let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        #expect(body?["model"] as? String == "qwen3:8b")
        #expect(body?["stream"] as? Bool == true)
    }

    @Test func pullThatEndsEarlyFails() async {
        let host = uniqueHost()
        let truncated = #"{"status":"pulling a","digest":"a","total":10,"completed":5}"# + "\n"
        let provider = makeOllama(host: host) { _, _, _ in .init(status: 200, body: Data(truncated.utf8)) }
        await #expect(throws: ProviderError.self) {
            for try await _ in provider.pullModel("x") {}
        }
    }

    @Test func pullOfUnknownModelReportsServerError() async {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, _, _ in
            .init(status: 500, body: json(["error": "pull model manifest: file does not exist"]))
        }
        await #expect(throws: ProviderError.http(status: 500, message: "pull model manifest: file does not exist")) {
            for try await _ in provider.pullModel("nope") {}
        }
    }

    @Test func deleteSendsDELETEWithModel() async throws {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { method, path, _ in
            method == "DELETE" && path == "/api/delete" ? .init(status: 200, body: Data()) : .init(status: 405, body: Data())
        }
        try await provider.deleteModel("gemma3:4b")
        let request = try #require(StubURLProtocol.requests(for: host).first)
        let body = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        #expect(body?["model"] as? String == "gemma3:4b")
    }

    @Test func deleteMissingModelMapsToModelNotFound() async {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, _, _ in .init(status: 404, body: json(["error": "model 'x' not found"])) }
        await #expect(throws: ProviderError.modelNotFound("model 'x' not found")) {
            try await provider.deleteModel("x")
        }
    }

    @Test func modelDetailsParsesShow() async throws {
        let host = uniqueHost()
        let provider = makeOllama(host: host) { _, _, _ in
            .init(status: 200, body: json([
                "parameters": "temperature 0.7\nstop \"<|eot|>\"",
                "template": "{{ .Prompt }}",
                "license": "MIT",
                "details": ["family": "llama", "parameter_size": "3.2B", "quantization_level": "Q4_K_M"],
                "model_info": ["general.architecture": "llama", "llama.context_length": 131072, "llama.block_count": 28],
                "capabilities": ["completion", "tools", "vision"],
            ]))
        }
        let details = try await provider.modelDetails(id: "llama3.2:3b")
        #expect(details.info.contextLength == 131072)
        #expect(details.info.capabilities == [.completion, .tools, .vision])
        #expect(details.info.parameterSize == "3.2B")
        #expect(details.license == "MIT")
        #expect(details.metadata["llama.block_count"] == "28")
    }
}
