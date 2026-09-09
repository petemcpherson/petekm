import Foundation
import Testing
@testable import PeteKM

// MARK: - Fixtures

private func makeFolder() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-search-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

private func write(_ text: String, to url: URL) throws {
    try FileWriting.writeAtomically(text, to: url)
}

private func indexedFile(_ path: String, _ text: String, modified: Date = Date()) -> IndexedFile {
    IndexedFile(relativePath: path, modified: modified, size: text.utf8.count, text: text)
}

// MARK: - Fuzzy matching (§10.3)

@Test func fuzzyMatchesSubsequencesOnly() {
    #expect(FuzzyMatch.score("movie", in: "Movies Watched.md") != nil)
    #expect(FuzzyMatch.score("movie", in: "Movie Recommendations.md") != nil)
    #expect(FuzzyMatch.score("movie", in: "Grocery List.md") == nil)
}

@Test func fuzzyPrefersContiguousMatchesAtTheStart() throws {
    let tight = try #require(FuzzyMatch.score("mov", in: "Movies.md"))
    let scattered = try #require(FuzzyMatch.score("mov", in: "Meeting Overview.md"))
    #expect(tight > scattered)
}

@Test func emptyFuzzyQueryMatchesEverything() {
    #expect(FuzzyMatch.score("", in: "Anything.md") == 0)
}

// MARK: - Search (§11.2–§11.3)

@Test func searchFindsBodyTextAcrossDailyAndLibrary() throws {
    let files = [
        indexedFile("daily/2026-08-19.md", """
        # August 19, 2026

        ## Redwood onboarding

        certificate-based authentication is common for MFT vendors.
        """),
        indexedFile("library/Work/MFT.md", """
        # MFT

        ## Authentication

        certificate authentication can replace passwords here.
        """),
        indexedFile("library/Home/Groceries.md", "- milk\n- bread\n")
    ]

    let results = SearchQuery.run("certificate authentication", over: files)

    #expect(results.count == 2)
    #expect(Set(results.map(\.relativePath)) == ["daily/2026-08-19.md", "library/Work/MFT.md"])
}

@Test func searchResultsCarryHeadingSnippetAndDate() throws {
    let files = [indexedFile("daily/2026-08-19.md", """
    # August 19, 2026

    ## Redwood onboarding

    certificate-based authentication is common for MFT vendors.
    """)]

    let result = try #require(SearchQuery.run("certificate", over: files).first)

    #expect(result.heading == "Redwood onboarding")
    #expect(result.snippet.contains("certificate-based authentication"))
    #expect(result.dateLabel == "August 19, 2026")
    #expect(result.range.location > 0)
}

@Test func searchRangePointsAtTheMatch() throws {
    let text = "# Notes\n\nthe answer is 42 somewhere here.\n"
    let result = try #require(SearchQuery.run("answer", over: [indexedFile("library/Notes.md", text)]).first)

    let matched = (text as NSString).substring(with: result.range)
    #expect(matched == "answer")
}

@Test func everyTermMustMatchSomewhere() {
    let files = [indexedFile("library/Notes.md", "certificates are fine")]

    #expect(SearchQuery.run("certificate", over: files).count == 1)
    #expect(SearchQuery.run("certificate rutabaga", over: files).isEmpty)
}

@Test func filenameMatchesOutrankBodyMatches() throws {
    let files = [
        indexedFile("library/Work/Deep note.md", "movies are mentioned deep in this body text"),
        indexedFile("library/Movies Watched.md", "nothing relevant in the body")
    ]

    let results = SearchQuery.run("movies", over: files)

    #expect(results.first?.relativePath == "library/Movies Watched.md")
}

@Test func pathOnlyMatchesStillReturnAUsefulSnippet() throws {
    let files = [indexedFile("library/Movies Watched.md", "\n\nDune\nArrival\n")]

    let result = try #require(SearchQuery.run("watched", over: files).first)

    #expect(result.snippet == "Dune")
    #expect(result.range == NSRange(location: 0, length: 0))
}

@Test func emptyQueryReturnsNothing() {
    #expect(SearchQuery.run("   ", over: [indexedFile("library/A.md", "text")]).isEmpty)
}

// MARK: - Index (§11.6, §5.8)

@Test func indexCoversEveryMarkdownFileButSkipsHiddenDirectories() throws {
    let folder = try makeFolder()
    try write("# today", to: folder.dailySticky(for: Date()))
    try write("# mft", to: folder.library.appending(path: "Work/MFT.md"))
    try write("# index", to: folder.index)
    try write("# skill", to: folder.skill("petekm-status"))
    try write("not markdown", to: folder.root.appending(path: "notes.txt"))

    let store = SearchIndexBuilder.scan(root: folder.root, previous: SearchIndexStore())

    #expect(store.files["library/Work/MFT.md"] != nil)
    #expect(store.files["INDEX.md"] != nil)
    #expect(store.files.count == 3)
    #expect(!store.files.keys.contains { $0.hasPrefix(".claude") })
    #expect(!store.files.keys.contains { $0.hasSuffix(".txt") })

    try? FileManager.default.removeItem(at: folder.root)
}

