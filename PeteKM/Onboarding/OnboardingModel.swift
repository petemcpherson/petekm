//
//  OnboardingModel.swift
//  PeteKM
//
//  First-run flow (spec §6, DESIGN.md §22). Short: pick a folder, create the
//  structure, choose how days start, hand off to the agent, then point at the
//  empty Library before opening the Daily Sticky.
//

import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class OnboardingModel {

    enum Step: Int, CaseIterable {
        case welcome
        case chooseFolder
        case structure
        case dailyPreference
        case claudeCode
        /// The `/petekm-*` commands, explained once. The app never runs them; this
        /// step is the only place they are introduced before the folder is handed over.
        case skills
        /// Last step. Purely a suggestion: shape `library/` and import existing
        /// notes now, while the folder is still empty. The app creates nothing
        /// here — no folder system is imposed (§6.2).
        case setUpLibrary
    }

    /// Sub-state of the folder step: the user is naming a new folder inside a
    /// parent they just picked (§6.1).
    struct PendingNewFolder: Equatable {
        var parent: URL
        var name: String
    }

    private let folderStore: FolderStore
    private let settings: AppSettings

    var step: Step = .welcome
    var pendingNewFolder: PendingNewFolder?
    var report: FolderInitializer.Report?
    var adoptedExistingFolder = false
    var errorMessage: String?
    var gitNotice: String?
    /// Terse result of a hand-off button on the last step. Never blocks (§15.3).
    var toolNotice: String?

    init(folderStore: FolderStore, settings: AppSettings) {
        self.folderStore = folderStore
        self.settings = settings
    }

    var folder: PeteKMFolder? { folderStore.folder }

    var settingsRef: AppSettings { settings }

    var isGitRepository: Bool {
        guard let folder else { return false }
        return GitSupport.isRepository(folder)
    }

    // MARK: - Library hand-off (last step)

    private var editor: ExternalEditor { ExternalEditorProvider.current }

    var editorName: String { editor.displayName }

    var isEditorAvailable: Bool { editor.isAvailable }

    func revealFolderInFinder() {
        guard let folder else { return }
        toolNotice = nil
        ExternalTools.revealInFinder(folder.root)
    }

    func openFolderInEditor() {
        guard let folder else { return }
        toolNotice = editor.open(folder: folder.root) ? nil : editor.unavailableNotice
    }

    func openTerminalAtFolder() {
        guard let folder else { return }
        toolNotice = ExternalTools.openTerminal(at: folder.root)
            ? nil
            : ExternalTools.terminalUnavailableNotice
    }

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func finish() {
        settings.hasCompletedOnboarding = true
    }

    // MARK: - Folder choice (§6.1)

    func chooseParentForNewFolder() {
        guard let parent = presentFolderPanel(
            title: "Where should notes live?",
            prompt: "Choose"
        ) else { return }
        pendingNewFolder = PendingNewFolder(parent: parent, name: "PeteKM")
        errorMessage = nil
    }

    func createPendingFolder() {
        guard let pending = pendingNewFolder else { return }
        let trimmed = pending.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else {
            errorMessage = "That folder name won't work. Use a plain name with no slashes."
            return
        }

        let url = pending.parent.appending(path: trimmed, directoryHint: .isDirectory)
        if FileWriting.exists(url) {
            errorMessage = "\(trimmed) already exists there. Choose a different name, or use it as an existing folder."
            return
        }

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            errorMessage = "PeteKM couldn't create a folder there. Pick a different location."
            return
        }

        adoptedExistingFolder = false
        adopt(url)
    }

    /// Replaying onboarding from Settings with a folder already set: keep it rather
    /// than making the user re-pick their own folder. Runs the same `.keep` adoption,
    /// so nothing on disk is overwritten (§19.2).
    func keepCurrentFolder() {
        guard let folder = folderStore.folder else { return }
        adoptedExistingFolder = true
        adopt(folder.root)
    }

    func chooseExistingFolder() {
        guard let url = presentFolderPanel(
            title: "Choose your PeteKM folder",
            prompt: "Use Folder"
        ) else { return }

        guard FolderStore.isReachable(url) else {
            errorMessage = "That folder isn't writable."
            return
        }

        adoptedExistingFolder = PeteKMFolder(root: url).looksInitialized
        adopt(url)
    }

    // MARK: - Git (§6.3)

    func initializeGit() {
        guard let folder else { return }
        if GitSupport.initializeRepository(at: folder) {
            gitNotice = "Git repository created."
        } else {
            gitNotice = "Git isn't available. PeteKM works the same without it."
        }
    }

    // MARK: - Private

    private func adopt(_ url: URL) {
        folderStore.setFolder(url)
        guard let folder = folderStore.folder else {
            errorMessage = "PeteKM couldn't open that folder."
            return
        }

        do {
            // Adoption never overwrites: existing files are left exactly as
            // they are (§19.2).
            report = try FolderInitializer.initialize(folder, policy: .keep)
            errorMessage = nil
            step = .structure
        } catch {
            errorMessage = "PeteKM couldn't set up that folder. Check that it's writable."
        }
    }

    private func presentFolderPanel(title: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = title
        panel.prompt = prompt
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.standardizedFileURL
    }
}
