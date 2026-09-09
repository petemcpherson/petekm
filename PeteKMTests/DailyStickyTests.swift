//
//  DailyStickyTests.swift
//  PeteKMTests
//

import Foundation
import Testing
@testable import PeteKM

private func makeTemporaryFolder() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-daily-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root.appending(path: "daily", directoryHint: .isDirectory),
                                            withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

private func remove(_ folder: PeteKMFolder) {
    try? FileManager.default.removeItem(at: folder.root)
}

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = dayOfMonth
    return Calendar.current.date(from: components)!
}

// MARK: - Dates

struct DailyDateTests {

    @Test func filenameUsesLocalCalendarDate() {
        #expect(DailyDate.filename(for: day(2026, 8, 19)) == "2026-08-19.md")
        #expect(DailyDate.stamp(for: day(2026, 1, 2)) == "2026-01-02")
    }

    @Test func roundTripsFilenames() {
        let date = day(2026, 8, 19)
        let parsed = DailyDate.date(fromFilename: DailyDate.filename(for: date))
        #expect(parsed == Calendar.current.startOfDay(for: date))
    }

    @Test func rejectsNonStickyFilenames() {
        #expect(DailyDate.date(fromFilename: "INDEX.md") == nil)
        #expect(DailyDate.date(fromFilename: "2026-8-19.md") == nil)
        #expect(DailyDate.date(fromFilename: "notes-2026-08-19.md") == nil)
    }

    @Test func dateHeadingIsHardCodedEnglish() {
        #expect(DailyDate.heading(for: day(2026, 8, 19)) == "# August 19, 2026")
    }

    @Test func conflictStampIncludesTime() {
        let stamped = Calendar.current.date(bySettingHour: 20, minute: 45, second: 0, of: day(2026, 8, 19))!
        #expect(DailyDate.conflictStamp(for: stamped) == "2026-08-19 2045")
    }
}

// MARK: - Headings

struct MarkdownHeadingsTests {

    private let sample = """
    # August 18, 2026

    ## Work

    Lots of text...

    ### Questions

    More text...

    ## App ideas

    Other text...
    """

    @Test func extractsHeadingsInOrderWithLevels() {
        let headings = MarkdownHeadings.headings(in: sample)
        #expect(headings == [
            MarkdownHeading(level: 1, title: "August 18, 2026"),
            MarkdownHeading(level: 2, title: "Work"),
            MarkdownHeading(level: 3, title: "Questions"),
            MarkdownHeading(level: 2, title: "App ideas"),
        ])
    }

    @Test func ignoresHashesInsideCodeFences() {
        let text = """
        ## Work

        ```bash
        # not a heading
        ```

        ## Personal
        """
        #expect(MarkdownHeadings.headings(in: text).map(\.title) == ["Work", "Personal"])
    }

    @Test func ignoresHashesWithoutASpace() {
        #expect(MarkdownHeadings.headings(in: "#tag\n####### too deep").isEmpty)
    }

    @Test func carryForwardDropsTheLeadingH1() {
        #expect(MarkdownHeadings.carryForward(from: sample).map(\.title) == ["Work", "Questions", "App ideas"])
    }
}

// MARK: - New Day content

struct NewDayComposerTests {

    @Test func scratchIsJustTodaysDateHeading() {
        let text = NewDayComposer.content(start: .scratch, date: day(2026, 8, 19),
                                          showDateHeading: true, defaultHeaders: "", priorStickyText: nil)
        #expect(text == "# August 19, 2026\n\n")
    }

    @Test func scratchCanOmitTheDateHeading() {
        let text = NewDayComposer.content(start: .scratch, date: day(2026, 8, 19),
                                          showDateHeading: false, defaultHeaders: "", priorStickyText: nil)
        #expect(text.isEmpty)
    }

