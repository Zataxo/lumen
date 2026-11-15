#if os(macOS)
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Profile on macOS: edited in place and saved as you type, like System Settings.
struct MacProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MacProfileForm(profile: profile)
            } else {
                Form {
                    Section {
                        HStack(spacing: Spacing.large) {
                            AvatarView(name: "", imageData: nil, color: .graphite, size: 56)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No profile")
                                    .font(.headline)
                                Text("Add your name and a little about yourself. Lumen greets you by name and can tell the model who it's talking to. Everything stays on this Mac.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Spacing.xSmall)
                    } footer: {
                        HStack {
                            Spacer()
                            Button("Create Profile") { createProfile() }
                                .keyboardShortcut(.defaultAction)
                        }
                        .padding(.top, Spacing.xSmall)
                    }
                    AccountSection()
                }
                .formStyle(.grouped)
            }
        }
    }

    private func createProfile() {
        // Start from the Mac account's name; the user can change it right away.
        let profile = UserProfile(name: NSFullUserName(), includeAboutMeInPrompt: true, avatarColor: PaletteColor.allCases.randomElement() ?? .blue)
        modelContext.insert(profile)
        try? modelContext.save()
    }
}

private struct MacProfileForm: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @State private var photoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: Spacing.large) {
                    AvatarView(profile: profile, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name.isEmpty ? "Your Name" : profile.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(profile.name.isEmpty ? .secondary : .primary)
                        Text("Shown in the sidebar and on the welcome screen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu("Edit Picture") {
                        Button("Choose from Photos…") { isPhotoPickerPresented = true }
                        Button("Choose File…") { isFileImporterPresented = true }
                        if profile.avatarData != nil {
                            Divider()
                            Button("Use Initials") { profile.avatarData = nil }
                        }
                    }
                    .fixedSize()
                }
                .padding(.vertical, Spacing.xSmall)

                if profile.avatarData == nil {
                    LabeledContent("Color") {
                        HStack(spacing: Spacing.small) {
                            ForEach(PaletteColor.allCases) { color in
                                Button {
                                    profile.avatarColor = color
                                } label: {
                                    Circle()
                                        .fill(color.color.gradient)
                                        .frame(width: 18, height: 18)
                                        .overlay {
                                            Circle()
                                                .strokeBorder(.primary.opacity(profile.avatarColor == color ? 0.7 : 0), lineWidth: 2)
                                                .padding(-3)
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(color.name)
                                .accessibilityLabel("\(color.name) avatar color")
                            }
                        }
                    }
                }
            }

            Section {
                TextField("Name", text: $profile.name, prompt: Text("Your name"))
            }

            Section {
                TextField("About me", text: $profile.aboutMe, prompt: Text("e.g. I'm an iOS developer in Lisbon. Keep answers concise."), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(3...8)
                    .multilineTextAlignment(.leading)
                Toggle("Include in system prompt", isOn: $profile.includeAboutMeInPrompt)
            } header: {
                Text("About Me")
            } footer: {
                Text("When on, your name and About me are sent to the model at the start of each chat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Your profile is stored only on this Mac.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove Profile…", role: .destructive) { isConfirmingRemoval = true }
                }
            }

            AccountSection()
        }
        .formStyle(.grouped)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoItem, matching: .images)
        .fileImporter(isPresented: $isFileImporterPresented, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result, let data = ImageIntake.read(url) {
                setAvatar(from: data)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { setAvatar(from: data) }
                photoItem = nil
            }
        }
        .confirmationDialog("Remove your profile?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Profile", role: .destructive) {
                modelContext.delete(profile)
                try? modelContext.save()
            }
        } message: {
            Text("Your name, picture and About me are deleted from this Mac. Chats are kept.")
        }
    }

    private func setAvatar(from data: Data) {
        Task {
            let thumbnail = await Task.detached { ImageDownscaler.jpegThumbnail(from: data, maxPixelSize: 256) }.value
            if let thumbnail { profile.avatarData = thumbnail }
        }
    }
}
#endif
