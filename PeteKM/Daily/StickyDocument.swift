import Foundation
import Observation

/// One open Markdown file. The file on disk is canonical; this object is a working copy that
/// autosaves atomically and never overwrites a newer disk version without asking (§8.4, §8.5, §19.3, §19.4).
@MainActor
@Observable
final class StickyDocument {

    enum ConflictChoice {
        case keepMine
        case keepDisk
        case keepBoth
    }

    struct Conflict: Equatable {
        let diskText: String
    }

    let url: URL

    var text: String {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    /// What we last read from, or wrote to, disk. Divergence from `text` means unsaved local edits.
    private(set) var savedText: String
    private(set) var conflict: Conflict?
    private(set) var lastError: String?

    var isDirty: Bool { text != savedText }
    var hasConflict: Bool { conflict != nil }

    private let autosaveDelay: Duration
    private var saveTask: Task<Void, Never>?

    init(url: URL, text: String, autosaveDelay: Duration = .milliseconds(600)) {
        self.url = url
        self.text = text
        self.savedText = text
        self.autosaveDelay = autosaveDelay
    }

    /// Opens an existing file, or creates it with `initialContent` when absent.
    static func open(url: URL, creatingWith initialContent: @autoclosure () -> String) throws -> StickyDocument {
        if let existing = FileWriting.readText(url) {
            return StickyDocument(url: url, text: existing)
        }
        let content = initialContent()
        try FileWriting.writeAtomically(content, to: url)
        return StickyDocument(url: url, text: content)
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    /// Writes pending edits immediately. Safe to call when clean or conflicted — it does nothing then.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard conflict == nil, isDirty else { return }

        let onDisk = FileWriting.readText(url)
        // Someone else changed the file since our last sync: never clobber it (§19.4).
        if let onDisk, onDisk != savedText {
            conflict = Conflict(diskText: onDisk)
            return
        }

        write(text)
    }

    private func write(_ contents: String) {
        do {
            try FileWriting.writeAtomically(contents, to: url)
            savedText = contents
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - External changes

    /// Called when the watcher reports activity in the containing folder.
    func reconcileWithDisk() {
        guard conflict == nil else { return }

        guard let onDisk = FileWriting.readText(url) else {
            // Deleted or moved out from under us — put our copy back rather than lose it.
            if !text.isEmpty { write(text) }
            return
        }

        guard onDisk != savedText else { return }   // our own write, or no real change

        if !isDirty {
            text = onDisk                            // silent reload (§19.4)
            savedText = onDisk
            saveTask?.cancel()
            saveTask = nil
            return
        }

        conflict = Conflict(diskText: onDisk)
    }

    // MARK: - Conflict resolution

    func resolve(_ choice: ConflictChoice, at date: Date = Date(), calendar: Calendar = .current) {
        guard let conflict else { return }
        let mine = text
        self.conflict = nil

        switch choice {
        case .keepMine:
            write(mine)

        case .keepDisk:
            text = conflict.diskText
            savedText = conflict.diskText
            saveTask?.cancel()
            saveTask = nil

        case .keepBoth:
            do {
                try FileWriting.writeAtomically(conflict.diskText,
                                                to: StickyDocument.conflictURL(for: url, at: date, calendar: calendar))
            } catch {
                lastError = error.localizedDescription
            }
            write(mine)
        }
    }

    /// `2026-08-19 (conflict 2026-08-19 2045).md`
    static func conflictURL(for url: URL, at date: Date = Date(), calendar: Calendar = .current) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = "\(base) (conflict \(DailyDate.conflictStamp(for: date, calendar: calendar)))"
        var candidate = url.deletingLastPathComponent().appending(path: ext.isEmpty ? name : "\(name).\(ext)")
        var counter = 2
        while FileWriting.exists(candidate) {
            let numbered = "\(name) \(counter)"
            candidate = url.deletingLastPathComponent().appending(path: ext.isEmpty ? numbered : "\(numbered).\(ext)")
            counter += 1
        }
        return candidate
    }
}
