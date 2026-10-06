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

    /// Today's composed text is on screen but not yet on disk: an arrival sync may still bring
    /// the other Mac's copy in (sync v2 §6.5). The first keystroke, or `commitDeferred()`, ends it.
    private(set) var isDeferred: Bool

    var isDirty: Bool { text != savedText }
    var hasConflict: Bool { conflict != nil }

    private let autosaveDelay: Duration
    private var saveTask: Task<Void, Never>?

    init(url: URL, text: String, deferredCreate: Bool = false, autosaveDelay: Duration = .milliseconds(600)) {
        self.url = url
        self.text = text
        self.savedText = text
        self.isDeferred = deferredCreate
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
        // A deferred file that appeared meanwhile is someone else's copy, whatever it says.
        if let onDisk, isDeferred || onDisk != savedText {
            // Someone else changed the file since our last sync: never clobber it (§19.4).
            conflict = Conflict(diskText: onDisk)
            isDeferred = false
            return
        }

        if write(text) { isDeferred = false }
    }

    /// Ends a deferral by writing the composed text, unless the file arrived meanwhile — then
    /// the disk copy wins the normal way (sync v2 §6.5, timeout path).
    func commitDeferred() {
        guard isDeferred else { return }
        if FileWriting.exists(url) {
            reconcileWithDisk()
            return
        }
        saveTask?.cancel()
        saveTask = nil
        if write(text) { isDeferred = false }
    }

    /// Swaps still-unwritten composed text for a fresher composition. No-op once the user
    /// has typed or the file exists.
    func recomposeDeferred(_ newText: String) {
        guard isDeferred, !isDirty, newText != text else { return }
        savedText = newText
        text = newText
        saveTask?.cancel()
        saveTask = nil
    }

    @discardableResult
    private func write(_ contents: String) -> Bool {
        do {
            try FileWriting.writeAtomically(contents, to: url)
            savedText = contents
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - External changes

    /// Called when the watcher reports activity in the containing folder.
    func reconcileWithDisk() {
        guard conflict == nil else { return }

        guard let onDisk = FileWriting.readText(url) else {
            // Deferred: not written yet on purpose, so there is nothing to put back (sync v2 §6.5).
            guard !isDeferred else { return }
            // Deleted or moved out from under us — put our copy back rather than lose it.
            if !text.isEmpty { write(text) }
            return
        }

        if isDeferred {
            isDeferred = false
            guard isDirty else {
                // The other Mac's copy arrived before any keystroke: adopt it, nothing was written.
                text = onDisk
                savedText = onDisk
                saveTask?.cancel()
                saveTask = nil
                return
            }
            conflict = Conflict(diskText: onDisk)
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