    @Test func carryForwardKeepsHeadingsOnlyAndRewritesTheDate() {
        let prior = """
        # August 18, 2026

        ## Work

        Lots of text...

        ### Questions

        More text...

        ## App ideas

        Other text...
        """
        let text = NewDayComposer.content(start: .carryForwardHeaders, date: day(2026, 8, 19),
                                          showDateHeading: true, defaultHeaders: "", priorStickyText: prior)
        #expect(text == """
        # August 19, 2026

        ## Work

        ### Questions

        ## App ideas


        """)
    }

    @Test func carryForwardFallsBackToScratchWithoutAPriorSticky() {
        let text = NewDayComposer.content(start: .carryForwardHeaders, date: day(2026, 8, 19),
                                          showDateHeading: true, defaultHeaders: "", priorStickyText: nil)
        #expect(text == "# August 19, 2026\n\n")
    }

    @Test func defaultHeadersArePreservedVerbatim() {
        let text = NewDayComposer.content(start: .defaultHeaders, date: day(2026, 8, 19),
                                          showDateHeading: true,
                                          defaultHeaders: "## Work\n\n## Personal\n",
                                          priorStickyText: nil)
        #expect(text == "# August 19, 2026\n\n## Work\n\n## Personal\n\n")
    }
}

// MARK: - Daily file lookup

struct DailyFilesTests {

    @Test func findsTheMostRecentPriorSticky() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        for date in [day(2026, 8, 10), day(2026, 8, 17), day(2026, 8, 19)] {
            try FileWriting.writeAtomically("x", to: folder.dailySticky(for: date))
        }
        try FileWriting.writeAtomically("x", to: folder.daily.appending(path: "scratch.md"))

        let previous = DailyFiles.mostRecentSticky(before: day(2026, 8, 19), in: folder)
        #expect(previous?.lastPathComponent == "2026-08-17.md")
    }

    @Test func returnsNilWhenDailyIsEmpty() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        #expect(DailyFiles.mostRecentSticky(before: day(2026, 8, 19), in: folder) == nil)
    }

    @Test func recognisesBlankStickies() {
        let date = day(2026, 8, 17)
        #expect(DailyFiles.isBlankSticky("", for: date))
        #expect(DailyFiles.isBlankSticky("\n\n   \n", for: date))
        #expect(DailyFiles.isBlankSticky("# August 17, 2026\n\n", for: date))
        #expect(!DailyFiles.isBlankSticky("# August 17, 2026\n\n## Work\n", for: date))
        #expect(!DailyFiles.isBlankSticky("a thought", for: date))
        // The heading of a *different* day is real content, not this day's own heading.
        #expect(!DailyFiles.isBlankSticky("# August 17, 2026\n", for: day(2026, 8, 18)))
    }

    @Test func stepsOverBlankDaysWhenLookingBack() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        try FileWriting.writeAtomically("# August 10, 2026\n\n## Work\n", to: folder.dailySticky(for: day(2026, 8, 10)))
        try FileWriting.writeAtomically("# August 17, 2026\n\n", to: folder.dailySticky(for: day(2026, 8, 17)))
        try FileWriting.writeAtomically("", to: folder.dailySticky(for: day(2026, 8, 18)))

        let previous = DailyFiles.mostRecentSticky(before: day(2026, 8, 19), in: folder)
        #expect(previous?.lastPathComponent == "2026-08-10.md")
    }

    @Test func returnsNilWhenEveryPriorDayIsBlank() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileWriting.writeAtomically("", to: folder.dailySticky(for: day(2026, 8, 17)))
        try FileWriting.writeAtomically("# August 18, 2026\n\n", to: folder.dailySticky(for: day(2026, 8, 18)))

        #expect(DailyFiles.mostRecentSticky(before: day(2026, 8, 19), in: folder) == nil)
    }
}

// MARK: - Document write safety

@MainActor
struct StickyDocumentTests {

    private func temporaryFile() throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            .appending(path: "petekm-doc-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "2026-08-19.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    @Test func openCreatesTheFileWithInitialContent() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "# August 19, 2026\n")
        #expect(document.text == "# August 19, 2026\n")
        #expect(FileWriting.readText(url) == "# August 19, 2026\n")
    }

    @Test func openKeepsExistingContent() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileWriting.writeAtomically("already here", to: url)

        let document = try StickyDocument.open(url: url, creatingWith: "should not be used")
        #expect(document.text == "already here")
    }

    @Test func saveNowWritesPendingEdits() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "a")
        document.text = "a b"
        #expect(document.isDirty)
        document.saveNow()
        #expect(!document.isDirty)
        #expect(FileWriting.readText(url) == "a b")
    }

    @Test func autosaveFiresWithoutAManualSave() async throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = StickyDocument(url: url, text: "a", autosaveDelay: .milliseconds(20))
        try FileWriting.writeAtomically("a", to: url)
        document.text = "typed"
        try await Task.sleep(for: .milliseconds(300))
        #expect(FileWriting.readText(url) == "typed")
    }

    @Test func externalChangeReloadsSilentlyWhenClean() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        try FileWriting.writeAtomically("edited in VS Code", to: url)
        document.reconcileWithDisk()

        #expect(document.text == "edited in VS Code")
        #expect(!document.hasConflict)
        #expect(!document.isDirty)
    }

    @Test func bothSidesChangedRaisesAConflict() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        document.text = "mine"
        try FileWriting.writeAtomically("theirs", to: url)
        document.reconcileWithDisk()

        #expect(document.conflict == StickyDocument.Conflict(diskText: "theirs"))
    }

    @Test func saveNeverClobbersANewerDiskVersion() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        document.text = "mine"
        try FileWriting.writeAtomically("theirs", to: url)
        document.saveNow()

        #expect(document.hasConflict)
        #expect(FileWriting.readText(url) == "theirs")
    }

    @Test func keepMineOverwritesDisk() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        document.text = "mine"
        try FileWriting.writeAtomically("theirs", to: url)
        document.reconcileWithDisk()
        document.resolve(.keepMine)

        #expect(FileWriting.readText(url) == "mine")
        #expect(!document.hasConflict)
    }

    @Test func keepDiskDiscardsLocalEdits() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        document.text = "mine"
        try FileWriting.writeAtomically("theirs", to: url)
        document.reconcileWithDisk()
        document.resolve(.keepDisk)

        #expect(document.text == "theirs")
        #expect(!document.isDirty)
        #expect(FileWriting.readText(url) == "theirs")
    }

    @Test func keepBothWritesTheDiskVersionAlongside() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "original")
        document.text = "mine"
        try FileWriting.writeAtomically("theirs", to: url)
        document.reconcileWithDisk()

        let stamped = Calendar.current.date(bySettingHour: 20, minute: 45, second: 0, of: day(2026, 8, 19))!
        document.resolve(.keepBoth, at: stamped)

        let sidecar = url.deletingLastPathComponent().appending(path: "2026-08-19 (conflict 2026-08-19 2045).md")
        #expect(FileWriting.readText(url) == "mine")
        #expect(FileWriting.readText(sidecar) == "theirs")
    }

    @Test func aDeletedFileIsRecreatedRatherThanLost() throws {
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let document = try StickyDocument.open(url: url, creatingWith: "keep me")
        try FileManager.default.removeItem(at: url)
        document.reconcileWithDisk()

        #expect(FileWriting.readText(url) == "keep me")
    }
}

// MARK: - Session

@MainActor
struct DailySessionTests {

    private func settings(_ behavior: DailyStartBehavior, headers: String = "") -> AppSettings {
        let defaults = UserDefaults(suiteName: "petekm-tests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.dailyStartBehavior = behavior
        settings.defaultHeaders = headers
        return settings
    }

    @Test func opensTodaysStickyCreatingItWhenAbsent() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let session = DailySession(folder: folder, settings: settings(.scratch))
        #expect(session.document != nil)
        #expect(session.openedFileName == DailyDate.filename(for: Date()))
        #expect(FileWriting.exists(folder.dailySticky(for: Date())))
    }

    @Test func reopensTheSameFileForTheSameDay() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        let url = folder.dailySticky(for: Date())
        try FileWriting.writeAtomically("typed earlier today", to: url)

        let session = DailySession(folder: folder, settings: settings(.scratch))
        #expect(session.document?.text == "typed earlier today")
    }

    @Test func askPromptsOnlyWhenThereIsMoreThanOneChoice() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        // No prior sticky, no default headers → nothing to ask about.
        let bare = DailySession(folder: folder, settings: settings(.ask))
        #expect(bare.newDayOptions == nil)
        #expect(bare.document != nil)

        try FileManager.default.removeItem(at: folder.dailySticky(for: Date()))
        try FileWriting.writeAtomically("## Work\n", to: folder.dailySticky(for: day(2026, 1, 5)))

        let asked = DailySession(folder: folder, settings: settings(.ask))
        #expect(asked.newDayOptions == [.carryForwardHeaders, .scratch])
        #expect(asked.document == nil)

        asked.startNewDay(.scratch)
        #expect(asked.newDayOptions == nil)
        #expect(asked.document != nil)
    }

    @Test func carryForwardUsesTheMostRecentPriorSticky() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileWriting.writeAtomically("# Old\n\n## Ancient\n", to: folder.dailySticky(for: day(2026, 1, 1)))
        try FileWriting.writeAtomically("# Yesterday\n\n## Work\n\n### Questions\n",
                                        to: folder.dailySticky(for: day(2026, 1, 5)))

        let session = DailySession(folder: folder, settings: settings(.carryForwardHeaders))
        let text = try #require(session.document?.text)
        #expect(text.contains("## Work"))
        #expect(text.contains("### Questions"))
        #expect(!text.contains("## Ancient"))
        #expect(text.hasPrefix(DailyDate.heading(for: Date())))
    }

    @Test func blankStickyIsPrunedOnFlush() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let session = DailySession(folder: folder, settings: settings(.scratch))
        let url = folder.dailySticky(for: Date())
        #expect(FileWriting.exists(url))

        session.flush()
        #expect(!FileWriting.exists(url))
    }

    @Test func aStickyWithContentSurvivesFlush() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let session = DailySession(folder: folder, settings: settings(.scratch))
        session.document?.text = "one line is enough"
        session.flush()

        #expect(FileWriting.readText(folder.dailySticky(for: Date())) == "one line is enough")
    }

    @Test func pruningNeverTouchesALibraryFile() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileManager.default.createDirectory(at: folder.library, withIntermediateDirectories: true)
        let note = folder.library.appending(path: "empty.md")
        try FileWriting.writeAtomically("", to: note)

        let session = DailySession(folder: folder, settings: settings(.scratch))
        session.open(fileURL: note)
        session.flush()

        #expect(FileWriting.exists(note))
    }

    @Test func leavingABlankDayForAnotherPrunesIt() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileWriting.writeAtomically("history", to: folder.dailySticky(for: day(2026, 1, 5)))

        let session = DailySession(folder: folder, settings: settings(.scratch))
        let today = folder.dailySticky(for: Date())
        #expect(FileWriting.exists(today))

        session.open(date: day(2026, 1, 5))
        #expect(!FileWriting.exists(today))
        #expect(FileWriting.readText(folder.dailySticky(for: day(2026, 1, 5))) == "history")
    }

    @Test func pastStickiesOpenFullyEditable() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileWriting.writeAtomically("history", to: folder.dailySticky(for: day(2026, 1, 5)))

        let session = DailySession(folder: folder, settings: settings(.scratch))
        session.open(date: day(2026, 1, 5))

        #expect(session.document?.text == "history")
        #expect(session.openedAsToday == false)

        session.document?.text = "history, amended"
        session.flush()
        #expect(FileWriting.readText(folder.dailySticky(for: day(2026, 1, 5))) == "history, amended")
    }

    @Test func activationAfterMidnightRollsForwardToTheNewDay() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let session = DailySession(folder: folder, settings: settings(.scratch))
        let today = session.openedFileName

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        session.handleActivation(now: tomorrow)

        #expect(session.openedFileName == DailyDate.filename(for: tomorrow))
        #expect(session.openedFileName != today)
        #expect(FileWriting.exists(folder.dailySticky(for: tomorrow)))
    }

    @Test func activationDoesNotYankAwayADeliberatelyOpenedPastSticky() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }
        try FileWriting.writeAtomically("history", to: folder.dailySticky(for: day(2026, 1, 5)))

        let session = DailySession(folder: folder, settings: settings(.scratch))
        session.open(date: day(2026, 1, 5))
        session.handleActivation(now: Date())

        #expect(session.openedFileName == "2026-01-05.md")
    }
}
