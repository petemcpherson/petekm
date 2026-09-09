import Foundation

/// Reads `daily/` as the canonical store — no index, no cache (§2.2).
enum DailyFiles {

    /// Every `YYYY-MM-DD.md` in `daily/`, oldest first. Anything else in the folder is ignored.
    static func stickyDates(in folder: PeteKMFolder, calendar: Calendar = .current) -> [Date] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.daily.path(percentEncoded: false))) ?? []
        return names
            .compactMap { DailyDate.date(fromFilename: $0, calendar: calendar) }
            .sorted()
    }

    /// The most recent Daily Sticky strictly before `date`, if any.
    /// True when a Daily Sticky holds nothing but whitespace and, at most, its own date heading —
    /// a file indistinguishable from a day that was never opened.
    static func isBlankSticky(_ text: String, for date: Date, calendar: Calendar = .current) -> Bool {
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
        for previous in stickyDates(in: folder, calendar: calendar).reversed() where previous < target {
            let url = folder.dailySticky(for: previous, calendar: calendar)
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
