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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
