import Foundation
import Observation

/// App-wide cache of each server's model list, used by the chat model picker.
@Observable
final class ModelCatalog {
    enum State: Equatable {
        case idle, loading, loaded, failed(ProviderError)
    }

    private(set) var models: [UUID: [ModelInfo]] = [:]
    private(set) var states: [UUID: State] = [:]
    @ObservationIgnored private var loadedAt: [UUID: Date] = [:]

    func models(for serverID: UUID) -> [ModelInfo] { models[serverID] ?? [] }
    func state(for serverID: UUID) -> State { states[serverID] ?? .idle }

    func model(_ id: String?, on serverID: UUID?) -> ModelInfo? {
        guard let id, let serverID else { return nil }
        return models[serverID]?.first { $0.id == id }
    }

    /// Forces the next `load` to refetch (after a pull or delete).
    func invalidate(_ serverID: UUID) {
        loadedAt[serverID] = nil
    }

    /// Loads (or refreshes after 60 s, or when forced) a server's models.
    func load(_ server: ServerConfig, force: Bool = false) async {
        let id = server.id
        if !force, let loadedAt = loadedAt[id], Date.now.timeIntervalSince(loadedAt) < 60, states[id] == .loaded { return }
        guard let connection = ServerConnection(server: server) else {
            states[id] = .failed(.invalidURL)
            return
        }
        if models[id] == nil { states[id] = .loading }
        do {
            let list = try await ProviderFactory.makeProvider(for: connection).listModels()
            models[id] = list.filter { !$0.capabilities.contains(.embedding) }
            states[id] = .loaded
            loadedAt[id] = .now
        } catch {
            guard !(error is CancellationError) else { return }
            states[id] = .failed(ProviderError.map(error, host: connection.baseURL.host()))
        }
    }
}
