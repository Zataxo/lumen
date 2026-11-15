import SwiftUI

/// Full metadata for one model, with Use / Set as Default and (for Ollama) Delete.
struct ModelDetailView: View {
    let server: ServerConfig
    let model: ModelInfo
    let loaded: LoadedModel?
    var onUseModel: ((ServerConfig, String) -> Void)?
    var onDeleted: () -> Void
    /// Pop the navigation stack after deleting (iOS push). The macOS split browser clears
    /// its selection instead, so dismissing would close the whole sheet.
    var dismissesOnDelete = true

    @Environment(\.dismiss) private var dismiss
    @State private var details: ModelDetails?
    @State private var loadError: ProviderError?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: ProviderError?
    @State private var metadataFilter = ""

    /// List info (size, modified date) merged with `/api/show` details (capabilities, context).
    private var info: ModelInfo {
        guard let detail = details?.info else { return model }
        var merged = model
        merged.family = merged.family ?? detail.family
        merged.parameterSize = merged.parameterSize ?? detail.parameterSize
        merged.quantization = merged.quantization ?? detail.quantization
        merged.contextLength = detail.contextLength ?? merged.contextLength
        if !detail.capabilities.isEmpty { merged.capabilities = detail.capabilities }
        return merged
    }

    var body: some View {
        Form {
            header
            actionsSection
            overview
            if let details {
                textSections(details)
                metadataSection(details)
            } else if let loadError {
                Section {
                    Label(loadError.title, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await load() } }
                }
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            if server.kind == .ollama {
                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        if isDeleting {
                            HStack(spacing: Spacing.small) { ProgressView().controlSize(.small); Text("Deleting…") }
                        } else {
                            Label("Delete Model…", systemImage: "trash")
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(isDeleting)
                } footer: {
                    if let deleteError {
                        Text([deleteError.title, deleteError.hint].compactMap { $0 }.joined(separator: " — "))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(info.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .confirmationDialog("Delete “\(model.id)”?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Model", role: .destructive) { Task { await delete() } }
        } message: {
            Text("It will be removed from \(server.name)\(info.sizeBytes.map { " and free \(Format.bytes($0))" } ?? ""). You'd need to download it again to use it.")
        }
    }

    // MARK: Sections

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(info.displayName)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                    if let tag = info.tag {
                        Text(tag)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                let badges = [ModelCapability.completion, .vision, .tools, .thinking, .embedding].filter(info.capabilities.contains)
                if !badges.isEmpty {
                    HStack(spacing: Spacing.xSmall) {
                        ForEach(badges, id: \.self) { CapabilityBadge(capability: $0) }
                        if loaded != nil {
                            CapsuleBadge(title: "Loaded", systemImage: "memorychip", tint: .green)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.xSmall)
        }
    }

    /// Actions as plain rows (the platform pattern for a Form; buttons inside one row misbehave).
    @ViewBuilder
    private var actionsSection: some View {
        let isChatModel = !info.capabilities.contains(.embedding)
        if isChatModel {
            Section {
                if let onUseModel {
                    Button {
                        onUseModel(server, model.id)
                    } label: {
                        Label("Use in This Chat", systemImage: "checkmark.circle")
                    }
                }
                if server.defaultModelID == model.id {
                    Label("Default for new chats", systemImage: "star.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        server.defaultModelID = model.id
                    } label: {
                        Label("Set as Default for New Chats", systemImage: "star")
                    }
                }
            }
        }
    }

    private var overview: some View {
        Section("Overview") {
            row("Family", info.family)
            row("Parameters", info.parameterSize)
            row("Quantization", info.quantization)
            row("Size on Disk", info.sizeBytes.map(Format.bytes))
            row("Context Length", info.contextLength.map { "\($0.formatted()) tokens" })
            row("Modified", info.modifiedAt?.formatted(date: .abbreviated, time: .shortened))
            if let loaded {
                row("In Memory", loaded.sizeInVRAMBytes.map { "\(Format.bytes($0)) on GPU" } ?? loaded.sizeBytes.map(Format.bytes))
                if let context = loaded.contextLength { row("Loaded Context", "\(context.formatted()) tokens") }
            }
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(title) {
                Text(value).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func textSections(_ details: ModelDetails) -> some View {
        if let parameters = details.parameters?.trimmingCharacters(in: .whitespacesAndNewlines), !parameters.isEmpty {
            Section("Default Parameters") {
                Text(parameters)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
        let blocks: [(String, String?)] = [("System Prompt", details.systemPrompt), ("Template", details.template), ("License", details.license)]
        ForEach(blocks, id: \.0) { title, text in
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                Section {
                    DisclosureGroup(title) {
                        ScrollView {
                            Text(text)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metadataSection(_ details: ModelDetails) -> some View {
        let entries = details.metadata
            .filter { metadataFilter.isEmpty || $0.key.localizedStandardContains(metadataFilter) }
            .sorted { $0.key < $1.key }
        if !details.metadata.isEmpty {
            Section {
                DisclosureGroup("Metadata (\(details.metadata.count))") {
                    TextField("Filter keys", text: $metadataFilter)
                        .autocorrectionDisabled()
                    ForEach(entries, id: \.key) { key, value in
                        LabeledContent {
                            Text(value)
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .textSelection(.enabled)
                        } label: {
                            Text(key)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        loadError = nil
        guard let connection = ServerConnection(server: server) else {
            loadError = .invalidURL
            return
        }
        do {
            details = try await ProviderFactory.makeProvider(for: connection).modelDetails(id: model.id)
        } catch {
            loadError = ProviderError.map(error, host: connection.baseURL.host())
        }
    }

    private func delete() async {
        guard let connection = ServerConnection(server: server),
              let provider = ProviderFactory.makeProvider(for: connection) as? any ModelManaging
        else { return }
        isDeleting = true
        deleteError = nil
        do {
            try await provider.deleteModel(model.id)
            if server.defaultModelID == model.id { server.defaultModelID = nil }
            isDeleting = false
            onDeleted()
            if dismissesOnDelete { dismiss() }
        } catch {
            isDeleting = false
            deleteError = ProviderError.map(error, host: connection.baseURL.host())
        }
    }
}
