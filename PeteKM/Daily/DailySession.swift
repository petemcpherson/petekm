import Foundation
import Observation

/// Owns whichever Daily Sticky is currently open, the New Day flow, and disk watching.
@MainActor
@Observable
final class DailySession {

    private(set) var openedDate: Date
    private(set) var document: StickyDocument?
    private(set) var lastError: String?

    /// Non-nil while the tiny "Ask me each day" prompt is up (§7.3).
    private(set) var newDayOptions: [NewDayStart]?

    /// True when the currently open sticky was today's at the moment it was opened.
    private(set) var openedAsToday: Bool = true

    private let folder: PeteKMFolder
    private let settings: AppSettings
    private let calendar: Calendar
    private var watcher: DirectoryWatcher?

    init(folder: PeteKMFolder, settings: AppSettings, calendar: Calendar = .current, now: Date = Date()) {
        self.folder = folder
        self.settings = settings
        self.calendar = calendar
        self.openedDate = calendar.startOfDay(for: now)
        openToday(now: now)
        startWatching()
    }

    var openedFileName: String { DailyDate.filename(for: openedDate, calendar: calendar) }

    var openedTitle: String { DailyDate.longForm(openedDate, calendar: calendar) }

    var isShowingToday: Bool {
        calendar.isDate(openedDate, inSameDayAs: Date())
    }

    // MARK: - Opening

    /// Today's sticky: opens the file if it exists, otherwise runs the New Day flow (§7.1).
    func openToday(now: Date = Date()) {
        open(date: now)
    }

    /// Any date. Past stickies are fully editable — the immutability rule binds agents only (§8.9).
    func open(date: Date) {
        let day = calendar.startOfDay(for: date)
        openedDate = day
        openedAsToday = calendar.isDate(day, inSameDayAs: Date())
        newDayOptions = nil

        let url = folder.dailySticky(for: day, calendar: calendar)
        if FileWriting.exists(url) {
            adopt(StickyDocument(url: url, text: FileWriting.readText(url) ?? ""))
            return
        }

        switch settings.dailyStartBehavior {
        case .ask:
            let options = availableNewDayOptions(for: day)
            if options.count > 1 {
                document = nil
                newDayOptions = options
            } else {
                create(start: options.first ?? .scratch, for: day)
            }
        case .scratch:
            create(start: .scratch, for: day)
        case .carryForwardHeaders:
            create(start: .carryForwardHeaders, for: day)
        case .defaultHeaders:
            create(start: .defaultHeaders, for: day)
        }
    }

    /// Answer to the New Day prompt.
    func startNewDay(_ start: NewDayStart) {
        newDayOptions = nil
        create(start: start, for: openedDate)
    }

    /// Offer only what the folder and settings can actually deliver (§7.3).
    private func availableNewDayOptions(for day: Date) -> [NewDayStart] {
        var options: [NewDayStart] = []
        if DailyFiles.mostRecentSticky(before: day, in: folder, calendar: calendar) != nil {
            options.append(.carryForwardHeaders)
        }
        options.append(.scratch)
        if !settings.defaultHeaders.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            options.append(.defaultHeaders)
        }
        return options
    }

    private func create(start: NewDayStart, for day: Date) {
        let url = folder.dailySticky(for: day, calendar: calendar)
        let content = NewDayComposer.content(
            start: start,
            date: day,
            showDateHeading: settings.showDateHeading,
            defaultHeaders: settings.defaultHeaders,
            priorStickyText: start == .carryForwardHeaders
                ? DailyFiles.priorStickyText(before: day, in: folder, calendar: calendar)
                : nil,
            calendar: calendar
        )

        do {
            let document = try StickyDocument.open(url: url, creatingWith: content)
            adopt(document)
            lastError = nil
        } catch {
            document = nil
            lastError = error.localizedDescription
        }
    }

    private func adopt(_ document: StickyDocument) {
        self.document?.saveNow()
        self.document = document
    }

    // MARK: - Lifecycle

    /// Call on show/focus: crossing midnight must not leave yesterday presented as today (§7.7).
    /// Only rolls forward when the open sticky *was* today when it was opened — a deliberately
    /// opened past sticky is never yanked away.
    func handleActivation(now: Date = Date()) {
        document?.reconcileWithDisk()
        guard openedAsToday, !calendar.isDate(openedDate, inSameDayAs: now) else { return }
        flush()
        openToday(now: now)
    }

    func flush() {
        document?.saveNow()
    }

    private func startWatching() {
        try? FileManager.default.createDirectory(at: folder.daily, withIntermediateDirectories: true)
        watcher = DirectoryWatcher(url: folder.daily) { [weak self] in
            Task { @MainActor [weak self] in self?.document?.reconcileWithDisk() }
        }
    }
}
