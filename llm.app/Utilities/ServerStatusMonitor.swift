import Foundation
import Observation

nonisolated enum ServerStatus: Equatable, Sendable {
    case unknown
    case checking
    case online(latencyMilliseconds: Int)
    case slow(latencyMilliseconds: Int)
    case offline(ProviderError)

    static let slowThresholdMilliseconds = 1000

    init(report: HealthReport) {
        let ms = report.latencyMilliseconds
        self = ms >= Self.slowThresholdMilliseconds ? .slow(latencyMilliseconds: ms) : .online(latencyMilliseconds: ms)
    }

    var description: String {
        switch self {
        case .unknown: "Not checked yet"
        case .checking: "Checking…"
        case .online(let ms): "Online · \(ms) ms"
        case .slow(let ms): "Slow · \(ms) ms"
        case .offline(let error): "Offline · \(error.title)"
        }
    }
}

/// Live online / slow / offline state for each server, refreshed while a view that shows it
/// is on screen (`monitor(_:)` runs until its task is cancelled).
@Observable
final class ServerStatusMonitor {
    private(set) var statuses: [UUID: ServerStatus] = [:]

    func status(for serverID: UUID) -> ServerStatus { statuses[serverID] ?? .unknown }

    func monitor(_ servers: [ServerConfig], interval: Duration = .seconds(20)) async {
        while !Task.isCancelled {
            await refresh(servers)
            try? await Task.sleep(for: interval)
        }
    }

    func refresh(_ servers: [ServerConfig]) async {
        let connections = servers.compactMap { server -> ServerConnection? in
            guard let connection = ServerConnection(server: server) else {
                statuses[server.id] = .offline(.invalidURL)
                return nil
            }
            if statuses[server.id] == nil { statuses[server.id] = .checking }
            return connection
        }
        await withTaskGroup(of: (UUID, ServerStatus).self) { group in
            for connection in connections {
                group.addTask {
                    // Short timeout for background polling regardless of the server's own setting.
                    var probe = connection
                    probe.timeout = min(connection.timeout, 8)
                    return (connection.serverID, await Self.probe(probe))
                }
            }
            for await (id, status) in group {
                statuses[id] = status
            }
        }
    }

    func setStatus(_ status: ServerStatus, for serverID: UUID) {
        statuses[serverID] = status
    }

    nonisolated static func probe(_ connection: ServerConnection) async -> ServerStatus {
        do {
            return ServerStatus(report: try await ProviderFactory.makeProvider(for: connection).healthCheck())
        } catch {
            return .offline(ProviderError.map(error, host: connection.baseURL.host()))
        }
    }
}

#if os(macOS)
nonisolated enum LocalOllamaDetector {
    static let address = "http://localhost:11434"

    /// True when an Ollama server answers on this Mac's default port.
    static func isRunning() async -> Bool {
        guard let url = URL(string: address + "/api/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    static func isLocalOllama(_ server: ServerConfig) -> Bool {
        guard let url = server.baseURL, server.kind == .ollama else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host() ?? "") && (url.port ?? 80) == 11434
    }
}
#endif

nonisolated enum Format {
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func contextLength(_ tokens: Int) -> String {
        tokens >= 1024 ? "\(tokens / 1024)K ctx" : "\(tokens) ctx"
    }
}
