import Foundation

nonisolated struct SSEEvent: Hashable, Sendable {
    var event: String?
    var data: String
}

/// Server-Sent Events parser (https://html.spec.whatwg.org/multipage/server-sent-events.html).
/// Feed it complete lines (from `LineSplitter`); it returns an event whenever a blank line
/// dispatches one. Multi-line `data:` fields are joined with `\n`; comments are ignored.
nonisolated struct SSEParser: Sendable {
    private var dataLines: [String] = []
    private var eventName: String?

    init() {}

    mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil } // comment / keep-alive

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "data": dataLines.append(String(value))
        case "event": eventName = String(value)
        default: break // `id`, `retry` are irrelevant for chat completions
        }
        return nil
    }

    /// Call when the stream ends; dispatches a final event some servers send without a
    /// trailing blank line.
    mutating func finish() -> SSEEvent? { dispatch() }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            dataLines.removeAll(keepingCapacity: true)
            eventName = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}
