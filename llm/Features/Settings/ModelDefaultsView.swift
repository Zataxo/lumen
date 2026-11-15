import SwiftData
import SwiftUI

/// Settings → Models: the default model for new chats (from the default server), plus the
/// default system prompt and sampling parameters.
struct ModelDefaultsView: View {
    @Query(sort: \ServerConfig.createdAt) private var servers: [ServerConfig]
    @State private var listModel = ModelListModel()
    @State private var defaults = GenerationDefaults.current


    private var defaultServer: ServerConfig? { servers.first(where: \.isDefault) ?? servers.first }

    var body: some View {
        Form {
            if let defaultServer {
                Section {
                    LabeledContent("Server", value: defaultServer.name)
                    modelPicker(for: defaultServer)
                } header: {
                    Text("New Chats")
                } footer: {
                    Text("New chats start with this model. You can switch models in any chat.")
                        .font(.caption)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Default Server",
                        systemImage: "server.rack",
                        description: Text("Add a server first, then pick its default model here.")
                    )
                }
            }
            parametersSections
        }
        .onChange(of: defaults) { _, newValue in newValue.save() }
        .formStyle(.grouped)
        .navigationTitle("Models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: defaultServer?.id) {
            guard let defaultServer else { return }
            await listModel.load(from: ServerConnection(server: defaultServer))
            await ModelListModel.ensureDefaultModel(for: defaultServer)
        }
    }

    @ViewBuilder
    private var parametersSections: some View {
        Section {
            TextField("System Prompt", text: $defaults.systemPrompt, prompt: Text("You are a helpful assistant."), axis: .vertical)
                .lineLimit(3...10)
        } header: {
            Text("System Prompt")
        } footer: {
            Text("Sent at the start of every new conversation. Leave empty to use the model's own.")
                .font(.caption)
        }

        Section {
            ParameterControls(parameters: Binding(
                get: { defaults.parameters },
                set: {
                    defaults.temperature = $0.temperature
                    defaults.topP = $0.topP
                    defaults.contextLength = $0.contextLength
                }
            ))
        } header: {
            Text("Parameters")
        } footer: {
            Text("Context length is sent as num_ctx to Ollama; other servers use their own setting.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private func modelPicker(for server: ServerConfig) -> some View {
        switch listModel.state {
        case .idle, .loading:
            LabeledContent("Default Model") { ProgressView().controlSize(.small) }
        case .failed(let error):
            LabeledContent("Default Model") {
                HStack {
                    Text(error.title).foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await listModel.load(from: ServerConnection(server: server)) }
                    }
                }
            }
        case .loaded:
            Picker("Default Model", selection: Binding(
                get: { server.defaultModelID },
                set: { server.defaultModelID = $0 }
            )) {
                if server.defaultModelID == nil { Text("None").tag(String?.none) }
                ForEach(listModel.models.filter { !$0.capabilities.contains(.embedding) }) { model in
                    Text(model.id).tag(Optional(model.id))
                }
                // Keep a stored model selectable even if the server no longer lists it.
                if let current = server.defaultModelID, !listModel.models.contains(where: { $0.id == current }) {
                    Text("\(current) (unavailable)").tag(Optional(current))
                }
            }
        }
    }
}
