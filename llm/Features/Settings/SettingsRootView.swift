import SwiftUI

/// macOS: the system Settings window with tabs. iOS: a sheet with a navigation list.
struct SettingsRootView: View {
    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsRouter.self) private var settingsRouter
    @State private var path = NavigationPath()
    #endif

    var body: some View {
        #if os(macOS)
        // Each tab sizes itself; the Settings window animates between them like System Settings.
        TabView {
            Tab("Servers", systemImage: "server.rack") {
                MacServersSettingsView()
                    .frame(width: 600, height: 420)
            }
            Tab("Models", systemImage: "cpu") {
                ModelDefaultsView()
                    .frame(width: 600, height: 560)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                AppearanceSettingsView()
                    .frame(width: 600, height: 600)
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                MacProfileSettingsView()
                    .frame(width: 600, height: 480)
            }
            Tab("Data", systemImage: "externaldrive") {
                DataSettingsView()
                    .frame(width: 600, height: 500)
            }
        }
        #else
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: SettingsPage.servers) {
                        Label("Servers", systemImage: "server.rack")
                    }
                    NavigationLink(value: SettingsPage.models) {
                        Label("Models", systemImage: "cpu")
                    }
                }
                Section {
                    NavigationLink(value: SettingsPage.appearance) {
                        Label("Appearance", systemImage: "paintpalette")
                    }
                    NavigationLink(value: SettingsPage.profile) {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }
                Section {
                    NavigationLink(value: SettingsPage.data) {
                        Label("Data", systemImage: "externaldrive")
                    }
                } footer: {
                    Text("Lumen \(AppInfo.versionLine)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.large)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .servers: ServersSettingsView()
                case .models: ModelDefaultsView()
                case .appearance: AppearanceSettingsView()
                case .profile: ProfileSettingsView()
                case .data: DataSettingsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            // Requests like "Add Server" go straight to the Servers page.
            if settingsRouter.pendingRequest != nil, path.isEmpty { path.append(SettingsPage.servers) }
        }
        #endif
    }
}

#if os(iOS)
private enum SettingsPage: Hashable {
    case servers, models, appearance, profile, data
}
#endif
