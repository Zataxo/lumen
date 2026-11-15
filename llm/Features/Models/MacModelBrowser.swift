#if os(macOS)
import SwiftData
import SwiftUI

/// macOS model browser: list on the left, details on the right, all inside one sheet.
/// No navigation pushes or window-toolbar items, so it behaves the same in the Settings
/// window and over a chat.
struct MacModelBrowser: View {
    var allowsServerSwitching = false
    var onUseModel: ((ServerConfig, String) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(PullManager.self) private var pullManager
    @Environment(ModelCatalog.self) private var catalog
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @State private var serverID: UUID
    @State private var listModel = ModelListModel()
    @State private var search = ""
    @State private var capabilityFilter: ModelCapability?
    @State private var selection: String?
    @State private var isPullSheetPresented = false

    init(serverID: UUID, allowsServerSwitching: Bool = false, onUseModel: ((ServerConfig, String) -> Void)? = nil) {
        _serverID = State(initialValue: serverID)
        self.allowsServerSwitching = allowsServerSwitching
        self.onUseModel = onUseModel
    }

    private var server: ServerConfig? { servers.first { $0.id == serverID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                modelList
                    .frame(width: 300)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 860, minHeight: 560, idealHeight: 620)
        .sheet(isPresented: $isPullSheetPresented) {
            if let server { PullModelView(server: server) }
        }
        .task(id: ReloadKey(serverID: serverID, completions: pullManager.completions[serverID] ?? 0)) {
            await reload()
        }
        .onChange(of: serverID) { _, _ in selection = nil }
    }

    private struct ReloadKey: Hashable {
        var serverID: UUID
        var completions: Int
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: Spacing.medium) {
            if allowsServerSwitching, servers.count > 1 {
                Picker("Server", selection: $serverID) {
                    ForEach(servers) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            } else if let server {
                Label(server.name, systemImage: "server.rack")
                    .font(.headline)
            }
            Spacer()
            TextField("Search models", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            Picker("Show", selection: $capabilityFilter) {
                Text("All Models").tag(ModelCapability?.none)
                Divider()
                ForEach([ModelCapability.vision, .tools, .thinking, .embedding], id: \.self) {
                    Label($0.label, systemImage: $0.symbolName).tag(Optional($0))
                }
            }
            .labelsHidden()
            .fixedSize()
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
    }

    private var footer: some View {
        HStack {
            if server?.kind == .ollama {
                Button("Pull Model…", systemImage: "arrow.down.circle") { isPullSheetPresented = true }
            }
            if let total = totalSize, total > 0, let server {
                Text("\(listModel.models.count) models · \(Format.bytes(total)) on \(server.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
    }

    private var totalSize: Int64? {
        let sizes = listModel.models.compactMap(\.sizeBytes)
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }

    // MARK: List

    @ViewBuilder
    private var modelList: some View {
        switch listModel.state {
        case .idle, .loading:
            List(0..<6, id: \.self) { _ in ModelRow.placeholder }
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
        case .failed(let error):
            ContentUnavailableView {
                Label(error.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.hint ?? "")
            } actions: {
                Button("Retry") { Task { await reload() } }
            }
        case .loaded:
            let models = listModel.filteredModels(search: search, capability: capabilityFilter)
            let jobs = server.map { pullManager.jobs(for: $0.id) } ?? []
            List(selection: $selection) {
                if !jobs.isEmpty, let server {
                    Section("Downloads") {
                        ForEach(jobs) { PullJobRow(job: $0, server: server) }
                    }
                }
                if !listModel.loadedModels.isEmpty, search.isEmpty, capabilityFilter == nil {
                    Section("Loaded Now") {
                        ForEach(listModel.loadedModels) { LoadedModelRow(model: $0).tag($0.id) }
                    }
                }
                Section(models.count == 1 ? "1 Model" : "\(models.count) Models") {
                    ForEach(models) { model in
                        ModelRow(model: model, isDefault: model.id == server?.defaultModelID)
                            .tag(model.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if models.isEmpty, jobs.isEmpty {
                    if search.isEmpty, capabilityFilter == nil {
                        ContentUnavailableView("No Models", systemImage: "cpu")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let server {
            ModelDetailView(
                server: server,
                model: listModel.models.first { $0.id == selection } ?? ModelInfo(id: selection),
                loaded: listModel.loadedModels.first { $0.id == selection },
                onUseModel: onUseModel,
                onDeleted: {
                    self.selection = nil
                    Task { await reload() }
                },
                dismissesOnDelete: false
            )
            .id(selection)
        } else {
            ContentUnavailableView(
                "Select a Model",
                systemImage: "cpu",
                description: Text("Choose a model to see its details\(onUseModel == nil ? "" : " or use it in this chat").")
            )
        }
    }

    private func reload() async {
        guard let server else { return }
        await listModel.load(from: ServerConnection(server: server))
        catalog.invalidate(server.id)
    }
}
#endif
