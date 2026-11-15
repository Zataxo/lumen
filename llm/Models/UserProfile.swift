import Foundation
import SwiftData
import SwiftUI

/// The optional on-device user profile. At most one exists.
@Model
final class UserProfile {
    var name: String
    var aboutMe: String
    var includeAboutMeInPrompt: Bool
    /// Downscaled JPEG; nil means "use initials".
    @Attribute(.externalStorage) var avatarData: Data?
    var avatarColorRawValue: String
    var createdAt: Date

    init(name: String, aboutMe: String = "", includeAboutMeInPrompt: Bool = false, avatarData: Data? = nil, avatarColor: PaletteColor = .blue) {
        self.name = name
        self.aboutMe = aboutMe
        self.includeAboutMeInPrompt = includeAboutMeInPrompt
        self.avatarData = avatarData
        self.avatarColorRawValue = avatarColor.rawValue
        self.createdAt = .now
    }

    var avatarColor: PaletteColor {
        get { PaletteColor(rawValue: avatarColorRawValue) ?? .blue }
        set { avatarColorRawValue = newValue.rawValue }
    }

    static func current(in context: ModelContext) -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

/// Shared color palette for the accent color and initials avatars.
nonisolated enum PaletteColor: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, green, teal, graphite

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .graphite: .gray
        }
    }
}

nonisolated enum Initials {
    /// "Hassan Abdalla" → "HA", "madonna" → "M", "  " → "?"
    static func from(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}
