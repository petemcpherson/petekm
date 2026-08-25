//
//  SettingsView.swift
//  PeteKM
//
//  A normal macOS Settings window, not a custom dashboard (DESIGN §21).
//  Sections follow spec §18: folder, shortcut, Daily Start Behavior, default
//  headers, date heading, a small set of editor preferences, app behavior,
//  Git, agent-file refresh, updates. No AI settings anywhere (§18.8).
//

import AppKit
import SwiftUI

struct SettingsView: View {

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DailyStickySettingsView()
                .tabItem { Label("Daily Sticky", systemImage: "note.text") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "textformat") }
            FolderSettingsView()
                .tabItem { Label("Folder", systemImage: "folder") }
            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            GuideSettingsView()
                .tabItem { Label("Guide", systemImage: "book") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

struct GeneralSettingsView: View {

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
        }
        .formStyle(.grouped)
        .settingsPane()
    }
}

// MARK: - Daily Sticky

struct DailyStickySettingsView: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("New Day") {
                Picker("Daily Start Behavior", selection: $settings.dailyStartBehavior) {
                    ForEach(DailyStartBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Text(settings.dailyStartBehavior.detail)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)

                Toggle("Start each Daily Sticky with the date", isOn: $settings.showDateHeading)
                Text("An H1 like \"# August 20, 2026\" at the top of the file.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }

            Section("Default Headers") {
                TextEditor(text: $settings.defaultHeaders)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                Text("Plain Markdown. Used when Daily Start Behavior is \"Use default headers\".")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .settingsPane()
    }
}

// MARK: - Editor

struct EditorSettingsView: View {

    @Environment(AppSettings.self) private var settings

    /// Family names only, and only fonts that can actually render notes.
    private var fontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Text") {
                Picker("Font", selection: Binding(
                    get: { settings.editorFontName ?? "" },
                    set: { settings.editorFontName = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System").tag("")
                    Divider()
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                Picker("Size", selection: $settings.editorFontSize) {
                    ForEach(AppSettings.editorFontSizes, id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }

                Slider(value: $settings.editorLineSpacing, in: 0...12, step: 1) {
                    Text("Line spacing")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("12")
                }
            }

            Section("Behavior") {
                Toggle("Show table of contents", isOn: $settings.showTableOfContents)
                Toggle("Auto-close brackets and quotes", isOn: $settings.autoClosePairs)
                Toggle("Continue lists on Return", isOn: $settings.continueListMarkers)
                Text("Markdown markers stay visible while you type. PeteKM never hides syntax.")
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .settingsPane()
    }
}

// MARK: - Shared layout

private struct SettingsPane: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    func settingsPane() -> some View { modifier(SettingsPane()) }
}
