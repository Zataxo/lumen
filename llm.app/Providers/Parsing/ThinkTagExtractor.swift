import Foundation

/// Splits streamed text into answer content and `<think>…</think>` reasoning.
/// Tags may arrive split across chunks (`"<thi"` + `"nk>"`), so any trailing text that could
/// be the start of a tag is held back until the next chunk decides it.
nonisolated struct ThinkTagExtractor: Sendable {
    private static let openTag = "<think>"
    private static let closeTag = "</think>"

    private var pending = ""
    private var isThinking = false
    /// Models usually emit blank lines right after `</think>`; drop them.
    private var trimLeadingWhitespace = false

    init() {}

    mutating func feed(_ text: String) -> [ChatChunk] {
        var output: [ChatChunk] = []
        var buffer = pending + text
        pending = ""

        while !buffer.isEmpty {
            let tag = isThinking ? Self.closeTag : Self.openTag
            if let range = buffer.range(of: tag) {
                emit(String(buffer[..<range.lowerBound]), into: &output)
                buffer = String(buffer[range.upperBound...])
                isThinking.toggle()
                if !isThinking { trimLeadingWhitespace = true }
            } else {
                let held = Self.longestSuffix(of: buffer, thatPrefixes: tag)
                emit(String(buffer.dropLast(held)), into: &output)
                pending = String(buffer.suffix(held))
                buffer = ""
            }
        }
        return output
    }

    /// Flushes held-back text when the stream ends.
    mutating func finish() -> [ChatChunk] {
        var output: [ChatChunk] = []
        emit(pending, into: &output)
        pending = ""
        return output
    }

    private mutating func emit(_ text: String, into output: inout [ChatChunk]) {
        var text = text
        if !isThinking, trimLeadingWhitespace {
            text = String(text.drop(while: \.isWhitespace))
            if text.isEmpty { return }
            trimLeadingWhitespace = false
        }
        guard !text.isEmpty else { return }
        // `isThinking` is the state *while* this text was produced.
        output.append(isThinking ? .thinking(text) : .content(text))
    }

    private static func longestSuffix(of text: String, thatPrefixes tag: String) -> Int {
        let maxLength = min(text.count, tag.count - 1)
        guard maxLength > 0 else { return 0 }
        for length in stride(from: maxLength, through: 1, by: -1)
        where tag.hasPrefix(text.suffix(length)) {
            return length
        }
        return 0
    }
}
