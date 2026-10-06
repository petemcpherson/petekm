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

    /// False while a Library or root Markdown file is open instead of a Daily Sticky (§10.2, §30).
    private(set) var openedIsDaily: Bool = true

    /// Where the caret should land when the open document is built — a search hit (§11.4).
    private(set) var revealRange: NSRange?

    private let folder: PeteKMFolder
    private let settings: AppSettings
    private let calendar: Calendar
    private var watcher: DirectoryWatcher?
    private var openedFileWatcher: DirectoryWatcher?

    /// Absent in tests and before the view wires it: then today's file is written at once, as v1.
    private var autoSync: AutoSync?
    private let newDayBudget: Duration
    /// The Pre-New-Day wait (sync v2 §6.5): the arrival run and its 2s budget.
    private var deferralRun: Task<Void, Never>?
    private var deferralTimeout: Task<Void, Never>?

    init(folder: PeteKMFolder, settings: AppSettings, autoSync: AutoSync? = nil,
         newDayBudget: Duration = .seconds(AutoSync.Timing.newDayBudget),
         calendar: Calendar = .current, now: Date = Date()) {
        self.folder = folder
        self.settings = settings
        self.autoSync = autoSync
        self.newDayBudget = newDayBudget
        self.calendar = calendar
        self.openedDate = calendar.startOfDay(for: now)
        openToday(now: now)
        startWatching()
    }

    var openedFileName: String {
        document?.url.lastPathComponent ?? DailyDate.filename(for: openedDate, calendar: calendar)
    }

    var openedTitle: String {
        guard openedIsDaily else {
            return document?.url.deletingPathExtension().lastPathComponent ?? ""
        }
        return DailyDate.longForm(openedDate, calendar: calendar)
    }

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
        openedIsDaily = true
        revealRange = nil
        newDayOptions = nil
        openedFileWatcher = nil
        cancelDeferral()

        let url = folder.dailySticky(for: day, calendar: calendar)
        if FileWriting.exists(url) {
            adopt(StickyDocument(url: url, text: FileWriting.readText(url) ?? ""))
            return
        }

        switch settings.dailyStartBehavior {
        case .ask:
            let options = availableNewDayOptions(for: day)
            if options.count > 1 {
                adopt(nil)
                newDayOptions = options
                syncWhilePrompting(for: day)
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

    /// Opens any Markdown file in the folder — a Library file, `INBOX.md`, a past sticky
    /// reached from search. Never creates the file: the palette only offers what exists (§19.2).
    func open(fileURL url: URL, reveal: NSRange? = nil) {
        let dailyDate = dailyDate(for: url)

        // A daily file reached by path is still a Daily Sticky, midnight rules and all.
        if let dailyDate {
            open(date: dailyDate)
            revealRange = reveal
            return
        }

        guard let text = FileWriting.readText(url) else {
            lastError = "PeteKM couldn't open \(url.lastPathComponent)."
            return
        }

        newDayOptions = nil
        openedIsDaily = false
        openedAsToday = false
        revealRange = reveal
        adopt(StickyDocument(url: url, text: text))
        lastError = nil
        watchOpenedFile()
    }

    /// The date behind `daily/YYYY-MM-DD.md`, or nil for anything else.
    private func dailyDate(for url: URL) -> Date? {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent == folder.daily.standardizedFileURL else { return nil }
        return DailyDate.date(fromFilename: url.lastPathComponent, calendar: calendar)
    }

    /// Answer to the New Day prompt. Today's file may have arrived from the other Mac while
    /// the prompt was up; then it opens instead (sync v2 §6.5 step 4).
    func startNewDay(_ start: NewDayStart) {
        newDayOptions = nil
        if FileWriting.exists(folder.dailySticky(for: openedDate, calendar: calendar)) {
            open(date: openedDate)
            return
        }
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
        let content = compose(start: start, for: day)

        if shouldDeferCreate(of: url) {
            let document = StickyDocument(url: url, text: content, deferredCreate: true)
            adopt(document)
            lastError = nil
            beginDeferral(of: document, start: start, for: day)
            return
        }

        do {
            let document = try StickyDocument.open(url: url, creatingWith: content)
            adopt(document)
            lastError = nil
        } catch {
            document = nil
            lastError = error.localizedDescription
        }
    }

    private func compose(start: NewDayStart, for day: Date) -> String {
        NewDayComposer.content(
            start: start,
            date: day,
            showDateHeading: settings.showDateHeading,
            defaultHeaders: settings.defaultHeaders,
            priorStickyText: start == .carryForwardHeaders
                ? DailyFiles.priorStickyText(before: day, in: folder, calendar: calendar)
                : nil,
            calendar: calendar
        )
    }

    /// An outgoing deferred sticky was never written and is simply dropped: the next open
    /// composes it again, so nothing is lost.
    private func adopt(_ document: StickyDocument?) {
        cancelDeferral()
        let outgoing = self.document
        outgoing?.saveNow()
        pruneIfBlank(outgoing)
        self.document = document
    }

    // MARK: - Pre-New-Day (sync v2 §6.5)

    /// Gives the session the coordinator once the view has one.
    func attach(_ autoSync: AutoSync) {
        self.autoSync = autoSync
    }

    /// All four §6.5 conditions: automatic sync on, an upstream, today, and no file yet.
    private func shouldDeferCreate(of url: URL) -> Bool {
        guard let autoSync, openedAsToday, !FileWriting.exists(url) else { return false }
        return autoSync.canDeferNewDay(in: folder)
    }

    /// The composed text is already on screen. The first of three events writes it or
    /// replaces it: the run brings today's file in, the user types (autosave), or the budget ends.
    private func beginDeferral(of document: StickyDocument, start: NewDayStart, for day: Date) {
        let autoSync = autoSync
        let budget = newDayBudget
        deferralTimeout = Task { [weak self, weak document] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled, let self, let document, document === self.document else { return }
            document.commitDeferred()
            self.deferralRun?.cancel()
            self.deferralRun = nil
        }
        deferralRun = Task { [weak self, weak document] in
            let run = await autoSync?.request(.newDay)
            guard !Task.isCancelled, let self, let document, document === self.document else { return }
            self.deferralTimeout?.cancel()
            self.deferralTimeout = nil
            self.finishDeferral(of: document, after: run, start: start, for: day)
        }
    }

    private func finishDeferral(of document: StickyDocument, after run: GitSupport.SyncRun?,
                                start: NewDayStart, for day: Date) {
        guard document.isDeferred else { return }
        document.reconcileWithDisk()                 // adopts today's file if the run brought it
        guard document.isDeferred else { return }
        // Carry-forward now reads the other Mac's latest sticky, not a stale one.
        if start == .carryForwardHeaders, run?.didBringIn == true {
            document.recomposeDeferred(compose(start: start, for: day))
        }
        document.commitDeferred()
    }

    /// With "Ask me each day" the prompt is the wait: sync while it is up, and if today's file
    /// arrives before an answer, open it and drop the prompt.
    private func syncWhilePrompting(for day: Date) {
        let url = folder.dailySticky(for: day, calendar: calendar)
        guard let autoSync, openedAsToday, autoSync.canDeferNewDay(in: folder) else { return }
        deferralRun = Task { [weak self] in
            await autoSync.request(.newDay)
            guard !Task.isCancelled, let self, self.newDayOptions != nil,
                  self.calendar.isDate(self.openedDate, inSameDayAs: day),
                  FileWriting.exists(url) else { return }
            self.open(date: day)
        }
    }

    private func cancelDeferral() {
        deferralRun?.cancel()
        deferralTimeout?.cancel()
        deferralRun = nil
        deferralTimeout = nil
    }

    /// Removes a Daily Sticky that holds nothing, so a day spent entirely in Scratch — or not
    /// spent here at all — leaves no file behind. Deliberately narrow: blank in memory *and* on
    /// disk, never dirty, never conflicted, never a Library file. The next open recreates it
    /// identically, so there is nothing to lose and nothing to notice.
    private func pruneIfBlank(_ document: StickyDocument?) {
        guard let document,
              !document.hasConflict, !document.isDirty,
              let day = dailyDate(for: document.url),
              DailyFiles.isBlankSticky(document.text, for: day, calendar: calendar),
              let onDisk = FileWriting.readText(document.url),
              DailyFiles.isBlankSticky(onDisk, for: day, calendar: calendar)
        else { return }

        try? FileManager.default.removeItem(at: document.url)
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
        pruneIfBlank(document)
    }

    private func startWatching() {
        try? FileManager.default.createDirectory(at: folder.daily, withIntermediateDirectories: true)
        watcher = DirectoryWatcher(url: folder.daily) { [weak self] in
            Task { @MainActor [weak self] in self?.document?.reconcileWithDisk() }
        }
    }

    /// Library files live outside `daily/`, so they need their own watch (§8.5).
    private func watchOpenedFile() {
        guard let directory = document?.url.deletingLastPathComponent().standardizedFileURL,
              directory != folder.daily.standardizedFileURL else {
            openedFileWatcher = nil
            return
        }
        openedFileWatcher = DirectoryWatcher(url: directory) { [weak self] in
            Task { @MainActor [weak self] in self?.document?.reconcileWithDisk() }
        }
    }
}
