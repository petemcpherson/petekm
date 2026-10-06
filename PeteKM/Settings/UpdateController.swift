//
//  UpdateController.swift
//  PeteKM
//
//  In-app updates (spec §20.2). Sparkle is the shipping mechanism: background
//  check, user-approved install, never an install without consent.
//
//  Sparkle is linked as a Swift package in release builds (see
//  `context/DISTRIBUTION.md`). Everything here is behind `canImport(Sparkle)`
//  so a checkout without the package still builds and runs — an update
//  mechanism must never be able to block capture (§17.4 in spirit).
//

import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class UpdateController {

    static let shared = UpdateController()

    /// Where appcasts come from. Empty in a source checkout; set by
    /// `SUFeedURL` in the built app's Info.plist.
    nonisolated static var feedURL: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    /// `1.0 (12)` — shown in Settings and About.
    nonisolated static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// Copy shown when updates can't run — plain, no apology (DESIGN §32).
    nonisolated static let unavailableNotice = "This build doesn't check for updates."

    /// Set when Sparkle is about to relaunch into an update, so that quit skips the
    /// unsent-notes alert (sync v2 §9.2).
    static var isRelaunchingForUpdate = false

#if canImport(Sparkle)
    private let relaunchObserver = RelaunchObserver()
    private let updaterController: SPUStandardUpdaterController

    var isAvailable: Bool { UpdateController.feedURL != nil }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Never auto-install: Sparkle downloads, the user approves (§20.2).
    var canCheckForUpdates: Bool { updaterController.updater.canCheckForUpdates }

    func checkForUpdates() {
        guard isAvailable else { return }
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.checkForUpdates(nil)
    }

    func lastCheckDescription() -> String? {
        updaterController.updater.lastUpdateCheckDate.map {
            "Last checked \($0.formatted(date: .abbreviated, time: .shortened))."
        }
    }
#else
    var isAvailable: Bool { false }
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }
    var canCheckForUpdates: Bool { false }
    func checkForUpdates() {}
    func lastCheckDescription() -> String? { nil }
#endif

    /// Called at launch so the stored preference and the updater agree.
    func apply(settings: AppSettings) {
        guard isAvailable else { return }
        automaticallyChecksForUpdates = settings.automaticUpdateChecks
    }

#if canImport(Sparkle)
    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: relaunchObserver,
            userDriverDelegate: nil
        )
    }
#else
    private init() {}
#endif
}

#if canImport(Sparkle)
/// Sparkle's will-relaunch callback, the one quit path that never shows the
/// unsent-notes alert because the app comes straight back.
nonisolated private final class RelaunchObserver: NSObject, SPUUpdaterDelegate {
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { UpdateController.isRelaunchingForUpdate = true }
    }
}
#endif
