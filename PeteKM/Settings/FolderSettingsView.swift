//
//  FolderSettingsView.swift
//  PeteKM
//
//  Folder location (§18.1), Refresh Agent Files (§6.5) and Git (§18.9).
//  Changing the folder is deliberate: it asks first, and nothing on disk is
//  moved, copied, or deleted — both folders stay exactly as they are.
//

import AppKit
import SwiftUI

struct FolderSettingsView: View {

    @Environment(FolderStore.self) private var folderStore
    @Environment(AppSettings.self) private var settings

    @State private var notice: String?

    var body: some View {
        Form {
            Section("PeteKM Folder") {
                Text(folderStore.lastKnownPath ?? "No folder set.")
                    .font(DS.Text.monoCaption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Change Folder…") { changeFolder() }
                    Button("Reveal in Finder") { reveal() }
                        .disabled(folderStore.folder == nil)
                }
                Text("Changing the folder only changes what PeteKM opens. No files are moved or deleted.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            if case .ready(let folder) = folderStore.state {
                AgentFilesSection(folder: folder)
                GitSettingsSection(folder: folder)
            }

            if let notice {
                Section {
                    Text(notice)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsPane()
    }

    // MARK: - Actions

    private func reveal() {
        guard let folder = folderStore.folder else { return }
        ExternalTools.revealInFinder(folder.root)
    }

    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder PeteKM should open."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard confirmChange(to: url) else { return }

        folderStore.setFolder(url)
        guard let folder = folderStore.folder else {
            notice = "PeteKM couldn't open that folder."
            return
        }

        // Adoption never overwrites: missing pieces are created, existing files
        // are left exactly as they are (§19.2).
        do {
            let report = try FolderInitializer.initialize(folder)
            settings.hasCompletedOnboarding = true
            notice = report.created.isEmpty
                ? "PeteKM folder changed."
                : "PeteKM folder changed. Added \(report.created.count) missing \(report.created.count == 1 ? "file" : "files")."
        } catch {
            notice = "PeteKM folder changed, but setup files couldn't be written."
        }
    }

    private func confirmChange(to url: URL) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Use this folder as your PeteKM folder?"
        alert.informativeText = """
        \(url.path(percentEncoded: false))

        Nothing is moved or deleted. Your current folder stays where it is. \
        Missing PeteKM files are created in the new folder; existing files are left alone.
        """
        alert.addButton(withTitle: "Use Folder")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Refresh Agent Files (§6.5)

private struct AgentFilesSection: View {

    let folder: PeteKMFolder

    @State private var status: String?

    var body: some View {
        Section("Agent Files") {
            Button("Refresh Agent Files") { refresh() }
            Text("Rewrites CLAUDE.md, AGENTS.md, and the PeteKM skills. Anything different is backed up first. Your notes aren't touched.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Color.textSecondary)

            if let status {
                Text(status)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private func refresh() {
        guard confirm() else { return }
        do {
            status = try FolderInitializer.refreshAgentFiles(folder).summary
        } catch {
            status = "Couldn't write the agent files."
        }
    }

    private func confirm() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Refresh agent files?"
        alert.informativeText = """
        CLAUDE.md, AGENTS.md, and the PeteKM skills are rewritten from this version of the app. \
        Any file that differs is backed up alongside it first.
        """
        alert.addButton(withTitle: "Refresh")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Git (§18.9)

private struct GitSettingsSection: View {

    let folder: PeteKMFolder

    @State private var isRepository = false
    @State private var remote: String?
    @State private var status: String?
    @State private var isWorking = false
    @State private var remoteURL = ""

    var body: some View {
        Section("Git") {
            if !GitSupport.isGitAvailable {
                Text("Git isn't available.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            } else if isRepository {
                Text(remote.map { "Remote: \($0)" } ?? "No Git remote set.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                if remote == nil {
                    TextField("GitHub URL", text: $remoteURL)
                    Button("Set Remote") { setRemote() }
                        .disabled(isWorking || remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("Sync") { sync() }
                    .disabled(isWorking)
                Text("Saves your notes, then syncs with GitHub. Never overwrites anything — if the same note changed on two devices, it stops and tells you.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            } else {
                Text("This PeteKM folder isn't a Git repository.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                Button("Initialize Repository") { initialize() }
                    .disabled(isWorking)
            }

            if let status {
                Text(status)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        isRepository = GitSupport.isRepository(folder)
        remote = isRepository ? GitSupport.remoteName(of: folder) : nil
    }

    private func initialize() {
        isWorking = true
        let folder = folder
        Task {
            let ok = await Task.detached(priority: .utility) {
                GitSupport.initializeRepository(at: folder)
            }.value
            status = ok ? "Repository initialized." : "Git init failed."
            isWorking = false
            refresh()
        }
    }

    private func setRemote() {
        isWorking = true
        let folder = folder
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await Task.detached(priority: .utility) {
                GitSupport.setRemote(url, in: folder)
            }.value
            status = ok ? nil : "Couldn't add that remote — check the URL."
            if ok { remoteURL = "" }
            isWorking = false
            refresh()
        }
    }

    private func sync() {
        isWorking = true
        let folder = folder
        let editorName = ExternalEditorProvider.current.displayName
        Task {
            // No session is reachable from Settings, so no flush or reconcile:
            // the open sticky's autosave and directory watcher cover both.
            let run = await Task.detached(priority: .utility) {
                await GitSupport.run(folder, context: GitSupport.SyncContext())
            }.value
            status = run.outcome.manualNotice(editorName: editorName)
            isWorking = false
            refresh()
        }
    }
}
