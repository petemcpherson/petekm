//
//  OnboardingModel.swift
//  PeteKM
//
//  First-run flow (spec §6, DESIGN.md §22). Short: pick a folder, create the
//  structure, choose how days start, open the Daily Sticky.
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
