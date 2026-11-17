import Foundation

/// Errors shown to the user, each with a short title and a hint about what to check.
nonisolated enum ProviderError: Error, LocalizedError, Hashable, Sendable {
    case invalidURL
    case connectionRefused
    case timedOut
    case hostNotFound
    case offline(isLocalHost: Bool)
    case insecureConnectionBlocked
    case tlsFailed
    /// `message` is the server's own reason, when it gave one (e.g. "No auth credentials found").
    case unauthorized(status: Int, message: String? = nil)
    case notFound
    /// The server is reachable but doesn't have the requested model (Ollama and OpenAI-style 404s).
    case modelNotFound(String)
    case http(status: Int, message: String?)
    case server(String)
    case decoding(String)
    case cancelled
    case other(String)

    var title: String {
        switch self {
        case .invalidURL: "Invalid server URL"
        case .connectionRefused: "Connection refused"
        case .timedOut: "Timed out"
        case .hostNotFound: "Server not found"
        case .offline(let isLocal): isLocal ? "Local network unavailable" : "You're offline"
        case .insecureConnectionBlocked: "Insecure connection blocked"
        case .tlsFailed: "Secure connection failed"
        case .unauthorized(let status, _): status == 403 ? "403 Forbidden" : "401 Unauthorized"
        case .notFound: "404 Not Found"
        case .modelNotFound: "Model not available"
        case .http(let status, _): "HTTP \(status)"
        case .server: "Server error"
        case .decoding: "Unexpected response"
        case .cancelled: "Cancelled"
        case .other: "Connection failed"
        }
    }

    var hint: String? {
        switch self {
        case .invalidURL:
            "Use a full address like http://192.168.1.50:11434 or https://example.com."
        case .connectionRefused:
            "Nothing is listening at that address. Check the port, and that the server is running. Ollama on another computer needs OLLAMA_HOST=0.0.0.0."
        case .timedOut:
            "The server didn't answer in time. Check the address, your VPN, or raise the timeout."
        case .hostNotFound:
            "The hostname couldn't be resolved. Check for typos, or try the IP address."
        case .offline(let isLocal):
            isLocal
                ? "Allow Lumen in Settings → Privacy & Security → Local Network, and make sure you're on the same Wi-Fi."
                : "Check your internet connection."
        case .insecureConnectionBlocked:
            "This server must be reached over https://."
        case .tlsFailed:
            "The server's certificate couldn't be verified. If it only speaks plain HTTP, use http://."
        case .unauthorized(_, let message):
            [message.map { "The server said: \($0)." }, "Check the API key, or the Authorization header if the server is behind a proxy."]
                .compactMap { $0 }
                .joined(separator: " ")
        case .modelNotFound(let message):
            "\(message.prefix(1).uppercased() + message.dropFirst()). Choose another model from the picker, or install it on the server."
        case .notFound:
            "The endpoint wasn't found. Check the server type (Ollama vs OpenAI-compatible) and the base URL path."
        case .http(_, let message):
            message
        case .server(let message):
            message
        case .decoding(let detail):
            "\(detail) Check that the server type matches."
        case .cancelled, .other:
            nil
        }
    }

    var errorDescription: String? { title }
    var failureReason: String? { hint }

    static func map(_ error: any Error, host: String?) -> ProviderError {
        if let providerError = error as? ProviderError { return providerError }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .other(error.localizedDescription) }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .cannotConnectToHost: return .connectionRefused
        case .timedOut: return .timedOut
        case .cannotFindHost, .dnsLookupFailed: return .hostNotFound
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline(isLocalHost: URLNormalizer.isLocalNetworkHost(host))
        case .appTransportSecurityRequiresSecureConnection: return .insecureConnectionBlocked
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return .tlsFailed
        case .badURL, .unsupportedURL: return .invalidURL
        default: return .other(urlError.localizedDescription)
        }
    }

    static func fromHTTP(status: Int, body: Data) -> ProviderError {
        switch status {
        case 401, 403: return .unauthorized(status: status, message: extractMessage(from: body))
        case 404:
            // Ollama: "model 'x' not found"; OpenAI-style: "The model `x` does not exist".
            if let message = extractMessage(from: body), message.localizedCaseInsensitiveContains("model") {
                return .modelNotFound(message)
            }
            return .notFound
        default: return .http(status: status, message: extractMessage(from: body))
        }
    }

    /// Pulls `error` / `error.message` / `message` out of a JSON error body.
    private static func extractMessage(from body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let text = object["error"] as? String { return text }
            if let nested = object["error"] as? [String: Any], let text = nested["message"] as? String { return text }
            if let text = object["message"] as? String { return text }
        }
        let text = String(decoding: body.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
