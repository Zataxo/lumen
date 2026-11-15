import Foundation

/// Parsed Markdown for finished messages, keyed by message id + content. Rows in a lazy
/// stack are re-created while scrolling; this keeps them from re-parsing.
final class MarkdownCache {
    static let shared = MarkdownCache()

    private struct Key: Hashable {
        var id: UUID
        var contentHash: Int
    }

    private var storage: [Key: MarkdownDocument] = [:]
    private let limit = 600

    func document(for id: UUID, content: String) -> MarkdownDocument {
        let key = Key(id: id, contentHash: content.hashValue)
        if let cached = storage[key] { return cached }
        let document = MarkdownParser.parse(content)
        if storage.count >= limit { storage.removeAll(keepingCapacity: true) }
        storage[key] = document
        return document
    }
}
