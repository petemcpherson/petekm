//
//  SettingsTests.swift
//  PeteKMTests
//
//  Phase 7: Settings persistence (§18), editor typography, agent-file refresh
//  copy (§6.5), and the vocabulary/tone rules from DESIGN.md §2 and §39.
//

import AppKit
import Foundation
import Testing
@testable import PeteKM

private func settings(in defaults: UserDefaults) -> AppSettings { AppSettings(defaults: defaults) }

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "petekm.tests.\(UUID().uuidString)")!
}

// MARK: - Persistence (§18)

@Test func settingsDefaultsMatchTheSpec() {
    let s = settings(in: freshDefaults())

    #expect(s.dailyStartBehavior == .ask)
    #expect(s.showDateHeading)                 // §18.5 default: enabled
    #expect(s.globalShortcut == nil)           // §8.2: nothing pre-assigned
    #expect(s.editorFontName == nil)           // system font until chosen
    #expect(s.autoClosePairs)
    #expect(s.continueListMarkers)
    #expect(s.automaticUpdateChecks)
    #expect(s.syncAutomatically)               // sync v2 §4: on by default
}

@Test func everySettingSurvivesRelaunch() {
    let defaults = freshDefaults()
    let s = settings(in: defaults)

    s.dailyStartBehavior = .carryForwardHeaders
    s.defaultHeaders = "## Work\n\n## Ideas"
    s.showDateHeading = false
    s.editorFontName = "Menlo"
    s.editorFontSize = 16
    s.editorLineSpacing = 8
    s.showTableOfContents = true
    s.autoClosePairs = false
    s.continueListMarkers = false
    s.automaticUpdateChecks = false
    s.syncAutomatically = false

    let reloaded = settings(in: defaults)
    #expect(reloaded.dailyStartBehavior == .carryForwardHeaders)
    #expect(reloaded.defaultHeaders == "## Work\n\n## Ideas")
    #expect(reloaded.showDateHeading == false)
    #expect(reloaded.editorFontName == "Menlo")
    #expect(reloaded.editorFontSize == 16)
    #expect(reloaded.editorLineSpacing == 8)
    #expect(reloaded.showTableOfContents)
    #expect(reloaded.autoClosePairs == false)
    #expect(reloaded.continueListMarkers == false)
    #expect(reloaded.automaticUpdateChecks == false)
    #expect(reloaded.syncAutomatically == false)
}

// MARK: - Window background

@Test func backgroundDefaultsToSystemSurfaceAndFullyOpaque() {
    let s = settings(in: freshDefaults())
    #expect(s.backgroundHex == nil)
    #expect(s.backgroundColor == nil)
    #expect(s.backgroundOpacity == 1)
}

@Test func backgroundSettingsSurviveRelaunch() {
    let defaults = freshDefaults()
    let s = settings(in: defaults)
    s.backgroundHex = "ff3030"
    s.backgroundOpacity = 0.4

    let reloaded = settings(in: defaults)
    #expect(reloaded.backgroundHex == "#FF3030")
    #expect(reloaded.backgroundOpacity == 0.4)
}

@Test func textColorPersistsAndReachesTheEditorStyle() {
    let defaults = freshDefaults()
    let s = settings(in: defaults)
    #expect(s.textHex == nil)
    #expect(s.editorStyle.textColor == nil)

    s.textHex = "#ff3030"
    let reloaded = settings(in: defaults)
    #expect(reloaded.textHex == "#FF3030")
    #expect(reloaded.editorStyle.textColor != nil)

    s.textHex = "nope"
    #expect(s.textHex == nil)
}

@Test func backgroundOpacityIsClampedToTenPercentMinimum() {
    let s = settings(in: freshDefaults())
    s.backgroundOpacity = 0
    #expect(s.backgroundOpacity == 0.1)
    s.backgroundOpacity = 3
    #expect(s.backgroundOpacity == 1)
}

@Test func invalidHexIsRejectedAndKeepsDefaultSurface() {
    let s = settings(in: freshDefaults())
    s.backgroundHex = "#zzz"
    #expect(s.backgroundHex == nil)
    s.backgroundHex = "#12345"
    #expect(s.backgroundHex == nil)
}

@Test func hexColorParsesCommonForms() {
    #expect(HexColor.normalize("#333") == "#333333")
    #expect(HexColor.normalize(" 333333 ") == "#333333")
    #expect(HexColor.normalize("#ff3030cc") == "#FF3030CC")
    #expect(HexColor.normalize("") == nil)

    let c = HexColor.color("#FF3030")!.usingColorSpace(.sRGB)!
    #expect(abs(c.redComponent - 1) < 0.01)
    #expect(abs(c.greenComponent - 0x30 / 255.0) < 0.01)
    #expect(abs(c.blueComponent - 0x30 / 255.0) < 0.01)
    #expect(c.alphaComponent == 1)
}

