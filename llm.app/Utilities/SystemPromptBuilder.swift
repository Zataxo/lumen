import Foundation

/// What the model is told about the user (only when the profile toggle is on).
nonisolated struct ProfileContext: Hashable, Sendable {
    var name: String
    var aboutMe: String
}

nonisolated enum SystemPromptBuilder {
    /// Combines the configured system prompt with the user's profile. Returns "" when there's
    /// nothing to send.
    static func build(base: String, profile: ProfileContext?) -> String {
        var sections: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty { sections.append(trimmedBase) }

        if let profile {
            var lines: [String] = []
            let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let about = profile.aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { lines.append("The user's name is \(name).") }
            if !about.isEmpty { lines.append("About the user:\n\(about)") }
            if !lines.isEmpty { sections.append(lines.joined(separator: "\n")) }
        }
        return sections.joined(separator: "\n\n")
    }
}

nonisolated enum Greeting {
    /// "Good evening, Hassan" with a profile; a neutral prompt without one.
    static func text(name: String?, date: Date = .now, calendar: Calendar = .current) -> String {
        guard let firstName = name?.split(separator: " ").first.map(String.init), !firstName.isEmpty else {
            return "What can I help with?"
        }
        let hour = calendar.component(.hour, from: date)
        let salutation = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello"
        }
        return "\(salutation), \(firstName)"
    }
}

nonisolated struct PromptSuggestion: Identifiable, Hashable, Sendable {
    var id: String { title }
    var symbol: String
    var title: String
    var prompt: String

    static let all: [PromptSuggestion] = [
        .init(symbol: "lightbulb", title: "Explain a concept", prompt: "Explain how public-key cryptography works, with a simple analogy."),
        .init(symbol: "chevron.left.forwardslash.chevron.right", title: "Write some code", prompt: "Write a Swift function that removes duplicates from an array while keeping order."),
        .init(symbol: "airplane", title: "Plan a trip", prompt: "Plan a relaxed 3-day itinerary for Lisbon with food recommendations."),
        .init(symbol: "text.badge.checkmark", title: "Improve my writing", prompt: "Make this paragraph clearer and more concise:\n\n"),
        .init(symbol: "sparkles", title: "Brainstorm ideas", prompt: "Give me 10 name ideas for a minimalist note-taking app."),
        .init(symbol: "ladybug", title: "Debug an error", prompt: "What usually causes \"Thread 1: Fatal error: Index out of range\" in Swift, and how do I find it?"),
        .init(symbol: "envelope", title: "Draft an email", prompt: "Draft a polite email asking to move tomorrow's meeting to Friday."),
        .init(symbol: "scalemass", title: "Compare options", prompt: "Compare SQLite, Core Data and SwiftData for a small iOS app in a table."),
    ]

    /// A stable-per-call random selection.
    static func sample(_ count: Int) -> [PromptSuggestion] {
        Array(all.shuffled().prefix(count))
    }
}
