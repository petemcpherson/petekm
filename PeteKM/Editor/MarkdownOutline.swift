import Foundation

/// One ATX heading, with the range of its line in the document (§9.4).
struct MarkdownOutlineEntry: Identifiable, Equatable {
    let id: Int
    let level: Int
    let title: String
    /// Range of the whole heading line, excluding the line terminator.
    let range: NSRange
}

/// Single heading scanner shared by carry-forward (§7.4) and the table of contents (§9.4).
/// Fenced code blocks are skipped so a `# comment` in a shell snippet is never a heading.
enum MarkdownOutline {

    static func entries(in text: String) -> [MarkdownOutlineEntry] {
        let ns = text as NSString
        var result: [MarkdownOutlineEntry] = []
        var fence: String?

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if line.hasPrefix(open) { fence = nil }
                return
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fence = String(line.prefix(3))
                return
            }
            guard let heading = Self.heading(inTrimmedLine: line) else { return }

            result.append(MarkdownOutlineEntry(id: result.count,
                                               level: heading.level,
                                               title: heading.title,
                                               range: lineRange))
        }

        return result
    }

    /// `## Work` → (2, "Work"). Returns nil for non-headings and for empty titles.
    static func heading(inTrimmedLine line: String) -> (level: Int, title: String)? {
        guard line.hasPrefix("#") else { return nil }

        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }

        let rest = line.dropFirst(hashes.count)
        guard rest.first == " " || rest.isEmpty else { return nil }

        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        return (hashes.count, title)
    }
}
