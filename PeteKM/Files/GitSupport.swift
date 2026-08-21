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

    // MARK: - Git Sync (§17.2)

    /// What a sync attempt did. Every case is survivable: capture never depends
    /// on any of this (§17.4).
    enum SyncOutcome: Equatable {
        case gitUnavailable
        case notARepository
        case nothingToCommit
        case pushed
        case committedNotPushed(reason: PushSkipReason)
        case commitFailed

        enum PushSkipReason: Equatable {
            case noRemote
            case pushFailed
        }

        /// Terse, no-apology notice (DESIGN §32).
        var notice: String {
            switch self {
            case .gitUnavailable: return "Git isn't available."
            case .notARepository: return "This PeteKM folder isn't a Git repository."
            case .nothingToCommit: return "Nothing to commit."
            case .pushed: return "Committed and pushed."
            case .committedNotPushed(.noRemote): return "Committed locally. No Git remote set."
            case .committedNotPushed(.pushFailed): return "Committed locally. Push failed — resolve in a Git tool."
            case .commitFailed: return "Git commit failed."
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

    /// Commit everything, then push. One-way by design: the app never pulls,
    /// merges, or rebases (§17.2). Blocking — call it off the main actor.
    static func sync(_ folder: PeteKMFolder, now: Date = Date(), calendar: Calendar = .current) -> SyncOutcome {
        guard isGitAvailable else { return .gitUnavailable }
        guard isRepository(folder) else { return .notARepository }

        run(["add", "-A"], in: folder.root)

        let dirty = run(["status", "--porcelain"], in: folder.root)?.isEmpty == false
        if dirty {
            guard run(["commit", "-m", commitMessage(for: now, calendar: calendar)], in: folder.root) != nil else {
                return .commitFailed
            }
        }

        guard let remote = remoteName(of: folder) else {
            return dirty ? .committedNotPushed(reason: .noRemote) : .nothingToCommit
        }

        // No upstream yet on a fresh branch — set it once, still never pulling.
        let branch = run(["rev-parse", "--abbrev-ref", "HEAD"], in: folder.root)
        var arguments = ["push"]
        if let branch, branch != "HEAD", run(["rev-parse", "--abbrev-ref", "@{upstream}"], in: folder.root) == nil {
            arguments += ["--set-upstream", remote, branch]
        }

        guard run(arguments, in: folder.root) != nil else {
            return .committedNotPushed(reason: .pushFailed)
        }
        // Pushing a clean tree is a no-op in the ordinary case; say what changed.
        return dirty ? .pushed : .nothingToCommit
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
