/// Splits text into tokens for the word-level diff: identifier runs
/// (letters, digits, underscore), whitespace runs, and every other
/// character on its own. Joining the tokens reproduces the input.
enum Tokenizer {
    static func tokens(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var currentClass: Character.Class?

        for ch in text {
            let cls = ch.tokenClass
            if cls == .other {
                if !current.isEmpty { out.append(current); current = "" }
                out.append(String(ch))
                currentClass = nil
                continue
            }
            if cls == currentClass {
                current.append(ch)
            } else {
                if !current.isEmpty { out.append(current) }
                current = String(ch)
                currentClass = cls
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

private extension Character {
    enum Class { case word, space, other }
    var tokenClass: Class {
        if isWhitespace || isNewline { return .space }
        if isLetter || isNumber || self == "_" { return .word }
        return .other
    }
}
