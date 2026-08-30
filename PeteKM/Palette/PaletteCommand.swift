//
//  PaletteCommand.swift
//  PeteKM
//
//  The command catalog (spec §10.2, DESIGN §12). Commands are absent rather
//  than dead, so the palette never shows something that cannot happen: Git Sync
//  appears only in a repository, the VS Code commands only when VS Code exists.
//

import Foundation

enum PaletteCommandID: String, CaseIterable, Identifiable {
    case openDailySticky
    case openPreviousDailySticky
    case openDate
    case openScratch
    case searchAllPeteKM
    case openLibraryFile
    case openLibraryIndex
    case openLibraryInEditor
    case openFolderInEditor
    case openCurrentFileInEditor
    case reviewInbox
    case openTerminal
    case revealFolderInFinder
    case gitSync
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openDailySticky: return "Open Daily Sticky"
        case .openPreviousDailySticky: return "Open Previous Daily Sticky"
        case .openDate: return "Open Date…"
        case .openScratch: return "Open Scratch"
        case .searchAllPeteKM: return "Search All PeteKM…"
        case .openLibraryFile: return "Open Library File…"
        case .openLibraryIndex: return "Open Library Index"
        case .openLibraryInEditor: return "Open Library in \(PaletteCommandID.editorName)"
        case .openFolderInEditor: return "Open PeteKM Folder in \(PaletteCommandID.editorName)"
        case .openCurrentFileInEditor: return "Open Current File in \(PaletteCommandID.editorName)"
        case .reviewInbox: return "Review Inbox"
        case .openTerminal: return "Open Terminal in PeteKM Folder"
        case .revealFolderInFinder: return "Reveal PeteKM Folder in Finder"
        case .gitSync: return "Git Sync"
        case .settings: return "Settings"
        }
    }

    /// Named, not hard-coded: a future setting changes the editor without
    /// touching the catalog (§18.7).
    static var editorName: String { ExternalEditorProvider.current.displayName }

    /// One plain sentence per command, shown under the title in the palette so the
    /// full catalog explains itself without a manual (DESIGN §2 tone: terse).
    var explainer: String {
        switch self {
        case .openDailySticky: return "Jump back to today's capture."
        case .openPreviousDailySticky: return "Open the most recent earlier day."
        case .openDate: return "Open a past day by date, like 2026-08-19 or \"last friday\"."
        case .openScratch: return "The pane under the editor. Carries over day to day; never filed, never committed."
        case .searchAllPeteKM: return "Full-text search across Daily Stickies and the Library."
        case .openLibraryFile: return "Open a Library file by name."
        case .openLibraryIndex: return "Open INDEX.md — the map of the Library and where things get filed."
        case .openLibraryInEditor: return "Open the library/ folder in \(PaletteCommandID.editorName)."
        case .openFolderInEditor: return "Open the whole PeteKM folder in \(PaletteCommandID.editorName)."
        case .openCurrentFileInEditor: return "Open the file you are looking at in \(PaletteCommandID.editorName)."
        case .reviewInbox: return "Open INBOX.md — items the filing agent could not place."
        case .openTerminal: return "Open Terminal at the folder root. Run your AI agent from there to file notes."
        case .revealFolderInFinder: return "Show the PeteKM folder in Finder."
        case .gitSync: return "Commit everything and push. Never pulls or merges."
        case .settings: return "Folder, shortcut, editor, and update preferences."
        }
    }

    var group: String {
        switch self {
        case .openDailySticky, .openPreviousDailySticky, .openDate, .openScratch: return "Daily Sticky"
        case .searchAllPeteKM, .openLibraryFile, .openLibraryIndex, .openLibraryInEditor: return "Library"
        case .openFolderInEditor, .openCurrentFileInEditor, .openTerminal, .revealFolderInFinder: return "External"
        case .reviewInbox, .gitSync, .settings: return "PeteKM"
        }
    }
}

/// What the palette hands back to the window when a row is chosen.
enum PaletteOutcome: Equatable {
    case openToday
    case openDaily(Date)
    case openScratch
    /// Any Markdown file in the folder, optionally with a range to jump to (§11.4, §30).
    case openFile(URL, reveal: NSRange?)
    case revealFolderInFinder
    case openSettings

    // Phase 6 — external tools (§12, §15.1, §17). Each degrades to a notice.
    /// Open a path in the external editor, with the PeteKM folder as workspace.
    case openInEditor(URL)
    /// Whatever Daily Sticky or Library file is on screen right now (§12.3).
    case openCurrentFileInEditor
    case openTerminalInFolder
    case gitSync
}
