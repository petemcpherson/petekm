//
//  UpdateSettingsView.swift
//  PeteKM
//
//  Update preferences (§18.10, §20.2). Checks happen in the background;
//  installing always needs the user's approval, and a check never gets in the
//  way of capture.
//

import SwiftUI

struct UpdateSettingsView: View {

    @Environment(AppSettings.self) private var settings

    private let updates = UpdateController.shared

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Updates") {
                if updates.isAvailable {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { settings.automaticUpdateChecks },
                        set: {
                            settings.automaticUpdateChecks = $0
                            updates.automaticallyChecksForUpdates = $0
                        }
                    ))
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                    Text(updates.lastCheckDescription() ?? "Updates install only after you approve them.")
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text(UpdateController.unavailableNotice)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            Section("Version") {
                Text(UpdateController.versionString)
                    .font(DS.Text.monoCaption)
                    .foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .settingsPane()
    }
}
