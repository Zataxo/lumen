import Foundation
import Synchronization

/// Collects streamed chunks off the main actor. The UI pulls snapshots at a fixed rate
/// (`ChatSession` flushes ~30×/s), so token bursts never cause more than one update per frame
/// budget, however fast the server streams.
nonisolated final class StreamAccumulator: Sendable {
    struct Snapshot: Equatable, Sendable {
        var content: String
        var thinking: String
        var firstTokenAt: ContinuousClock.Instant?
        var thinkingStartedAt: ContinuousClock.Instant?
        var contentStartedAt: ContinuousClock.Instant?

        /// Reasoning time: from the first thinking token to the first answer token (or `end`).
        func thinkingDuration(end: ContinuousClock.Instant) -> Duration? {
            guard let thinkingStartedAt, !thinking.isEmpty else { return nil }
            return (contentStartedAt ?? end) - thinkingStartedAt
        }
    }

    struct Outcome: Sendable {
        var stats: GenerationStats?
        var error: ProviderError?
        var wasCancelled: Bool
    }

    private struct State {
        var content = ""
        var thinking = ""
        var firstTokenAt: ContinuousClock.Instant?
        var thinkingStartedAt: ContinuousClock.Instant?
        var contentStartedAt: ContinuousClock.Instant?
        var version = 0
        var deliveredVersion = 0
    }

    private let state = Mutex(State())

    /// Drains `stream`, splitting `<think>` tags out of content. Never throws: failures and
    /// cancellation are reported in the outcome so partial text is kept.
    @concurrent
    func consume(_ stream: AsyncThrowingStream<ChatChunk, any Error>) async -> Outcome {
        var extractor = ThinkTagExtractor()
        var stats: GenerationStats?
        do {
            for try await chunk in stream {
                switch chunk {
                case .content(let text):
                    extractor.feed(text).forEach(apply)
                case .thinking(let text):
                    apply(.thinking(text))
                case .done(let doneStats):
                    stats = doneStats
                }
            }
            extractor.finish().forEach(apply)
            return Outcome(stats: stats, error: nil, wasCancelled: Task.isCancelled)
        } catch {
            extractor.finish().forEach(apply)
            let mapped = ProviderError.map(error, host: nil)
            if mapped == .cancelled || Task.isCancelled {
                return Outcome(stats: stats, error: nil, wasCancelled: true)
            }
            return Outcome(stats: stats, error: mapped, wasCancelled: false)
        }
    }

    func apply(_ chunk: ChatChunk) {
        state.withLock { state in
            let now = ContinuousClock.now
            switch chunk {
            case .content(let text):
                state.content += text
                if state.contentStartedAt == nil { state.contentStartedAt = now }
            case .thinking(let text):
                state.thinking += text
                if state.thinkingStartedAt == nil { state.thinkingStartedAt = now }
            case .done:
                return
            }
            if state.firstTokenAt == nil { state.firstTokenAt = now }
            state.version += 1
        }
    }

    /// Returns a snapshot only if something arrived since the last call.
    func takeSnapshotIfChanged() -> Snapshot? {
        state.withLock { state in
            guard state.version != state.deliveredVersion else { return nil }
            state.deliveredVersion = state.version
            return Self.snapshot(of: state)
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { Self.snapshot(of: $0) }
    }

    private static func snapshot(of state: State) -> Snapshot {
        Snapshot(
            content: state.content,
            thinking: state.thinking,
            firstTokenAt: state.firstTokenAt,
            thinkingStartedAt: state.thinkingStartedAt,
            contentStartedAt: state.contentStartedAt
        )
    }
}
