import Foundation

// Syntax colouring for the columns (issue #9). A small hand-written
// scanner per language family, no grammar files and no dependency
// (DECISIONS.md D1, D9). It classifies, it does not parse: a wrong
// colour costs nothing, a slow one costs scrolling (spec "Scrolling":
// syntax colour may lag a frame, diff colour may not).

public enum TokenKind: String, Sendable, Hashable, CaseIterable {
    case keyword, type, string, number, comment, function, attribute, constant, key, heading
}

/// A run of one kind inside a line, in UTF-16 offsets (what
/// NSAttributedString wants).
public struct Token: Sendable, Hashable {
    public var kind: TokenKind
    public var range: Range<Int>

    public init(_ kind: TokenKind, _ range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// What is still open at the end of a line: a block comment or a
/// string that spans lines.
public enum ScanState: Sendable, Hashable {
    case normal
    case blockComment(close: String)
    case string(close: String)
}

public enum Language: String, Sendable, Hashable, CaseIterable {
    case go, rust, python, swift, zig, javascript, c, shell, yaml, toml, json, markdown, css, plain

    /// By file extension (or name, for a few extension-less files).
    public static func forPath(_ path: String) -> Language {
        let name = (path as NSString).lastPathComponent.lowercased()
        if ["makefile", "dockerfile"].contains(name) { return .shell }
        switch (name as NSString).pathExtension {
        case "go": return .go
        case "rs": return .rust
        case "py", "pyi": return .python
        case "swift": return .swift
        case "zig": return .zig
        case "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "java", "kt", "kts", "scala", "dart", "cs": return .javascript
        case "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "m", "mm": return .c
        case "sh", "bash", "zsh", "fish", "mk": return .shell
        case "yml", "yaml": return .yaml
        case "toml", "ini", "cfg": return .toml
        case "json", "jsonc": return .json
        case "md", "markdown": return .markdown
        case "css", "scss", "less": return .css
        default: return .plain
        }
    }
}

public enum SyntaxHighlighter {

    /// Tokens of one line. `state` carries an open block comment or
    /// string into the next line.
    public static func tokens(_ line: String, language: Language, state: inout ScanState) -> [Token] {
        guard language != .plain else { return [] }
        let u = Array(line.utf16)
        let spec = Spec.for(language)
        var out: [Token] = []
        var i = 0
        var declares = false   // the last word was fn / func / def / function

        // Finish whatever the previous line left open.
        switch state {
        case .normal: break
        case .blockComment(let close):
            if let end = find(close, in: u, from: 0) {
                out.append(Token(.comment, 0..<end + close.utf16.count)); i = end + close.utf16.count; state = .normal
            } else {
                return u.isEmpty ? [] : [Token(.comment, 0..<u.count)]
            }
        case .string(let close):
            if let end = findStringEnd(close, in: u, from: 0, escapes: true) {
                out.append(Token(.string, 0..<end)); i = end; state = .normal
            } else {
                return u.isEmpty ? [] : [Token(.string, 0..<u.count)]
            }
        }

        switch language {
        case .markdown: return out + markdown(u, from: i)
        case .yaml, .toml:
            let after = lineKey(u, language: language, into: &out, from: i)
            if after == u.count { return out }
            i = after
        default: break
        }

        while i < u.count {
            let c = u[i]
            if c == lparen { declares = false }   // Go: func (s *T) Name(
            // Comments.
            if let block = spec.blockComment, starts(block.open, in: u, at: i) {
                let from = i + block.open.utf16.count
                if let end = find(block.close, in: u, from: from) {
                    out.append(Token(.comment, i..<end + block.close.utf16.count)); i = end + block.close.utf16.count; continue
                }
                out.append(Token(.comment, i..<u.count)); state = .blockComment(close: block.close); return out
            }
            if spec.lineComments.contains(where: { starts($0, in: u, at: i) }) && commentAllowed(u, at: i, language: language) {
                out.append(Token(.comment, i..<u.count)); return out
            }
            // Strings: multi-line openers first, then single ones.
            if let open = spec.multilineStrings.first(where: { starts($0.open, in: u, at: i) }) {
                let from = i + open.open.utf16.count
                if let end = findStringEnd(open.close, in: u, from: from, escapes: open.escapes) {
                    out.append(Token(.string, i..<end)); i = end; continue
                }
                out.append(Token(.string, i..<u.count)); state = .string(close: open.close); return out
            }
            if spec.quotes.contains(c) {
                if c == q1, language == .rust, isLifetime(u, at: i) {   // 'a is a lifetime, not a char
                    let end = scanIdentifier(u, from: i + 1)
                    out.append(Token(.type, i..<end)); i = end; continue
                }
                let end = findStringEnd(String(utf16CodeUnits: [c], count: 1), in: u, from: i + 1, escapes: true) ?? u.count
                let kind: TokenKind = (language == .json || language == .css) && nextNonSpace(u, from: end) == colon ? .key : .string
                out.append(Token(kind, i..<end)); i = end; continue
            }
            // Attributes: @name, Rust #[...].
            if c == at, spec.atAttributes, i + 1 < u.count, isIdentStart(u[i + 1]) {
                let end = scanIdentifier(u, from: i + 1)
                out.append(Token(.attribute, i..<end)); i = end; continue
            }
            if language == .rust, c == hash, i + 1 < u.count, u[i + 1] == lbracket || (u[i + 1] == bang && i + 2 < u.count && u[i + 2] == lbracket) {
                let end = (u[i...].firstIndex(of: rbracket) ?? (u.count - 1)) + 1
                out.append(Token(.attribute, i..<end)); i = end; continue
            }
            // C preprocessor directives: #include, #define, …
            if c == hash, language == .c, previousNonSpace(u, before: i) == nil, i + 1 < u.count, isIdentStart(u[i + 1]) {
                let end = scanIdentifier(u, from: i + 1)
                out.append(Token(.keyword, i..<end)); i = end; continue
            }
            // Shell and Makefile variables.
            if c == dollar, language == .shell, i + 1 < u.count {
                var end = i + 1
                if u[end] == lbrace { end = (u[end...].firstIndex(of: rbrace) ?? (u.count - 1)) + 1 } else { end = scanIdentifier(u, from: end) }
                if end > i + 1 { out.append(Token(.constant, i..<end)); i = end; continue }
            }
            // CSS colours.
            if c == hash, language == .css, i + 1 < u.count, isHex(u[i + 1]) {
                var end = i + 1
                while end < u.count, isHex(u[end]) { end += 1 }
                out.append(Token(.number, i..<end)); i = end; continue
            }
            // Numbers.
            if isDigit(c) || (c == dot && i + 1 < u.count && isDigit(u[i + 1])), i == 0 || !isIdentPart(u[i - 1]) {
                var end = i + 1
                while end < u.count, isIdentPart(u[end]) || u[end] == dot || ((u[end] == plus || u[end] == minus) && (u[end - 1] == e || u[end - 1] == E) && !isHexLiteral(u, from: i)) {
                    if u[end] == dot, end + 1 < u.count, u[end + 1] == dot { break }   // 0..<n
                    end += 1
                }
                if language == .css, end < u.count, u[end] == percent { end += 1 }
                out.append(Token(.number, i..<end)); i = end; continue
            }
            // Identifiers: keyword, constant, type, function, CSS property.
            if isIdentStart(c) || (language == .css && c == minus && i + 1 < u.count && isIdentStart(u[i + 1])) {
                var end = scanIdentifier(u, from: i + 1)
                if language == .css { while end < u.count, u[end] == minus || isIdentPart(u[end]) { end += 1 } }
                if language == .rust, end < u.count, u[end] == bang { end += 1 }   // macro!
                let word = String(utf16CodeUnits: Array(u[i..<end]), count: end - i)
                let previous = previousNonSpace(u, before: i)
                let declared = declares
                declares = ["fn", "func", "def", "function"].contains(word)
                if spec.constants.contains(word) {
                    out.append(Token(.constant, i..<end))
                } else if spec.keywords.contains(word) {
                    out.append(Token(.keyword, i..<end))
                } else if declared, language != .css {
                    out.append(Token(.function, i..<end))
                } else if language == .css {
                    if nextNonSpace(u, from: end) == colon, previous != colon { out.append(Token(.key, i..<end)) }
                } else if spec.types.contains(word) || (spec.capitalizedTypes && isUpper(c) && previous != dot) {
                    out.append(Token(nextNonSpace(u, from: end) == lparen && !spec.capitalizedTypes ? .function : .type, i..<end))
                } else if nextNonSpace(u, from: end) == lparen || word.hasSuffix("!") {
                    out.append(Token(.function, i..<end))
                } else if language == .json, nextNonSpace(u, from: end) == colon {
                    out.append(Token(.key, i..<end))
                }
                i = end; continue
            }
            i += 1
        }
        return out
    }

    /// Tokens for every line of a text, carrying state across lines.
    public static func tokens(lines: [String], language: Language) -> [[Token]] {
        var state = ScanState.normal
        return lines.map { tokens($0, language: language, state: &state) }
    }

    // MARK: - Line-shaped languages

    /// YAML `key:` and TOML `key =` / `[section]` at the start of a line.
    /// Returns where the rest of the line should be scanned from.
    @discardableResult
    static func lineKey(_ u: [UInt16], language: Language, into out: inout [Token], from start: Int) -> Int {
        var i = start
        while i < u.count, u[i] == space || u[i] == tab || (language == .yaml && u[i] == minus && i + 1 < u.count && u[i + 1] == space) { i += 1 }
        guard i < u.count else { return start }
        if language == .toml, u[i] == lbracket {
            let end = (u[i...].firstIndex(of: rbracket) ?? (u.count - 1)) + 1
            out.append(Token(.heading, i..<end)); return end
        }
        var end = i
        while end < u.count, u[end] != colon, u[end] != equals, u[end] != hash, u[end] != quote, u[end] != q1 { end += 1 }
        guard end < u.count, end > i else { return start }
        let separator: UInt16 = language == .yaml ? colon : equals
        guard u[end] == separator else { return start }
        var keyEnd = end
        while keyEnd > i, u[keyEnd - 1] == space { keyEnd -= 1 }
        if language == .yaml, end + 1 < u.count, u[end + 1] != space { return start }   // http://…
        out.append(Token(.key, i..<keyEnd))
        return end + 1
    }

    static func markdown(_ u: [UInt16], from start: Int) -> [Token] {
        var i = start
        while i < u.count, u[i] == space { i += 1 }
        if i < u.count, u[i] == hash { return [Token(.heading, i..<u.count)] }
        if i + 2 < u.count, u[i] == backtick, u[i + 1] == backtick, u[i + 2] == backtick { return [Token(.string, i..<u.count)] }
        var out: [Token] = []
        if i < u.count, u[i] == minus || u[i] == star || u[i] == plus, i + 1 < u.count, u[i + 1] == space { out.append(Token(.keyword, i..<i + 1)) }
        var j = i
        while j < u.count {
            if u[j] == backtick, let close = u[(j + 1)...].firstIndex(of: backtick) {
                out.append(Token(.string, j..<close + 1)); j = close + 1; continue
            }
            if u[j] == lbracket, let close = u[(j + 1)...].firstIndex(of: rbracket), close + 1 < u.count, u[close + 1] == lparen {
                out.append(Token(.function, j..<close + 1)); j = close + 1; continue
            }
            j += 1
        }
        return out
    }

    // MARK: - Scanning helpers

    static func starts(_ s: String, in u: [UInt16], at i: Int) -> Bool {
        let p = Array(s.utf16)
        guard i + p.count <= u.count else { return false }
        for k in 0..<p.count where u[i + k] != p[k] { return false }
        return true
    }

    static func find(_ s: String, in u: [UInt16], from: Int) -> Int? {
        var i = from
        while i < u.count { if starts(s, in: u, at: i) { return i }; i += 1 }
        return nil
    }

    /// Index just past the closing delimiter, honouring backslash escapes.
    static func findStringEnd(_ close: String, in u: [UInt16], from: Int, escapes: Bool) -> Int? {
        var i = from
        let n = close.utf16.count
        while i < u.count {
            if escapes, u[i] == backslash { i += 2; continue }
            if starts(close, in: u, at: i) { return i + n }
            i += 1
        }
        return nil
    }

    /// `#` starts a comment in shell only at a word boundary (`$#`, `a#b`).
    static func commentAllowed(_ u: [UInt16], at i: Int, language: Language) -> Bool {
        guard language == .shell, u[i] == hash else { return true }
        return i == 0 || u[i - 1] == space || u[i - 1] == tab
    }

    static func isLifetime(_ u: [UInt16], at i: Int) -> Bool {
        guard i + 1 < u.count, isIdentStart(u[i + 1]) else { return false }
        let end = scanIdentifier(u, from: i + 1)
        return end >= u.count || u[end] != q1
    }

    static func isHexLiteral(_ u: [UInt16], from i: Int) -> Bool {
        i + 1 < u.count && u[i] == zero && (u[i + 1] == x || u[i + 1] == X)
    }

    static func scanIdentifier(_ u: [UInt16], from: Int) -> Int {
        var i = from
        while i < u.count, isIdentPart(u[i]) { i += 1 }
        return i
    }

    static func nextNonSpace(_ u: [UInt16], from: Int) -> UInt16? {
        var i = from
        while i < u.count, u[i] == space || u[i] == tab { i += 1 }
        return i < u.count ? u[i] : nil
    }

    static func previousNonSpace(_ u: [UInt16], before: Int) -> UInt16? {
        var i = before - 1
        while i >= 0, u[i] == space || u[i] == tab { i -= 1 }
        return i >= 0 ? u[i] : nil
    }

    static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    static func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) }
    static func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127 }
    static func isIdentPart(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }

    static let space: UInt16 = 32, tab: UInt16 = 9, quote: UInt16 = 34, q1: UInt16 = 39, backtick: UInt16 = 96
    static let hash: UInt16 = 35, dollar: UInt16 = 36, percent: UInt16 = 37, lparen: UInt16 = 40, star: UInt16 = 42
    static let plus: UInt16 = 43, minus: UInt16 = 45, dot: UInt16 = 46, zero: UInt16 = 48, colon: UInt16 = 58
    static let equals: UInt16 = 61, at: UInt16 = 64, E: UInt16 = 69, X: UInt16 = 88, lbracket: UInt16 = 91
    static let backslash: UInt16 = 92, rbracket: UInt16 = 93, e: UInt16 = 101, x: UInt16 = 120, lbrace: UInt16 = 123
    static let rbrace: UInt16 = 125, bang: UInt16 = 33
}

