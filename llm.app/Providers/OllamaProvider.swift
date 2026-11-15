import Foundation

/// Ollama's native API: `/api/tags`, `/api/show`, `/api/ps`, `/api/chat` (NDJSON stream).
/// Also manages models: `/api/pull` (NDJSON progress) and `/api/delete`.
nonisolated final class OllamaProvider: LLMProvider, ModelManaging {
    let connection: ServerConnection
    private let transport: HTTPTransport
    private let streams = StreamTaskRegistry()

    init(connection: ServerConnection, configuration: URLSessionConfiguration = .ephemeral) {
        self.connection = connection
        self.transport = HTTPTransport(connection: connection, configuration: configuration)
    }

    // MARK: Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            var name: String
            var model: String?
            var modified_at: String?
            var size: Int64?
            var details: Details?
        }
        var models: [Model]
    }

    private struct Details: Decodable {
        var family: String?
        var parameter_size: String?
        var quantization_level: String?
    }

    private struct ShowResponse: Decodable {
        var parameters: String?
        var template: String?
        var license: String?
        var system: String?
        var details: Details?
        var model_info: [String: JSONValue]?
        var capabilities: [String]?
    }

    private struct PSResponse: Decodable {
        struct Model: Decodable {
            var name: String
            var size: Int64?
            var size_vram: Int64?
            var expires_at: String?
            var context_length: Int?
        }
        var models: [Model]
    }

    private struct VersionResponse: Decodable { var version: String? }

    private struct ChatBody: Encodable {
        struct Message: Encodable {
            var role: String
            var content: String
            var images: [String]?
        }
        struct Options: Encodable {
            var temperature: Double?
            var top_p: Double?
            var num_ctx: Int?
        }
        var model: String
        var messages: [Message]
        var stream = true
        var options: Options?
        var think: Bool?
    }

    // MARK: LLMProvider

    func listModels() async throws -> [ModelInfo] {
        let base = try await fetchTags()
        // `/api/tags` lacks capabilities and context length; `/api/show` has them.
        // Ask for all models concurrently, a few at a time, and keep the basic info on failure.
        return await withTaskGroup(of: (Int, ModelInfo?).self) { group in
            var enriched = base
            var nextIndex = 0
            func addNext() {
                guard nextIndex < base.count else { return }
                let index = nextIndex
                let id = base[index].id
                nextIndex += 1
                group.addTask { (index, try? await self.modelDetails(id: id).info) }
            }
            for _ in 0..<min(6, base.count) { addNext() }
            while let (index, details) = await group.next() {
                if let details {
                    enriched[index].capabilities = details.capabilities
                    enriched[index].contextLength = details.contextLength
                    enriched[index].family = enriched[index].family ?? details.family
                }
                addNext()
            }
            return enriched
        }
    }

    func modelDetails(id: String) async throws -> ModelDetails {
        struct Body: Encodable { var model: String }
        let request = try transport.makeRequest(path: "/api/show", method: "POST", jsonBody: Body(model: id))
        let response = try await transport.decode(ShowResponse.self, for: request)

        let modelInfo = response.model_info ?? [:]
        let contextLength = modelInfo.first { $0.key.hasSuffix(".context_length") }?.value.intValue
        var capabilities = Set((response.capabilities ?? []).compactMap(ModelCapability.init(rawValue:)))
        if capabilities.isEmpty { capabilities = [.completion] }

        let info = ModelInfo(
            id: id,
            family: response.details?.family ?? modelInfo["general.architecture"]?.displayString,
            parameterSize: response.details?.parameter_size,
            quantization: response.details?.quantization_level,
            contextLength: contextLength,
            capabilities: capabilities
        )
        return ModelDetails(
            info: info,
            parameters: response.parameters,
            template: response.template,
            license: response.license,
            systemPrompt: response.system,
            metadata: modelInfo.mapValues(\.displayString)
        )
    }

    func loadedModels() async throws -> [LoadedModel] {
        let request = try transport.makeRequest(path: "/api/ps")
        let response = try await transport.decode(PSResponse.self, for: request)
        return response.models.map {
            LoadedModel(
                id: $0.name,
                sizeBytes: $0.size,
                sizeInVRAMBytes: $0.size_vram,
                expiresAt: ServerDateParser.parse($0.expires_at),
                contextLength: $0.context_length
            )
        }
    }

    func healthCheck() async throws -> HealthReport {
        let clock = ContinuousClock()
        let start = clock.now
        let models = try await fetchTags()
        let latency = clock.now - start
        let versionRequest = try transport.makeRequest(path: "/api/version")
        let version = try? await transport.decode(VersionResponse.self, for: versionRequest).version
        return HealthReport(latency: latency, modelCount: models.count, serverVersion: version.map { "Ollama \($0)" })
    }

    func streamChat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, any Error> {
        let body = ChatBody(
            model: request.model,
            messages: request.messages.map {
                .init(
                    role: $0.role.rawValue,
                    content: $0.content,
                    images: $0.images.isEmpty ? nil : $0.images.map { $0.base64EncodedString() }
                )
            },
            options: .init(
                temperature: request.parameters.temperature,
                top_p: request.parameters.topP,
                num_ctx: request.parameters.contextLength
            ),
            think: request.enableThinking
        )
        let transport = transport
        let streams = streams

        return AsyncThrowingStream { continuation in
            let streamID = UUID()
            let task = Task {
                do {
                    let urlRequest = try transport.makeRequest(path: "/api/chat", method: "POST", jsonBody: body)
                    let bytes = try await transport.bytes(for: urlRequest)
                    var splitter = LineSplitter()
                    var didFinish = false
                    func handle(_ line: String) throws {
                        for chunk in try OllamaStreamDecoder.chunks(fromLine: line) {
                            if case .done = chunk { didFinish = true }
                            continuation.yield(chunk)
                        }
                    }
                    for try await byte in bytes {
                        if let line = splitter.append(byte) { try handle(line) }
                    }
                    if let line = splitter.finish() { try handle(line) }
                    if !didFinish { continuation.yield(.done(nil)) }
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

    // MARK: ModelManaging

    func pullModel(_ name: String) -> AsyncThrowingStream<PullProgress, any Error> {
        struct Body: Encodable {
            var model: String
            var stream = true
        }
        let transport = transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try transport.makeRequest(path: "/api/pull", method: "POST", jsonBody: Body(model: name))
                    // Verifying a large download can be silent for minutes.
                    request.timeoutInterval = max(transport.connection.timeout, 900)
                    let bytes = try await transport.bytes(for: request)
                    var splitter = LineSplitter()
                    var tracker = PullProgressTracker()
                    func handle(_ line: String) throws {
                        if let progress = try tracker.consume(line: line) { continuation.yield(progress) }
                    }
                    for try await byte in bytes {
                        if let line = splitter.append(byte) { try handle(line) }
                    }
                    if let line = splitter.finish() { try handle(line) }
                    guard tracker.isComplete else {
                        throw ProviderError.other("The download ended before it finished.")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ProviderError.map(error, host: transport.host))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func deleteModel(_ name: String) async throws {
        struct Body: Encodable { var model: String }
        let request = try transport.makeRequest(path: "/api/delete", method: "DELETE", jsonBody: Body(model: name))
        _ = try await transport.data(for: request)
    }

    // MARK: Helpers

    private func fetchTags() async throws -> [ModelInfo] {
        let request = try transport.makeRequest(path: "/api/tags")
        let response = try await transport.decode(TagsResponse.self, for: request)
        return response.models.map {
            ModelInfo(
                id: $0.name,
                family: $0.details?.family,
                parameterSize: $0.details?.parameter_size,
                quantization: $0.details?.quantization_level,
                sizeBytes: $0.size,
                modifiedAt: ServerDateParser.parse($0.modified_at)
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
}
