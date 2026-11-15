import Foundation

/// A rendered-ready Markdown block. Built off the main actor, cached per message, and
/// compared by value so unchanged blocks skip re-rendering while a reply streams.
nonisolated indirect enum MarkdownBlock: Hashable, Sendable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case code(CodeBlockContent)
    case quote([MarkdownBlock])
    case list(MarkdownList)
    case table(MarkdownTable)
    case rule
}

nonisolated struct CodeBlockContent: Hashable, Sendable {
    var language: String?
    var code: String
    var highlighted: AttributedString
}

nonisolated struct MarkdownList: Hashable, Sendable {
    enum Checkbox: Hashable, Sendable { case checked, unchecked }

    struct Item: Hashable, Sendable {
        var checkbox: Checkbox?
        var blocks: [MarkdownBlock]
    }

    var isOrdered: Bool
    var startIndex: Int
    var items: [Item]
}

nonisolated struct MarkdownTable: Hashable, Sendable {
    enum Alignment: Hashable, Sendable { case leading, center, trailing }

    var alignments: [Alignment]
    var header: [AttributedString]
    var rows: [[AttributedString]]

    var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }
}

/// A parsed document. `blocks` keep their index as identity, which is stable while a
/// streaming reply only appends text.
nonisolated struct MarkdownDocument: Hashable, Sendable {
    var blocks: [MarkdownBlock]

    static let empty = MarkdownDocument(blocks: [])
}
