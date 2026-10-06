import Foundation

/// How the window dot and menu-bar badge show a `SyncStatus` (sync v2 §8.1, §8.2).
/// The window's sync light. Always visible while automatic sync is on, so a
/// working sync is as visible as a broken one.
enum SyncDotStyle: Equatable, Sendable {
    case hidden
    /// No result yet this session (the first run is still going).
    case neutral
    /// Everything is on GitHub.
    case synced
    /// Changes on this Mac that GitHub doesn't have yet.
    case pending
    /// The network is down.
    case offline
    /// Paused on a conflict, can't push, or stuck: the user should look.
    case problem
}

extension SyncStatus {

    /// Pending under this long is the normal gap between typing and the next
    /// departure trigger, and gets no signal (§8.1, the 2-minute rule).
    static let pendingSignalAfter: TimeInterval = 2 * 60

    /// The status line from §8.4. Nil when automatic sync is off.
    func line(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        func time(_ date: Date) -> String {
            SyncTime.phrase(for: date, now: now, calendar: calendar, locale: locale)
        }
        switch self {
        case .off:
            return nil
        case .synced(let at):
            return "Synced \(time(at)). All notes are on GitHub."
        case .syncing:
            return "Syncing…"
        case .pending(let since):
            return "Not synced yet — changes from \(time(since)) are only on this Mac."
        case .offline(_, let pendingSince?):
            return "Offline — changes from \(time(pendingSince)) are only on this Mac."
        case .offline(_, nil):
            return "Offline. Nothing waiting to sync."
        case .paused:
            return "Sync paused — the same note changed on two Macs. Nothing was lost."
        case .failing(.push):
            return "Can't send changes to GitHub. Try Sync Now, or check your Git sign-in."
        case .failing(.lock):
            return GitSupport.stuckLine
        }
    }

    /// Which dot, if any, the window and menu bar show (§8.1).
    var dot: SyncDotStyle {
        switch self {
        case .off: .hidden
        case .syncing: .neutral
        case .synced: .synced
        case .pending: .pending
        case .offline: .offline
        case .paused, .failing: .problem
        }
    }

    /// The menu-bar badge: problems at once, unsent changes only after 2 min, since
    /// pending for less is the normal gap between typing and the next send.
    func needsAttention(now: Date) -> Bool {
        switch self {
        case .off, .synced, .syncing, .offline(_, nil):
            return false
        case .pending(let since), .offline(_, let since?):
            return now.timeIntervalSince(since) >= Self.pendingSignalAfter
        case .paused, .failing:
            return true
        }
    }

    /// Whether a later `now` could change `line` or `dot`, so the clock needs ticking.
    var isTimeSensitive: Bool {
        switch self {
        case .off, .syncing, .paused, .failing: false
        case .synced, .pending, .offline: true
        }
    }
}

/// One time phrase for every sync line (§8.4): relative under an hour, clock time
/// today, a date beyond today.
enum SyncTime {

    static func phrase(for date: Date, now: Date, calendar: Calendar = .current,
                       locale: Locale = .current, todayPrefix: Bool = false) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0, elapsed < 60 * 60 {
            let minutes = Int(elapsed / 60)
            return minutes < 1 ? "just now" : "\(minutes) min ago"
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            style = style.hour().minute()
            let clock = date.formatted(style)
            return todayPrefix ? "today \(clock)" : clock
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(style.month(.abbreviated).day())
        }
        return date.formatted(style.year().month(.abbreviated).day())
    }

    /// "Last from <other Mac>: <time>." (§9.3), or nil when no other Mac is known.
    static func otherDeviceLine(_ other: (name: String, at: Date)?, now: Date,
                                calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let other else { return nil }
        let time = phrase(for: other.at, now: now, calendar: calendar, locale: locale, todayPrefix: true)
        return "Last from \(other.name): \(time)."
    }

    /// §9.2.3: at the start of a wake or launch run, commits not yet on GitHub that
    /// are older than the wake/launch survived it unpushed.
    static func fetchLine(_ at: Date?, now: Date,
                          calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let at else { return nil }
        let time = phrase(for: at, now: now, calendar: calendar, locale: locale, todayPrefix: true)
        return "Last checked GitHub for updates: \(time)."
    }

    static func showsEarlierNotesNotice(ahead: Int, oldestUnpushed: Date?, arrivedAt: Date) -> Bool {
        guard ahead > 0, let oldestUnpushed else { return false }
        return oldestUnpushed < arrivedAt
    }
}
