import Foundation
import Observation

/// Loads a server's models (and, for Ollama, what's loaded in memory). Keeps networking out of views.
@Observable
final class ModelListModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(ProviderError)
    }

    private(set) var state: LoadState = .idle
    private(set) var models: [ModelInfo] = []
    private(set) var loadedModels: [LoadedModel] = []

    func load(from connection: ServerConnection?) async {
        guard let connection else {
            state = .failed(.invalidURL)
            return
        }
        if models.isEmpty { state = .loading }
        let provider = ProviderFactory.makeProvider(for: connection)
        do {
            async let models = provider.listModels()
            async let loaded = try? provider.loadedModels()
            self.models = try await models
            self.loadedModels = await loaded ?? []
            state = .loaded
        } catch {
            guard !(error is CancellationError) else { return }
            state = .failed(ProviderError.map(error, host: connection.baseURL.host()))
        }
    }

    /// Gives a server a default chat model (the first non-embedding one) if it has none.
    static func ensureDefaultModel(for server: ServerConfig) async {
        guard server.defaultModelID == nil, let connection = ServerConnection(server: server) else { return }
        let models = (try? await ProviderFactory.makeProvider(for: connection).listModels()) ?? []
        if server.defaultModelID == nil,
           let first = models.first(where: { !$0.capabilities.contains(.embedding) }) {
            server.defaultModelID = first.id
        }
    }

    func filteredModels(search: String, capability: ModelCapability?) -> [ModelInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return models.filter { model in
            (query.isEmpty || model.id.localizedStandardContains(query) || (model.family?.localizedStandardContains(query) ?? false))
                && (capability.map { model.capabilities.contains($0) } ?? true)
        }
    }
}
