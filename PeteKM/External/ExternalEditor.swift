//
//  ExternalEditor.swift
//  PeteKM
//
//  The filesystem is the shared interface, so opening the folder in a real
//  editor is a first-class action (spec §12). VS Code is the default, not a
//  hard-coded dependency (§18.7): everything goes through `ExternalEditor`, and
//  every call reports failure so the caller can show a plain notice instead of
//  blocking capture.
//

import AppKit
import Foundation

/// What the app needs from an external editor. A future setting swaps the
/// implementation; nothing above this protocol knows about VS Code.
protocol ExternalEditor: Sendable {
    var displayName: String { get }
    var isAvailable: Bool { get }

    /// Open a folder as the editor's workspace.
    @discardableResult
    func open(folder: URL) -> Bool

    /// Open `file` with `folder` as the surrounding workspace, so search and the
    /// file tree work from the PeteKM root (§12.3).
    @discardableResult
    func open(file: URL, in folder: URL) -> Bool
}

extension ExternalEditor {
    /// Copy for the failure notice — "PeteKM couldn't open VS Code." (DESIGN §32).
    var unavailableNotice: String { "PeteKM couldn't open \(displayName)." }
}

/// The single place that decides which editor the app uses. VS Code today
/// (§18.7); a Settings picker would replace the body and nothing else.
enum ExternalEditorProvider {
    static let current: ExternalEditor = VSCodeEditor()
}

/// VS Code via its `code` CLI when installed, otherwise by launching the app
/// bundle with the URLs. Both paths tolerate the other being absent.
struct VSCodeEditor: ExternalEditor {

    let displayName = "VS Code"

    /// Bundle identifiers tried in order — stable VS Code, Insiders, VSCodium.
    static let bundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
    ]

    /// `code` locations outside a bundle. Inside a bundle the CLI is found
    /// relative to `applicationURL`.
    static let cliSearchPaths = [
        "/usr/local/bin/code",
        "/opt/homebrew/bin/code",
    ]

    var isAvailable: Bool { applicationURL != nil || commandLineTool != nil }

    // MARK: - Locating VS Code

    var applicationURL: URL? {
        for identifier in Self.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }

    var commandLineTool: URL? {
        var candidates = Self.cliSearchPaths.map { URL(filePath: $0) }
        if let applicationURL {
            candidates.append(applicationURL.appending(path: "Contents/Resources/app/bin/code"))
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    // MARK: - Opening

    @discardableResult
    func open(folder: URL) -> Bool {
        if let cli = commandLineTool, run(cli, ["--new-window", folder.path(percentEncoded: false)]) {
            return true
        }
        return launchApp(with: [folder])
    }

    @discardableResult
    func open(file: URL, in folder: URL) -> Bool {
        // `-g` lands on the file with the folder still open as the workspace.
        if let cli = commandLineTool,
           run(cli, [folder.path(percentEncoded: false), "-g", file.path(percentEncoded: false)]) {
            return true
        }
        return launchApp(with: [folder, file])
    }

    private func launchApp(with urls: [URL]) -> Bool {
        guard let applicationURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration)
        return true
    }

    /// Launch the CLI without waiting on it — VS Code keeps running, and a slow
    /// editor must never stall the capture window.
    private func run(_ tool: URL, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
