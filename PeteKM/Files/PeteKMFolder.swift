//
//  PeteKMFolder.swift
//  PeteKM
//
//  The shape of a PeteKM folder on disk (spec §5). Markdown files are the only
//  canonical store; nothing here caches note content.
//

import Foundation

/// Every path the app knows about inside a PeteKM folder, derived from its root.
struct PeteKMFolder: Equatable, Hashable {
    let root: URL

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    // Directories (§5.1, §5.2, §14)
    var daily: URL { root.appending(path: "daily", directoryHint: .isDirectory) }
    var library: URL { root.appending(path: "library", directoryHint: .isDirectory) }
    var claude: URL { root.appending(path: ".claude", directoryHint: .isDirectory) }
    var skills: URL { claude.appending(path: "skills", directoryHint: .isDirectory) }

    // Root files (§5.4–§5.7, §6.2)
    var index: URL { root.appending(path: "INDEX.md") }
    var claudeMd: URL { root.appending(path: "CLAUDE.md") }
    var agentsMd: URL { root.appending(path: "AGENTS.md") }
    var inbox: URL { root.appending(path: "INBOX.md") }
    var state: URL { root.appending(path: ".petekm-state.json") }
    var gitignore: URL { root.appending(path: ".gitignore") }

    /// The Scratch pane's backing file. Deliberately outside the daily/library contract:
    /// dot-prefixed so the search index skips it, `.gitignore`d so Git Sync never commits
    /// it, and named as off-limits in `CLAUDE.md`/`AGENTS.md`. Never a note.
    /// Where every `.bak-` file goes — hidden, gitignored, out of the root listing.
    var backups: URL { root.appending(path: ".petekm-backups", directoryHint: .isDirectory) }

    var scratch: URL { root.appending(path: PeteKMFolder.scratchFilename) }

    static let scratchFilename = ".petekm-scratch.md"
    var gitDirectory: URL { root.appending(path: ".git", directoryHint: .isDirectory) }

    var name: String { root.lastPathComponent }

    func skill(_ name: String) -> URL {
        skills.appending(path: name, directoryHint: .isDirectory).appending(path: "SKILL.md")
    }

    /// A Daily Sticky path for a local calendar date (§5.1). Filenames are
    /// machine-generated; the user never names these files.
    func dailySticky(for date: Date, calendar: Calendar = .current) -> URL {
        daily.appending(path: PeteKMFolder.dailyFilename(for: date, calendar: calendar))
    }

    static func dailyFilename(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.md", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// True when the folder looks like it has already been used as a PeteKM
    /// folder — used to word adoption copy, never to gate anything.
    var looksInitialized: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: daily.path(percentEncoded: false))
            || fm.fileExists(atPath: library.path(percentEncoded: false))
            || fm.fileExists(atPath: agentsMd.path(percentEncoded: false))
    }
}