@Test func rescanReusesUnchangedFilesAndDropsDeletedOnes() throws {
    let folder = try makeFolder()
    let kept = folder.library.appending(path: "Kept.md")
    let removed = folder.library.appending(path: "Removed.md")
    try write("# kept", to: kept)
    try write("# removed", to: removed)

    let first = SearchIndexBuilder.scan(root: folder.root, previous: SearchIndexStore())
    try FileManager.default.removeItem(at: removed)
    let second = SearchIndexBuilder.scan(root: folder.root, previous: first)

    #expect(second.files["library/Removed.md"] == nil)
    #expect(second.files["library/Kept.md"] == first.files["library/Kept.md"])

    try? FileManager.default.removeItem(at: folder.root)
}

@Test func rebuildingFromAnEmptyIndexProducesTheSameContent() throws {
    let folder = try makeFolder()
    try write("certificate authentication", to: folder.library.appending(path: "MFT.md"))

    let built = SearchIndexBuilder.scan(root: folder.root, previous: SearchIndexStore())
    let rebuilt = SearchIndexBuilder.scan(root: folder.root, previous: SearchIndexStore())

    #expect(built.files == rebuilt.files)
    #expect(SearchQuery.run("certificate", over: Array(rebuilt.files.values)).count == 1)

    try? FileManager.default.removeItem(at: folder.root)
}

@Test func indexLivesOutsideThePeteKMFolder() throws {
    let folder = try makeFolder()

    let cache = SearchIndex.indexFileURL(for: folder)

    #expect(!cache.path(percentEncoded: false).hasPrefix(folder.root.path(percentEncoded: false)))
    #expect(cache.path(percentEncoded: false).contains("PeteKM/SearchIndex"))

    try? FileManager.default.removeItem(at: folder.root)
}

// MARK: - Open Date… input (§10.2)

@Test func dateInputAcceptsWhatPeopleType() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20)))

    func stamp(_ raw: String) -> String? {
        PaletteDateInput.parse(raw, calendar: calendar, now: now).map { DailyDate.stamp(for: $0, calendar: calendar) }
    }

    #expect(stamp("2026-08-19") == "2026-08-19")
    #expect(stamp("today") == "2026-08-20")
    #expect(stamp("yesterday") == "2026-08-19")
    #expect(stamp("8/19") == "2026-08-19")
    #expect(stamp("8/19/25") == "2025-08-19")
    #expect(stamp("") == "2026-08-20")
    #expect(stamp("rutabaga") == nil)
    #expect(stamp("19/45") == nil)
}

@Test func libraryDestinationsCoverEveryFolderAndFile() {
    let paths = [
        "library/Work/Acme.md",
        "library/Work/Projects/MFT.md",
        "library/Lists/Gifts.md",
    ]
    let destinations = LibraryPaths.destinations(from: paths)

    // Folders first, each with a trailing slash, `library/` itself included.
    #expect(destinations.prefix(5) == [
        "library/",
        "library/Lists/",
        "library/Work/",
        "library/Work/Projects/",
        "library/Lists/Gifts.md",
    ])
    #expect(destinations.filter { $0.hasSuffix("/") }.count == 4)
    #expect(destinations.count == 7)
    // Every inserted path is agent-recognizable: it starts with `library/`.
    #expect(destinations.allSatisfy { $0.hasPrefix("library/") })
}

@Test func libraryDestinationsOfAnEmptyLibraryAreJustTheRoot() {
    #expect(LibraryPaths.destinations(from: []) == ["library/"])
}

@Test func insertedPathCarriesTheArrowHint() {
    #expect(PaletteModel.destinationHintPrefix + "library/Work/" == "-> library/Work/")
}

@Test func slashSpaceIsTheOnlyShapeThatTriggersTheFileShortcut() {
    #expect(PaletteModel.libraryFileShortcut("/ acme") == "acme")
    #expect(PaletteModel.libraryFileShortcut("/ ") == "")
    #expect(PaletteModel.libraryFileShortcut("/acme") == nil)
    #expect(PaletteModel.libraryFileShortcut("acme") == nil)
    #expect(PaletteModel.libraryFileShortcut(" / acme") == nil)
}

@MainActor
@Test func typingSlashSpaceInTheCommandListJumpsToFileOpen() {
    let palette = PaletteModel()
    palette.present()

    palette.query = "/ "
    #expect(palette.mode == .files)
    #expect(palette.query == "")

    palette.query = "acme"
    #expect(palette.mode == .files)
    // Already in file mode: the prefix is literal text, not a second jump.
    palette.query = "/ acme"
    #expect(palette.mode == .files)
    #expect(palette.query == "/ acme")

    // Escape steps back to the command list with a clean query (§10.1).
    palette.back()
    #expect(palette.mode == .commands)
    #expect(palette.query == "")
}
