//
//  SearchQuery.swift
//  PeteKM
//
//  Deterministic full-text matching over the index (spec §11.2–§11.5).
//  Literal terms, no stemming, no embeddings — semantic retrieval belongs to the
//  user's own agent in the terminal.
//

import Foundation

/// One match, carrying enough context to know why it matched (§11.3).
struct SearchResult: Identifiable, Equatable {
    let relativePath: String
    let filename: String
    /// Nearest Markdown heading at or above the match, when there is one.
    let heading: String?
    let snippet: String
    /// Long-form date for `daily/YYYY-MM-DD.md` files.
    let dateLabel: String?
    /// Where to put the caret when the result is opened (§11.4).
    let range: NSRange
    let score: Int
    let modified: Date

    var id: String { "\(relativePath)#\(range.location)" }

    /// `library/Work/MFT.md` → `library/Work`; root files have no folder.
    var folderPath: String? {
        let folder = (relativePath as NSString).deletingLastPathComponent
        return folder.isEmpty ? nil : folder
    }
}

enum SearchQuery {

    static let snippetContext = 48

    static func run(_ raw: String,
                    over files: [IndexedFile],
                    calendar: Calendar = .current,
                    limit: Int = 60) -> [SearchResult] {

        let terms = raw
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !terms.isEmpty else { return [] }

        let results = files.compactMap { result(for: $0, terms: terms, calendar: calendar) }

        return results
            .sorted { left, right in
                if left.score != right.score { return left.score > right.score }
                if left.modified != right.modified { return left.modified > right.modified }
                return left.relativePath < right.relativePath
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Per-file matching

    private static func result(for file: IndexedFile, terms: [String], calendar: Calendar) -> SearchResult? {
        let path = file.relativePath.lowercased()
        let name = file.filename.lowercased()
        let text = file.text.lowercased()

        // Every term has to appear somewhere — in the path or in the body (§11.1).
        guard terms.allSatisfy({ text.contains($0) || path.contains($0) }) else { return nil }

        let ns = file.text as NSString
        let anchor = anchorRange(in: ns, terms: terms)

        var score = 0
        if terms.allSatisfy({ name.contains($0) }) { score += 400 }
        else if terms.contains(where: { path.contains($0) }) { score += 150 }
        if anchor != nil { score += 50 }
        if file.relativePath.hasPrefix("daily/") { score += 10 }

        let date = DailyDate.date(fromFilename: file.filename, calendar: calendar)

        return SearchResult(
            relativePath: file.relativePath,
            filename: file.filename,
            heading: heading(in: file.text, before: anchor?.location ?? 0),
            snippet: snippet(in: ns, around: anchor),
            dateLabel: file.relativePath.hasPrefix("daily/") ? date.map { DailyDate.longForm($0, calendar: calendar) } : nil,
            range: anchor ?? NSRange(location: 0, length: 0),
            score: score,
            modified: file.modified
        )
    }

    /// The longest term that actually occurs in the body wins the caret — it is the
    /// most specific thing the user typed.
    private static func anchorRange(in text: NSString, terms: [String]) -> NSRange? {
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            if found.location != NSNotFound { return found }
        }
        return nil
    }

    private static func heading(in text: String, before location: Int) -> String? {
        MarkdownOutline.entries(in: text)
            .last { $0.range.location <= location }?
            .title
    }

    /// A window of the matching line, ellipsised when it is cut on either side.
    private static func snippet(in text: NSString, around match: NSRange?) -> String {
        guard text.length > 0 else { return "" }

        guard let match else {
            return firstMeaningfulLine(in: text)
        }

        let line = text.lineRange(for: NSRange(location: match.location, length: 0))
        let start = max(line.location, match.location - snippetContext)
        let end = min(line.location + line.length, match.location + match.length + snippetContext)
        let window = text.substring(with: NSRange(location: start, length: max(0, end - start)))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let leading = start > line.location ? "…" : ""
        let trailing = end < line.location + line.length - 1 ? "…" : ""
        return leading + window + trailing
    }

    private static func firstMeaningfulLine(in text: NSString) -> String {
        var snippet = ""
        text.enumerateSubstrings(in: NSRange(location: 0, length: min(text.length, 2000)),
                                 options: [.byLines]) { line, _, _, stop in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            snippet = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
            stop.pointee = true
        }
        return snippet
    }
}
