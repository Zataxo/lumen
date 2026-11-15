import Foundation
import SwiftData

/// The protocol family a server speaks.
nonisolated enum ServerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ollama: 11434
        case .openAICompatible: 1234
        }
    }

    var urlPlaceholder: String {
        switch self {
        case .ollama: "http://192.168.1.50:11434"
        case .openAICompatible: "https://example.com/v1"
        }
    }
}

/// A user-configured LLM server. Secrets (API key, custom headers) live in the Keychain,
/// keyed by `id` — never in SwiftData.
@Model
final class ServerConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRawValue: String
    var baseURLString: String
    var timeoutSeconds: Double
    var isDefault: Bool
    var createdAt: Date
    /// The model new chats use when this server is the default (set in Settings → Models).
    var defaultModelID: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: ServerKind,
        baseURLString: String,
        timeoutSeconds: Double = 60,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kind.rawValue
        self.baseURLString = baseURLString
        self.timeoutSeconds = timeoutSeconds
        self.isDefault = isDefault
        self.createdAt = .now
    }

    var kind: ServerKind {
        get { ServerKind(rawValue: kindRawValue) ?? .ollama }
        set { kindRawValue = newValue.rawValue }
    }

    var baseURL: URL? { URLNormalizer.normalizedBaseURL(from: baseURLString) }

    var isUnencrypted: Bool { baseURL?.scheme?.lowercased() == "http" }
}
