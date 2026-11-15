import SwiftUI

/// A finished message. Assistant Markdown is parsed once and cached.
struct MessageRow: View {
    struct Actions {
        var regenerate: () -> Void
        var beginEdit: (UUID) -> Void
        var endEdit: () -> Void
        var resend: (Message, String) -> Void
    }

    let message: Message
    let isLastAssistant: Bool
    let isBusy: Bool
    let isEditing: Bool
    let actions: Actions

    var body: some View {
        switch message.role {
        case .user:
            UserMessageView(message: message, isBusy: isBusy, isEditing: isEditing, actions: actions)
        case .assistant:
            AssistantMessageView(message: message, isLastAssistant: isLastAssistant, isBusy: isBusy, actions: actions)
        case .system:
            EmptyView()
        }
    }
}

private struct UserMessageView: View {
    let message: Message
    let isBusy: Bool
    let isEditing: Bool
    let actions: MessageRow.Actions
    @Environment(\.messageTypography) private var typography
    @Environment(\.appAccent) private var accent
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.small) {
            let attachments = message.sortedAttachments
            if !attachments.isEmpty {
                MessageAttachmentsView(attachments: attachments)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if isEditing || !message.content.isEmpty {
                bubble
            }
        }
    }

    private var bubble: some View {
        HStack {
            Spacer(minLength: 48)
            if isEditing {
                editor
            } else {
                Text(message.content)
                    .font(typography.body)
                    .lineSpacing(typography.lineSpacing)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.medium + 2)
                    .padding(.vertical, Spacing.small + 2)
                    .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(message.content) }
                        Button("Edit", systemImage: "pencil") { actions.beginEdit(message.id) }
                            .disabled(isBusy)
                    }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: Spacing.small) {
            TextField("Message", text: $draft, axis: .vertical)
                .font(typography.body)
                .textFieldStyle(.plain)
                .lineLimit(1...12)
                .focused($isFocused)
                .padding(Spacing.medium)
                .background(Color.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                }
                .onSubmit(resend)
            HStack {
                Button("Cancel") { actions.endEdit() }
                    .keyboardShortcut(.cancelAction)
                Button("Send", action: resend)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.small)
            Text("Later messages will be replaced.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            draft = message.content
            isFocused = true
        }
    }

    private func resend() {
        actions.resend(message, draft)
    }
}

private struct AssistantMessageView: View {
    let message: Message
    let isLastAssistant: Bool
    let isBusy: Bool
    let actions: MessageRow.Actions
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let thinking = message.thinking, !thinking.isEmpty {
                ThinkingDisclosure(thinking: thinking, seconds: message.thinkingSeconds)
            }
            if !message.content.isEmpty {
                MarkdownView(document: MarkdownCache.shared.document(for: message.id, content: message.content))
            }
            if let errorText = message.errorText {
                ErrorBanner(text: errorText, onRetry: isLastAssistant && !isBusy ? actions.regenerate : nil)
            }
            actionBar
        }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(message.content) }
            if isLastAssistant {
                Button("Regenerate", systemImage: "arrow.clockwise", action: actions.regenerate)
                    .disabled(isBusy)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: Spacing.medium) {
            Button {
                Clipboard.copy(message.content)
                withAnimation(.snappy) { didCopy = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.snappy) { didCopy = false }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .help("Copy")
            .accessibilityLabel("Copy message")
            .disabled(message.content.isEmpty)

            if isLastAssistant {
                Button(action: actions.regenerate) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Regenerate")
                .accessibilityLabel("Regenerate response")
                .disabled(isBusy)
            }

            let stats = ReplyStatsFormatter.Input(message: message)
            let summary = ReplyStatsFormatter.summary(stats)
            if !summary.isEmpty {
                let details = ReplyStatsFormatter.details(stats)
                Text(summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(details)
                    .accessibilityLabel(details.isEmpty ? summary : details.replacingOccurrences(of: "\n", with: ", "))
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}

/// The reply that's still streaming. Re-parses Markdown on each flush (≤ 30×/s).
struct LiveReplyRow: View {
    let live: LiveReply
    var onGrow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if !live.thinking.isEmpty {
                ThinkingDisclosure(
                    thinking: live.thinking,
                    seconds: live.thinkingDuration?.seconds,
                    liveSince: live.thinkingDuration == nil ? live.thinkingStartedAt : nil
                )
            }
            if live.content.isEmpty {
                if live.thinking.isEmpty {
                    TypingIndicator()
                        .padding(.vertical, Spacing.xSmall)
                }
            } else {
                MarkdownView(document: MarkdownParser.parse(live.content))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: live.content.utf8.count) { _, _ in onGrow() }
    }
}

struct TypingIndicator: View {
    var label: String?

    var body: some View {
        HStack(spacing: Spacing.small) {
            // A miniature of the welcome orb, running faster while the model works.
            NeuralOrbView(size: 30, tint: Color(red: 0.30, green: 0.80, blue: 0.98), isActive: true)
            if let label {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Waiting for response")
    }
}

struct ErrorBanner: View {
    let text: String
    var onRetry: (() -> Void)?

    var body: some View {
        let lines = text.split(separator: "\n", maxSplits: 1).map(String.init)
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(lines.first ?? text)
                    .font(.callout.weight(.medium))
                if lines.count > 1 {
                    Text(lines[1])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }
        }
        .padding(Spacing.medium)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .textSelection(.enabled)
    }
}

extension Color {
    static let userBubble = Color.dynamic(light: (0.92, 0.93, 0.96), dark: (0.17, 0.18, 0.21))
}
