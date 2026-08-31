//
//  SyncLaunchCheck.swift
//  PeteKM
//
//  The passive launch check (sync spec §4.3): once per app process, ask Git
//  whether this device has drifted from GitHub and, if so, show one dismissible
//  banner. It may never produce an error state — no git, not a repository, no
//  upstream, or an unreachable remote are all silent.
//

import Foundation
import Observation

@MainActor
@Observable
final class SyncLaunchCheck {

    /// True while the "Changes to sync." banner should be on screen.
    private(set) var showsBanner = false

    /// Once per process, not once per view: the Daily Sticky view can be rebuilt
    /// at any time, and a re-summon must not re-run the check.
    private(set) var hasRun = false

    /// The decision itself, split out so it is testable without a repository,
    /// a remote, or a network.
    nonisolated static func shouldPrompt(aheadBehind: (ahead: Int, behind: Int)?) -> Bool {
        guard let counts = aheadBehind else { return false }
        return counts.ahead > 0 || counts.behind > 0
    }

    /// Fetch and compare, off the main actor. Every failure means "show nothing".
    func runIfNeeded(folder: PeteKMFolder) {
        guard !hasRun else { return }
        hasRun = true

        Task {
            let counts = await Task.detached(priority: .utility) { () -> (ahead: Int, behind: Int)? in
                guard GitSupport.isGitAvailable, GitSupport.isRepository(folder) else { return nil }
                guard GitSupport.run(["fetch"], in: folder.root) != nil else { return nil }
                return GitSupport.aheadBehind(folder)
            }.value

            showsBanner = SyncLaunchCheck.shouldPrompt(aheadBehind: counts)
        }
    }

    /// Dismissed, or Sync ran: gone for the rest of the session. Because the
    /// check runs once per process there is no reappearance path to guard.
    func dismiss() {
        showsBanner = false
    }
}
