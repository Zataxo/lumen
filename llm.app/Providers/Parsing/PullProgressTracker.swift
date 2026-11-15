import Foundation

/// Overall progress of a model download.
nonisolated struct PullProgress: Hashable, Sendable {
    /// Ollama's phase text, e.g. "pulling manifest", "pulling 6a0746a1ec1a", "verifying sha256 digest".
    var status: String
    var completedBytes: Int64
    var totalBytes: Int64
    var isComplete = false

    /// 0…1 once the size is known; nil while only manifest / verification steps are running.
    var fraction: Double? {
        guard totalBytes > 0 else { return isComplete ? 1 : nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    /// A short, human phase label.
    var phase: String {
        if isComplete { return "Done" }
        let lower = status.lowercased()
        if lower.hasPrefix("pulling manifest") { return "Fetching manifest" }
        if lower.hasPrefix("pulling") || lower.hasPrefix("downloading") { return "Downloading" }
        if lower.hasPrefix("verifying") { return "Verifying" }
        if lower.hasPrefix("writing") { return "Writing manifest" }
        if lower.hasPrefix("removing") { return "Cleaning up" }
        return status.prefix(1).uppercased() + status.dropFirst()
    }
}

/// Folds Ollama's `/api/pull` NDJSON lines into overall progress. A model has several layers
/// (weights, template, license…), each reported with its own digest, total and completed bytes,
/// so totals are summed across layers rather than taken from the latest line.
nonisolated struct PullProgressTracker: Sendable {
    private struct Line: Decodable {
        var status: String?
        var digest: String?
        var total: Int64?
        var completed: Int64?
        var error: String?
    }

    private var layers: [String: (completed: Int64, total: Int64)] = [:]
    private var layerOrder: [String] = []
    private(set) var isComplete = false

    init() {}

    /// Returns updated progress for a line, nil for blank lines; throws on `{"error": …}`.
    mutating func consume(line: String) throws -> PullProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let decoded: Line
        do {
            decoded = try JSONDecoder().decode(Line.self, from: Data(trimmed.utf8))
        } catch {
            throw ProviderError.decoding("Unexpected download progress from Ollama.")
        }
        if let message = decoded.error { throw ProviderError.server(message) }

        if let digest = decoded.digest, let total = decoded.total, total > 0 {
            if layers[digest] == nil { layerOrder.append(digest) }
            let completed = min(decoded.completed ?? layers[digest]?.completed ?? 0, total)
            // Progress never goes backwards for a layer (Ollama occasionally re-reports).
            layers[digest] = (max(completed, layers[digest]?.completed ?? 0), total)
        }
        let status = decoded.status ?? ""
        if status == "success" { isComplete = true }

        let completed = layers.values.reduce(0) { $0 + $1.completed }
        let total = layers.values.reduce(0) { $0 + $1.total }
        return PullProgress(status: status, completedBytes: completed, totalBytes: total, isComplete: isComplete)
    }
}
