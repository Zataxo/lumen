import SwiftData
import SwiftUI

/// Settings → Servers: list with live status, default marker, add / edit / delete.
struct ServersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ServerStatusMonitor.self) private var statusMonitor
    @Environment(SettingsRouter.self) private var settingsRouter
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]

    @State private var editorTarget: ServerEditorTarget?
    @State private var serverPendingDeletion: ServerConfig?
    #if os(macOS)
    @State private var localOllamaAvailable = false
    #endif

    var body: some View {
        List {
            #if os(macOS)
            if localOllamaAvailable, !servers.contains(where: LocalOllamaDetector.isLocalOllama) {
                LocalOllamaBanner { editorTarget = .localOllama }
            }
            #endif

            if servers.isEmpty {
                ContentUnavailableView {
                    Label("No Servers", systemImage: "server.rack")
                } description: {
                    Text("Add an Ollama or OpenAI-compatible server to start chatting.")
                } actions: {
                    Button("Add Server…") { editorTarget = .new }
                        .buttonStyle(.borderedProminent)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(servers) { server in
                        NavigationLink(value: server.id) {
                            ServerRow(server: server, status: statusMonitor.status(for: server.id))
                        }
                        .contextMenu { menuItems(for: server) }
                        #if os(iOS)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { serverPendingDeletion = server }
                            Button("Edit", systemImage: "pencil") { editorTarget = .existing(server.id) }
                                .tint(.gray)
                        }
                        .swipeActions(edge: .leading) {
                            if !server.isDefault {
                                Button("Make Default", systemImage: "star") { makeDefault(server) }
                                    .tint(.yellow)
                            }
                        }
                        #endif
                    }
                } footer: {
                    Text("Select a server to browse its models. API keys and headers are stored in the Keychain.")
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { macBottomBar }
        #endif
        .navigationTitle("Servers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(for: UUID.self) { id in
            if let server = servers.first(where: { $0.id == id }) {
                ModelExplorerView(serverID: server.id)
            }
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button("Add Server", systemImage: "plus") { editorTarget = .new }
            }
            #endif
        }
        .sheet(item: $editorTarget) { target in
            ServerEditorView(target: target)
        }
        .confirmationDialog(
            "Delete “\(serverPendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { serverPendingDeletion != nil }, set: { if !$0 { serverPendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Server", role: .destructive) {
                if let serverPendingDeletion { delete(serverPendingDeletion) }
            }
        } message: {
            Text("Chats that used this server are kept.")
        }
        .task(id: servers.map(\.id)) {
            await statusMonitor.monitor(servers)
        }
        #if os(macOS)
        .task { localOllamaAvailable = await LocalOllamaDetector.isRunning() }
        #endif
        .onChange(of: settingsRouter.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            settingsRouter.pendingRequest = nil
            switch request {
            case .addServer: editorTarget = .new
            case .addLocalOllama: editorTarget = .localOllama
            }
        }
    }

    @ViewBuilder
    private func menuItems(for server: ServerConfig) -> some View {
        Button("Edit…", systemImage: "pencil") { editorTarget = .existing(server.id) }
        if !server.isDefault {
            Button("Make Default", systemImage: "star") { makeDefault(server) }
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { serverPendingDeletion = server }
    }

    #if os(macOS)
    private var macBottomBar: some View {
        HStack {
            Button("Add Server…", systemImage: "plus") { editorTarget = .new }
            Spacer()
        }
        .padding(Spacing.medium)
        .background(.bar)
    }
    #endif

    private func makeDefault(_ server: ServerConfig) {
        for other in servers { other.isDefault = other.id == server.id }
    }

    private func delete(_ server: ServerConfig) {
        let wasDefault = server.isDefault
        KeychainStore.deleteSecrets(for: server.id)
        modelContext.delete(server)
        if wasDefault, let next = servers.first(where: { $0.id != server.id }) {
            next.isDefault = true
        }
        serverPendingDeletion = nil
    }
}

private struct ServerRow: View {
    let server: ServerConfig
    let status: ServerStatus
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(spacing: Spacing.medium) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.small - 2) {
                    Text(server.name)
                        .font(.body.weight(.medium))
                    if server.isDefault {
                        CapsuleBadge(title: "Default", systemImage: "star.fill", tint: accent)
                    }
                    if server.isUnencrypted {
                        NotEncryptedBadge()
                    }
                }
                Text(server.baseURLString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(server.kind.displayName) · \(status.description)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
                    .animation(.easeOut, value: status)
            }
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

#if os(macOS)
private struct LocalOllamaBanner: View {
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ollama is running on this Mac")
                    .font(.body.weight(.medium))
                Text(LocalOllamaDetector.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, Spacing.xSmall)
    }
}
#endif
