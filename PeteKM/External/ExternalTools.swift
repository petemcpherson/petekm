//
//  ExternalTools.swift
//  PeteKM
//
//  Terminal and Finder (spec §10.2, §15.1). "Open Terminal in PeteKM Folder"
//  launches Terminal.app at the folder root and nothing more — the app never
//  runs an agent, watches one, or reads its output (§15).
//

import AppKit
import Foundation

enum ExternalTools {

    static let terminalBundleIdentifier = "com.apple.Terminal"

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens a Terminal window whose working directory is `folder`. Returns
    /// false when Terminal.app can't be found; the caller shows a notice.
    @discardableResult
    static func openTerminal(at folder: URL) -> Bool {
        guard let terminal = terminalApplicationURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: configuration)
        return true
    }

    static var terminalApplicationURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleIdentifier) {
            return url
        }
        let fallback = URL(filePath: "/System/Applications/Utilities/Terminal.app", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: fallback.path(percentEncoded: false)) ? fallback : nil
    }

    static let terminalUnavailableNotice = "PeteKM couldn't open Terminal."
}
