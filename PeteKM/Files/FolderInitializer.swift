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

        // Same for `.gitattributes`: user lines are kept, the daily union line is added.
        if ensureDailyUnionMerge(folder), !report.created.contains(".gitattributes") {
            report.created.append(".gitattributes")
            report.kept.removeAll { $0 == ".gitattributes" }
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

    /// Guarantees `.gitattributes` merges Daily Stickies by line union (sync v2 §7.5).
    ///
    /// Modeled on `ensureScratchIgnored`: creates the file when missing, appends the
    /// line when absent, never replaces what the user already has. Folders that
    /// predate sync v2 are repaired on window open without a prompt. Returns true if
    /// it wrote.
    @discardableResult
    static func ensureDailyUnionMerge(_ folder: PeteKMFolder) -> Bool {
        let url = folder.gitattributes

        guard let existing = FileWriting.readText(url) else {
            try? FileWriting.writeAtomically(AgentTemplates.gitattributes, to: url)
            return true
        }

        let present = Set(existing.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        guard !present.contains(AgentTemplates.dailyUnionLine) else { return false }

        var text = existing
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += AgentTemplates.dailyUnionLine + "\n"
        try? FileWriting.writeAtomically(text, to: url)
        return true
    }

    /// Puts the daily union line in `.git/info/attributes` too.
    ///
    /// A rebase reads attributes from the files checked out while it runs, which are
    /// the remote's. Until `.gitattributes` has reached the remote, the first v2 sync
    /// on each Mac would conflict on same-day stickies instead of merging them. The
    /// repository-local file applies whatever is checked out and is never committed.
    /// Does nothing when there is no `.git` directory. Returns true if it wrote.
    @discardableResult
    static func ensureLocalDailyUnionMerge(_ folder: PeteKMFolder) -> Bool {
        guard FileWriting.isDirectory(folder.gitDirectory) else { return false }
        let info = folder.gitDirectory.appending(path: "info", directoryHint: .isDirectory)
        let url = info.appending(path: "attributes")

        let existing = FileWriting.readText(url) ?? ""
        let present = Set(existing.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) })
        guard !present.contains(AgentTemplates.dailyUnionLine) else { return false }

        var text = existing
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += AgentTemplates.dailyUnionLine + "\n"
        try? FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
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

        migrateRenamedSkills(folder, now: now, into: &report)

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

    /// Skills that were renamed by a later version. Their `SKILL.md` is backed up
    /// (hand-edits are preserved, same as every other tracked file) and the old
    /// directory is removed, so Refresh Agent Files doesn't leave two dead slash
    /// commands next to the one that replaced them (sync spec §3.5).
    private static let retiredSkillNames = ["petekm-process-today", "petekm-process-date"]

    private static func migrateRenamedSkills(
        _ folder: PeteKMFolder,
        now: Date,
        into report: inout Report
    ) {
        for name in retiredSkillNames {
            let url = folder.skill(name)
            let directory = url.deletingLastPathComponent()

            if FileWriting.exists(url) {
                do {
                    try FileWriting.backUp(url, into: folder.backups, on: now)
                    report.backedUp.append(relativePath(of: url, in: folder))
                } catch {
                    report.failed.append(relativePath(of: url, in: folder))
                    continue
                }
            }

            // Only ever remove the directory if it is empty — anything else in
            // there is the user's, not ours.
            guard FileWriting.isDirectory(directory) else { continue }
            let contents = try? FileManager.default.contentsOfDirectory(
                atPath: directory.path(percentEncoded: false))
            if contents?.isEmpty == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

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
