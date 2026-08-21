import AppKit
import SwiftUI

/// Phase 4 slice of Settings: the global shortcut and window/app behavior (§18.2, §18.6).
/// The full Settings surface (folder, editor, daily start, Git) arrives with Phase 7.
struct SettingsView: View {

    @Environment(FolderStore.self) private var folderStore
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Global Shortcut") {
                ShortcutRecorder(combo: $settings.globalShortcut)
                Text(settings.globalShortcut == nil
                     ? "No shortcut set. \(AppSettings.suggestedShortcut.displayString) is a safe suggestion."
                     : "Press it anywhere to show PeteKM. Press it again to hide.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
                if settings.globalShortcut == nil {
                    Button("Use \(AppSettings.suggestedShortcut.displayString)") {
                        settings.globalShortcut = AppSettings.suggestedShortcut
                    }
                }
            }

            Section("Window") {
                Toggle("Float above other apps", isOn: $settings.floatOnTop)
            }

            Section("App") {
                Toggle("Hide Dock icon", isOn: $settings.hideDockIcon)
                Toggle("Hide menu bar item", isOn: $settings.hideMenuBarItem)
                    .disabled(settings.hideDockIcon)
                Text("The Dock icon and the menu bar item can't both be hidden.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Section("PeteKM Folder") {
                Text(folderStore.lastKnownPath ?? "No folder set.")
                    .font(DS.Text.monoCaption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
            }

            if case .ready(let folder) = folderStore.state {
                GitSettingsSection(folder: folder)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Git stays optional (§17.1). Nothing here can block capture: the worst case
/// is a line of text saying what didn't happen.
private struct GitSettingsSection: View {

    let folder: PeteKMFolder

    @State private var isRepository = false
    @State private var remote: String?
    @State private var status: String?
    @State private var isWorking = false

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
                Button("Git Sync") { sync() }
                    .disabled(isWorking)
                Text("Commits everything, then pushes. PeteKM never pulls, merges, or rebases.")
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

    private func sync() {
        isWorking = true
        let folder = folder
        Task {
            let outcome = await Task.detached(priority: .utility) {
                GitSupport.sync(folder)
            }.value
            status = outcome.notice
            isWorking = false
            refresh()
        }
    }
}