@Test func clearingTheFontFallsBackToTheSystemFont() {
    let defaults = freshDefaults()
    let s = settings(in: defaults)

    s.editorFontName = "Menlo"
    s.editorFontName = nil

    #expect(settings(in: defaults).editorFontName == nil)
    #expect(settings(in: defaults).editorStyle.fontName == nil)
}

@Test func editorStyleCarriesEveryTypographySetting() {
    let s = settings(in: freshDefaults())
    s.editorFontSize = 18
    s.editorLineSpacing = 6
    s.editorFontName = "Menlo"

    let style = s.editorStyle
    #expect(style.fontSize == 18)
    #expect(style.lineSpacing == 6)
    #expect(style.fontName == "Menlo")
}

// MARK: - Editor typography (§18.6)

@Test func chosenFontIsUsedForBodyAndHeadings() {
    let style = MarkdownStyle(fontSize: 14, lineSpacing: 4, fontName: "Menlo")

    #expect(style.body.familyName == "Menlo")
    #expect(style.heading(1).pointSize == style.headingSize(1))
}

@Test func missingFontFallsBackInsteadOfBreakingTheEditor() {
    let style = MarkdownStyle(fontSize: 13, lineSpacing: 4, fontName: "No Such Font 12345")

    #expect(style.body.pointSize == 13)
    #expect(style.heading(2).pointSize == style.headingSize(2))
}

@Test func systemFontIsTheDefaultTypeface() {
    #expect(MarkdownStyle.default.fontName == nil)
    #expect(MarkdownStyle.default.body == NSFont.systemFont(ofSize: 13, weight: .regular))
}

@Test func offeredFontSizesStayInAReadableRange() {
    #expect(AppSettings.editorFontSizes.contains(13))
    #expect(AppSettings.editorFontSizes.allSatisfy { $0 >= 11 && $0 <= 20 })
}

// MARK: - Refresh Agent Files (§6.5)

@Test func refreshSummaryCountsWhatHappened() throws {
    let root = URL.temporaryDirectory.appending(path: "petekm-refresh-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = PeteKMFolder(root: root)

    try FolderInitializer.initialize(folder)
    #expect(try FolderInitializer.refreshAgentFiles(folder).summary == "Already up to date.")

    try FileWriting.writeAtomically("hand-edited", to: folder.agentsMd)
    let summary = try FolderInitializer.refreshAgentFiles(folder).summary
    #expect(summary.contains("Wrote 1."))
    #expect(summary.contains("Backed up 1."))
}

@Test func refreshNeverTouchesNotesOrTheIndex() throws {
    let root = URL.temporaryDirectory.appending(path: "petekm-refresh-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = PeteKMFolder(root: root)

    try FolderInitializer.initialize(folder)
    let note = folder.library.appending(path: "certificates.md")
    try FileWriting.writeAtomically("# Certificates\n\nmine", to: note)
    try FileWriting.writeAtomically("# Library Index\n\nhand written", to: folder.index)

    try FolderInitializer.refreshAgentFiles(folder)

    #expect(FileWriting.readText(note) == "# Certificates\n\nmine")
    #expect(FileWriting.readText(folder.index) == "# Library Index\n\nhand written")
}

// MARK: - Update posture (§20.2)

@Test func updatesStayInertWithoutAFeed() {
    // The test bundle has no SUFeedURL, so updates must report themselves off
    // rather than pretending to work.
    #expect(UpdateController.feedURL == nil)
    #expect(UpdateController.unavailableNotice == "This build doesn't check for updates.")
}

@Test func versionStringReadsFromTheBundle() {
    #expect(!UpdateController.versionString.isEmpty)
}

// MARK: - Vocabulary and tone (DESIGN §2, §39)

@Test func settingsCopyUsesProductVocabulary() {
    let copy = DailyStartBehavior.allCases.map { "\($0.title) \($0.detail)" }.joined(separator: " ")
        + " " + FolderInitializer.Report().summary
        + " " + UpdateController.unavailableNotice
        + " " + GitSupport.SyncOutcome.pushFailed.manualNotice(editorName: "Stub Editor")

    let banned = ["journal", "entry", "vault", "knowledge base", "AI Assistant",
                  "streak", "productivity", "Great job", "🎉"]
    for word in banned {
        #expect(!copy.localizedCaseInsensitiveContains(word), "banned vocabulary: \(word)")
    }
    #expect(DailyStartBehavior.carryForwardHeaders.detail.contains("Daily Sticky"))
}
