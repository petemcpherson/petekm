//
//  PaletteModel.swift
//  PeteKM
//
//  State behind the ⌘K palette (spec §10, §11). Everything here is keyboard-driven:
//  a query, a list of rows, one selection.
//

import AppKit
import Foundation
import Observation

/// One row in the palette, whatever mode produced it.
struct PaletteRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case command(PaletteCommandID)
        case file(String)          // relative path
        case result(SearchResult)
        case day(Date)
    }

    let id: String
    let title: String
    /// Path, group, or long-form date — the "where is this" line.
    let subtitle: String?
    /// Matching text for search results (§11.3).
    let snippet: String?
    let kind: Kind
}

@MainActor
@Observable
final class PaletteModel {

    enum Mode: Equatable {
        case commands
        case search
        case files
        case date

        var prompt: String {
            switch self {
            case .commands: return "Command"
            case .search: return "Search All PeteKM"
            case .files: return "Open Library File"
            case .date: return "Open Date"
            }
        }

        var breadcrumb: String? {
            switch self {
            case .commands: return nil
            case .search: return "Search"
            case .files: return "Library File"
            case .date: return "Date"
            }
        }
    }

    private(set) var isPresented = false
    private(set) var mode: Mode = .commands
    private(set) var rows: [PaletteRow] = []
    private(set) var selection = 0
    /// Terse status shown in place of results — "Nothing in Inbox." (§13.12, DESIGN §31).
    private(set) var message: String?

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            message = nil
            reload()
        }
    }

    private(set) var folder: PeteKMFolder?
    private(set) var index: SearchIndex?
    private var onPerform: (PaletteOutcome) -> Void = { _ in }
    private let calendar: Calendar
    private let editor: ExternalEditor

    /// Sampled when the palette opens rather than per keystroke — both are disk
    /// or Launch Services lookups (§10.2).
    private(set) var isGitRepository = false
    private(set) var isEditorAvailable = false

    init(calendar: Calendar = .current, editor: ExternalEditor = ExternalEditorProvider.current) {
        self.calendar = calendar
        self.editor = editor
    }

    // MARK: - Wiring

    func configure(folder: PeteKMFolder, onPerform: @escaping (PaletteOutcome) -> Void) {
        self.onPerform = onPerform
        guard self.folder != folder else { return }
        self.folder = folder
        self.index = SearchIndex(folder: folder)
        refreshAvailability()
    }

    /// A command the folder can't perform is absent, not greyed out (§10.2).
    func refreshAvailability() {
        isEditorAvailable = editor.isAvailable
        isGitRepository = folder.map(GitSupport.isRepository) ?? false
    }

    func isAvailable(_ command: PaletteCommandID) -> Bool {
        switch command {
        case .openLibraryInEditor, .openFolderInEditor, .openCurrentFileInEditor:
            return isEditorAvailable
        case .gitSync:
            return isGitRepository
        default:
            return true
        }
    }

    // MARK: - Presentation

    func present(mode: Mode = .commands) {
        self.mode = mode
        query = ""
        message = nil
        isPresented = true
        refreshAvailability()
        reload()
        refreshIndex()
    }

    func dismiss() {
        isPresented = false
        query = ""
        mode = .commands
        message = nil
        rows = []
    }

    /// Escape and backspace-on-empty step back one level before closing (§10.1).
    func back() {
        if mode == .commands {
            dismiss()
        } else {
            present(mode: .commands)
        }
    }

    // MARK: - Selection

    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selection = (selection + delta + rows.count) % rows.count
    }

    func select(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        selection = index
    }

    func commit() {
        guard rows.indices.contains(selection) else { return }
        commit(rows[selection])
    }

    func commit(_ row: PaletteRow) {
        switch row.kind {
        case .command(let command):
            run(command)
        case .file(let path):
            guard let folder else { return }
            perform(.openFile(folder.root.appending(path: path), reveal: nil))
        case .result(let result):
            guard let folder else { return }
            perform(.openFile(folder.root.appending(path: result.relativePath), reveal: result.range))
        case .day(let date):
            perform(.openDaily(date))
        }
    }

    // MARK: - Commands

    private func run(_ command: PaletteCommandID) {
        guard let folder else { return }

        switch command {
        case .openDailySticky:
            perform(.openToday)

        case .openPreviousDailySticky:
            guard let url = DailyFiles.mostRecentSticky(before: Date(), in: folder, calendar: calendar) else {
                message = "No earlier Daily Sticky."
                rows = []
                return
            }
            perform(.openFile(url, reveal: nil))

        case .openDate:
            present(mode: .date)

        case .searchAllPeteKM:
            present(mode: .search)

        case .openLibraryFile:
            present(mode: .files)

        case .openLibraryIndex:
            open(folder.index, whenMissing: "No Library Index yet.")

        case .reviewInbox:
            // The one and only Inbox affordance the app has (DESIGN §17).
            let text = FileWriting.readText(folder.inbox)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, !text.isEmpty else {
                message = "Nothing in Inbox."
                rows = []
                return
            }
            perform(.openFile(folder.inbox, reveal: nil))

        case .openLibraryInEditor:
            perform(.openInEditor(folder.library))

        case .openFolderInEditor:
            perform(.openInEditor(folder.root))

        case .openCurrentFileInEditor:
            perform(.openCurrentFileInEditor)

        case .openTerminal:
            perform(.openTerminalInFolder)

        case .gitSync:
            perform(.gitSync)

        case .revealFolderInFinder:
            perform(.revealFolderInFinder)

        case .settings:
            perform(.openSettings)
        }
    }

    private func open(_ url: URL, whenMissing missing: String) {
        guard FileWriting.exists(url) else {
            message = missing
            rows = []
            return
        }
        perform(.openFile(url, reveal: nil))
    }

    private func perform(_ outcome: PaletteOutcome) {
        dismiss()
        onPerform(outcome)
    }

    // MARK: - Rows

    private func reload() {
        selection = 0
        switch mode {
        case .commands: rows = commandRows()
        case .search: rows = searchRows()
        case .files: rows = fileRows()
        case .date: rows = dayRows()
        }
    }

    private func commandRows() -> [PaletteRow] {
        PaletteCommandID.allCases
            .filter(isAvailable)
            .compactMap { command -> (PaletteCommandID, Int)? in
                guard let score = FuzzyMatch.score(query, in: command.title) else { return nil }
                return (command, score)
            }
            .sorted { $0.1 > $1.1 }
            .map { command, _ in
                PaletteRow(id: command.rawValue,
                           title: command.title,
                           subtitle: command.group,
                           snippet: command.explainer,
                           kind: .command(command))
            }
    }

    private func searchRows() -> [PaletteRow] {
        guard let index, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return index.search(query, calendar: calendar).map { result in
            PaletteRow(id: result.id,
                       title: result.dateLabel ?? result.filename,
                       subtitle: [result.relativePath, result.heading].compactMap { $0 }.joined(separator: " · "),
                       snippet: result.snippet,
                       kind: .result(result))
        }
    }

    private func fileRows() -> [PaletteRow] {
        guard let index else { return [] }

        return index.libraryPaths
            .compactMap { path -> (String, Int)? in
                let name = (path as NSString).lastPathComponent
                guard let score = FuzzyMatch.score(query, in: name)
                        ?? FuzzyMatch.score(query, in: path) else { return nil }
                return (path, score)
            }
            .sorted { left, right in
                left.1 == right.1 ? left.0 < right.0 : left.1 > right.1
            }
            .prefix(60)
            .map { path, _ in
                PaletteRow(id: path,
                           title: (path as NSString).lastPathComponent,
                           subtitle: (path as NSString).deletingLastPathComponent,
                           snippet: nil,
                           kind: .file(path))
            }
    }

    /// Typed dates first, then existing Daily Stickies newest first (§10.2).
    private func dayRows() -> [PaletteRow] {
        guard let folder else { return [] }

        var rows: [PaletteRow] = []
        if let typed = PaletteDateInput.parse(query, calendar: calendar) {
            rows.append(PaletteRow(id: "typed-\(DailyDate.stamp(for: typed, calendar: calendar))",
                                   title: DailyDate.longForm(typed, calendar: calendar),
                                   subtitle: "daily/" + DailyDate.filename(for: typed, calendar: calendar),
                                   snippet: nil,
                                   kind: .day(typed)))
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let existing = DailyFiles.stickyDates(in: folder, calendar: calendar)
            .reversed()
            .filter { date in
                guard !trimmed.isEmpty else { return true }
                let stamp = DailyDate.stamp(for: date, calendar: calendar)
                return stamp.contains(trimmed)
                    || DailyDate.longForm(date, calendar: calendar).lowercased().contains(trimmed)
            }
            .filter { date in
                !rows.contains { row in
                    if case .day(let typed) = row.kind { return calendar.isDate(typed, inSameDayAs: date) }
                    return false
                }
            }
            .prefix(40)

        rows.append(contentsOf: existing.map { date in
            PaletteRow(id: DailyDate.stamp(for: date, calendar: calendar),
                       title: DailyDate.longForm(date, calendar: calendar),
                       subtitle: "daily/" + DailyDate.filename(for: date, calendar: calendar),
                       snippet: nil,
                       kind: .day(date))
        })

        return rows
    }

    private func refreshIndex() {
        guard let index else { return }
        Task { @MainActor in
            await index.refreshIfNeeded()
            if isPresented { reload() }
        }
    }
}

/// Date entry for **Open Date…** — accepts what people actually type (§10.2).
enum PaletteDateInput {

    static func parse(_ raw: String, calendar: Calendar = .current, now: Date = Date()) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return calendar.startOfDay(for: now) }

        switch text {
        case "today": return calendar.startOfDay(for: now)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        default: break
        }

        if let iso = DailyDate.date(fromFilename: text, calendar: calendar) { return iso }

        // `8/19`, `8/19/26`, `8-19-2026`
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
        guard (2...3).contains(parts.count), let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }

        var year = calendar.component(.year, from: now)
        if parts.count == 3 {
            guard let typed = Int(parts[2]) else { return nil }
            year = typed < 100 ? 2000 + typed : typed
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}
