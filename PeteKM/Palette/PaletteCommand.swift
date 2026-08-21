//
//  PaletteCommand.swift
//  PeteKM
//
//  The command catalog (spec §10.2, DESIGN §12). External-tool and Git commands
//  arrive with Phase 6 — they are absent rather than dead, so the palette never
//  shows something that cannot happen.
//

import Foundation

enum PaletteCommandID: String, CaseIterable, Identifiable {
    case openDailySticky
    case openPreviousDailySticky
    case openDate
    case searchAllPeteKM
    case openLibraryFile
    case openLibraryIndex
    case reviewInbox
    case revealFolderInFinder
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
        case .reviewInbox: return "Review Inbox"
        case .revealFolderInFinder: return "Reveal PeteKM Folder in Finder"
        case .settings: return "Settings"
        }
    }

    var group: String {
        switch self {
        case .openDailySticky, .openPreviousDailySticky, .openDate: return "Daily Sticky"
        case .searchAllPeteKM, .openLibraryFile, .openLibraryIndex: return "Library"
        case .reviewInbox, .revealFolderInFinder, .settings: return "PeteKM"
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
}
