import Foundation

/// Pure text-editing logic behind the editor niceties (§9.3). Kept free of AppKit so it is testable.
enum EditorEdits {

    static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"
    ]

    static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`"]

    /// Two spaces per nesting level — matches what the highlighter reads back.
    static let indentUnit = "  "

    // MARK: - Auto-close

    enum AutoClose: Equatable {
        /// Move past the closing character the user already has.
        case skipOver
        /// Surround the selection with the pair.
        case wrapSelection(open: Character, close: Character)
        /// Insert both characters, leaving the caret between them.
        case insertPair(open: Character, close: Character)
        /// Ordinary typing.
        case none
    }

    static func autoClose(typing character: Character, nextCharacter: Character?, hasSelection: Bool) -> AutoClose {
        if let close = pairs[character] {
            if hasSelection { return .wrapSelection(open: character, close: close) }
            // Quotes mid-word are apostrophes and contractions, not pairs.
            if isQuote(character), let next = nextCharacter, next.isLetter || next.isNumber {
                return .none
            }
            if closers.contains(character), nextCharacter == character { return .skipOver }
            return .insertPair(open: character, close: close)
        }

        if closers.contains(character), !hasSelection, nextCharacter == character { return .skipOver }
        return .none
    }

    /// Backspace between a freshly typed pair removes both characters.
    static func deletesPair(previousCharacter: Character?, nextCharacter: Character?) -> Bool {
        guard let previous = previousCharacter, let next = nextCharacter else { return false }
        return pairs[previous] == next
    }

    private static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "'" || character == "`"
    }

    // MARK: - List markers

    struct ListMarker: Equatable {
        let indent: String
        let marker: String
        let spacing: String
        /// Everything after the marker on that line.
        let content: String

        var prefixLength: Int { indent.count + marker.count + spacing.count }

        /// `- ` stays `- `; `3. ` becomes `4. `.
        var next: String {
            guard let number = Int(marker.dropLast()) else { return indent + marker + spacing }
            return indent + "\(number + 1)" + String(marker.suffix(1)) + spacing
        }
    }

    static func listMarker(in line: String) -> ListMarker? {
        let ns = line as NSString
        let regex = try? NSRegularExpression(pattern: MarkdownSyntaxHighlighter.listPattern,
                                             options: [.anchorsMatchLines])
        guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ListMarker(indent: ns.substring(with: match.range(at: 1)),
                          marker: ns.substring(with: match.range(at: 2)),
                          spacing: ns.substring(with: match.range(at: 3)),
                          content: ns.substring(from: match.range.upperBound))
    }

    // MARK: - Return key

    struct NewlineEdit: Equatable {
        /// Characters to remove before the caret first (used to clear an empty list marker).
        var deleteBackward: Int = 0
        var insert: String
    }

    /// `line` is the text from the start of the current line up to the caret.
    static func newline(after line: String) -> NewlineEdit {
        if let marker = listMarker(in: line) {
            // Return on an empty list item ends the list instead of adding another bullet.
            if marker.content.trimmingCharacters(in: .whitespaces).isEmpty,
               line.count == marker.prefixLength + marker.content.count {
                return NewlineEdit(deleteBackward: line.count, insert: "\n")
            }
            return NewlineEdit(insert: "\n" + marker.next)
        }
        return NewlineEdit(insert: "\n" + leadingWhitespace(of: line))
    }

    static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    // MARK: - Tab / Shift-Tab

    static func indent(_ line: String) -> String { indentUnit + line }

    static func outdent(_ line: String) -> String {
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        var result = line
        for _ in 0..<indentUnit.count where result.hasPrefix(" ") {
            result.removeFirst()
        }
        return result
    }
}
