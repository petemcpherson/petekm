import Foundation

struct MarkdownHeading: Equatable {
    let level: Int
    let title: String

    var line: String { String(repeating: "#", count: level) + " " + title }
}

/// ATX heading extraction for the carry-forward flow. Scanning lives in `MarkdownOutline`
/// so the table of contents and carry-forward always agree on what a heading is.
enum MarkdownHeadings {

    static func headings(in text: String) -> [MarkdownHeading] {
        MarkdownOutline.entries(in: text).map { MarkdownHeading(level: $0.level, title: $0.title) }
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
