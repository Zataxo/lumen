import SwiftUI

/// Collapsible reasoning ("Thinking") — collapsed by default. While the model is still
/// reasoning the header counts up; afterwards it reads "Thought for 4s".
struct ThinkingDisclosure: View {
    let thinking: String
    /// Final duration, when known.
    var seconds: Double?
    /// Set while the reply is streaming and the model hasn't started answering yet.
    var liveSince: ContinuousClock.Instant?

    @State private var isExpanded = false
    @Environment(\.messageTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool { liveSince != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                withAnimation(Motion.spring(reduceMotion: reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.small - 2) {
                    Image(systemName: "brain")
                        .symbolEffect(.pulse, options: .repeating, isActive: isLive && !reduceMotion)
                    header
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(typography.callout)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide reasoning" : "Show reasoning")
            .accessibilityValue(headerText(now: .now))

            if isExpanded {
                Text(thinking.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(typography.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(typography.lineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Spacing.medium)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(.quaternary).frame(width: 2)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if isLive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(headerText(now: .now))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        } else {
            Text(headerText(now: .now))
        }
    }

    private func headerText(now: ContinuousClock.Instant) -> String {
        if let liveSince {
            let elapsed = Int((now - liveSince).seconds)
            return elapsed < 1 ? "Thinking…" : "Thinking… \(elapsed)s"
        }
        guard let seconds else { return "Thoughts" }
        return "Thought for \(ThinkingFormat.duration(seconds))"
    }
}

nonisolated enum ThinkingFormat {
    /// 0.4 → "a moment", 3.2 → "3s", 75 → "1m 15s".
    static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return "a moment" }
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole)s" }
        return "\(whole / 60)m \(whole % 60)s"
    }
}

/// The subtle line under a finished reply: model · tokens/s · tokens · time to first token.
nonisolated enum ReplyStatsFormatter {
    struct Input: Equatable {
        var modelID: String?
        var tokensPerSecond: Double?
        var completionTokens: Int?
        var promptTokens: Int?
        var timeToFirstToken: Double?
        var totalSeconds: Double?
    }

    static func summary(_ input: Input) -> String {
        var parts: [String] = []
        if let model = input.modelID { parts.append(model) }
        if let rate = input.tokensPerSecond, rate > 0 {
            parts.append("\(rate.formatted(.number.precision(.fractionLength(rate < 10 ? 1 : 0)))) tok/s")
        }
        if let tokens = input.completionTokens {
            parts.append(tokens == 1 ? "1 token" : "\(tokens.formatted()) tokens")
        } else if let total = input.totalSeconds {
            parts.append(seconds(total))
        }
        if let ttft = input.timeToFirstToken {
            parts.append("\(seconds(ttft)) to first token")
        }
        return parts.joined(separator: " · ")
    }

    /// Fuller breakdown for the tooltip / accessibility.
    static func details(_ input: Input) -> String {
        var lines: [String] = []
        if let prompt = input.promptTokens { lines.append("Prompt: \(prompt.formatted()) tokens") }
        if let completion = input.completionTokens { lines.append("Reply: \(completion.formatted()) tokens") }
        if let prompt = input.promptTokens, let completion = input.completionTokens {
            lines.append("Total: \((prompt + completion).formatted()) tokens")
        }
        if let ttft = input.timeToFirstToken { lines.append("Time to first token: \(seconds(ttft))") }
        if let total = input.totalSeconds { lines.append("Total time: \(seconds(total))") }
        return lines.joined(separator: "\n")
    }

    static func seconds(_ value: Double) -> String {
        value < 10
            ? "\(value.formatted(.number.precision(.fractionLength(value < 1 ? 2 : 1)))) s"
            : "\(Int(value.rounded())) s"
    }
}

extension ReplyStatsFormatter.Input {
    init(message: Message) {
        self.init(
            modelID: message.modelID,
            tokensPerSecond: message.tokensPerSecond,
            completionTokens: message.completionTokens,
            promptTokens: message.promptTokens,
            timeToFirstToken: message.timeToFirstTokenSeconds,
            totalSeconds: message.totalSeconds
        )
    }
}
