//
//  FolderInitializer.swift
//  PeteKM
//
//  Creates the standard PeteKM folder structure (spec §6.2) without ever
//  silently overwriting an existing file (§19.2).
//

import Foundation

enum FolderInitializer {

    /// What to do when a managed file already exists on disk.
    enum ExistingFilePolicy {
        /// Onboarding and adoption: leave it exactly as it is.
        case keep
        /// Refresh Agent Files (§6.5): back the differing file up, then write the
        /// current template. Identical files are left alone.
        case backUpThenReplace
    }

    struct Report: Equatable {
        var created: [String] = []
        var kept: [String] = []
        var backedUp: [String] = []
        var failed: [String] = []

        var isEmpty: Bool { created.isEmpty && kept.isEmpty && backedUp.isEmpty && failed.isEmpty }

        /// One terse line for the UI — counts, no congratulations (DESIGN §39).
        var summary: String {
            var parts: [String] = []
            if !created.isEmpty { parts.append("Wrote \(created.count).") }
            if !backedUp.isEmpty { parts.append("Backed up \(backedUp.count).") }
            if !failed.isEmpty { parts.append("Couldn't write \(failed.count).") }
            return parts.isEmpty ? "Already up to date." : parts.joined(separator: " ")
        }
    }

    /// Create everything a PeteKM folder needs. Safe to run against a folder
    /// that is already set up.
    @discardableResult
    static func initialize(
        _ folder: PeteKMFolder,
        policy: ExistingFilePolicy = .keep,
        now: Date = Date()
    ) throws -> Report {
        var report = Report()

        try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)

        for directory in [folder.daily, folder.library, folder.claude, folder.skills] {
            let relative = relativePath(of: directory, in: folder)
            if FileWriting.isDirectory(directory) {
                report.kept.append(relative)
            } else if FileWriting.exists(directory) {
                // A *file* named `daily` or `library` is a real problem; never
                // clobber it, just report it.
                report.failed.append(relative)
            } else {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    report.created.append(relative)
                } catch {
                    report.failed.append(relative)
                }
            }
        }

        var items: [(URL, String, Bool)] = [
            (folder.claudeMd, AgentTemplates.claudeMd, true),
            (folder.agentsMd, AgentTemplates.agentsMd, true),
            (folder.index, AgentTemplates.index, false),
            (folder.gitignore, AgentTemplates.gitignore, false),
            (folder.state, AgentTemplates.state, false),
        ]
        for name in AgentTemplates.skillNames {
            items.append((folder.skill(name), AgentTemplates.skill(name), true))
        }

        for (url, contents, isTemplate) in items {
            // `policy` only ever applies to the agent-file templates. INDEX.md,
            // .gitignore, and state are user/agent data and are never replaced.
            let effectivePolicy: ExistingFilePolicy = isTemplate ? policy : .keep
            write(contents, to: url, in: folder, policy: effectivePolicy, now: now, into: &report)
        }

        return report
    }

    /// Rewrite just the agent-file templates, backing up anything that differs
    /// (§6.5). `INDEX.md`, `INBOX.md`, and knowledge files are never touched.
    @discardableResult
    static func refreshAgentFiles(_ folder: PeteKMFolder, now: Date = Date()) throws -> Report {
        var report = Report()

        for directory in [folder.claude, folder.skills] where !FileWriting.isDirectory(directory) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            report.created.append(relativePath(of: directory, in: folder))
        }

        write(AgentTemplates.claudeMd, to: folder.claudeMd, in: folder,
              policy: .backUpThenReplace, now: now, into: &report)
        write(AgentTemplates.agentsMd, to: folder.agentsMd, in: folder,
              policy: .backUpThenReplace, now: now, into: &report)
        for name in AgentTemplates.skillNames {
            write(AgentTemplates.skill(name), to: folder.skill(name), in: folder,
                  policy: .backUpThenReplace, now: now, into: &report)
        }

        return report
    }

    // MARK: - Private

    private static func write(
        _ contents: String,
        to url: URL,
        in folder: PeteKMFolder,
        policy: ExistingFilePolicy,
        now: Date,
        into report: inout Report
    ) {
        let relative = relativePath(of: url, in: folder)

        if FileWriting.exists(url) {
            switch policy {
            case .keep:
                report.kept.append(relative)
                return
            case .backUpThenReplace:
                if FileWriting.readText(url) == contents {
                    report.kept.append(relative)
                    return
                }
                do {
                    try FileWriting.backUp(url, on: now)
                    report.backedUp.append(relative)
                } catch {
                    report.failed.append(relative)
                    return
                }
            }
        }

        do {
            try FileWriting.writeAtomically(contents, to: url)
            report.created.append(relative)
        } catch {
            report.failed.append(relative)
        }
    }

    private static func relativePath(of url: URL, in folder: PeteKMFolder) -> String {
        let root = folder.root.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.hasSuffix("/") ? root.count : root.count + 1))
    }
}
