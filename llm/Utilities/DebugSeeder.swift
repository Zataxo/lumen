#if DEBUG
import Foundation
import SwiftData

/// Debug-only: launch with `-LumenSeedChats 1000` to fill history for performance testing
/// (sidebar scrolling, search, grouping). Seeded chats are titled "Sample …" and spread over
/// the last 90 days; nothing happens without the launch argument.
enum DebugSeeder {
    static func seedIfRequested(into context: ModelContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-LumenSeedChats"),
              flag + 1 < arguments.count,
              let count = Int(arguments[flag + 1]), count > 0
        else { return }

        let existing = (try? context.fetchCount(FetchDescriptor<Chat>(predicate: #Predicate { $0.title.starts(with: "Sample ") }))) ?? 0
        guard existing < count else { return }

        let topics = ["Swift concurrency", "Sourdough starter", "Kubernetes ingress", "Trip to Lisbon", "Rust lifetimes",
                      "SQL window functions", "Marathon training", "SwiftData migrations", "French grammar", "Regex for emails",
                      "Tax deductions", "Garden irrigation", "Neural network basics", "Bash one-liners", "Coffee extraction"]
        let models = ["llama3.2:3b", "qwen3:8b", "gemma3:12b"]
        for index in existing..<count {
            let chat = Chat(title: "Sample \(index + 1): \(topics[index % topics.count])", serverID: nil, modelID: models[index % models.count])
            chat.hasTitle = true
            let age = TimeInterval((index * 7919) % (90 * 24)) * 3600 // pseudo-random spread over 90 days
            chat.updatedAt = Date.now.addingTimeInterval(-age)
            chat.createdAt = chat.updatedAt
            chat.isPinned = index < 3
            context.insert(chat)

            let question = Message(role: .user, content: "Tell me about \(topics[index % topics.count]).")
            question.chatID = chat.id
            question.position = 0
            question.chat = chat
            let answer = Message(role: .assistant, content: "## \(topics[index % topics.count])\n\nHere are **three** key points:\n\n1. First\n2. Second\n3. Third\n\n```swift\nlet answer = \(index)\n```")
            answer.chatID = chat.id
            answer.position = 1
            answer.modelID = chat.modelID
            answer.chat = chat
            context.insert(question)
            context.insert(answer)
        }
        try? context.save()
    }
}
#endif
