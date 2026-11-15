import SwiftUI

/// Spacing scale used across the app (4-pt grid).
enum Spacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
    static let xxLarge: CGFloat = 32
}

enum Radius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 16
}

enum Motion {
    /// The app's standard spring; falls back to a short fade when Reduce Motion is on.
    static func spring(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.86)
    }
}

extension View {
    /// Liquid Glass on OS 26+, a system material before that.
    @ViewBuilder
    func glassSurface(in shape: some Shape = RoundedRectangle(cornerRadius: Radius.large, style: .continuous)) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
