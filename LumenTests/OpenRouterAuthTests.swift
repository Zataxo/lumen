import Foundation
import Testing
@testable import Lumen

/// OpenRouter lists models without a key, so Test Connection must check the key separately.
struct OpenRouterAuthTests {
    private func makeProvider(host: String, apiKey: String?, handler: @escaping StubURLProtocol.Handler) -> OpenAICompatibleProvider {
        StubURLProtocol.register(host: host, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let connection = ServerConnection(
            serverID: UUID(), kind: .openAICompatible, baseURL: URL(string: "https://\(host)/api/v1")!,
            secrets: ServerSecrets(apiKey: apiKey), timeout: 10
        )
        return OpenAICompatibleProvider(connection: connection, configuration: configuration)
    }

    private func openRouterHost() -> String { "t\(UUID().uuidString.prefix(8).lowercased()).openrouter.ai" }

    private static let models = Data(#"{"data":[{"id":"openai/gpt-4o-mini"}]}"#.utf8)

    @Test func healthCheckFailsWhenKeyIsRejected() async throws {
        let host = openRouterHost()
        let provider = makeProvider(host: host, apiKey: "sk-or-wrong") { _, path, _ in
            path.hasSuffix("/key")
                ? .init(status: 401, body: Data(#"{"error":{"message":"User not found.","code":401}}"#.utf8))
                : .init(status: 200, body: Self.models)
        }
        await #expect(throws: ProviderError.unauthorized(status: 401, message: "User not found.")) {
            try await provider.healthCheck()
        }
        #expect(StubURLProtocol.requests(for: host).map(\.path) == ["/api/v1/models", "/api/v1/key"])
    }

    @Test func healthCheckPassesWithValidKey() async throws {
        let host = openRouterHost()
        let provider = makeProvider(host: host, apiKey: "sk-or-good") { _, path, _ in
            .init(status: 200, body: path.hasSuffix("/key") ? Data(#"{"data":{"label":"x"}}"#.utf8) : Self.models)
        }
        let report = try await provider.healthCheck()
        #expect(report.modelCount == 1)
    }

    @Test func otherServersSkipKeyCheck() async throws {
        let host = uniqueHost()
        let provider = makeProvider(host: host, apiKey: nil) { _, _, _ in .init(status: 200, body: Self.models) }
        _ = try await provider.healthCheck()
        #expect(StubURLProtocol.requests(for: host).map(\.path) == ["/api/v1/models"])
    }

    @Test func unauthorizedKeepsServerReason() {
        let body = Data(#"{"error":{"message":"No auth credentials found","code":401}}"#.utf8)
        let error = ProviderError.fromHTTP(status: 401, body: body)
        #expect(error == .unauthorized(status: 401, message: "No auth credentials found"))
        #expect(error.hint?.contains("No auth credentials found") == true)
    }
}
