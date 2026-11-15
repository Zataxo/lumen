import Foundation

nonisolated enum URLNormalizer {
    /// Turns what the user typed into a usable base URL.
    /// `192.168.1.5:11434` → `http://192.168.1.5:11434`; trailing slashes are removed.
    static func normalizedBaseURL(from input: String) -> URL? {
        var text = asciiDigits(input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    /// Arabic-Indic (٠-٩) and Persian (۰-۹) digits → ASCII, so an IP or port typed on an
    /// Arabic or Persian keyboard still works. Other characters are left alone.
    static func asciiDigits(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x0660...0x0669: Unicode.Scalar(scalar.value - 0x0660 + 0x30)!
            case 0x06F0...0x06F9: Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!
            default: scalar
            }
        }))
    }

    /// True for hosts that only resolve on the local network (used to explain
    /// iOS Local Network permission errors).
    static func isLocalNetworkHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || !host.contains(".") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true // CGNAT range used by Tailscale
        default: return false
        }
    }
}
