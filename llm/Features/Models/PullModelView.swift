import SwiftUI

/// Download a model to an Ollama server by name. The download keeps running if this sheet is
/// closed; it also appears under "Downloads" in the model explorer.
struct PullModelView: View {
    let server: ServerConfig

    @Environment(\.dismiss) private var dismiss
    @Environment(PullManager.self) private var pullManager
    @State private var name = ""
    @State private var job: PullJob?
    @FocusState private var nameFocused: Bool

    private static let suggestions = ["llama3.2:3b", "qwen3:8b", "gemma3:4b", "mistral:7b", "deepseek-r1:8b", "nomic-embed-text"]

    private var isValid: Bool { ModelNameValidator.isValid(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Model", text: $name, prompt: Text("e.g. llama3.2:3b"))
                        .font(.body.monospaced())
                        .focused($nameFocused)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        #endif
                        .onSubmit(start)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.small) {
                            ForEach(Self.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { name = suggestion }
                                    .font(.caption.monospaced())
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                } header: {
                    Text("Model Name")
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        if !name.isEmpty, !isValid {
                            Text("Use a name like “llama3.2” or “qwen3:8b” (letters, numbers, . _ - / and one “:” tag).")
                                .foregroundStyle(.red)
                        }
                        Text("Downloads to \(server.name). Find names in the [Ollama library](https://ollama.com/library).")
                    }
                    .font(.caption)
                }

                if let job {
                    Section("Progress") {
                        PullJobRow(job: job, server: server)
                    }
                    if job.isActive {
                        Section {
                            Text("You can close this window — the download continues in the background.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pull Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(job == nil ? "Cancel" : "Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if job?.state == .finished {
                        Button("Done") { dismiss() }
                    } else {
                        Button("Pull", action: start)
                            .disabled(!isValid || job?.isActive == true)
                    }
                }
            }
            .animation(.snappy, value: job?.state)
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 360)
        #endif
        .onAppear { nameFocused = true }
    }

    private func start() {
        guard isValid else { return }
        job = pullManager.pull(name, on: server)
    }
}
