import SwiftData
import SwiftUI

/// Toolbar control showing the current model and server; opens the picker.
struct ModelPickerButton: View {
    let session: ChatSession
    let server: ServerConfig?
    let modelID: String?
    /// Re-applied to the popover, which may be hosted outside the window's view tree.
    let environment: ForwardedEnvironment
    var onBrowse: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: Spacing.xSmall + 1) {
                VStack(spacing: 0) {
                    Text(modelID ?? "Choose Model")
                        .font(.headline)
                        .lineLimit(1)
                    if let server {
                        Text(server.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch model or server")
        .accessibilityLabel("Model: \(modelID ?? "none"), server: \(server?.name ?? "none")")
        .popover(isPresented: $isPresented, arrowEdge: Self.arrowEdge) {
            ModelPickerView(
                session: session,
                initialServerID: server?.id,
                currentModelID: modelID,
                onDone: { isPresented = false },
                onBrowse: {
                    isPresented = false
                    // Let the popover finish dismissing before presenting the sheet.
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        onBrowse()
                    }
                }
            )
            .forwardingEnvironment(environment)
            .modifier(ModelPickerPresentation())
        }
    }
}

extension ModelPickerButton {
    /// macOS names the anchor's edge; iOS names the popover's edge, so `.top` places it below.
    #if os(macOS)
    static let arrowEdge = Edge.bottom
    #else
    static let arrowEdge = Edge.top
    #endif
}

/// iPad: always a compact popover under the title, even in a narrow window, where it would
/// otherwise turn into a half-height sheet. iPhone: a sheet with a grabber.
private struct ModelPickerPresentation: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.presentationCompactAdaptation(.popover)
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCompactAdaptation(.sheet)
        }
        #else
        content
        #endif
    }
}

/// The model explorer presented from a chat: can switch servers and pick a model for the chat.
struct ChatModelExplorerSheet: View {
    let session: ChatSession
    let serverID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        MacModelBrowser(serverID: serverID, allowsServerSwitching: true) { chosenServer, model in
            session.select(server: chosenServer, modelID: model)
            dismiss()
        }
        #else
        NavigationStack {
            ModelExplorerView(serverID: serverID, allowsServerSwitching: true) { chosenServer, model in
                session.select(server: chosenServer, modelID: model)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #endif
    }
}

/// Server switcher + searchable model list.
struct ModelPickerView: View {
    let session: ChatSession
    let currentModelID: String?
    var onDone: () -> Void
    var onBrowse: () -> Void

    @Environment(ModelCatalog.self) private var catalog
    @Environment(\.openAppSettings) private var openAppSettings
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @State private var serverID: UUID?
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    init(session: ChatSession, initialServerID: UUID?, currentModelID: String?, onDone: @escaping () -> Void, onBrowse: @escaping () -> Void) {
        self.session = session
        self.currentModelID = currentModelID
        self.onDone = onDone
        self.onBrowse = onBrowse
        _serverID = State(initialValue: initialServerID)
    }

    private var server: ServerConfig? { servers.first { $0.id == serverID } ?? servers.first }

    var body: some View {
        VStack(spacing: 0) {
            if servers.count > 1 || showsSearch {
                VStack(spacing: Spacing.small) {
                    if servers.count > 1 {
                        Picker("Server", selection: $serverID) {
                            ForEach(servers) { server in
                                Text(server.name).tag(Optional(server.id))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if showsSearch {
                        searchField
                    }
                }
                .padding(Spacing.medium)
                Divider()
            }

            content
                #if os(macOS)
                .frame(minHeight: 220)
                #else
                .frame(minHeight: isPad ? nil : 220)
                .frame(height: isPad ? padListHeight : nil)
                #endif
            Divider()

            HStack {
                Button("Browse Models…", systemImage: "square.grid.2x2", action: onBrowse)
                Spacer(minLength: Spacing.small)
                Button("Manage Servers…") {
                    onDone()
                    openAppSettings()
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small + 2)
        }
        #if os(macOS)
        .frame(width: 360, height: 420)
        #else
        .frame(width: isPad ? 380 : nil)
        #endif
        .task(id: server?.id) {
            if let server { await catalog.load(server) }
        }
        #if os(macOS)
        // Type-to-filter and Return to pick. On iPad and iPhone this would pop up the
        // on-screen keyboard over the list the moment the picker opens.
        .onAppear { searchFocused = true }
        #endif
    }

    private var searchField: some View {
        HStack(spacing: Spacing.small - 2) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search models", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let first = filteredModels.first { choose(first) } }
        }
        .padding(.horizontal, Spacing.small + 2)
        .padding(.vertical, Spacing.small - 1)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// Mac keeps the search field for typing to filter; on touch screens a short list doesn't need it.
    private var showsSearch: Bool {
        #if os(macOS)
        true
        #else
        guard let server else { return false }
        return catalog.models(for: server.id).count > 6 || !search.isEmpty
        #endif
    }

    #if os(iOS)
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// iPad popovers size to their content, and a List has no natural height, so estimate one
    /// that fits the rows without leaving a large empty gap.
    private var padListHeight: CGFloat {
        guard let server else { return 200 }
        switch catalog.state(for: server.id) {
        case .loaded:
            let rows = filteredModels.reduce(CGFloat(0)) { total, model in
                let hasDetails = model.parameterSize != nil || model.quantization != nil
                return total + (hasDetails ? 71 : 50)
            }
            return min(max(rows, 140), 420)
        case .failed:
            return 240
        case .idle, .loading:
            return 5 * 71
        }
    }
    #endif

    private var filteredModels: [ModelInfo] {
        guard let server else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces)
        let all = catalog.models(for: server.id)
        return query.isEmpty ? all : all.filter { $0.id.localizedStandardContains(query) }
    }

    @ViewBuilder
    private var content: some View {
        if let server {
            switch catalog.state(for: server.id) {
            case .idle, .loading:
                List(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("placeholder-model:8b")
                        Text("8.0B · Q4_K_M").font(.caption)
                    }
                }
                .listStyle(.plain)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.hint ?? "")
                } actions: {
                    Button("Retry") { Task { await catalog.load(server, force: true) } }
                }
            case .loaded:
                List(filteredModels) { model in
                    Button {
                        choose(model)
                    } label: {
                        HStack(spacing: Spacing.small) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.id)
                                    .foregroundStyle(.primary)
                                let details = [model.parameterSize, model.quantization].compactMap { $0 }
                                if !details.isEmpty {
                                    Text(details.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            ForEach([ModelCapability.vision, .thinking].filter(model.capabilities.contains), id: \.self) {
                                Image(systemName: $0.symbolName)
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                                    .help($0.label)
                            }
                            if model.id == currentModelID, server.id == session.resolvedSelection(servers: servers).server?.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .overlay {
                    if filteredModels.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        } else {
            ContentUnavailableView("No Servers", systemImage: "server.rack")
        }
    }

    private func choose(_ model: ModelInfo) {
        guard let server else { return }
        session.select(server: server, modelID: model.id)
        onDone()
    }
}
