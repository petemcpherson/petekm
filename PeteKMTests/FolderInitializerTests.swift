//
//  FolderInitializerTests.swift
//  PeteKMTests
//

import Foundation
import Testing
@testable import PeteKM

private func makeTemporaryFolder() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

private func remove(_ folder: PeteKMFolder) {
    try? FileManager.default.removeItem(at: folder.root)
}

struct FolderInitializerTests {

    @Test func createsTheFullStructure() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let report = try FolderInitializer.initialize(folder)

        #expect(FileWriting.isDirectory(folder.daily))
        #expect(FileWriting.isDirectory(folder.library))
        #expect(FileWriting.isDirectory(folder.skills))
        #expect(FileWriting.exists(folder.index))
        #expect(FileWriting.exists(folder.claudeMd))
        #expect(FileWriting.exists(folder.agentsMd))
        #expect(FileWriting.exists(folder.state))
        #expect(FileWriting.exists(folder.gitignore))
        for name in AgentTemplates.skillNames {
            #expect(FileWriting.exists(folder.skill(name)))
        }
        // INBOX.md is created lazily by the agent, never at setup (§13.12).
        #expect(!FileWriting.exists(folder.inbox))
        #expect(report.failed.isEmpty)
    }

    @Test func neverOverwritesExistingFiles() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let mine = "# My own CLAUDE.md\n"
        try FileWriting.writeAtomically(mine, to: folder.claudeMd)
        try FileWriting.writeAtomically("keep me", to: folder.index)
        try FileWriting.writeAtomically("*.tmp", to: folder.gitignore)

        let report = try FolderInitializer.initialize(folder)

        #expect(FileWriting.readText(folder.claudeMd) == mine)
        #expect(FileWriting.readText(folder.index) == "keep me")
        #expect(FileWriting.readText(folder.gitignore) == "*.tmp")
        #expect(report.kept.contains("CLAUDE.md"))
        #expect(report.kept.contains("INDEX.md"))
        #expect(report.backedUp.isEmpty)
    }

    @Test func isIdempotent() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        _ = try FolderInitializer.initialize(folder)
        let second = try FolderInitializer.initialize(folder)

        #expect(second.created.isEmpty)
        #expect(second.failed.isEmpty)
        #expect(second.kept.contains("AGENTS.md"))
    }

    @Test func refreshBacksUpDifferingAgentFiles() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        try FileWriting.writeAtomically("# stale\n", to: folder.agentsMd)
        try FileWriting.writeAtomically("# my index\n", to: folder.index)

        let report = try FolderInitializer.refreshAgentFiles(folder, now: Date(timeIntervalSince1970: 1_787_000_000))

        #expect(report.backedUp.contains("AGENTS.md"))
        #expect(FileWriting.readText(folder.agentsMd) == AgentTemplates.agentsMd)
        // Knowledge files are outside the refresh's reach (§6.5).
        #expect(FileWriting.readText(folder.index) == "# my index\n")

        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.root.path(percentEncoded: false))
            .filter { $0.hasPrefix("AGENTS.md.bak-") }
        #expect(backups.count == 1)
    }

    @Test func refreshLeavesUnchangedTemplatesAlone() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        _ = try FolderInitializer.initialize(folder)
        let report = try FolderInitializer.refreshAgentFiles(folder)

        #expect(report.backedUp.isEmpty)
        #expect(report.created.isEmpty)
        #expect(report.kept.contains("CLAUDE.md"))
    }

    @Test func backupsNeverClobberEachOther() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let day = Date(timeIntervalSince1970: 1_787_000_000)
        try FileWriting.writeAtomically("one", to: folder.agentsMd)
        let first = try FileWriting.backUp(folder.agentsMd, on: day)
        try FileWriting.writeAtomically("two", to: folder.agentsMd)
        let second = try FileWriting.backUp(folder.agentsMd, on: day)

        #expect(first != second)
        #expect(FileWriting.readText(first) == "one")
        #expect(FileWriting.readText(second) == "two")
    }
}

struct AgentTemplateTests {

    @Test func everySkillHasFrontmatterWithNameAndDescription() {
        for name in AgentTemplates.skillNames {
            let text = AgentTemplates.skill(name)
            #expect(text.hasPrefix("---\n"), "\(name) must open with YAML frontmatter")
            #expect(text.contains("name: \(name)\n"))
            #expect(text.contains("\ndescription: "))
        }
    }

