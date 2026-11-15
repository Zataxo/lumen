import Foundation
import Synchronization

/// The interface every backend implements. Implementations are `Sendable` and do their work
/// off the main actor; views talk to them through view models only.
nonisolated protocol LLMProvider: Sendable {
    var connection: ServerConnection { get }

    func listModels() async throws -> [ModelInfo]
    func modelDetails(id: String) async throws -> ModelDetails
    /// Models currently resident in memory (Ollama `/api/ps`); empty where unsupported.
    func loadedModels() async throws -> [LoadedModel]
    func streamChat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, any Error>
    /// Cancels every in-flight stream started by this provider.
    func cancel()
    func healthCheck() async throws -> HealthReport
}

/// Servers that can download and remove models (Ollama).
nonisolated protocol ModelManaging: LLMProvider {
    /// Streams progress until the model is fully downloaded and verified.
    func pullModel(_ name: String) -> AsyncThrowingStream<PullProgress, any Error>
    func deleteModel(_ name: String) async throws
}

/// Tracks in-flight streaming tasks so `cancel()` can stop them all.
nonisolated final class StreamTaskRegistry: Sendable {
    private let tasks = Mutex<[UUID: Task<Void, Never>]>([:])

    func register(_ task: Task<Void, Never>, id: UUID) {
        tasks.withLock { $0[id] = task }
    }

    func remove(id: UUID) {
        _ = tasks.withLock { $0.removeValue(forKey: id) }
    }

    func cancelAll() {
        let running = tasks.withLock { tasks in
            defer { tasks.removeAll() }
            return Array(tasks.values)
        }
        running.forEach { $0.cancel() }
    }
}

nonisolated enum ProviderFactory {
    static func makeProvider(for connection: ServerConnection) -> any LLMProvider {
        switch connection.kind {
        case .ollama: OllamaProvider(connection: connection)
        case .openAICompatible: OpenAICompatibleProvider(connection: connection)
        }
    }
}

extension ServerConnection {
    /// Reads secrets from the Keychain. Returns nil when the stored URL is unusable.
    @MainActor
    init?(server: ServerConfig) {
        guard let baseURL = server.baseURL else { return nil }
        self.init(
            serverID: server.id,
            kind: server.kind,
            baseURL: baseURL,
            secrets: KeychainStore.secrets(for: server.id),
            timeout: server.timeoutSeconds
        )
    }
}

/// Lenient JSON value used for loosely-typed metadata such as Ollama's `model_info`.
nonisolated enum JSONValue: Decodable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    var displayString: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int64(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        case .array(let values): "[\(values.count) items]"
        case .object(let values): "{\(values.count) keys}"
        case .null: "—"
        }
    }
}

nonisolated enum ServerDateParser {
    /// Parses ISO-8601 dates, including Ollama's nanosecond fractions which
    /// `ISO8601DateFormatter` rejects.
    static func parse(_ text: String?) -> Date? {
        guard var text else { return nil }
        if let dot = text.firstIndex(of: "."),
           let zoneStart = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            text.removeSubrange(dot..<zoneStart)
        }
        return try? Date(text, strategy: .iso8601)
    }
}