/// Per-language word lists and delimiters.
struct Spec {
    struct Multiline { var open: String; var close: String; var escapes: Bool }

    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = []
    var lineComments: [String] = []
    var blockComment: (open: String, close: String)?
    var quotes: Set<UInt16> = [SyntaxHighlighter.quote]
    var multilineStrings: [Multiline] = []
    var atAttributes = false
    /// Capitalized identifiers are types (Go exported names are not, so Go is off).
    var capitalizedTypes = false

    static func `for`(_ language: Language) -> Spec {
        let cBlock = (open: "/*", close: "*/")
        let q = SyntaxHighlighter.quote, q1 = SyntaxHighlighter.q1, bt = SyntaxHighlighter.backtick
        switch language {
        case .go:
            return Spec(keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"],
                        types: ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "any"],
                        constants: ["true", "false", "nil", "iota"],
                        lineComments: ["//"], blockComment: cBlock, quotes: [q, q1],
                        multilineStrings: [Multiline(open: "`", close: "`", escapes: false)])
        case .rust:
            return Spec(keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "static", "struct", "super", "trait", "type", "unsafe", "use", "where", "while", "Self", "self"],
                        types: ["bool", "char", "str", "u8", "u16", "u32", "u64", "u128", "usize", "i8", "i16", "i32", "i64", "i128", "isize", "f32", "f64"],
                        constants: ["true", "false", "None", "Some", "Ok", "Err"],
                        lineComments: ["//"], blockComment: cBlock, quotes: [q, q1],
                        multilineStrings: [Multiline(open: "r#\"", close: "\"#", escapes: false)], capitalizedTypes: true)
        case .python:
            return Spec(keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case", "self"],
                        types: ["int", "float", "str", "bytes", "bool", "list", "dict", "set", "tuple", "object", "type"],
                        constants: ["True", "False", "None"],
                        lineComments: ["#"], quotes: [q, q1],
                        multilineStrings: [Multiline(open: "\"\"\"", close: "\"\"\"", escapes: true), Multiline(open: "'''", close: "'''", escapes: true)],
                        atAttributes: true, capitalizedTypes: true)
        case .swift:
            return Spec(keywords: ["actor", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nonisolated", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "some", "any", "static", "struct", "subscript", "switch", "throw", "throws", "try", "typealias", "var", "where", "while", "self", "Self", "super", "fileprivate", "final", "lazy", "mutating", "override", "weak"],
                        constants: ["true", "false", "nil"],
                        lineComments: ["//"], blockComment: cBlock,
                        multilineStrings: [Multiline(open: "\"\"\"", close: "\"\"\"", escapes: true)],
                        atAttributes: true, capitalizedTypes: true)
        case .zig:
            return Spec(keywords: ["addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm", "async", "await", "break", "callconv", "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export", "extern", "fn", "for", "if", "inline", "noalias", "nosuspend", "opaque", "or", "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch", "test", "threadlocal", "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while"],
                        types: ["u8", "u16", "u32", "u64", "usize", "i8", "i16", "i32", "i64", "isize", "f32", "f64", "bool", "void", "type", "anyerror", "noreturn"],
                        constants: ["true", "false", "null", "undefined"],
                        lineComments: ["//"], quotes: [q, q1], atAttributes: true, capitalizedTypes: true)
        case .javascript:
            return Spec(keywords: ["abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "of", "package", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "try", "type", "typeof", "var", "void", "while", "with", "yield", "keyof", "namespace", "fun", "val", "override"],
                        types: ["string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint", "int", "long", "double", "float", "char", "byte", "short", "void"],
                        constants: ["true", "false", "null", "undefined", "NaN", "Infinity"],
                        lineComments: ["//"], blockComment: cBlock, quotes: [q, q1],
                        multilineStrings: [Multiline(open: "`", close: "`", escapes: true)],
                        atAttributes: true, capitalizedTypes: true)
        case .c:
            return Spec(keywords: ["auto", "break", "case", "catch", "class", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "explicit", "extern", "for", "friend", "goto", "if", "inline", "namespace", "new", "operator", "private", "protected", "public", "register", "return", "sizeof", "static", "struct", "switch", "template", "this", "throw", "try", "typedef", "typename", "union", "using", "virtual", "volatile", "while"],
                        types: ["bool", "char", "double", "float", "int", "long", "short", "signed", "unsigned", "void", "size_t", "int8_t", "int16_t", "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "std", "string", "vector"],
                        constants: ["true", "false", "NULL", "nullptr"],
                        lineComments: ["//"], blockComment: cBlock, quotes: [q, q1], atAttributes: true, capitalizedTypes: true)
        case .shell:
            return Spec(keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "return", "local", "export", "set", "unset", "echo", "exit", "cd", "test", "source", "readonly", "shift"],
                        constants: ["true", "false"],
                        lineComments: ["#"], quotes: [q, q1])
        case .yaml, .toml:
            return Spec(constants: ["true", "false", "null", "yes", "no", "on", "off", "~"],
                        lineComments: ["#"], quotes: [q, q1],
                        multilineStrings: language == .toml ? [Multiline(open: "\"\"\"", close: "\"\"\"", escapes: true)] : [])
        case .json:
            return Spec(constants: ["true", "false", "null"], lineComments: ["//"], blockComment: cBlock)
        case .css:
            return Spec(keywords: ["@media", "@import", "@keyframes", "@font-face", "!important"],
                        lineComments: [], blockComment: cBlock, quotes: [q, q1], atAttributes: true)
        case .markdown, .plain:
            return Spec(quotes: [bt])
        }
    }
}
