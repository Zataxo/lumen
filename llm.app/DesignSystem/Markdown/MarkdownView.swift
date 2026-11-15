import SwiftUI

/// Renders a `MarkdownDocument`. Blocks are `Equatable` views, so during streaming only the
/// block that's still growing (usually the last one) re-renders.
struct MarkdownView: View {
    let document: MarkdownDocument
    @Environment(\.messageTypography) private var typography

    var body: some View {
        MarkdownBlocksView(blocks: document.blocks)
            .font(typography.body)
            .textSelection(.enabled)
    }
}

private struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    @Environment(\.messageTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: typography.blockSpacing) {
            ForEach(blocks.indices, id: \.self) { index in
                MarkdownBlockView(block: blocks[index])
                    .equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    @Environment(\.messageTypography) private var typography

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.block == rhs.block }

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .lineSpacing(typography.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(text)
                .font(typography.heading(level))
                .padding(.top, level <= 2 ? Spacing.xSmall : 0)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .code(let content):
            CodeBlockView(content: content)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: Spacing.medium) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.tertiary)
                    .frame(width: 3)
                MarkdownBlocksView(blocks: blocks)
                    .foregroundStyle(.secondary)
            }
        case .list(let list):
            MarkdownListView(list: list)
        case .table(let table):
            MarkdownTableView(table: table)
        case .rule:
            Divider().padding(.vertical, Spacing.xSmall)
        }
    }

}

private struct MarkdownListView: View {
    let list: MarkdownList
    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small - 2) {
            ForEach(list.items.indices, id: \.self) { index in
                let item = list.items[index]
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    marker(for: item, index: index)
                        .frame(minWidth: list.isOrdered ? 20 : 12, alignment: .trailing)
                    MarkdownBlocksView(blocks: item.blocks)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for item: MarkdownList.Item, index: Int) -> some View {
        if let checkbox = item.checkbox {
            Image(systemName: checkbox == .checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checkbox == .checked ? accent : .secondary)
                .imageScale(.small)
        } else if list.isOrdered {
            Text("\(list.startIndex + index).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable
    @Environment(\.messageTypography) private var typography

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<table.columnCount, id: \.self) { column in
                        cell(table.header[safe: column], column: column)
                            .font(typography.callout.weight(.semibold))
                            .background(.quaternary.opacity(0.5))
                    }
                }
                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { column in
                            cell(table.rows[rowIndex][safe: column], column: column)
                                .font(typography.callout)
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        }
    }

    private func cell(_ text: AttributedString?, column: Int) -> some View {
        Text(text ?? "")
            .multilineTextAlignment(textAlignment(column))
            .frame(minWidth: 60, maxWidth: 320, alignment: frameAlignment(column))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .gridColumnAlignment(gridAlignment(column))
    }

    private func alignment(_ column: Int) -> MarkdownTable.Alignment {
        table.alignments[safe: column] ?? .leading
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        switch alignment(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        switch alignment(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private func gridAlignment(_ column: Int) -> HorizontalAlignment {
        switch alignment(column) {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// A code block with a language label, copy button and horizontal scrolling.
struct CodeBlockView: View {
    let content: CodeBlockContent
    @State private var didCopy = false
    @Environment(\.messageTypography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(content.language ?? "code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Clipboard.copy(content.code)
                    withAnimation(.snappy) { didCopy = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.snappy) { didCopy = false }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(didCopy ? Color.green : .secondary)
                .help("Copy code")
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small - 2)
            .background(Color.codeHeaderBackground)

            ScrollView(.horizontal) {
                Text(content.highlighted)
                    .font(typography.code)
                    .lineSpacing(2)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(Spacing.medium)
                    .textSelection(.enabled)
            }
            .scrollIndicators(.automatic)
        }
        .background(Color.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

extension Color {
    static let codeBackground = Color.dynamic(light: (0.965, 0.965, 0.975), dark: (0.105, 0.105, 0.115))
    static let codeHeaderBackground = Color.dynamic(light: (0.93, 0.93, 0.945), dark: (0.15, 0.15, 0.165))
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
