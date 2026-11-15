import SwiftData
import SwiftUI

/// Subsequence matching with bonuses for contiguous runs and word starts, so "q8" finds
/// "qwen3:8b" and "lam" ranks "llama3.2" above "gemma3:llama-merge".
nonisolated enum CommandPaletteMatcher {
    /// nil when `query` isn't a subsequence of `text`. Higher is better.
    static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(text.lowercased())
        var score = 0
        var queryIndex = 0
        var previousMatch: Int?
        for (index, character) in haystack.enumerated() where queryIndex < needle.count {
            guard character == needle[queryIndex] else { continue }
            score += 1
            if let previousMatch, previousMatch == index - 1 { score += 5 }        // contiguous
            if index == 0 || !haystack[index - 1].isLetter { score += 3 }          // word start
            if index == 0 { score += 2 }
            previousMatch = index
            queryIndex += 1
        }
        guard queryIndex == needle.count else { return nil }
        return score * 100 / max(haystack.count, 1) + score * 10
    }

    /// Items whose best field matches, best first; ties keep their original order.
    static func rank<Item>(_ items: [Item], query: String, fields: (Item) -> [String]) -> [Item] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item -> (Item, Int, Int)? in
                let best = fields(item).compactMap { score(query, in: $0) }.max()
                return best.map { (item, $0, offset) }
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .map(\.0)
    }
}

/// ⌘K: switch model or server, or run a common action, from the keyboard.
struct CommandPaletteView: View {
    let session: ChatSession
    var onClose: () -> Void
    var onAction: (CommandPaletteAction) -> Void

    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @Environment(ModelCatalog.self) private var catalog
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool

    struct Item: Identifiable, Hashable {
        enum Kind: Hashable {
            case model(serverID: UUID, modelID: String)
            case action(CommandPaletteAction)
        }
        var id: String
        var kind: Kind
        var title: String
        var subtitle: String?
        var symbol: String
        var badges: [ModelCapability] = []
        var isCurrent = false
        var shortcut: String?
    }

    private var items: [Item] {
        let current = session.resolvedSelection(servers: servers)
        var models: [Item] = []
        for server in servers {
            for model in catalog.models(for: server.id) {
                models.append(Item(
                    id: "\(server.id)|\(model.id)",
                    kind: .model(serverID: server.id, modelID: model.id),
                    title: model.id,
                    subtitle: servers.count > 1 ? server.name : [model.parameterSize, model.quantization].compactMap { $0 }.joined(separator: " · "),
                    symbol: "cpu",
                    badges: [ModelCapability.vision, .thinking].filter(model.capabilities.contains),
                    isCurrent: server.id == current.server?.id && model.id == current.modelID
                ))
            }
        }
        let actions = CommandPaletteAction.allCases.map {
            Item(id: "action-\($0)", kind: .action($0), title: $0.title, symbol: $0.symbol, shortcut: $0.shortcut)
        }
        return CommandPaletteMatcher.rank(models + actions, query: query) { [$0.title, $0.subtitle ?? ""] }
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: Spacing.small + 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Switch model or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { activate(items[safe: highlighted]) }
                    .onKeyPress(.downArrow) { move(1, count: items.count); return .handled }
                    .onKeyPress(.upArrow) { move(-1, count: items.count); return .handled }
                    .onKeyPress(.escape) { onClose(); return .handled }
                Text("esc")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(Spacing.large)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isHighlighted: index == highlighted)
                                .id(item.id)
                                .onTapGesture { activate(item) }
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                    .padding(Spacing.small)
                }
                // Shrink to the results instead of leaving an empty card (rows are ~52 pt).
                .frame(height: min(CGFloat(max(items.count, 1)) * 52 + 16, 380))
                .animation(.snappy(duration: 0.2), value: items.count)
                .onChange(of: highlighted) { _, index in
                    if let id = items[safe: index]?.id { proxy.scrollTo(id) }
                }
            }
            .overlay {
                if items.isEmpty {
                    Text(catalog.states.values.contains(.loading) ? "Loading models…" : "No matches")
                        .foregroundStyle(.secondary)
                        .padding(Spacing.xLarge)
                }
            }
        }
        .frame(maxWidth: 580)
        .glassSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onAppear { isFocused = true }
        .task {
            for server in servers { await catalog.load(server) }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: item.symbol)
                .frame(width: 22)
                .foregroundStyle(isHighlighted ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.small)
            ForEach(item.badges, id: \.self) { badge in
                Image(systemName: badge.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : Color.secondary)
                    .help(badge.label)
            }
            if item.isCurrent {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
            }
        }
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(isHighlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    private func activate(_ item: Item?) {
        guard let item else { return }
        switch item.kind {
        case .model(let serverID, let modelID):
            if let server = servers.first(where: { $0.id == serverID }) {
                session.select(server: server, modelID: modelID)
            }
            onClose()
        case .action(let action):
            onClose()
            onAction(action)
        }
    }
}

nonisolated enum CommandPaletteAction: CaseIterable, Hashable, Sendable {
    case newChat, chatSettings, browseModels, settings

    var title: String {
        switch self {
        case .newChat: "New Chat"
        case .chatSettings: "Chat Settings…"
        case .browseModels: "Browse Models…"
        case .settings: "Settings…"
        }
    }

    var symbol: String {
        switch self {
        case .newChat: "square.and.pencil"
        case .chatSettings: "slider.horizontal.3"
        case .browseModels: "square.grid.2x2"
        case .settings: "gearshape"
        }
    }

    var shortcut: String? {
        switch self {
        case .newChat: "⌘N"
        case .chatSettings: "⌥⌘I"
        case .browseModels: nil
        case .settings: "⌘,"
        }
    }
}

/// Dimmed backdrop + palette, with a spring (or a fade under Reduce Motion).
struct CommandPaletteOverlay: View {
    let session: ChatSession
    @Binding var isPresented: Bool
    var onAction: (CommandPaletteAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if isPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .accessibilityLabel("Close command palette")
                    .accessibilityAddTraits(.isButton)
                CommandPaletteView(session: session, onClose: close, onAction: onAction)
                    .padding(.horizontal, Spacing.large)
                    .padding(.top, Spacing.xxLarge)
                    .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -8)))
            }
        }
        .animation(Motion.spring(reduceMotion: reduceMotion), value: isPresented)
    }

    private func close() { isPresented = false }
}
