import SwiftData
import SwiftUI

/// Add / edit a server, with an inline "Test connection" result.
struct ServerEditorView: View {
    let target: ServerEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ServerStatusMonitor.self) private var statusMonitor
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]

    @State private var draft = ServerDraft()
    @State private var tester = ConnectionTester()
    @State private var didLoad = false
    /// Stable id so test results and saved secrets refer to the same server.
    @State private var serverID = UUID()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, url, apiKey }

    private var existingServer: ServerConfig? {
        guard case .existing(let id) = target else { return nil }
        return servers.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                authenticationSection
                headersSection
                connectionSection
                testSection
            }
            .formStyle(.grouped)
            .navigationTitle(existingServer == nil ? "Add Server" : "Edit Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingServer == nil ? "Add" : "Save") { save() }
                        .disabled(!draft.isValid)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 560, idealHeight: 640)
        #endif
        .onAppear(perform: load)
        .onChange(of: draft.urlString) { _, _ in tester.reset() }
        .onChange(of: draft.kind) { _, _ in tester.reset() }
    }

    // MARK: Sections

    private var serverSection: some View {
        Section {
            Picker("Type", selection: $draft.kind) {
                ForEach(ServerKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            LabeledContent("URL") {
                TextField("URL", text: $draft.urlString, prompt: Text(draft.kind.urlPlaceholder))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .font(.callout.monospaced())
                    .focused($focusedField, equals: .url)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .textContentType(.URL)
                    #endif
                    .onSubmit { tester.test(draft.connection(serverID: serverID)) }
            }

            LabeledContent("Name") {
                TextField("Name", text: $draft.name, prompt: Text(draft.normalizedURL?.host() ?? "My Server"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .name)
            }
        } header: {
            Text("Server")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if draft.isUnencrypted {
                    Label("Plain http:// isn't encrypted. Fine on a trusted network or VPN; avoid it over the internet.", systemImage: "lock.open")
                        .foregroundStyle(.orange)
                } else if !draft.urlString.isEmpty, !draft.isValid {
                    Label("Enter a full address, e.g. \(draft.kind.urlPlaceholder)", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else if draft.kind == .ollama {
                    Text("Ollama listens on port \(String(draft.kind.defaultPort)) by default.")
                } else {
                    Text("Works with LM Studio, llama.cpp, vLLM and other servers exposing /v1/chat/completions.")
                }
            }
            .font(.caption)
        }
    }

    private var authenticationSection: some View {
        Section {
            LabeledContent("API Key") {
                SecureField("API Key", text: $draft.apiKey, prompt: Text("Optional"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .apiKey)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        } header: {
            Text("Authentication")
        } footer: {
            Text("Sent as “Authorization: Bearer …”. Stored in the Keychain.")
                .font(.caption)
        }
    }

    private var headersSection: some View {
        Section {
            ForEach($draft.headers) { $header in
                HStack(spacing: Spacing.small) {
                    TextField("Header", text: $header.name, prompt: Text("Header"))
                        .font(.body.monospaced())
                        .frame(maxWidth: 160)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Value", text: $header.value, prompt: Text("Value"))
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button {
                        draft.headers.removeAll { $0.id == header.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove header")
                }
                .labelsHidden()
            }
            Button("Add Header", systemImage: "plus") {
                draft.headers.append(HTTPHeader(name: "", value: ""))
            }
        } header: {
            Text("Custom Headers")
        } footer: {
            Text("For servers behind a proxy, e.g. “Authorization: Basic …”. Custom headers override the API key.")
                .font(.caption)
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("Request Timeout") {
                HStack(spacing: Spacing.small) {
                    Text("\(Int(draft.timeoutSeconds)) s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("Request Timeout", value: $draft.timeoutSeconds, in: 5...600, step: 5)
                        .labelsHidden()
                }
            }
            Toggle("Default Server", isOn: $draft.isDefault)
                .disabled(servers.isEmpty || (existingServer?.isDefault ?? false))
        }
    }

    private var testSection: some View {
        Section {
            HStack {
                Button {
                    focusedField = nil
                    tester.test(draft.connection(serverID: serverID))
                } label: {
                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(!draft.isValid || tester.state == .testing)
                Spacer()
                if tester.state == .testing {
                    ProgressView().controlSize(.small)
                }
            }
            ConnectionTestResultView(state: tester.state)
        }
        .animation(.snappy, value: tester.state)
    }

    // MARK: Load / save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        switch target {
        case .existing:
            if let existingServer {
                draft = ServerDraft(server: existingServer)
                serverID = existingServer.id
            }
        case .localOllama:
            draft.kind = .ollama
            draft.urlString = "http://localhost:11434"
            draft.name = "This Mac"
            draft.isDefault = servers.isEmpty
            tester.test(draft.connection(serverID: serverID))
        case .new:
            draft.isDefault = servers.isEmpty
            focusedField = .url
        }
    }

    private func save() {
        guard draft.isValid else { return }
        let server: ServerConfig
        if let existingServer {
            server = existingServer
        } else {
            server = ServerConfig(id: serverID, name: draft.resolvedName, kind: draft.kind, baseURLString: "")
            modelContext.insert(server)
        }
        server.name = draft.resolvedName
        // A different server type or address has a different model list: re-pick the default.
        let newURLString = draft.normalizedURL?.absoluteString ?? draft.urlString
        if server.kind != draft.kind || server.baseURLString != newURLString { server.defaultModelID = nil }
        server.kind = draft.kind
        server.baseURLString = draft.normalizedURL?.absoluteString ?? draft.urlString
        server.timeoutSeconds = draft.timeoutSeconds

        // Exactly one default server; the first server is always the default.
        let makeDefault = draft.isDefault || !servers.contains(where: { $0.isDefault && $0.id != server.id })
        if makeDefault {
            for other in servers where other.id != server.id { other.isDefault = false }
        }
        server.isDefault = makeDefault

        KeychainStore.setSecrets(draft.secrets, for: server.id)
        try? modelContext.save()

        if case .success(let report) = tester.state {
            statusMonitor.setStatus(ServerStatus(report: report), for: server.id)
        }
        dismiss()
    }
}

private struct ConnectionTestResultView: View {
    let state: ConnectionTester.State

    var body: some View {
        switch state {
        case .idle, .testing:
            EmptyView()
        case .success(let report):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.body.weight(.medium))
                    Text(summary(report))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .failure(let error):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title)
                        .font(.body.weight(.medium))
                    if let hint = error.hint {
                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .textSelection(.enabled)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func summary(_ report: HealthReport) -> String {
        var parts = ["\(report.latencyMilliseconds) ms", report.modelCount == 1 ? "1 model" : "\(report.modelCount) models"]
        if let version = report.serverVersion { parts.append(version) }
        return parts.joined(separator: " · ")
    }
}
