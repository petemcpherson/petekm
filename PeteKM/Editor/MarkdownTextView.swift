import AppKit

/// NSTextView with the Markdown capture conveniences from §9.3. All text logic lives in
/// `EditorEdits`; this class only translates it into undoable text-view edits.
final class MarkdownTextView: NSTextView {

    var autoClosePairs = true
    var continueListMarkers = true

    // MARK: - Auto-close

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string

        guard autoClosePairs,
              let typed, typed.count == 1,
              let character = typed.first
        else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let selection = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        let action = EditorEdits.autoClose(typing: character,
                                           nextCharacter: characterAt(selection.upperBound),
                                           hasSelection: selection.length > 0)

        switch action {
        case .none:
            super.insertText(string, replacementRange: replacementRange)

        case .skipOver:
            setSelectedRange(NSRange(location: selection.upperBound + 1, length: 0))

        case let .insertPair(open, close):
            replace(selection,
                    with: "\(open)\(close)",
                    selecting: NSRange(location: selection.location + 1, length: 0))

        case let .wrapSelection(open, close):
            let inner = (self.string as NSString).substring(with: selection)
            replace(selection,
                    with: "\(open)\(inner)\(close)",
                    selecting: NSRange(location: selection.location + 1, length: selection.length))
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let selection = selectedRange()
        guard autoClosePairs,
              selection.length == 0,
              selection.location > 0,
              EditorEdits.deletesPair(previousCharacter: characterAt(selection.location - 1),
                                      nextCharacter: characterAt(selection.location))
        else {
            super.deleteBackward(sender)
            return
        }

        replace(NSRange(location: selection.location - 1, length: 2),
                with: "",
                selecting: NSRange(location: selection.location - 1, length: 0))
    }

    // MARK: - Return

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard continueListMarkers else {
            super.insertNewline(sender)
            return
        }

        let ns = string as NSString
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let prefix = ns.substring(with: NSRange(location: lineStart, length: selection.location - lineStart))
        let edit = EditorEdits.newline(after: prefix)

        guard edit.deleteBackward > 0 || edit.insert != "\n" else {
            super.insertNewline(sender)
            return
        }

        let deleted = (String(prefix.suffix(edit.deleteBackward)) as NSString).length
        let range = NSRange(location: selection.location - deleted, length: selection.length + deleted)
        replace(range,
                with: edit.insert,
                selecting: NSRange(location: range.location + (edit.insert as NSString).length, length: 0))
    }

    // MARK: - Tab / Shift-Tab

    override func insertTab(_ sender: Any?) {
        guard continueListMarkers, shouldReindent() else {
            super.insertTab(sender)
            return
        }
        reindent(EditorEdits.indent)
    }

    override func insertBacktab(_ sender: Any?) {
        guard continueListMarkers, shouldReindent() else {
            super.insertBacktab(sender)
            return
        }
        reindent(EditorEdits.outdent)
    }

    /// Tab keeps its ordinary meaning outside lists and outside multi-line selections.
    private func shouldReindent() -> Bool {
        let selection = selectedRange()
        if selection.length > 0 { return true }
        let ns = string as NSString
        let line = ns.substring(with: ns.lineRange(for: selection))
        return EditorEdits.listMarker(in: line) != nil
    }

    private func reindent(_ transform: @escaping (String) -> String) {
        let selection = selectedRange()
        let ns = string as NSString
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)

        var rebuilt = ""
        var firstLineDelta = 0
        var isFirst = true
        (block as NSString).enumerateSubstrings(in: NSRange(location: 0, length: (block as NSString).length),
                                                options: [.byLines, .substringNotRequired]) { _, sub, enclosing, _ in
            let text = (block as NSString).substring(with: sub)
            let terminator = (block as NSString).substring(with: enclosing).dropFirst(text.count)
            let updated = text.isEmpty ? text : transform(text)
            if isFirst {
                firstLineDelta = (updated as NSString).length - (text as NSString).length
                isFirst = false
            }
            rebuilt += updated + terminator
        }

        guard rebuilt != block else { return }

        let delta = (rebuilt as NSString).length - lineRange.length
        let newSelection = selection.length > 0
            ? NSRange(location: lineRange.location, length: lineRange.length + delta)
            : NSRange(location: max(lineRange.location, selection.location + firstLineDelta), length: 0)

        replace(lineRange, with: rebuilt, selecting: newSelection)
    }

    // MARK: - Helpers

    private func characterAt(_ location: Int) -> Character? {
        let ns = string as NSString
        guard location >= 0, location < ns.length else { return nil }
        return ns.substring(with: NSRange(location: location, length: 1)).first
    }

    /// Undoable, delegate-notifying replacement.
    private func replace(_ range: NSRange, with text: String, selecting: NSRange?) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if let selecting {
            setSelectedRange(selecting)
        }
    }
}
