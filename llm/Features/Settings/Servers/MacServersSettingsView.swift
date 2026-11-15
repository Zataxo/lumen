#if os(macOS)
import SwiftData
import SwiftUI

/// Settings → Servers on macOS: grouped rows in the System Settings style. Everything opens
/// in a sheet (editor, model browser), so nothing is pushed into the Settings window.
struct MacServersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ServerStatusMonitor.self) private var statusMonitor
    @Environment(SettingsRouter.self) private var settingsRouter
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]

    @State private var editorTarget: ServerEditorTarget?
    @State private var browsingServer: ServerConfig?
    @State private var serverPendingDeletion: ServerConfig?
    @State private var localOllamaAvailable = false

    var body: some View {
        Form {
            if localOllamaAvailable, !servers.contains(where: LocalOllamaDetector.isLocalOllama) {
                Section {
                    HStack(spacing: Spacing.medium) {
                        Image(systemName: "desktopcomputer")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ollama is running on this Mac")
                            Text(LocalOllamaDetector.address)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add") { editorTarget = .localOllama }
                    }
                }
            }

            Section {
                if servers.isEmpty {
                    HStack(spacing: Spacing.medium) {
                        Image(systemName: "server.rack")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No servers yet")
                            Text("Add an Ollama or OpenAI-compatible server to start chatting.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Spacing.xSmall)
                } else {
                    ForEach(servers) { server in
                        MacServerRow(
                            server: server,
                            status: statusMonitor.status(for: server.id),
                            onModels: { browsingServer = server },
                            onEdit: { editorTarget = .existing(server.id) },
                            onMakeDefault: { makeDefault(server) },
                            onDelete: { serverPendingDeletion = server }
                        )
                    }
                }
            } header: {
                Text("Servers")
            } footer: {
                HStack(alignment: .top) {
                    Text("API keys and custom headers are stored in the Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Server…") { editorTarget = .new }
                }
                .padding(.top, Spacing.xSmall)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editorTarget) { ServerEditorView(target: $0) }
        .sheet(item: $browsingServer) { MacModelBrowser(serverID: $0.id) }
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
        .task(id: servers.map(\.id)) { await statusMonitor.monitor(servers) }
        .task { localOllamaAvailable = await LocalOllamaDetector.isRunning() }
        .onChange(of: settingsRouter.pendingRequest, initial: true) { _, request in
            guard let request else { return }
            settingsRouter.pendingRequest = nil
            switch request {
            case .addServer: editorTarget = .new
            case .addLocalOllama: editorTarget = .localOllama
            }
        }
    }

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

private struct MacServerRow: View {
    let server: ServerConfig
    let status: ServerStatus
    var onModels: () -> Void
    var onEdit: () -> Void
    var onMakeDefault: () -> Void
    var onDelete: () -> Void
    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            StatusDot(status: status)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.small - 2) {
                    Text(server.name)
                        .fontWeight(.medium)
                    if server.isDefault {
                        CapsuleBadge(title: "Default", systemImage: "star.fill", tint: accent)
                    }
                    if server.isUnencrypted {
                        NotEncryptedBadge()
                    }
                }
                Text("\(server.kind.displayName) · \(server.baseURLString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(status.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: Spacing.medium)
            Button("Models…", action: onModels)
            Menu {
                Button("Edit…", action: onEdit)
                if !server.isDefault {
                    Button("Make Default", action: onMakeDefault)
                }
                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.vertical, Spacing.xxSmall)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Browse Models…", action: onModels)
            Button("Edit…", action: onEdit)
            if !server.isDefault { Button("Make Default", action: onMakeDefault) }
            Divider()
            Button("Delete…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .contain)
    }
}
#endif
