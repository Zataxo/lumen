import Foundation

/// Incrementally splits a byte stream into lines. Network chunks can end anywhere —
/// mid-line or even mid-way through a multi-byte UTF-8 character — so bytes are only decoded
/// once a full `\n`-terminated line is available. A trailing `\r` is stripped (CRLF streams).
nonisolated struct LineSplitter: Sendable {
    private var buffer: [UInt8] = []

    init() {
        buffer.reserveCapacity(4096)
    }

    /// Feeds one byte; returns a completed line when `byte` is a newline.
    @inline(__always)
    mutating func append(_ byte: UInt8) -> String? {
        guard byte == 0x0A else {
            buffer.append(byte)
            return nil
        }
        return takeLine()
    }

    /// Feeds a chunk; returns every line it completed, in order.
    mutating func feed(_ bytes: some Sequence<UInt8>) -> [String] {
        var lines: [String] = []
        for byte in bytes {
            if let line = append(byte) { lines.append(line) }
        }
        return lines
    }

    mutating func feed(_ text: String) -> [String] { feed(Array(text.utf8)) }

    /// Returns any unterminated final line once the stream ends.
    mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func takeLine() -> String {
        if buffer.last == 0x0D { buffer.removeLast() }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}
