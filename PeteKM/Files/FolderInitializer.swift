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

        // An adopted folder keeps its own `.gitignore`; it still has to exclude Scratch.
        if ensureScratchIgnored(folder), !report.created.contains(".gitignore") {
            report.created.append(".gitignore")
            report.kept.removeAll { $0 == ".gitignore" }
        }

        return report
    }

    /// True when any agent file on disk differs from the shipped template, or is
    /// missing — i.e. Refresh Agent Files would change something.
    /// Guarantees `.gitignore` excludes the Scratch file.
    ///
    /// `.gitignore` is written with policy `.keep`, so a folder created before Scratch
    /// existed would never gain the line on its own — and a missed line here means the
    /// user's private scratch text gets committed and pushed. The lines are appended to
    /// whatever the user already has rather than replacing it. Returns true if it wrote.
    @discardableResult
    static func ensureScratchIgnored(_ folder: PeteKMFolder) -> Bool {
        let url = folder.gitignore

        guard let existing = FileWriting.readText(url) else {
            try? FileWriting.writeAtomically(AgentTemplates.gitignore, to: url)
            return true
        }

        let present = Set(existing.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = AgentTemplates.scratchIgnoreLines.filter { !present.contains($0) }
        guard !missing.isEmpty else { return false }

        var text = existing
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += missing.joined(separator: "\n") + "\n"
        try? FileWriting.writeAtomically(text, to: url)
        return true
    }

    static func agentFilesAreOutOfDate(_ folder: PeteKMFolder) -> Bool {
        var items: [(URL, String)] = [(folder.claudeMd, AgentTemplates.claudeMd),
                                      (folder.agentsMd, AgentTemplates.agentsMd)]
        for name in AgentTemplates.skillNames {
            items.append((folder.skill(name), AgentTemplates.skill(name)))
        }
        return items.contains { url, contents in FileWriting.readText(url) != contents }
    }

    /// A stable fingerprint of the shipped templates. Changes only when the app
    /// ships new agent content, so a notice keyed on it fires once per version.
    static var agentTemplatesFingerprint: String {
        let all = ([AgentTemplates.claudeMd, AgentTemplates.agentsMd]
                   + AgentTemplates.skillNames.map(AgentTemplates.skill)).joined(separator: "\u{0}")
        // FNV-1a: `hashValue` is per-process randomized and must not be persisted.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in all.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
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

        if ensureScratchIgnored(folder) { report.created.append(".gitignore") }

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
                    try FileWriting.backUp(url, into: folder.backups, on: now)
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
