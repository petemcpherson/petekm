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
                    DailyStickyView(folder: folder)
                        .id(folder)
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