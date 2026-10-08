import Foundation

/// Date <-> `daily/YYYY-MM-DD.md` conversions and the hard-coded English H1 date heading (§18.5).
nonisolated enum DailyDate {

    static let filenameSuffix = ".md"

    /// `2026-08-19`
    static func stamp(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2026-08-19.md`
    static func filename(for date: Date, calendar: Calendar = .current) -> String {
        stamp(for: date, calendar: calendar) + filenameSuffix
    }

    /// Parses `2026-08-19.md` (or the bare stamp) back into a date at the start of that local day.
    static func date(fromFilename filename: String, calendar: Calendar = .current) -> Date? {
        var stamp = filename
        if stamp.hasSuffix(filenameSuffix) {
            stamp.removeLast(filenameSuffix.count)
        }
        let parts = stamp.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// `August 19, 2026` — always US English, never localized (§18.5).
    static func longForm(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// `# August 19, 2026`
    static func heading(for date: Date, calendar: Calendar = .current) -> String {
        "# " + longForm(date, calendar: calendar)
    }

    /// `2026-08-19 2045` — used for conflict filenames (§19.4).
    static func conflictStamp(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0)
    }
}
