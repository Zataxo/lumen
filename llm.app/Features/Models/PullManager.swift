import Foundation
import Observation

/// One model download.
@Observable
final class PullJob: Identifiable {
    enum State: Equatable {
        case running
        case finished
        case failed(ProviderError)
        case cancelled
    }

    let id: String
    let serverID: UUID
    let model: String
    let startedAt = Date.now
    var progress = PullProgress(status: "Starting…", completedBytes: 0, totalBytes: 0)
    var state: State = .running
    /// Average download speed in bytes/second, once measurable.
    var bytesPerSecond: Double?

    @ObservationIgnored var task: Task<Void, Never>?

    init(serverID: UUID, model: String) {
        self.serverID = serverID
        self.model = model
        self.id = PullJob.id(serverID: serverID, model: model)
    }

    static func id(serverID: UUID, model: String) -> String { "\(serverID.uuidString)|\(model)" }

    var isActive: Bool { state == .running }
}

/// Runs model downloads independently of any screen, so closing the pull sheet or leaving the
/// explorer doesn't cancel them. Progress is published at most ~8×/s.
@Observable
final class PullManager {
    private(set) var jobs: [PullJob] = []
    /// Bumped per server when a download finishes, so model lists can refresh.
    private(set) var completions: [UUID: Int] = [:]

    func jobs(for serverID: UUID) -> [PullJob] { jobs.filter { $0.serverID == serverID } }

    func job(serverID: UUID, model: String) -> PullJob? {
        jobs.first { $0.id == PullJob.id(serverID: serverID, model: model) }
    }

    /// Starts (or restarts) a download. Returns the job to observe.
    @discardableResult
    func pull(_ rawModel: String, on server: ServerConfig) -> PullJob? {
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, let connection = ServerConnection(server: server),
              let provider = ProviderFactory.makeProvider(for: connection) as? any ModelManaging
        else { return nil }

        if let existing = job(serverID: server.id, model: model) {
            if existing.isActive { return existing }
            jobs.removeAll { $0.id == existing.id }
        }
        let job = PullJob(serverID: server.id, model: model)
        jobs.insert(job, at: 0)

        job.task = Task { [weak self, weak job] in
            var lastPublish = ContinuousClock.now
            do {
                for try await progress in provider.pullModel(model) {
                    guard let job else { return }
                    let now = ContinuousClock.now
                    let phaseChanged = progress.phase != job.progress.phase
                    if phaseChanged || progress.isComplete || now - lastPublish > .milliseconds(125) {
                        job.progress = progress
                        let elapsed = Date.now.timeIntervalSince(job.startedAt)
                        if elapsed > 1, progress.completedBytes > 0 {
                            job.bytesPerSecond = Double(progress.completedBytes) / elapsed
                        }
                        lastPublish = now
                    }
                }
                job?.progress.isComplete = true
                job?.state = .finished
                self?.completions[server.id, default: 0] += 1
            } catch {
                let mapped = ProviderError.map(error, host: connection.baseURL.host())
                job?.state = mapped == .cancelled || Task.isCancelled ? .cancelled : .failed(mapped)
            }
        }
        return job
    }

    func cancel(_ job: PullJob) {
        job.task?.cancel()
        job.state = .cancelled
    }

    func dismiss(_ job: PullJob) {
        if job.isActive { cancel(job) }
        jobs.removeAll { $0.id == job.id }
    }
}

/// Validates Ollama model references like `llama3.2`, `qwen3:8b`, `hf.co/user/repo:Q4_K_M`.
nonisolated enum ModelNameValidator {
    static func isValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200, !trimmed.hasPrefix(":"), !trimmed.hasSuffix(":"),
              trimmed.filter({ $0 == ":" }).count <= 1
        else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-:/"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) && $0.isASCII }
    }
}
