import Foundation
import SwiftUI

/// A small, fast, regex-free syntax highlighter: comments, strings, numbers, keywords,
/// types and decorators for ~20 common languages. Good enough for chat answers, and cheap
/// enough to re-run on every streaming flush.
nonisolated enum SyntaxHighlighter {
    enum TokenKind: Hashable, Sendable {
        case keyword, string, comment, number, type, attribute, plain
    }

    struct Token: Hashable, Sendable {
        var kind: TokenKind
        /// Character (grapheme) offsets into the source.
        var range: Range<Int>
    }

    private struct LanguageSpec {
        var keywords: Set<String>
        var lineComments: [String]
        var blockComment: (open: String, close: String)?
        var hashComments = false
        var stringQuotes: Set<Character> = ["\"", "'"]
        var backtickStrings = false
        var decoratorPrefix: Character?
        var capitalizedAreTypes = true
    }

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var attributed = AttributedString(code)
        guard let spec = spec(for: language), code.utf8.count < 200_000 else { return attributed }
        let characters = Array(code)
        var index = attributed.startIndex
        var characterOffset = 0

        // Walk tokens in order, advancing an AttributedString index in step.
        for token in tokenize(characters, spec: spec) where token.kind != .plain {
            let startOffset = token.range.lowerBound - characterOffset
            let start = attributed.characters.index(index, offsetBy: startOffset)
            let end = attributed.characters.index(start, offsetBy: token.range.count)
            attributed[start..<end].foregroundColor = color(for: token.kind)
            index = end
            characterOffset = token.range.upperBound
        }
        return attributed
    }

    static func tokenize(_ code: String, language: String?) -> [Token] {
        guard let spec = spec(for: language) else { return [] }
        return tokenize(Array(code), spec: spec)
    }

    // MARK: Tokenizer

    private static func tokenize(_ chars: [Character], spec: LanguageSpec) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        let count = chars.count

        func matches(_ literal: String, at position: Int) -> Bool {
            var p = position
            for c in literal {
                guard p < count, chars[p] == c else { return false }
                p += 1
            }
            return true
        }

        while i < count {
            let c = chars[i]

            // Line comments
            if let marker = spec.lineComments.first(where: { matches($0, at: i) }) ?? (spec.hashComments && c == "#" ? "#" : nil) {
                _ = marker
                let start = i
                while i < count, chars[i] != "\n" { i += 1 }
                tokens.append(Token(kind: .comment, range: start..<i))
                continue
            }
            // Block comments
            if let block = spec.blockComment, matches(block.open, at: i) {
                let start = i
                i += block.open.count
                while i < count, !matches(block.close, at: i) { i += 1 }
                i = min(count, i + block.close.count)
                tokens.append(Token(kind: .comment, range: start..<i))
                continue
            }
            // Strings
            if spec.stringQuotes.contains(c) || (spec.backtickStrings && c == "`") {
                let start = i
                // Triple-quoted strings (Python, Swift)
                let triple = String(repeating: c, count: 3)
                if matches(triple, at: i) {
                    i += 3
                    while i < count, !matches(triple, at: i) { i += chars[i] == "\\" ? 2 : 1 }
                    i = min(count, i + 3)
                } else {
                    i += 1
                    while i < count, chars[i] != c, chars[i] != "\n" || c == "`" {
                        i += chars[i] == "\\" ? 2 : 1
                    }
                    i = min(count, i + 1)
                }
                tokens.append(Token(kind: .string, range: start..<i))
                continue
            }
            // Numbers
            if c.isNumber, i == 0 || !isIdentifierCharacter(chars[i - 1]) {
                let start = i
                while i < count, chars[i].isHexDigit || chars[i] == "." || chars[i] == "_" || chars[i] == "x" || chars[i] == "X" {
                    i += 1
                }
                tokens.append(Token(kind: .number, range: start..<i))
                continue
            }
            // Decorators / attributes (@main, @Observable, @decorator)
            if let prefix = spec.decoratorPrefix, c == prefix, i + 1 < count, chars[i + 1].isLetter {
                let start = i
                i += 1
                while i < count, isIdentifierCharacter(chars[i]) { i += 1 }
                tokens.append(Token(kind: .attribute, range: start..<i))
                continue
            }
            // Identifiers / keywords / types
            if c.isLetter || c == "_" || c == "$" {
                let start = i
                while i < count, isIdentifierCharacter(chars[i]) || chars[i] == "$" { i += 1 }
                let word = String(chars[start..<i])
                if spec.keywords.contains(word) {
                    tokens.append(Token(kind: .keyword, range: start..<i))
                } else if spec.capitalizedAreTypes, let first = word.first, first.isUppercase, word.count > 1 {
                    tokens.append(Token(kind: .type, range: start..<i))
                }
                continue
            }
            i += 1
        }
        return tokens
    }

    private static func isIdentifierCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    // MARK: Colors (Xcode-like, tuned for both appearances)

    private static func color(for kind: TokenKind) -> Color {
        switch kind {
        case .keyword: .dynamic(light: (0.61, 0.14, 0.58), dark: (0.99, 0.37, 0.64))
        case .string: .dynamic(light: (0.77, 0.10, 0.09), dark: (0.99, 0.42, 0.36))
        case .comment: .dynamic(light: (0.42, 0.47, 0.51), dark: (0.50, 0.55, 0.60))
        case .number: .dynamic(light: (0.11, 0.00, 0.81), dark: (0.82, 0.75, 0.41))
        case .type: .dynamic(light: (0.04, 0.37, 0.43), dark: (0.36, 0.85, 0.89))
        case .attribute: .dynamic(light: (0.51, 0.27, 0.0), dark: (0.99, 0.63, 0.31))
        case .plain: .primary
        }
    }

    // MARK: Languages

    private static func spec(for language: String?) -> LanguageSpec? {
        guard let language else { return nil }
        let c = ["//"]
        let cBlock = (open: "/*", close: "*/")
        switch language {
        case "swift":
            return LanguageSpec(keywords: words("""
                actor any as associatedtype async await break case catch class continue default defer do else enum extension \
                fallthrough false fileprivate final for func guard if import in init inout internal is let lazy mutating nil \
                nonisolated open operator override private protocol public repeat rethrows return self Self some static struct \
                subscript super switch throw throws true try typealias var weak where while consuming borrowing sending
                """), lineComments: c, blockComment: cBlock, stringQuotes: ["\""], decoratorPrefix: "@")
        case "python", "py":
            return LanguageSpec(keywords: words("""
                False None True and as assert async await break class continue def del elif else except finally for from \
                global if import in is lambda nonlocal not or pass raise return try while with yield match case self print
                """), lineComments: [], blockComment: nil, hashComments: true, decoratorPrefix: "@")
        case "javascript", "js", "jsx", "typescript", "ts", "tsx", "mjs":
            return LanguageSpec(keywords: words("""
                abstract any as async await boolean break case catch class const constructor continue debugger declare default \
                delete do else enum export extends false finally for from function get if implements import in instanceof \
                interface keyof let new null number of private protected public readonly return set static string super switch \
                this throw true try type typeof undefined var void while with yield
                """), lineComments: c, blockComment: cBlock, backtickStrings: true, decoratorPrefix: "@")
        case "java", "kotlin", "kt", "scala", "dart":
            return LanguageSpec(keywords: words("""
                abstract as boolean break byte case catch char class const continue data default do double else enum extends \
                false final finally float for fun if implements import in instanceof int interface is long native new null \
                object override package private protected public return short static super switch synchronized this throw \
                throws true try val var void volatile when while
                """), lineComments: c, blockComment: cBlock, decoratorPrefix: "@")
        case "c", "cpp", "c++", "cc", "h", "hpp", "objc", "objective-c", "cs", "csharp", "c#":
            return LanguageSpec(keywords: words("""
                auto bool break case catch char class const constexpr continue default delete do double else enum explicit \
                extern false float for friend goto if inline int long namespace new nullptr operator private protected public \
                return short signed sizeof static struct switch template this throw true try typedef typename union unsigned \
                using virtual void volatile while var string async await foreach in out ref readonly override
                """), lineComments: c, blockComment: cBlock, stringQuotes: ["\"", "'"], decoratorPrefix: "#")
        case "go", "golang":
            return LanguageSpec(keywords: words("""
                break case chan const continue default defer else fallthrough false for func go goto if import interface map \
                nil package range return select struct switch true type var
                """), lineComments: c, blockComment: cBlock, backtickStrings: true)
        case "rust", "rs":
            return LanguageSpec(keywords: words("""
                as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move \
                mut pub ref return self Self static struct super trait true type unsafe use where while
                """), lineComments: c, blockComment: cBlock, stringQuotes: ["\""], decoratorPrefix: "#")
        case "ruby", "rb":
            return LanguageSpec(keywords: words("""
                alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or \
                redo rescue retry return self super then true undef unless until when while yield puts require
                """), lineComments: [], blockComment: nil, hashComments: true)
        case "php":
            return LanguageSpec(keywords: words("""
                abstract and array as break case catch class const continue declare default do echo else elseif empty \
                extends false final for foreach function global if implements include interface isset namespace new null \
                or private protected public require return static switch this throw true try use var while
                """), lineComments: ["//"], blockComment: cBlock, hashComments: true)
        case "bash", "sh", "shell", "zsh", "console":
            return LanguageSpec(keywords: words("""
                if then else elif fi for while do done case esac in function return export local echo exit cd sudo set unset
                """), lineComments: [], blockComment: nil, hashComments: true, capitalizedAreTypes: false)
        case "sql":
            return LanguageSpec(keywords: words("""
                select from where and or not insert into values update set delete create table drop alter index join left \
                right inner outer on group by order having limit offset as distinct null is in like between union all case \
                when then else end primary key foreign references SELECT FROM WHERE AND OR NOT INSERT INTO VALUES UPDATE SET \
                DELETE CREATE TABLE DROP ALTER INDEX JOIN LEFT RIGHT INNER OUTER ON GROUP BY ORDER HAVING LIMIT OFFSET AS \
                DISTINCT NULL IS IN LIKE BETWEEN UNION ALL CASE WHEN THEN ELSE END PRIMARY KEY FOREIGN REFERENCES
                """), lineComments: ["--"], blockComment: cBlock, capitalizedAreTypes: false)
        case "json", "jsonc":
            return LanguageSpec(keywords: ["true", "false", "null"], lineComments: c, blockComment: cBlock, stringQuotes: ["\""], capitalizedAreTypes: false)
        case "yaml", "yml", "toml", "ini", "dockerfile", "makefile", "properties":
            return LanguageSpec(keywords: words("true false null yes no on off FROM RUN CMD COPY ADD ENV WORKDIR EXPOSE ENTRYPOINT ARG"),
                                lineComments: [], blockComment: nil, hashComments: true, capitalizedAreTypes: false)
        case "html", "xml", "svg", "vue":
            return LanguageSpec(keywords: [], lineComments: [], blockComment: (open: "<!--", close: "-->"), capitalizedAreTypes: false)
        case "css", "scss", "less":
            return LanguageSpec(keywords: words("important media import from to"), lineComments: ["//"], blockComment: cBlock, decoratorPrefix: "@", capitalizedAreTypes: false)
        default:
            return nil
        }
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
    }
}

extension Color {
    /// A color that adapts to light / dark appearance (RGB components 0…1).
    nonisolated static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #endif
    }
}
