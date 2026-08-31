//
//  ScratchStore.swift
//  PeteKM
//
//  The Scratch pane's backing file: `.petekm-scratch.md` at the folder root.
//
//  Durable but temporary. It carries over day to day because nothing about it is keyed
//  to a date — there is one file, always the same one, no matter which day or Library
//  file is open. It is deliberately outside the daily/library contract:
//
//    1. dot-prefixed, so `SearchIndexBuilder.scan` skips it (never searched, never in
//       Open Library File…, never in the table of contents);
//    2. listed in `.gitignore`, so `Sync` never commits or pushes it;
//    3. outside `daily/` and `library/`, the only folders the agent is pointed at;
//    4. named as off-limits in the `CLAUDE.md` and `AGENTS.md` the app writes.
//
//  It is plain UTF-8 Markdown on disk like everything else — nothing is cached anywhere
//  that could not be thrown away and reread.
//

import Foundation
import Observation

@MainActor
@Observable
final class ScratchStore {

    /// Same document type as a Daily Sticky: atomic debounced autosave, external-change
    /// reconciliation, and the same never-clobber conflict path.
    let document: StickyDocument

    private(set) var lastError: String?

    private var watcher: DirectoryWatcher?

    private let backups: URL

    init(folder: PeteKMFolder) {
        let url = folder.scratch
        backups = folder.backups
        // Absent file is the normal empty state. Nothing is written until the user types,
        // so an untouched PeteKM folder never grows a scratch file.
        document = StickyDocument(url: url, text: FileWriting.readText(url) ?? "")
        watcher = DirectoryWatcher(url: folder.root) { [weak self] in
            Task { @MainActor [weak self] in self?.document.reconcileWithDisk() }
        }
    }

    var isEmpty: Bool {
        document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// First non-blank line, for the collapsed strip.
    var firstLine: String {
        for line in document.text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    func flush() {
        document.saveNow()
    }

    /// Empties the pane. Scratch is gitignored, so there is no version history to fall
    /// back on — the old text is moved aside into `.petekm-backups/` as
    /// `.petekm-scratch.md.bak-YYYY-MM-DD` first (also gitignored).
    func clear(on date: Date = Date()) {
        document.saveNow()
        if FileWriting.exists(document.url) {
            do {
                try FileWriting.backUp(document.url, into: backups, on: date)
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        document.text = ""
        document.saveNow()
        lastError = nil
    }
}
