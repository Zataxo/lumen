import SwiftUI

/// macOS Settings window while signed out: settings stay unavailable until sign-in.
struct SettingsLockedView: View {
    var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Sign in to change settings")
                .font(.headline)
            Text("Use the Lumen window to sign in.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 220)
    }
}
