import Foundation

/// A snapshot of everything needed to talk to one server, safe to hand to background tasks.
nonisolated struct ServerConnection: Hashable, Sendable {
    var serverID: UUID
    var kind: ServerKind
    var baseURL: URL
    var secrets: ServerSecrets
    var timeout: TimeInterval
}

/// Builds requests (auth + custom headers) and runs them, mapping failures to `ProviderError`.
nonisolated final class HTTPTransport: Sendable {
    let connection: ServerConnection
    private let session: URLSession

    /// `configuration` is injectable so tests can install a stub `URLProtocol`.
    init(connection: ServerConnection, configuration: URLSessionConfiguration = .ephemeral) {
        self.connection = connection
        // Interval between packets, not total duration — long streams are fine.
        configuration.timeoutIntervalForRequest = connection.timeout
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Lumen"]
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    var host: String? { connection.baseURL.host() }

    func makeRequest(path: String, method: String = "GET", jsonBody: (any Encodable)? = nil) throws -> URLRequest {
        guard let url = URL(string: connection.baseURL.absoluteString + path) else { throw ProviderError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey = connection.secrets.apiKey?.trimmingCharacters(in: .whitespaces), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        // Custom headers win, e.g. `Authorization: Basic …` for a proxy.
        for header in connection.secrets.headers where !header.name.trimmingCharacters(in: .whitespaces).isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.name.trimmingCharacters(in: .whitespaces))
        }
        if let jsonBody {
            request.httpBody = try JSONEncoder().encode(jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response, body: data)
            return data
        } catch {
            throw ProviderError.map(error, host: host)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, for request: URLRequest) async throws -> T {
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.decoding("The server's reply wasn't in the expected format.")
        }
    }

    /// Opens a streaming response. Non-2xx responses are drained (up to 4 KB) for an error message.
    func bytes(for request: URLRequest) async throws -> URLSession.AsyncBytes {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= 4096 { break }
                }
                throw ProviderError.fromHTTP(status: http.statusCode, body: body)
            }
            return bytes
        } catch {
            throw ProviderError.map(error, host: host)
        }
    }

    private static func validate(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.fromHTTP(status: http.statusCode, body: body)
        }
    }
}
