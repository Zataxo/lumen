import SwiftData
import SwiftUI

/// The app's main navigation: New Chat, search, history, Settings.
struct SidebarView: View {
    @Binding var selectedChatID: UUID?
    var onNewChat: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsRouter.self) private var settingsRouter
    @Query(sort: \Chat.updatedAt, order: .reverse) private var chats: [Chat]
    @State private var searchText = ""

    // Row actions
    @State private var chatBeingRenamed: Chat?
    @State private var renameText = ""
    @State private var chatPendingDeletion: Chat?
    @State private var exportDocument: ExportDocument?
    @State private var exportFileName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            history
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        #if os(macOS)
        .toolbar(removing: .title)
        #endif
        .alert("Rename Chat", isPresented: isPresented($chatBeingRenamed)) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename() }
                .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .confirmationDialog(
            "Delete “\(chatPendingDeletion?.title ?? "")”?",
            isPresented: isPresented($chatPendingDeletion),
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                if let chatPendingDeletion { delete(chatPendingDeletion) }
            }
        } message: {
            Text("This can't be undone.")
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .markdownText,
            defaultFilename: exportFileName
        ) { _ in
            exportDocument = nil
        }
    }

    private func isPresented<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Spacing.small) {
            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.small + 1)
                    .contentShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            }
            .buttonStyle(SidebarHeaderButtonStyle())
            .help("New Chat (⌘N)")

            SidebarSearchField(text: $searchText)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.xSmall)
    }

    // MARK: History

    private var filteredChats: [Chat] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return chats }
        // In-memory filter over titles (and model names): well under a millisecond for 1,000 chats.
        return chats.filter {
            $0.title.localizedStandardContains(query) || ($0.modelID?.localizedStandardContains(query) ?? false)
        }
    }

    @ViewBuilder
    private var history: some View {
        let visible = filteredChats
        let pinned = visible.filter(\.isPinned)
        let groups = HistoryGrouping.group(visible.filter { !$0.isPinned }, date: \.updatedAt)

        List(selection: $selectedChatID) {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned) { row(for: $0) }
                }
            }
            ForEach(groups) { group in
                Section(group.bucket.title) {
                    ForEach(group.items) { row(for: $0) }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .animation(.snappy, value: pinned.map(\.id))
        #if os(macOS)
        .onDeleteCommand {
            if let id = selectedChatID, let chat = chats.first(where: { $0.id == id }) {
                chatPendingDeletion = chat
            }
        }
        #endif
        .overlay {
            if visible.isEmpty {
                emptyHistory
            }
        }
    }

    private func row(for chat: Chat) -> some View {
        ChatHistoryRow(chat: chat)
            .tag(chat.id)
            .contextMenu {
                Button("Rename…", systemImage: "pencil") { beginRename(chat) }
                Button(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin") {
                    togglePin(chat)
                }
                Button("Export as Markdown…", systemImage: "square.and.arrow.up") { export(chat) }
                Divider()
                Button("Delete…", systemImage: "trash", role: .destructive) { chatPendingDeletion = chat }
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { chatPendingDeletion = chat }
                Button("Rename", systemImage: "pencil") { beginRename(chat) }
                    .tint(.gray)
            }
            .swipeActions(edge: .leading) {
                Button(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash.fill" : "pin.fill") {
                    togglePin(chat)
                }
                .tint(.orange)
            }
    }

    @ViewBuilder
    private var emptyHistory: some View {
        if searchText.isEmpty {
            VStack(spacing: Spacing.small) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No chats yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    // MARK: Actions

    private func beginRename(_ chat: Chat) {
        renameText = chat.title
        chatBeingRenamed = chat
    }

    private func commitRename() {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chat = chatBeingRenamed, !title.isEmpty else { return }
        chat.title = title
        chat.hasTitle = true
        chatBeingRenamed = nil
    }

    private func togglePin(_ chat: Chat) {
        withAnimation(.snappy) { chat.isPinned.toggle() }
    }

    private func export(_ chat: Chat) {
        let snapshot = ExportedChat(chat: chat, context: modelContext)
        exportFileName = ChatExporter.fileName(for: chat.title) + ".md"
        exportDocument = ExportDocument(data: Data(ChatExporter.markdown(snapshot).utf8), contentType: .markdownText)
    }

    private func delete(_ chat: Chat) {
        chatPendingDeletion = nil
        if selectedChatID == chat.id { selectedChatID = nil }
        // Windows showing this chat drop their session before the object goes away.
        settingsRouter.deleteChats([chat.id]) { [modelContext] in
            modelContext.delete(chat)
            try? modelContext.save()
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            VStack(spacing: Spacing.xxSmall) {
                SettingsRowButton()
                ProfileRowButton()
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.small)
        }
        .background(.bar) // rows scroll underneath; keep the footer legible
    }
}

private struct ChatHistoryRow: View {
    let chat: Chat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(chat.title)
                .lineLimit(1)
            if let model = chat.modelID {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The user's avatar and name at the very bottom of the sidebar; a subtle "Set up profile"
/// row when there's no profile. Opens the profile editor.
private struct ProfileRowButton: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            HStack(spacing: Spacing.small + 2) {
                if let profile = profiles.first {
                    AvatarView(profile: profile, size: 26)
                    Text(profile.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                    Text("Set up profile")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHeaderButtonStyle(isProminent: false))
        .help(profiles.isEmpty ? "Set up your profile" : "Edit profile")
        .sheet(isPresented: $isEditing) {
            ProfileEditorView()
        }
    }
}

/// Settings row: opens the Settings window on macOS, a sheet on iOS.
private struct SettingsRowButton: View {
    @Environment(\.openAppSettings) private var openAppSettings

    var body: some View {
        Button {
            openAppSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.small - 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(SidebarHeaderButtonStyle(isProminent: false))
        .help("Settings (⌘,)")
    }
}

private struct SidebarSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.small - 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.small + 2)
        .padding(.vertical, Spacing.small - 1)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        #if os(macOS)
        .onExitCommand { text = ""; isFocused = false }
        #endif
    }
}

private struct SidebarHeaderButtonStyle: ButtonStyle {
    var isProminent = true
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return .primary.opacity(0.12) }
        if isHovering { return .primary.opacity(0.08) }
        return isProminent ? .primary.opacity(0.05) : .clear
    }
}
