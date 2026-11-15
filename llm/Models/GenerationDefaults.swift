import Foundation

/// App-wide default system prompt and sampling parameters (Settings → Models).
/// `nil` parameters mean "use the server/model default". Stored as JSON in UserDefaults.
nonisolated struct GenerationDefaults: Codable, Hashable, Sendable {
    var systemPrompt = ""
    var temperature: Double?
    var topP: Double?
    var contextLength: Int?

    static let storageKey = "generation.defaults"

    var parameters: GenerationParameters {
        GenerationParameters(temperature: temperature, topP: topP, contextLength: contextLength)
    }

    static var current: GenerationDefaults {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(GenerationDefaults.self, from: data)
        else { return GenerationDefaults() }
        return value
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension GenerationParameters {
    /// Each field from `override` when set, otherwise from `defaults`.
    nonisolated static func merged(_ override: GenerationParameters?, over defaults: GenerationParameters) -> GenerationParameters {
        GenerationParameters(
            temperature: override?.temperature ?? defaults.temperature,
            topP: override?.topP ?? defaults.topP,
            contextLength: override?.contextLength ?? defaults.contextLength
        )
    }

    nonisolated var isEmpty: Bool { temperature == nil && topP == nil && contextLength == nil }
}

/// A chat's own system prompt and parameters. `systemPrompt == nil` uses the default prompt;
/// an empty string deliberately sends none.
nonisolated struct ChatOverrides: Codable, Hashable, Sendable {
    var systemPrompt: String?
    var parameters = GenerationParameters()

    var isEmpty: Bool { systemPrompt == nil && parameters.isEmpty }
}

/// Derives a short chat title from the first user message.
nonisolated enum ChatTitler {
    static func title(from text: String, maxLength: Int = 48) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // Strip leading Markdown markers like "# ", "> ", "- ".
        let cleaned = String(firstLine.drop(while: { "#>-*` ".contains($0) }))
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
        guard !cleaned.isEmpty else { return "New Chat" }
        guard cleaned.count > maxLength else { return cleaned }

        let prefix = cleaned.prefix(maxLength)
        if let lastSpace = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: lastSpace) > maxLength / 2 {
            return prefix[..<lastSpace].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
        }
        return prefix + "…"
    }
}
