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
    static func mostRecentSticky(before date: Date, in folder: PeteKMFolder, calendar: Calendar = .current) -> URL? {
        let target = calendar.startOfDay(for: date)
        guard let previous = stickyDates(in: folder, calendar: calendar).last(where: { $0 < target }) else {
            return nil
        }
        return folder.dailySticky(for: previous, calendar: calendar)
    }

    static func priorStickyText(before date: Date, in folder: PeteKMFolder, calendar: Calendar = .current) -> String? {
        guard let url = mostRecentSticky(before: date, in: folder, calendar: calendar) else { return nil }
        return FileWriting.readText(url)
    }
}
