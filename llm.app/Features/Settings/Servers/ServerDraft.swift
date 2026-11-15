import Foundation
import Observation

enum ServerEditorTarget: Identifiable, Hashable {
    case new
    case localOllama
    case existing(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .localOllama: "local-ollama"
        case .existing(let id): id.uuidString
        }
    }
}

/// Editable copy of a server plus its Keychain secrets. Nothing is persisted until `save`.
struct ServerDraft: Equatable {
    var name = ""
    var kind: ServerKind = .ollama
    var urlString = ""
    var apiKey = ""
    var headers: [HTTPHeader] = []
    var timeoutSeconds: Double = 60
    var isDefault = false

    init() {}

    init(server: ServerConfig) {
        let secrets = KeychainStore.secrets(for: server.id)
        name = server.name
        kind = server.kind
        urlString = server.baseURLString
        apiKey = secrets.apiKey ?? ""
        headers = secrets.headers
        timeoutSeconds = server.timeoutSeconds
        isDefault = server.isDefault
    }

    var normalizedURL: URL? { URLNormalizer.normalizedBaseURL(from: urlString) }

    var isUnencrypted: Bool { normalizedURL?.scheme == "http" }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return normalizedURL?.host() ?? kind.displayName
    }

    var secrets: ServerSecrets {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServerSecrets(
            apiKey: key.isEmpty ? nil : key,
            headers: headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        )
    }

    var isValid: Bool { normalizedURL != nil }

    /// Connection for "Test connection" — uses the unsaved values.
    func connection(serverID: UUID) -> ServerConnection? {
        guard let normalizedURL else { return nil }
        return ServerConnection(serverID: serverID, kind: kind, baseURL: normalizedURL, secrets: secrets, timeout: timeoutSeconds)
    }
}

/// Runs a health check against a draft and reports success, latency and model count.
@Observable
final class ConnectionTester {
    enum State: Equatable {
        case idle
        case testing
        case success(HealthReport)
        case failure(ProviderError)
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func test(_ connection: ServerConnection?) {
        task?.cancel()
        guard let connection else {
            state = .failure(.invalidURL)
            return
        }
        state = .testing
        task = Task {
            do {
                let report = try await ProviderFactory.makeProvider(for: connection).healthCheck()
                guard !Task.isCancelled else { return }
                state = .success(report)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failure(ProviderError.map(error, host: connection.baseURL.host()))
            }
        }
    }

    func reset() {
        task?.cancel()
        state = .idle
    }
}
