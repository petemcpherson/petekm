//
//  ScratchTests.swift
//  PeteKMTests
//
//  The Scratch pane's contract: one file, carried over day to day, and invisible to
//  search, to Git, and to the agent.
//

import AppKit
import Foundation
import Testing
@testable import PeteKM

private func makeScratchFolder() throws -> PeteKMFolder {
    let root = URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        .appending(path: "petekm-scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return PeteKMFolder(root: root)
}

private func remove(_ folder: PeteKMFolder) {
    try? FileManager.default.removeItem(at: folder.root)
}

// MARK: - Path

@Test func scratchLivesAtTheFolderRootAndIsHidden() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    #expect(folder.scratch.lastPathComponent == ".petekm-scratch.md")
    #expect(folder.scratch.deletingLastPathComponent().standardizedFileURL == folder.root)
    // The leading dot is what keeps it out of the search index.
    #expect(folder.scratch.lastPathComponent.hasPrefix("."))
    // Not a Daily Sticky and not a Library file.
    #expect(folder.scratch.deletingLastPathComponent() != folder.daily)
    #expect(folder.scratch.deletingLastPathComponent() != folder.library)
}

// MARK: - Search exclusion (§2.2, §10)

@Test func scratchIsNeverIndexed() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    try FileWriting.writeAtomically("# Today\nreal note\n", to: folder.dailySticky(for: Date()))
    try FileWriting.writeAtomically("- [ ] secret todo\nsk-live-abc123\n", to: folder.scratch)

    let store = SearchIndexBuilder.scan(root: folder.root, previous: SearchIndexStore())

    #expect(!store.files.keys.contains { $0.contains("petekm-scratch") })
    #expect(store.files.values.allSatisfy { !$0.text.contains("sk-live-abc123") })
    #expect(store.files.keys.contains { $0.hasPrefix("daily/") })
}

// MARK: - Git exclusion

@Test func gitignoreTemplateExcludesScratchAndItsBackups() {
    for line in AgentTemplates.scratchIgnoreLines {
        #expect(AgentTemplates.gitignore.contains(line))
    }
    #expect(AgentTemplates.scratchIgnoreLines.contains(PeteKMFolder.scratchFilename))
}

@Test func ensureScratchIgnoredAppendsToAnExistingGitignore() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    // A folder created before Scratch existed. Its `.gitignore` is kept, never replaced.
    try FileWriting.writeAtomically(".petekm-state.json\n.DS_Store\n", to: folder.gitignore)

    #expect(FolderInitializer.ensureScratchIgnored(folder))

    let text = try #require(FileWriting.readText(folder.gitignore))
    #expect(text.contains(".petekm-state.json"))       // the user's own lines survive
    #expect(text.contains(".DS_Store"))
    for line in AgentTemplates.scratchIgnoreLines {
        #expect(text.contains(line))
    }
}

@Test func ensureScratchIgnoredIsIdempotent() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    try FolderInitializer.initialize(folder)
    #expect(!FolderInitializer.ensureScratchIgnored(folder))

    let before = FileWriting.readText(folder.gitignore)
    #expect(!FolderInitializer.ensureScratchIgnored(folder))
    #expect(FileWriting.readText(folder.gitignore) == before)
}

@Test func ensureScratchIgnoredWritesTheTemplateWhenThereIsNoGitignore() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    #expect(FolderInitializer.ensureScratchIgnored(folder))
    #expect(FileWriting.readText(folder.gitignore) == AgentTemplates.gitignore)
}

@Test func initializingAnAdoptedFolderStillExcludesScratch() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    try FileWriting.writeAtomically("notes/\n", to: folder.gitignore)
    try FolderInitializer.initialize(folder)

    let text = try #require(FileWriting.readText(folder.gitignore))
    #expect(text.contains("notes/"))
    #expect(text.contains(PeteKMFolder.scratchFilename))
}

// MARK: - Agent exclusion (§13)

@Test func agentFilesForbidReadingScratch() {
    #expect(AgentTemplates.claudeMd.contains(PeteKMFolder.scratchFilename))
    #expect(AgentTemplates.agentsMd.contains(PeteKMFolder.scratchFilename))
    #expect(AgentTemplates.claudeMd.contains("Never read it"))
}

// MARK: - Store

@MainActor
@Test func scratchWritesNothingUntilTheUserTypes() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    _ = ScratchStore(folder: folder)
    #expect(!FileWriting.exists(folder.scratch))
}

