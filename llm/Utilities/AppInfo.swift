import Foundation

/// Version info from the app bundle (MARKETING_VERSION / CURRENT_PROJECT_VERSION).
nonisolated enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var configuration: String {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }

    /// "Version 1.0 (1)", plus " · Debug" for debug builds.
    static var versionLine: String {
        "Version \(version) (\(build))" + (configuration == "Debug" ? " · Debug" : "")
    }
}
