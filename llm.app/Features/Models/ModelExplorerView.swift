import SwiftData
import SwiftUI

struct ModelRoute: Hashable {
    var serverID: UUID
    var modelID: String
}

/// Browse a server's models: downloads in progress, what's loaded in memory, and every model
/// with its metadata and capability badges. Opened from Settings → Servers or the chat model
/// picker (where it can also switch servers and pick a model for the chat).
struct ModelExplorerView: View {
    var allowsServerSwitching = false
    /// Set when opened from a chat: shows "Use in This Chat" on the detail page.
    var onUseModel: ((ServerConfig, String) -> Void)?

    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @Environment(PullManager.self) private var pullManager
    @Environment(ModelCatalog.self) private var catalog
    @State private var serverID: UUID
    @State private var listModel = ModelListModel()
    @State private var searchText = ""
    @State private var capabilityFilter: ModelCapability?
    @State private var isPullSheetPresented = false

    init(serverID: UUID, allowsServerSwitching: Bool = false, onUseModel: ((ServerConfig, String) -> Void)? = nil) {
        _serverID = State(initialValue: serverID)
        self.allowsServerSwitching = allowsServerSwitching
        self.onUseModel = onUseModel
    }

    private var server: ServerConfig? { servers.first { $0.id == serverID } }

    var body: some View {
        Group {
            if let server {
                content(for: server)
            } else {
                ContentUnavailableView("Server Not Found", systemImage: "server.rack")
            }
        }
        .navigationTitle(server.map { allowsServerSwitching ? "Models" : $0.name } ?? "Models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search models")
        .toolbar { toolbarContent }
        .navigationDestination(for: ModelRoute.self) { route in
            if let server = servers.first(where: { $0.id == route.serverID }) {
                ModelDetailView(
                    server: server,
                    model: listModel.models.first { $0.id == route.modelID } ?? ModelInfo(id: route.modelID),
                    loaded: listModel.loadedModels.first { $0.id == route.modelID },
                    onUseModel: onUseModel,
                    onDeleted: { Task { await reload() } }
                )
            }
        }
        .sheet(isPresented: $isPullSheetPresented) {
            if let server { PullModelView(server: server) }
        }
        .task(id: ReloadKey(serverID: serverID, completions: pullManager.completions[serverID] ?? 0)) {
            await reload()
        }
    }

    private struct ReloadKey: Hashable {
        var serverID: UUID
        var completions: Int
    }

    // MARK: Content

    @ViewBuilder
    private func content(for server: ServerConfig) -> some View {
        switch listModel.state {
        case .idle, .loading:
            List {
                ForEach(0..<6, id: \.self) { _ in ModelRow.placeholder }
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
        case .failed(let error):
            ContentUnavailableView {
                Label(error.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.hint ?? "")
            } actions: {
                Button("Retry") { Task { await reload() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            loadedList(for: server)
        }
    }

    private func loadedList(for server: ServerConfig) -> some View {
        let models = listModel.filteredModels(search: searchText, capability: capabilityFilter)
        let jobs = pullManager.jobs(for: server.id)
        let isFiltering = !searchText.isEmpty || capabilityFilter != nil
        return List {
            if !jobs.isEmpty {
                Section("Downloads") {
                    ForEach(jobs) { PullJobRow(job: $0, server: server) }
                }
            }
            if !listModel.loadedModels.isEmpty, !isFiltering {
                Section("Loaded Now") {
                    ForEach(listModel.loadedModels) { loaded in
                        NavigationLink(value: ModelRoute(serverID: server.id, modelID: loaded.id)) {
                            LoadedModelRow(model: loaded)
                        }
                    }
                }
            }
            Section {
                ForEach(models) { model in
                    NavigationLink(value: ModelRoute(serverID: server.id, modelID: model.id)) {
                        ModelRow(model: model, isDefault: model.id == server.defaultModelID)
                    }
                }
            } header: {
                Text(models.count == 1 ? "1 Model" : "\(models.count) Models")
            } footer: {
                if !isFiltering, let total = totalSize, total > 0 {
                    Text("\(Format.bytes(total)) on \(server.name)")
                }
            }
        }
        .overlay {
            if models.isEmpty, jobs.isEmpty {
                if isFiltering {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("No Models", systemImage: "cpu")
                    } description: {
                        Text(server.kind == .ollama ? "Download a model to start chatting." : "This server didn't report any models.")
                    } actions: {
                        if server.kind == .ollama {
                            Button("Pull a Model…") { isPullSheetPresented = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .refreshable { await reload() }
    }

    private var totalSize: Int64? {
        let sizes = listModel.models.compactMap(\.sizeBytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if allowsServerSwitching, servers.count > 1 {
            ToolbarItem(placement: .principal) {
                Picker("Server", selection: $serverID) {
                    ForEach(servers) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if server?.kind == .ollama {
                Button("Pull Model", systemImage: "arrow.down.circle") { isPullSheetPresented = true }
                    .help("Download a model from the Ollama library")
            }
            Menu {
                Picker("Capability", selection: $capabilityFilter) {
                    Text("All Models").tag(ModelCapability?.none)
                    ForEach([ModelCapability.vision, .tools, .thinking, .embedding], id: \.self) {
                        Label($0.label, systemImage: $0.symbolName).tag(Optional($0))
                    }
                }
                .pickerStyle(.inline)
                #if os(macOS)
                Divider()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }
                #endif
            } label: {
                Label("Filter", systemImage: capabilityFilter == nil
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
            }
        }
    }

    private func reload() async {
        guard let server else { return }
        await listModel.load(from: ServerConnection(server: server))
        catalog.invalidate(server.id)
    }
}

/// Progress, result and controls for one download.
struct PullJobRow: View {
    let job: PullJob
    let server: ServerConfig
    @Environment(PullManager.self) private var pullManager

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            icon
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(job.model)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                switch job.state {
                case .running:
                    if let fraction = job.progress.fraction {
                        ProgressView(value: fraction)
                            .animation(.linear(duration: 0.15), value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(detailText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                case .finished:
                    Text("Downloaded \(Format.bytes(job.progress.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let error):
                    Text([error.title, error.hint].compactMap { $0 }.joined(separator: " — "))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                case .cancelled:
                    Text("Cancelled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch job.state {
        case .running: Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch job.state {
        case .running:
            Button("Cancel", systemImage: "xmark.circle.fill") { pullManager.cancel(job) }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .help("Cancel download")
        case .failed, .cancelled:
            HStack(spacing: Spacing.small) {
                Button("Retry") { pullManager.pull(job.model, on: server) }
                Button("Dismiss", systemImage: "xmark") { pullManager.dismiss(job) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        case .finished:
            Button("Dismiss", systemImage: "xmark") { pullManager.dismiss(job) }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
    }

    private var detailText: String {
        var parts = [job.progress.phase]
        if job.progress.totalBytes > 0 {
            parts.append("\(Format.bytes(job.progress.completedBytes)) of \(Format.bytes(job.progress.totalBytes))")
            if let fraction = job.progress.fraction { parts.append(fraction.formatted(.percent.precision(.fractionLength(0)))) }
        }
        if let speed = job.bytesPerSecond, job.progress.phase == "Downloading" {
            parts.append("\(Format.bytes(Int64(speed)))/s")
        }
        return parts.joined(separator: " · ")
    }
}
