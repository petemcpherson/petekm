import Foundation

/// Reads `daily/` as the canonical store — no index, no cache (§2.2).
///
/// A Daily Sticky lives at `daily/YYYY/MM/YYYY-MM-DD.md`. Folders from before 1.0.4 kept
/// them flat in `daily/`; `organize` moves those into place, and every reader here also
/// finds a sticky anywhere under `daily/`, so nothing goes missing before it runs.
enum DailyFiles {

    /// Every Daily Sticky under `daily/`, keyed by day. Where one day has two files — a
    /// stray an organize pass couldn't move — the file at the dated path wins.
    nonisolated static func stickyFiles(in folder: PeteKMFolder, calendar: Calendar = .current) -> [Date: URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder.daily,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }

        var files: [Date: URL] = [:]
        for case let url as URL in enumerator {
            guard let date = DailyDate.date(fromFilename: url.lastPathComponent, calendar: calendar),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let url = url.standardizedFileURL
            if files[date] == nil || url == folder.dailySticky(for: date, calendar: calendar).standardizedFileURL {
                files[date] = url
            }
        }
        return files
    }

    /// Every `YYYY-MM-DD.md` under `daily/`, oldest first. Anything else in the folder is ignored.
    static func stickyDates(in folder: PeteKMFolder, calendar: Calendar = .current) -> [Date] {
        stickyFiles(in: folder, calendar: calendar).keys.sorted()
    }

    /// Where `date`'s sticky is on disk right now: the dated path, else a not-yet-organized
    /// flat file, else the dated path (where a new one gets created).
    static func existingSticky(for date: Date, in folder: PeteKMFolder, calendar: Calendar = .current) -> URL {
        let dated = folder.dailySticky(for: date, calendar: calendar)
        if FileWriting.exists(dated) { return dated }
        let flat = folder.flatDailySticky(for: date, calendar: calendar)
        return FileWriting.exists(flat) ? flat : dated
    }

    /// Moves every Daily Sticky that isn't at `daily/YYYY/MM/YYYY-MM-DD.md` into place.
    ///
    /// Runs silently whenever the folder opens and after every sync. A rename keeps the
    /// file byte-for-byte, so the ledger is untouched in substance (§2.5); git records it
    /// as a rename on the next commit. Never overwrites: when the dated path already
    /// holds a different file, the stray stays where it is and both are still read.
    /// Only a stray identical to the dated file is removed. `open` — the file in the editor —
    /// is never touched. Returns the moves made.
    @discardableResult
    static func organize(_ folder: PeteKMFolder, skipping open: URL? = nil,
                         calendar: Calendar = .current) -> [(from: URL, to: URL)] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder.daily,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var strays: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard let date = DailyDate.date(fromFilename: url.lastPathComponent, calendar: calendar),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            let target = folder.dailySticky(for: date, calendar: calendar)
            if url.standardizedFileURL != target.standardizedFileURL,
               url.standardizedFileURL != open?.standardizedFileURL {
                strays.append((url.standardizedFileURL, date))
            }
        }

        let fm = FileManager.default
        var moved: [(from: URL, to: URL)] = []
        for (url, date) in strays {
            let target = folder.dailySticky(for: date, calendar: calendar)
            if FileWriting.exists(target) {
                if let a = try? Data(contentsOf: url), let b = try? Data(contentsOf: target), a == b {
                    try? fm.removeItem(at: url)
                }
                continue
            }
            do {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: url, to: target)
                moved.append((url, target))
            } catch {
                continue     // left where it is; still read, retried next time
            }
        }
        return moved
    }

    /// The most recent Daily Sticky strictly before `date`, if any.
    /// True when a Daily Sticky holds nothing but whitespace and, at most, its own date heading —
    /// a file indistinguishable from a day that was never opened.
    nonisolated static func isBlankSticky(_ text: String, for date: Date, calendar: Calendar = .current) -> Bool {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty { return true }
        return lines == [DailyDate.heading(for: date, calendar: calendar)]
    }

    /// The newest sticky before `date` that the user actually wrote on. Blank days are stepped
    /// over: they carry nothing, and stopping at one would hide the real headings behind it (§7.4).
    static func mostRecentSticky(before date: Date, in folder: PeteKMFolder, calendar: Calendar = .current) -> URL? {
        let target = calendar.startOfDay(for: date)
        let files = stickyFiles(in: folder, calendar: calendar)
        for previous in files.keys.sorted().reversed() where previous < target {
            guard let url = files[previous] else { continue }
            guard let text = FileWriting.readText(url) else { continue }
            guard !isBlankSticky(text, for: previous, calendar: calendar) else { continue }
            return url
        }
        return nil
    }

    static func priorStickyText(before date: Date, in folder: PeteKMFolder, calendar: Calendar = .current) -> String? {
        guard let url = mostRecentSticky(before: date, in: folder, calendar: calendar) else { return nil }
        return FileWriting.readText(url)
    }
}
