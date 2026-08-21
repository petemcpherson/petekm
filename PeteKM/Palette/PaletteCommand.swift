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

    var group: String {
        switch self {
        case .openDailySticky, .openPreviousDailySticky, .openDate: return "Daily Sticky"
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
