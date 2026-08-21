//
//  OnboardingView.swift
//  PeteKM
//
//  DESIGN.md §22: extremely short. Native controls, sentence case, no
//  methodology lessons, no exclamation marks.
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DS.Space.s8)

            Divider()

            footer
                .padding(.horizontal, DS.Space.s8)
                .padding(.vertical, DS.Space.s5)
        }
        .frame(width: 560, height: 460)
        .background(DS.Color.surfaceWindow)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .chooseFolder: chooseFolder
        case .structure: structure
        case .dailyPreference: dailyPreference
        case .claudeCode: claudeCode
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.s5) {
                PixelMark(size: 128)
                Wordmark(size: 26)
            }
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("A local second brain built around one simple idea: capture now, organize later.")
                    .font(DS.Text.title3)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Your notes never leave this Mac. They are plain Markdown files in a folder you choose.")
                    .font(DS.Text.body)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private var chooseFolder: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            header("Where should notes live?",
                   "PeteKM keeps your Daily Stickies, Library, and agent instructions here as normal files.")

            if let pending = model.pendingNewFolder {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Text("Name this folder")
                        .font(DS.Text.uiLabel)
                    TextField("PeteKM", text: Binding(
                        get: { pending.name },
                        set: { model.pendingNewFolder?.name = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .onSubmit { model.createPendingFolder() }

                    Text(pending.parent.path(percentEncoded: false))
                        .font(DS.Text.monoCaption)
                        .foregroundStyle(DS.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)

                    HStack(spacing: DS.Space.s4) {
                        Button("Create folder") { model.createPendingFolder() }
                            .buttonStyle(.borderedProminent)
                        Button("Choose a different location") { model.chooseParentForNewFolder() }
                        Button("Cancel") { model.pendingNewFolder = nil }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    Button("Create a new PeteKM folder…") { model.chooseParentForNewFolder() }
                        .buttonStyle(.borderedProminent)
                    Button("Use an existing folder…") { model.chooseExistingFolder() }
                }
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var structure: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            header(model.adoptedExistingFolder ? "Folder ready" : "Folder created",
                   model.adoptedExistingFolder
                   ? "PeteKM added only what was missing. Nothing existing was changed."
                   : "PeteKM created the structure it needs.")

            if let folder = model.folder {
                Text(folder.root.path(percentEncoded: false))
                    .font(DS.Text.monoCaption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            if let report = model.report {
                reportList(report)
            }

            Divider()

            VStack(alignment: .leading, spacing: DS.Space.s4) {
                Text("Version history")
                    .font(DS.Text.uiLabel)
                if model.isGitRepository {
                    Text("This folder is already a Git repository.")
                        .font(DS.Text.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                } else {
                    Text("Optional. PeteKM works the same either way.")
                        .font(DS.Text.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                    Button("Initialize Git here") { model.initializeGit() }
                }
                if let notice = model.gitNotice {
                    Text(notice)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    private var dailyPreference: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            header("How should each day start?",
                   "You can change this later in Settings.")

            Picker("", selection: Binding(
                get: { model.settingsRef.dailyStartBehavior },
                set: { model.settingsRef.dailyStartBehavior = $0 }
            )) {
                ForEach(DailyStartBehavior.allCases) { behavior in
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(behavior.title)
                        Text(behavior.detail)
                            .font(DS.Text.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .tag(behavior)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Global shortcut")
                    .font(DS.Text.uiLabel)
                Text("PeteKM has no shortcut until you set one. \(AppSettings.suggestedShortcut) is a safe suggestion.")
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DS.Space.s4) {
                    Button("Use \(AppSettings.suggestedShortcut)") {
                        model.settingsRef.globalShortcut = AppSettings.suggestedShortcut
                    }
                    .disabled(model.settingsRef.globalShortcut == AppSettings.suggestedShortcut)
                    Button("Set it later") {
                        model.settingsRef.globalShortcut = nil
                    }
                    .buttonStyle(.link)
                }
                if let shortcut = model.settingsRef.globalShortcut {
                    Text("Set to \(shortcut).")
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }

    private var claudeCode: some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            header("Use with Claude Code",
                   "Filing happens outside PeteKM. Open a terminal in your folder and run your agent there.")

            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("cd \(model.folder.map { shellQuoted($0.root.path(percentEncoded: false)) } ?? "your-folder")\nclaude")
                    .font(DS.Text.mono)
                    .textSelection(.enabled)
                    .padding(DS.Space.s5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Color.surfaceSunken)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(DS.Color.borderHairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))

                Text("The folder describes itself. `CLAUDE.md`, `AGENTS.md`, and the `/petekm-*` skills are already there, so there is no setup prompt to paste.")
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Daily Stickies are read-only to any agent. Only the Library changes.")
                    .font(DS.Text.callout)
                    .foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    // MARK: - Pieces

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text(title)
                .font(DS.Text.title1)
                .foregroundStyle(DS.Color.textPrimary)
            Text(detail)
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reportList(_ report: FolderInitializer.Report) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                ForEach(report.created, id: \.self) { path in
                    reportRow(path, label: "created", tone: DS.Color.textSecondary)
                }
                ForEach(report.kept, id: \.self) { path in
                    reportRow(path, label: "kept", tone: DS.Color.textTertiary)
                }
                ForEach(report.failed, id: \.self) { path in
                    reportRow(path, label: "skipped", tone: DS.Color.warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
        }
        .frame(maxHeight: 150)
        .background(DS.Color.surfaceSunken)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.borderHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func reportRow(_ path: String, label: String, tone: Color) -> some View {
        HStack(spacing: DS.Space.s4) {
            Text(path)
                .font(DS.Text.monoCaption)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: DS.Space.s4)
            Text(label)
                .font(DS.Text.caption)
                .foregroundStyle(tone)
        }
    }

    private var footer: some View {
        HStack {
            if model.step != .welcome && model.step != .structure {
                Button("Back") { model.back() }
                    .buttonStyle(.link)
            }
            Spacer()
            switch model.step {
            case .welcome:
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .chooseFolder:
                EmptyView()
            case .structure, .dailyPreference:
                Button("Continue") { model.advance() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .claudeCode:
                Button("Open Daily Sticky") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func shellQuoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }
}
