import Foundation

// Value types shared by providers and UI. All `nonisolated` so the networking layer can
// build them off the main actor (the app target defaults to MainActor isolation).

nonisolated enum ModelCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case completion, vision, tools, thinking, embedding

    var label: String {
        switch self {
        case .completion: "Chat"
        case .vision: "Vision"
        case .tools: "Tools"
        case .thinking: "Thinking"
        case .embedding: "Embedding"
        }
    }

    var symbolName: String {
        switch self {
        case .completion: "text.bubble"
        case .vision: "eye"
        case .tools: "wrench.and.screwdriver"
        case .thinking: "brain"
        case .embedding: "point.3.connected.trianglepath.dotted"
        }
    }
}

nonisolated struct ModelInfo: Identifiable, Hashable, Sendable {
    /// The identifier sent back to the server (e.g. `llama3.2:3b`).
    var id: String
    var family: String?
    var parameterSize: String?
    var quantization: String?
    var sizeBytes: Int64?
    var contextLength: Int?
    var capabilities: Set<ModelCapability> = []
    var modifiedAt: Date?

    /// `llama3.2:3b` → name `llama3.2`, tag `3b`.
    var displayName: String {
        id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? id
    }

    var tag: String? {
        let parts = id.split(separator: ":", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }
}

nonisolated struct LoadedModel: Identifiable, Hashable, Sendable {
    var id: String
    var sizeBytes: Int64?
    var sizeInVRAMBytes: Int64?
    var expiresAt: Date?
    var contextLength: Int?
}

nonisolated struct ModelDetails: Hashable, Sendable {
    var info: ModelInfo
    var parameters: String?
    var template: String?
    var license: String?
    var systemPrompt: String?
    /// Flattened `model_info` keys (Ollama) for the detail page.
    var metadata: [String: String] = [:]
}

nonisolated struct HealthReport: Hashable, Sendable {
    var latency: Duration
    var modelCount: Int
    var serverVersion: String?

    var latencyMilliseconds: Int {
        Int(latency.components.seconds * 1000 + latency.components.attoseconds / 1_000_000_000_000_000)
    }
}

nonisolated struct GenerationParameters: Codable, Hashable, Sendable {
    var temperature: Double?
    var topP: Double?
    var contextLength: Int?
}

nonisolated struct ChatRequestMessage: Hashable, Sendable {
    var role: MessageRole
    var content: String
    /// Raw image bytes (JPEG/PNG) for vision models.
    var images: [Data] = []
}

nonisolated struct ChatRequest: Sendable {
    var model: String
    var messages: [ChatRequestMessage]
    var parameters = GenerationParameters()
    var enableThinking: Bool?
}

nonisolated struct GenerationStats: Codable, Hashable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    /// Server-measured generation duration, when the server reports it (Ollama does).
    var generationSeconds: Double?

    var tokensPerSecond: Double? {
        guard let completionTokens, let generationSeconds, generationSeconds > 0 else { return nil }
        return Double(completionTokens) / generationSeconds
    }
}

/// One piece of a streamed reply.
nonisolated enum ChatChunk: Hashable, Sendable {
    case content(String)
    case thinking(String)
    case done(GenerationStats?)
}
