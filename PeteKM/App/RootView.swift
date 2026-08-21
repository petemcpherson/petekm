//
//  RootView.swift
//  PeteKM
//
//  Decides what the window shows: onboarding, the missing-folder panel
//  (spec §19.6), or the Daily Sticky.
//

import SwiftUI
import AppKit

struct RootView: View {
    @Environment(FolderStore.self) private var folderStore
    @Environment(AppSettings.self) private var settings

    @State private var onboarding: OnboardingModel?

    var body: some View {
        Group {
            switch folderStore.state {
            case .missing(let path):
                MissingFolderView(
                    lastKnownPath: path,
                    onLocate: { folderStore.setFolder($0) },
                    onReonboard: {
                        onboarding = nil
                        settings.hasCompletedOnboarding = false
                        folderStore.clear()
                    }
                )

            case .unset:
                onboardingView

            case .ready(let folder):
                if settings.hasCompletedOnboarding {
                    DailyStickyPlaceholder(folder: folder)
                } else {
                    onboardingView
                }
            }
        }
        .onAppear { folderStore.revalidate() }
    }

    @ViewBuilder
    private var onboardingView: some View {
        if let onboarding {
            OnboardingView(model: onboarding)
        } else {
            Color.clear
                .onAppear {
                    onboarding = OnboardingModel(folderStore: folderStore, settings: settings)
                }
        }
    }
}

/// Stand-in until the Daily Sticky editor lands. It shows where the notes are
/// and gets out of the way.
struct DailyStickyPlaceholder: View {
    let folder: PeteKMFolder

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            HStack(spacing: DS.Space.s5) {
                PixelMark(size: 32)
                Text(folder.name)
                    .font(DS.Text.title2)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            Text(folder.root.path(percentEncoded: false))
                .font(DS.Text.monoCaption)
                .foregroundStyle(DS.Color.textSecondary)
                .textSelection(.enabled)
            Text("The editor arrives in the next build. Your folder is ready for Claude Code now.")
                .font(DS.Text.body)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder.root])
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s8)
        .frame(minWidth: 420, minHeight: 260, alignment: .topLeading)
        .background(DS.Color.surfaceWindow)
    }
}
