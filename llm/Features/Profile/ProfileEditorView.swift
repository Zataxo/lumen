import PhotosUI
import SwiftData
import SwiftUI

/// Create or edit the on-device profile. Changes are saved with Save; Remove Profile deletes it.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @State private var name = ""
    @State private var aboutMe = ""
    @State private var includeAboutMe = true
    @State private var avatarData: Data?
    @State private var avatarColor = PaletteColor.blue
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isConfirmingRemoval = false
    @State private var didLoad = false
    @FocusState private var nameFocused: Bool

    private var existing: UserProfile? { profiles.first }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                Section {
                    TextField("Name", text: $name, prompt: Text("Your name"))
                        .focused($nameFocused)
                        #if os(iOS)
                        .textContentType(.name)
                        #endif
                }

                Section {
                    TextField("About me", text: $aboutMe, prompt: Text("e.g. I'm an iOS developer in Lisbon. Keep answers concise."), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(3...8)
                        .multilineTextAlignment(.leading)
                    Toggle("Include About me in system prompt", isOn: $includeAboutMe)
                } header: {
                    Text("About Me")
                } footer: {
                    Text("When on, your name and About me are sent to the model at the start of each chat so it knows who it's talking to. Everything else stays on this device.")
                        .font(.caption)
                }

                if existing != nil {
                    Section {
                        Button("Remove Profile…", role: .destructive) { isConfirmingRemoval = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "Set Up Profile" : "Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .confirmationDialog("Remove your profile?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("Remove Profile", role: .destructive, action: remove)
            } message: {
                Text("Your name, photo and About me are deleted from this device. Chats are kept.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 520, idealHeight: 580)
        #endif
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private var avatarSection: some View {
        Section {
            VStack(spacing: Spacing.medium) {
                ZStack {
                    AvatarView(name: trimmedName, imageData: avatarData, color: avatarColor, size: 84)
                    if isLoadingPhoto {
                        ProgressView()
                    }
                }
                HStack(spacing: Spacing.medium) {
                    // The picker's label closure is Sendable: capture a plain value, not state.
                    let photoTitle = avatarData == nil ? "Choose Photo" : "Change Photo"
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(photoTitle, systemImage: "photo")
                    }
                    if avatarData != nil {
                        Button("Use Initials", systemImage: "textformat") {
                            avatarData = nil
                            photoItem = nil
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if avatarData == nil {
                    HStack(spacing: Spacing.small) {
                        ForEach(PaletteColor.allCases) { color in
                            Button {
                                avatarColor = color
                            } label: {
                                Circle()
                                    .fill(color.color.gradient)
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        Circle().strokeBorder(.primary.opacity(avatarColor == color ? 0.6 : 0), lineWidth: 2)
                                            .padding(-3)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(color.name) avatar color")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.small)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            name = existing.name
            aboutMe = existing.aboutMe
            includeAboutMe = existing.includeAboutMeInPrompt
            avatarData = existing.avatarData
            avatarColor = existing.avatarColor
        } else {
            avatarColor = PaletteColor.allCases.randomElement() ?? .blue
            nameFocused = true
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Keep the stored avatar tiny: 256 px is plenty for a 2× retina 84 pt circle.
        avatarData = await Task.detached { ImageDownscaler.jpegThumbnail(from: data, maxPixelSize: 256) }.value
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let profile = existing ?? {
            let created = UserProfile(name: trimmedName)
            modelContext.insert(created)
            return created
        }()
        profile.name = trimmedName
        profile.aboutMe = aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.includeAboutMeInPrompt = includeAboutMe
        profile.avatarData = avatarData
        profile.avatarColor = avatarColor
        try? modelContext.save()
        dismiss()
    }

    private func remove() {
        for profile in profiles { modelContext.delete(profile) }
        try? modelContext.save()
        dismiss()
    }
}

/// Settings → Profile: summary plus Set Up / Edit, opening the editor sheet.
struct ProfileSettingsView: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var isEditing = false

    var body: some View {
        Form {
            if let profile = profiles.first {
                Section {
                    HStack(spacing: Spacing.medium) {
                        AvatarView(profile: profile, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            Text(profile.aboutMe.isEmpty ? "No About me" : profile.aboutMe)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Edit…") { isEditing = true }
                    }
                    .padding(.vertical, Spacing.xSmall)
                    LabeledContent("Included in system prompt", value: profile.includeAboutMeInPrompt ? "On" : "Off")
                } footer: {
                    Text("Your profile is stored only on this device.")
                        .font(.caption)
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("No Profile", systemImage: "person.crop.circle")
                    } description: {
                        Text("Add your name and a little about yourself. Lumen greets you by name, and can tell the model who it's talking to.")
                    } actions: {
                        Button("Set Up Profile…") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            AccountSection()
        }
        .formStyle(.grouped)
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $isEditing) { ProfileEditorView() }
    }
}

/// "Signed in as …" with Sign Out. Used by the Profile settings on every platform.
struct AccountSection: View {
    @Environment(AuthStore.self) private var auth
    @State private var isConfirming = false

    var body: some View {
        if let account = auth.currentAccount {
            Section {
                HStack(spacing: Spacing.medium) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as \(account.displayName)")
                        Text("Signing out returns to the sign-in screen. Chats stay on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out…", role: .destructive) { isConfirming = true }
                }
                .padding(.vertical, Spacing.xxSmall)
            } header: {
                Text("Account")
            }
            .confirmationDialog("Sign out of Lumen?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
            } message: {
                Text("You'll need your username and password to continue.")
            }
        }
    }
}
