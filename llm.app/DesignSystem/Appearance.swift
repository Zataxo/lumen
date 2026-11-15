import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: Preferences (stored in @AppStorage)

enum AppearanceKeys {
    static let theme = "appearance.theme"
    static let accent = "appearance.accent"
    static let textSize = "appearance.textSize"
    static let spacing = "appearance.spacing"
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TextSizePreference: String, CaseIterable, Identifiable {
    case small, standard, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        }
    }

    /// Applied on top of Dynamic Type.
    var multiplier: CGFloat {
        switch self {
        case .small: 0.88
        case .standard: 1
        case .large: 1.15
        }
    }
}

enum MessageSpacing: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// MARK: Message typography

/// Fonts and spacing for chat messages, derived from the platform body size, Dynamic Type,
/// and the Text Size / Spacing preferences.
struct MessageTypography: Equatable {
    var bodySize: CGFloat
    var spacing: MessageSpacing

    static let `default` = MessageTypography(bodySize: 15, spacing: .comfortable)

    var body: Font { .system(size: bodySize) }
    var callout: Font { .system(size: (bodySize * 0.93).rounded()) }
    var code: Font { .system(size: (bodySize * 0.88).rounded(), design: .monospaced) }

    func heading(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: (bodySize * 1.45).rounded(), weight: .bold)
        case 2: .system(size: (bodySize * 1.25).rounded(), weight: .semibold)
        case 3: .system(size: (bodySize * 1.1).rounded(), weight: .semibold)
        default: .system(size: bodySize, weight: .semibold)
        }
    }

    /// Space between messages.
    var messageSpacing: CGFloat { spacing == .compact ? 14 : 26 }
    /// Space between blocks inside a message.
    var blockSpacing: CGFloat { spacing == .compact ? 8 : 12 }
    var lineSpacing: CGFloat { spacing == .compact ? 2 : 4 }
}

extension EnvironmentValues {
    @Entry var messageTypography = MessageTypography.default
    /// The user's chosen accent color (Settings → Appearance).
    @Entry var appAccent: Color = .blue
}

// MARK: Applying preferences

/// Applies theme, accent and typography preferences to a window's content. Used by every
/// window and the macOS Settings scene, so changes apply instantly everywhere.
struct AppearanceModifier: ViewModifier {
    @AppStorage(AppearanceKeys.theme) private var theme = ThemePreference.system
    @AppStorage(AppearanceKeys.accent) private var accent = PaletteColor.blue
    @AppStorage(AppearanceKeys.textSize) private var textSize = TextSizePreference.standard
    @AppStorage(AppearanceKeys.spacing) private var spacing = MessageSpacing.comfortable

    #if os(macOS)
    private let baseBodySize: CGFloat = 13
    #else
    @ScaledMetric(relativeTo: .body) private var baseBodySize: CGFloat = 17
    #endif

    func body(content: Content) -> some View {
        content
            .tint(accent.color)
            .environment(\.appAccent, accent.color)
            .environment(\.messageTypography, MessageTypography(bodySize: (baseBodySize * textSize.multiplier).rounded(), spacing: spacing))
            .onChange(of: theme, initial: true) { _, newValue in
                Self.apply(newValue)
            }
            .onChange(of: accent, initial: true) { _, newValue in
                Self.applyTint(newValue.color)
            }
    }

    /// SwiftUI's `.tint` doesn't reach UIKit-hosted controls in sheets, menus and alerts on
    /// iOS; the window's tint color does.
    static func applyTint(_ color: Color) {
        #if os(iOS)
        let uiColor = UIColor(color)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.tintColor = uiColor }
        }
        #endif
    }

    /// Sets the appearance at the window level: instant, covers sheets, menus and popovers,
    /// and reliably returns to "System".
    static func apply(_ theme: ThemePreference) {
        #if os(macOS)
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #else
        let style: UIUserInterfaceStyle = switch theme {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
        #endif
    }
}

extension View {
    func lumenAppearance() -> some View { modifier(AppearanceModifier()) }
}
