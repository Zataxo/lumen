import Foundation
import Markdown

// This file deliberately imports only Foundation + swift-markdown: Markdown's `Text`, `Link`
// and `Image` would clash with SwiftUI's.

/// Converts Markdown text into `MarkdownDocument` blocks (GitHub-flavoured: tables,
/// strikethrough, task lists).
nonisolated enum MarkdownParser {
    static func parse(_ source: String) -> MarkdownDocument {
        guard !source.isEmpty else { return .empty }
        let document = Document(parsing: source)
        return MarkdownDocument(blocks: blocks(in: document))
    }

    private static func blocks(in container: some Markup) -> [MarkdownBlock] {
        container.children.compactMap(block(for:))
    }

    private static func block(for markup: any Markup) -> MarkdownBlock? {
        switch markup {
        case let paragraph as Paragraph:
            return .paragraph(inline(paragraph))
        case let heading as Heading:
            return .heading(level: heading.level, text: inline(heading))
        case let codeBlock as CodeBlock:
            var code = codeBlock.code
            if code.hasSuffix("\n") { code.removeLast() }
            let language = codeBlock.language?.trimmingCharacters(in: .whitespaces).lowercased()
            let normalized = (language?.isEmpty ?? true) ? nil : language
            return .code(CodeBlockContent(
                language: normalized,
                code: code,
                highlighted: SyntaxHighlighter.highlight(code, language: normalized)
            ))
        case let quote as BlockQuote:
            return .quote(blocks(in: quote))
        case let list as UnorderedList:
            return .list(MarkdownList(isOrdered: false, startIndex: 1, items: list.listItems.map(item)))
        case let list as OrderedList:
            return .list(MarkdownList(isOrdered: true, startIndex: Int(list.startIndex), items: list.listItems.map(item)))
        case let table as Table:
            return .table(convert(table))
        case is ThematicBreak:
            return .rule
        case let html as HTMLBlock:
            let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : .paragraph(AttributedString(raw))
        default:
            let text = markup.format().trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .paragraph(AttributedString(text))
        }
    }

    private static func item(_ listItem: ListItem) -> MarkdownList.Item {
        let checkbox: MarkdownList.Checkbox? = switch listItem.checkbox {
        case .checked: .checked
        case .unchecked: .unchecked
        case nil: nil
        }
        return MarkdownList.Item(checkbox: checkbox, blocks: blocks(in: listItem))
    }

    private static func convert(_ table: Table) -> MarkdownTable {
        let alignments: [MarkdownTable.Alignment] = table.columnAlignments.map {
            switch $0 {
            case .center: .center
            case .right: .trailing
            case .left, nil: .leading
            }
        }
        let header: [AttributedString] = table.head.cells.map { inline($0) }
        let rows: [[AttributedString]] = table.body.rows.map { row in Array(row.cells.map { inline($0) }) }
        return MarkdownTable(alignments: alignments, header: header, rows: rows)
    }

    // MARK: Inline

    private static func inline(_ markup: some Markup) -> AttributedString {
        var result = AttributedString()
        appendInline(children: markup, intent: [], link: nil, into: &result)
        return result
    }

    private static func appendInline(
        children markup: some Markup,
        intent: InlinePresentationIntent,
        link: URL?,
        into result: inout AttributedString
    ) {
        for child in markup.children {
            appendInline(child, intent: intent, link: link, into: &result)
        }
    }

    private static func appendInline(
        _ markup: any Markup,
        intent: InlinePresentationIntent,
        link: URL?,
        into result: inout AttributedString
    ) {
        func append(_ string: String, extraIntent: InlinePresentationIntent = []) {
            var piece = AttributedString(string)
            let combined = intent.union(extraIntent)
            if !combined.isEmpty { piece.inlinePresentationIntent = combined }
            if let link { piece.link = link }
            result.append(piece)
        }

        switch markup {
        case let text as Markdown.Text:
            append(text.string)
        case let code as InlineCode:
            append(code.code, extraIntent: .code)
        case is SoftBreak:
            append(" ")
        case is LineBreak:
            append("\n")
        case let emphasis as Emphasis:
            appendInline(children: emphasis, intent: intent.union(.emphasized), link: link, into: &result)
        case let strong as Strong:
            appendInline(children: strong, intent: intent.union(.stronglyEmphasized), link: link, into: &result)
        case let strike as Strikethrough:
            appendInline(children: strike, intent: intent.union(.strikethrough), link: link, into: &result)
        case let linkMarkup as Markdown.Link:
            let url = linkMarkup.destination.flatMap(URL.init(string:))
            if linkMarkup.childCount == 0 {
                append(linkMarkup.destination ?? "")
            } else {
                appendInline(children: linkMarkup, intent: intent, link: url ?? link, into: &result)
            }
        case let image as Markdown.Image:
            let alt = image.plainText.isEmpty ? (image.source ?? "image") : image.plainText
            var piece = AttributedString("🖼 " + alt)
            if let source = image.source, let url = URL(string: source) { piece.link = url }
            result.append(piece)
        case let html as InlineHTML:
            append(html.rawHTML)
        default:
            if markup.childCount > 0 {
                appendInline(children: markup, intent: intent, link: link, into: &result)
            } else {
                append(markup.format())
            }
        }
    }
}
