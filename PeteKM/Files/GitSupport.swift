//
//  GitSupport.swift
//  PeteKM
//
//  Git is optional and never required for capture (spec §6.3, §17.4).
//  Everything here degrades quietly: a Git failure must never block opening or
//  saving a Daily Sticky.
//

import Foundation

enum GitSupport {

    static func isRepository(_ folder: PeteKMFolder) -> Bool {
        FileWriting.isDirectory(folder.gitDirectory)
    }

    /// `git init` in the PeteKM folder. Returns false on any failure; the caller
    /// shows a plain notice and carries on.
    @discardableResult
    static func initializeRepository(at folder: PeteKMFolder) -> Bool {
        run(["init"], in: folder.root) != nil
    }

    /// Whether a usable `git` exists at all.
    static var isGitAvailable: Bool {
        run(["--version"], in: URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)) != nil
    }

    /// Name of the push remote, or nil when none is configured.
    static func remoteName(of folder: PeteKMFolder) -> String? {
        guard let output = run(["remote"], in: folder.root) else { return nil }
        return output.split(separator: "\n").first.map(String.init)
    }

    /// Add a push remote (sync spec §7). No validation, no auth, no repo creation.
    @discardableResult
    static func setRemote(_ url: String, in folder: PeteKMFolder) -> Bool {
        run(["remote", "add", "origin", url], in: folder.root) != nil
    }

    // MARK: - Sync (sync spec §4, §5)

    /// What a sync attempt did. Every case is survivable: capture never depends
    /// on any of this (§17.4, sync spec §6.6).
    enum SyncOutcome: Equatable {
        case gitUnavailable
        case notARepository
        case offline
        case noRemote
        case pullConflict
        case pushFailed
        case nothingToSync
        case synced

        /// Terse, no-apology notice (DESIGN §32). `editorName` is named, never
        /// hard-coded — only `pullConflict` uses it (sync spec §5.4).
        func notice(editorName: String) -> String {
            switch self {
            case .gitUnavailable: return "Git isn't available."
            case .notARepository: return "This PeteKM folder isn't a Git repository."
            case .offline: return "Saved locally. Couldn't reach GitHub."
            case .noRemote: return "Saved locally. No GitHub remote is set."
            case .pullConflict:
                return "Sync paused — the same note changed on two devices. Nothing was lost or changed. "
                     + "Ask PeteKM (in a terminal) to help sort it out, or open the folder in \(editorName) yourself."
            case .pushFailed: return "Saved and up to date locally, but couldn't publish to GitHub. Try Sync again."
            case .nothingToSync: return "Already up to date."
            case .synced: return "Synced."
            }
        }
    }

    /// `PeteKM backup 2026-08-19 20:45` (§17.2).
    static func commitMessage(for date: Date, calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "PeteKM backup \(formatter.string(from: date))"
    }

    /// How far the local branch has diverged from `@{upstream}`, or nil when
    /// there is no upstream to compare against (sync spec §5.1 step 4).
    static func aheadBehind(_ folder: PeteKMFolder) -> (ahead: Int, behind: Int)? {
        guard let output = run(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"], in: folder.root) else {
            return nil
        }
        let parts = output.split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) else { return nil }
        return (ahead, behind)
    }

    /// Commit, fetch, pull --rebase when behind, push (sync spec §5.1). Never
    /// force-pushes, never resolves a conflict: a conflicting rebase is aborted
    /// unconditionally and reported (§6.2–§6.4). Blocking — call it off the main actor.
    static func sync(_ folder: PeteKMFolder, now: Date = Date(), calendar: Calendar = .current) -> SyncOutcome {
        guard isGitAvailable else { return .gitUnavailable }
        guard isRepository(folder) else { return .notARepository }

        // 1. Commit first, before any network call (§6.1).
        run(["add", "-A"], in: folder.root)
        var didCommit = false
        if run(["status", "--porcelain"], in: folder.root)?.isEmpty == false {
            guard run(["commit", "-m", commitMessage(for: now, calendar: calendar)], in: folder.root) != nil else {
                // Deliberate mapping, not an oversight: §5.3 fixes the enum at eight
                // cases with no `commitFailed`. Stop here rather than take an
                // uncommitted tree into a pull; "Try Sync again." is the only one of
                // the eight notices that isn't actively false for a failed commit.
                return .pushFailed
            }
            didCommit = true
        }

        // 2. Network.
        guard run(["fetch"], in: folder.root) != nil else { return .offline }
        guard let remote = remoteName(of: folder) else { return .noRemote }

        let divergence = aheadBehind(folder)
        if let divergence, divergence.ahead == 0, divergence.behind == 0, !didCommit {
            return .nothingToSync
        }

        // 3. Pull only when behind, and abort the moment it conflicts (§6.4).
        if let divergence, divergence.behind > 0 {
            guard run(["pull", "--rebase", "--autostash"], in: folder.root) != nil else {
                run(["rebase", "--abort"], in: folder.root)
                return .pullConflict
            }
        }

        // 4. Push. No upstream yet on a fresh branch — set it once.
        let branch = run(["rev-parse", "--abbrev-ref", "HEAD"], in: folder.root)
        var arguments = ["push"]
        if let branch, branch != "HEAD", run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: folder.root) == nil {
            arguments += ["--set-upstream", remote, branch]
        }

        guard run(arguments, in: folder.root) != nil else { return .pushFailed }
        return .synced
    }

    /// Run a git subcommand, returning trimmed stdout, or nil if git is missing
    /// or exited non-zero.
    @discardableResult
    static func run(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
