import Foundation

/// `/v1/models` and `/v1/chat/completions` (SSE). Covers LM Studio, llama.cpp server, vLLM,
/// OpenRouter-style gateways and similar. The base URL may be given with or without `/v1`.
nonisolated final class OpenAICompatibleProvider: LLMProvider {
    let connection: ServerConnection
    private let transport: HTTPTransport
    private let streams = StreamTaskRegistry()
    private let apiPrefix: String

    init(connection: ServerConnection, configuration: URLSessionConfiguration = .ephemeral) {
        self.connection = connection
        self.transport = HTTPTransport(connection: connection, configuration: configuration)
        let path = connection.baseURL.path()
        self.apiPrefix = path.hasSuffix("/v1") || path.hasSuffix("/v1/") ? "" : "/v1"
    }

    // MARK: Wire types

    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            var id: String
            var created: Int?
            var owned_by: String?
            /// llama.cpp exposes the context window here.
            var meta: Meta?
            struct Meta: Decodable { var n_ctx_train: Int? }
        }
        var data: [Model]
    }

    private struct ChatBody: Encodable {
        struct Message: Encodable {
            var role: String
            var content: Content
        }
        enum Content: Encodable {
            case text(String)
            case parts([Part])

            func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text): try container.encode(text)
                case .parts(let parts): try container.encode(parts)
                }
            }
        }
        struct Part: Encodable {
            struct ImageURL: Encodable { var url: String }
            var type: String
            var text: String?
            var image_url: ImageURL?
        }
        struct StreamOptions: Encodable { var include_usage = true }

        var model: String
        var messages: [Message]
        var stream = true
        var stream_options = StreamOptions()
        var temperature: Double?
        var top_p: Double?
    }

    // MARK: LLMProvider

    func listModels() async throws -> [ModelInfo] {
        let request = try transport.makeRequest(path: apiPrefix + "/models")
        let response = try await transport.decode(ModelsResponse.self, for: request)
        return response.data.map {
            ModelInfo(
                id: $0.id,
                family: $0.owned_by,
                contextLength: $0.meta?.n_ctx_train,
                capabilities: [.completion],
                modifiedAt: $0.created.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func modelDetails(id: String) async throws -> ModelDetails {
        let models = try await listModels()
        guard let info = models.first(where: { $0.id == id }) else { throw ProviderError.notFound }
        return ModelDetails(info: info)
    }

    func loadedModels() async throws -> [LoadedModel] { [] }

    func healthCheck() async throws -> HealthReport {
        let clock = ContinuousClock()
        let start = clock.now
        let models = try await listModels()
        try await verifyKeyIfPossible()
        return HealthReport(latency: clock.now - start, modelCount: models.count, serverVersion: nil)
    }

    /// Some gateways (OpenRouter) list models without a key, so a successful model list doesn't
    /// prove the key works. Where the gateway has a key-info endpoint, ask it; a 401/403 there
    /// fails the test the same way a chat would.
    private func verifyKeyIfPossible() async throws {
        guard let host = connection.baseURL.host()?.lowercased(),
              host == "openrouter.ai" || host.hasSuffix(".openrouter.ai")
        else { return }
        let request = try transport.makeRequest(path: apiPrefix + "/key")
        do {
            _ = try await transport.data(for: request)
        } catch let error as ProviderError {
            if case .unauthorized = error { throw error }
            // Any other failure (endpoint moved, rate limit) shouldn't fail an otherwise good test.
        }
    }

    func streamChat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, any Error> {
        let body = ChatBody(
            model: request.model,
            messages: request.messages.map { message in
                guard !message.images.isEmpty else {
                    return .init(role: message.role.rawValue, content: .text(message.content))
                }
                var parts = [ChatBody.Part(type: "text", text: message.content)]
                parts += message.images.map {
                    .init(type: "image_url", image_url: .init(url: "data:image/jpeg;base64,\($0.base64EncodedString())"))
                }
                return .init(role: message.role.rawValue, content: .parts(parts))
            },
            temperature: request.parameters.temperature,
            top_p: request.parameters.topP
        )
        let transport = transport
        let streams = streams
        let path = apiPrefix + "/chat/completions"

        return AsyncThrowingStream { continuation in
            let streamID = UUID()
            let task = Task {
                do {
                    var urlRequest = try transport.makeRequest(path: path, method: "POST", jsonBody: body)
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let bytes = try await transport.bytes(for: urlRequest)
                    var splitter = LineSplitter()
                    var parser = SSEParser()
                    var stats: GenerationStats?
                    var receivedDone = false

                    func handle(_ event: SSEEvent) throws {
                        switch try OpenAIStreamDecoder.decode(event.data) {
                        case .done:
                            receivedDone = true
                        case .chunks(let chunks, let usage):
                            chunks.forEach { continuation.yield($0) }
                            if let usage { stats = usage }
                        }
                    }

                    for try await byte in bytes {
                        guard let line = splitter.append(byte) else { continue }
                        if let event = parser.consume(line: line) { try handle(event) }
                        if receivedDone { break }
                    }
                    if !receivedDone {
                        if let line = splitter.finish(), let event = parser.consume(line: line) { try handle(event) }
                        if let event = parser.finish() { try handle(event) }
                    }
                    continuation.yield(.done(stats))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ProviderError.map(error, host: transport.host))
                }
                streams.remove(id: streamID)
            }
            streams.register(task, id: streamID)
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cancel() { streams.cancelAll() }
}