@MainActor
@Test func scratchPersistsAcrossStores() async throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    let first = ScratchStore(folder: folder)
    first.document.text = "- [ ] finish the migration"
    first.flush()

    // A fresh store is what a relaunch — or any later day — sees. Nothing is keyed to a date.
    let second = ScratchStore(folder: folder)
    #expect(second.document.text == "- [ ] finish the migration")
    #expect(!second.isEmpty)
    #expect(second.firstLine == "- [ ] finish the migration")
}

@MainActor
@Test func scratchFirstLineSkipsBlankLines() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    let store = ScratchStore(folder: folder)
    #expect(store.firstLine == "")
    #expect(store.isEmpty)

    store.document.text = "\n\n   \nkey for staging\nand more"
    #expect(store.firstLine == "key for staging")
    #expect(!store.isEmpty)
}

@MainActor
@Test func clearingScratchKeepsABackup() throws {
    let folder = try makeScratchFolder()
    defer { remove(folder) }

    let store = ScratchStore(folder: folder)
    store.document.text = "sk-live-abc123"
    store.flush()

    store.clear(on: Date(timeIntervalSince1970: 1_756_512_000))

    #expect(store.document.text == "")
    #expect(store.isEmpty)
    #expect(store.lastError == nil)

    let backups = try FileManager.default
        .contentsOfDirectory(atPath: folder.backups.path(percentEncoded: false))
        .filter { $0.hasPrefix(".petekm-scratch.md.bak-") }
    #expect(backups.count == 1)
    // Backups are gitignored too — the backups folder has to be covered.
    #expect(AgentTemplates.gitignore.contains(".petekm-backups/"))
}

// MARK: - Settings

@Test func scratchHeightIsClamped() {
    #expect(AppSettings.clampScratchHeight(10) == AppSettings.scratchHeightRange.lowerBound)
    #expect(AppSettings.clampScratchHeight(9_000) == AppSettings.scratchHeightRange.upperBound)
    #expect(AppSettings.clampScratchHeight(200) == 200)
    #expect(AppSettings.clampScratchHeight(.nan) == AppSettings.scratchHeightRange.lowerBound)
}

@Test func scratchPreferencesRoundTrip() throws {
    let suite = try #require(UserDefaults(suiteName: "petekm.tests.scratch.\(UUID().uuidString)"))
    defer { suite.removeSuite(named: suite.description) }

    let settings = AppSettings(defaults: suite)
    #expect(settings.scratchVisible == false)
    #expect(settings.scratchHeight == 160)

    settings.scratchVisible = true
    settings.scratchHeight = 4_000

    let reloaded = AppSettings(defaults: suite)
    #expect(reloaded.scratchVisible)
    #expect(reloaded.scratchHeight == AppSettings.scratchHeightRange.upperBound)
}

// MARK: - Texture

@Test func scratchGroundFollowsTheWindowNotJustTheSystemAppearance() throws {
    let suite = try #require(UserDefaults(suiteName: "petekm.tests.ground.\(UUID().uuidString)"))
    defer { suite.removeSuite(named: suite.description) }

    let settings = AppSettings(defaults: suite)

    // No custom color: follow the system.
    #expect(settings.groundIsDark(systemIsDark: true))
    #expect(!settings.groundIsDark(systemIsDark: false))

    // A light custom window in Dark Mode still needs dark ink on it.
    settings.backgroundHex = "#FBF7EC"
    #expect(!settings.groundIsDark(systemIsDark: true))

    settings.backgroundHex = "#101014"
    #expect(settings.groundIsDark(systemIsDark: false))
}

@MainActor
@Test func scratchDotTilesAreCachedPerGround() {
    #expect(ScratchTexture.dots(dark: true) === ScratchTexture.dots(dark: true))
    #expect(ScratchTexture.dots(dark: true) !== ScratchTexture.dots(dark: false))
    #expect(ScratchTexture.wash(dark: true).alphaComponent < 0.1)
}

// MARK: - Palette

@MainActor
@Test func scratchIsReachableFromTheCommandPalette() {
    #expect(PaletteCommandID.allCases.contains(.openScratch))
    #expect(PaletteCommandID.openScratch.title == "Open Scratch")
    #expect(FuzzyMatch.score("scratch", in: PaletteCommandID.openScratch.title) != nil)
}