    @Test func templatesStateTheImmutableLedgerRule() {
        #expect(AgentTemplates.claudeMd.contains("read-only"))
        #expect(AgentTemplates.agentsMd.contains("immutable ledger"))
        #expect(AgentTemplates.agentsMd.contains(".petekm-state.json"))
        #expect(AgentTemplates.agentsMd.contains("INBOX.md"))
    }

    @Test func indexIsTieredAndSelfHealing() {
        for section in ["## Placement guide", "## Areas", "## Files"] {
            #expect(AgentTemplates.index.contains(section))
        }
        #expect(AgentTemplates.index.contains("library/Lists/"))
        #expect(AgentTemplates.skill("petekm-process-today").contains("freshness"))
        #expect(AgentTemplates.skill("petekm-rebuild-index").contains("incremental"))
        #expect(AgentTemplates.agentsMd.contains("Placement guide"))
    }

    @Test func detectsOutOfDateAgentFiles() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        _ = try FolderInitializer.initialize(folder)
        #expect(!FolderInitializer.agentFilesAreOutOfDate(folder))
        try FileWriting.writeAtomically("# edited", to: folder.agentsMd)
        #expect(FolderInitializer.agentFilesAreOutOfDate(folder))
        _ = try FolderInitializer.refreshAgentFiles(folder)
        #expect(!FolderInitializer.agentFilesAreOutOfDate(folder))
        #expect(FolderInitializer.agentTemplatesFingerprint == FolderInitializer.agentTemplatesFingerprint)
    }

    @Test func gitignoreIgnoresOnlyDisposableState() {
        #expect(AgentTemplates.gitignore.contains(".petekm-state.json"))
        #expect(AgentTemplates.gitignore.contains(".DS_Store"))
        #expect(!AgentTemplates.gitignore.contains("INBOX"))
        #expect(!AgentTemplates.gitignore.contains(".claude"))
    }
}

struct PeteKMFolderTests {

    @Test func dailyFilenamesAreZeroPadded() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        let date = Calendar(identifier: .gregorian).date(from: components)!
        #expect(PeteKMFolder.dailyFilename(for: date) == "2026-08-03.md")
    }

    @Test func dailyStickyResolvesUnderDaily() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 25
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let url = folder.dailySticky(for: date)

        #expect(url.lastPathComponent == "2026-12-25.md")
        #expect(url.deletingLastPathComponent().lastPathComponent == "daily")
    }

    @Test func looksInitializedOnlyAfterSetup() throws {
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        #expect(!folder.looksInitialized)
        _ = try FolderInitializer.initialize(folder)
        #expect(folder.looksInitialized)
    }
}

struct FolderStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "petekm.tests.\(UUID().uuidString)")!
        return suite
    }

    @Test func startsUnsetWithNoStoredFolder() {
        let store = FolderStore(defaults: makeDefaults())
        #expect(store.state == .unset)
        #expect(store.folder == nil)
    }

    @Test func remembersFolderAcrossLaunches() throws {
        let defaults = makeDefaults()
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let first = FolderStore(defaults: defaults)
        first.setFolder(folder.root)
        #expect(first.folder?.root == folder.root)

        let second = FolderStore(defaults: defaults)
        #expect(second.folder?.root == folder.root)
    }

    @Test func reportsMissingFolderWithoutRecreatingIt() throws {
        let defaults = makeDefaults()
        let folder = try makeTemporaryFolder()

        let first = FolderStore(defaults: defaults)
        first.setFolder(folder.root)
        let path = folder.root.path(percentEncoded: false)

        try FileManager.default.removeItem(at: folder.root)

        let second = FolderStore(defaults: defaults)
        #expect(second.state == .missing(lastKnownPath: path))
        #expect(second.folder == nil)
        #expect(!FileWriting.exists(folder.root))
    }

    @Test func clearForgetsTheFolder() throws {
        let defaults = makeDefaults()
        let folder = try makeTemporaryFolder()
        defer { remove(folder) }

        let store = FolderStore(defaults: defaults)
        store.setFolder(folder.root)
        store.clear()

        #expect(store.state == .unset)
        #expect(FolderStore(defaults: defaults).state == .unset)
        // Clearing the setting never touches the folder itself.
        #expect(FileWriting.isDirectory(folder.root))
    }
}
