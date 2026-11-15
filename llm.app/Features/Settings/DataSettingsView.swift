import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Data: export every chat (Markdown or JSON) and delete all chats.
struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsRouter.self) private var settingsRouter
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]

    @State private var exportDocument: ExportDocument?
    @State private var exportFileName = ""
    @State private var isConfirmingDeleteAll = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Chats", value: chats.count.formatted())
                LabeledContent("Messages", value: messageCount.formatted())
            } header: {
                Text("Storage")
            } footer: {
                Text("Chats are stored only on this device.")
                    .font(.caption)
            }

            Section {
                Button("Export All as Markdown…", systemImage: "doc.richtext") { export(as: .markdownText) }
                Button("Export All as JSON…", systemImage: "curlybraces") { export(as: .json) }
            } header: {
                Text("Export")
            } footer: {
                Text("Markdown is easy to read and share; JSON keeps every field for backups or other tools.")
                    .font(.caption)
            }
            .disabled(chats.isEmpty)

            Section {
                Button("Delete All Chats…", systemImage: "trash", role: .destructive) {
                    isConfirmingDeleteAll = true
                }
                .disabled(chats.isEmpty)
            } footer: {
                Text("Servers, settings and your profile are kept.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Data")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .markdownText,
            defaultFilename: exportFileName
        ) { result in
            exportDocument = nil
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .confirmationDialog(
            "Delete all \(chats.count) chats?",
            isPresented: $isConfirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete All Chats", role: .destructive, action: deleteAll)
        } message: {
            Text("This permanently removes every conversation. It can't be undone.")
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var messageCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Message>())) ?? 0
    }

    private func export(as type: UTType) {
        let snapshots = chats.map { ExportedChat(chat: $0, context: modelContext) }
        let date = Date.now.formatted(.iso8601.year().month().day())
        do {
            if type == .json {
                exportDocument = ExportDocument(data: try ChatExporter.json(snapshots), contentType: .json)
                exportFileName = "Lumen Chats \(date).json"
            } else {
                exportDocument = ExportDocument(data: Data(ChatExporter.markdown(snapshots).utf8), contentType: .markdownText)
                exportFileName = "Lumen Chats \(date).md"
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func deleteAll() {
        settingsRouter.deleteChats(nil) { [modelContext] in
            // Batch deletes skip cascade rules, so remove each level explicitly.
            try? modelContext.delete(model: Attachment.self)
            try? modelContext.delete(model: Message.self)
            try? modelContext.delete(model: Chat.self)
            try? modelContext.save()
        }
    }
}
