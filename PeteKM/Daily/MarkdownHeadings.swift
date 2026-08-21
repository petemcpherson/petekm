import Foundation

struct MarkdownHeading: Equatable {
    let level: Int
    let title: String

    var line: String { String(repeating: "#", count: level) + " " + title }
}

/// ATX heading extraction. Fenced code blocks are ignored so a `# comment` inside a
/// shell snippet never becomes a carried-forward heading.
enum MarkdownHeadings {

    static func headings(in text: String) -> [MarkdownHeading] {
        var result: [MarkdownHeading] = []
        var fence: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                if line.hasPrefix(open) { fence = nil }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                fence = String(line.prefix(3))
                continue
            }
            guard line.hasPrefix("#") else { continue }

            let hashes = line.prefix { $0 == "#" }
            guard hashes.count <= 6 else { continue }

            let rest = line.dropFirst(hashes.count)
            guard rest.first == " " || rest.isEmpty else { continue }

            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            result.append(MarkdownHeading(level: hashes.count, title: title))
        }

        return result
    }

    /// Headings carried into a new day: the previous day's own H1 date heading is dropped —
    /// today's H1 replaces it (§7.4). Body text is never carried.
    static func carryForward(from text: String) -> [MarkdownHeading] {
        var headings = headings(in: text)
        if headings.first?.level == 1 {
            headings.removeFirst()
        }
        return headings
    }
}
