import SwiftUI

/// Per-chat system prompt and sampling parameters. Anything left unset follows
/// Settings → Models.
struct ChatSettingsView: View {
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ChatOverrides()
    @State private var didLoad = false

    private var defaults: GenerationDefaults { GenerationDefaults.current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Custom System Prompt", isOn: Binding(
                        get: { draft.systemPrompt != nil },
                        set: { draft.systemPrompt = $0 ? (defaults.systemPrompt) : nil }
                    ))
                    if draft.systemPrompt != nil {
                        TextField("System Prompt", text: Binding(
                            get: { draft.systemPrompt ?? "" },
                            set: { draft.systemPrompt = $0 }
                        ), prompt: Text("Leave empty to send no system prompt"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...12)
                        .multilineTextAlignment(.leading)
                    }
                } header: {
                    Text("System Prompt")
                } footer: {
                    Text(draft.systemPrompt == nil
                         ? (defaults.systemPrompt.isEmpty ? "Uses no system prompt (Settings → Models has none)." : "Uses the default: “\(defaults.systemPrompt.prefix(80))\(defaults.systemPrompt.count > 80 ? "…" : "")”")
                         : "Only this chat uses this prompt.")
                        .font(.caption)
                }

                Section {
                    ParameterControls(parameters: $draft.parameters, inheritLabel: "Default")
                } header: {
                    Text("Parameters")
                } footer: {
                    Text("“Default” follows Settings → Models\(defaultsSummary).")
                        .font(.caption)
                }

                if !draft.isEmpty {
                    Section {
                        Button("Reset to Defaults", role: .destructive) {
                            withAnimation(.snappy) { draft = ChatOverrides() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chat Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        session.overrides = draft
                        dismiss()
                    }
                }
            }
            .animation(.snappy, value: draft.systemPrompt == nil)
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 480, idealHeight: 560)
        #endif
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            draft = session.overrides
        }
    }

    private var defaultsSummary: String {
        var parts: [String] = []
        if let temperature = defaults.temperature { parts.append("temperature \(temperature.formatted(.number.precision(.fractionLength(2))))") }
        if let topP = defaults.topP { parts.append("top P \(topP.formatted(.number.precision(.fractionLength(2))))") }
        if let context = defaults.contextLength { parts.append(Format.contextLength(context)) }
        return parts.isEmpty ? " (currently the model's own values)" : " (\(parts.joined(separator: ", ")))"
    }
}
