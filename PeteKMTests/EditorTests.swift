//
//  EditorTests.swift
//  PeteKMTests
//

import AppKit
import Foundation
import Testing
@testable import PeteKM

// MARK: - Outline (§9.4)

@Test func outlineCarriesHeadingRanges() {
    let text = "# August 20, 2026\n\nsome text\n\n## Work\n\n### Auth\n"
    let entries = MarkdownOutline.entries(in: text)

    #expect(entries.map(\.title) == ["August 20, 2026", "Work", "Auth"])
    #expect(entries.map(\.level) == [1, 2, 3])

    let ns = text as NSString
    #expect(ns.substring(with: entries[1].range) == "## Work")
}

@Test func outlineIgnoresHeadingsInsideFences() {
    let text = "## Real\n\n```sh\n# not a heading\n```\n\n## Also real\n"
    #expect(MarkdownOutline.entries(in: text).map(\.title) == ["Real", "Also real"])
}

@Test func outlineRejectsMalformedHeadings() {
    let text = "#NoSpace\n####### TooDeep\n#\n## Good\n"
    #expect(MarkdownOutline.entries(in: text).map(\.title) == ["Good"])
}

// MARK: - Auto-close (§9.3)

@Test func typingOpenerInsertsPair() {
    #expect(EditorEdits.autoClose(typing: "(", nextCharacter: nil, hasSelection: false)
            == .insertPair(open: "(", close: ")"))
}

@Test func typingCloserOverExistingOneSkipsIt() {
    #expect(EditorEdits.autoClose(typing: ")", nextCharacter: ")", hasSelection: false) == .skipOver)
    #expect(EditorEdits.autoClose(typing: "\"", nextCharacter: "\"", hasSelection: false) == .skipOver)
}

@Test func typingPairWithSelectionWrapsIt() {
    #expect(EditorEdits.autoClose(typing: "\"", nextCharacter: nil, hasSelection: true)
            == .wrapSelection(open: "\"", close: "\""))
}

@Test func singleQuoteIsNeverPaired() {
    #expect(EditorEdits.autoClose(typing: "'", nextCharacter: nil, hasSelection: false) == .none)
    #expect(EditorEdits.autoClose(typing: "'", nextCharacter: "'", hasSelection: false) == .none)
    #expect(EditorEdits.autoClose(typing: "'", nextCharacter: nil, hasSelection: true) == .none)
    #expect(!EditorEdits.deletesPair(previousCharacter: "'", nextCharacter: "'"))
}

@Test func quoteBeforeWordCharacterIsNotPaired() {
    #expect(EditorEdits.autoClose(typing: "\"", nextCharacter: "s", hasSelection: false) == .none)
    #expect(EditorEdits.autoClose(typing: "(", nextCharacter: "s", hasSelection: false)
            == .insertPair(open: "(", close: ")"))
}

@Test func backspaceBetweenPairRemovesBoth() {
    #expect(EditorEdits.deletesPair(previousCharacter: "[", nextCharacter: "]"))
    #expect(!EditorEdits.deletesPair(previousCharacter: "[", nextCharacter: ")"))
    #expect(!EditorEdits.deletesPair(previousCharacter: nil, nextCharacter: "]"))
}

// MARK: - Return key (§9.3)

@Test func returnContinuesBulletMarker() {
    #expect(EditorEdits.newline(after: "- first thing") == EditorEdits.NewlineEdit(insert: "\n- "))
    #expect(EditorEdits.newline(after: "  * nested") == EditorEdits.NewlineEdit(insert: "\n  * "))
}

@Test func returnIncrementsOrderedMarker() {
    #expect(EditorEdits.newline(after: "3. third") == EditorEdits.NewlineEdit(insert: "\n4. "))
}

@Test func returnOnEmptyItemEndsTheList() {
    #expect(EditorEdits.newline(after: "- ") == EditorEdits.NewlineEdit(deleteBackward: 2, insert: "\n"))
    #expect(EditorEdits.newline(after: "  - ") == EditorEdits.NewlineEdit(deleteBackward: 4, insert: "\n"))
}

@Test func returnPreservesPlainIndentation() {
    #expect(EditorEdits.newline(after: "    indented text") == EditorEdits.NewlineEdit(insert: "\n    "))
    #expect(EditorEdits.newline(after: "## Work") == EditorEdits.NewlineEdit(insert: "\n"))
}

// MARK: - Indentation

@Test func tabIndentsAndShiftTabOutdents() {
    #expect(EditorEdits.indent("- item") == "  - item")
    #expect(EditorEdits.outdent("  - item") == "- item")
    #expect(EditorEdits.outdent("\t- item") == "- item")
    #expect(EditorEdits.outdent("- item") == "- item")
}

@Test func nestingLevelComesFromLeadingWhitespace() {
    #expect(MarkdownSyntaxHighlighter.indentWidth(of: "") == 0)
    #expect(MarkdownSyntaxHighlighter.indentWidth(of: "  ") == 1)
    #expect(MarkdownSyntaxHighlighter.indentWidth(of: "    ") == 2)
    #expect(MarkdownSyntaxHighlighter.indentWidth(of: "\t") == 2)
}

// MARK: - Live styling (§9.1–9.2)

@MainActor
private func styled(_ text: String) -> NSTextStorage {
    let storage = NSTextStorage(string: text)
    MarkdownSyntaxHighlighter.apply(to: storage, style: .default)
    return storage
}

@MainActor
private func font(_ storage: NSTextStorage, at location: Int) -> NSFont {
    storage.attribute(.font, at: location, effectiveRange: nil) as! NSFont
}

@MainActor
@Test func headingsAreSizedByLevelWithSyntaxIntact() {
    let text = "# One\n## Two\n### Three\nbody\n"
    let storage = styled(text)
    let ns = text as NSString

    let h1 = font(storage, at: ns.range(of: "# One").location).pointSize
    let h2 = font(storage, at: ns.range(of: "## Two").location).pointSize
    let h3 = font(storage, at: ns.range(of: "### Three").location).pointSize
    let body = font(storage, at: ns.range(of: "body").location).pointSize

    #expect(h1 > h2 && h2 > h3 && h3 > body)
    #expect(storage.string == text)          // styling never rewrites the Markdown
}

@MainActor
@Test func boldAndItalicSpansKeepTheirMarkers() {
    let text = "This is **important** and *soft*.\n"
    let storage = styled(text)
    let ns = text as NSString

    let boldFont = font(storage, at: ns.range(of: "important").location)
    let italicFont = font(storage, at: ns.range(of: "soft").location)
    let plainFont = font(storage, at: ns.range(of: "This").location)

    #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
    #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
    #expect(!NSFontManager.shared.traits(of: plainFont).contains(.boldFontMask))
    #expect(storage.string == text)
}

@MainActor
@Test func nestedListsIndentByDepth() {
    let text = "- top\n  - nested\n"
    let storage = styled(text)
    let ns = text as NSString

    let top = storage.attribute(.paragraphStyle, at: ns.range(of: "- top").location, effectiveRange: nil) as! NSParagraphStyle
    let nested = storage.attribute(.paragraphStyle, at: ns.range(of: "  - nested").location, effectiveRange: nil) as! NSParagraphStyle

    #expect(nested.firstLineHeadIndent > top.firstLineHeadIndent)
}

@MainActor
@Test func fencedCodeIsNotStyledAsMarkdown() {
    let text = "```sh\n# not a heading\n```\n"
    let storage = styled(text)
    let ns = text as NSString

    let inFence = font(storage, at: ns.range(of: "# not a heading").location)
    #expect(inFence.pointSize <= MarkdownStyle.default.fontSize)
}

// MARK: - Cursor memory (§8.3)

@Test func cursorMemoryRoundTripsPerFile() throws {
    let defaults = UserDefaults(suiteName: "petekm.tests.\(UUID().uuidString)")!
    let memory = CursorMemory(defaults: defaults)
    let url = URL(filePath: "/tmp/petekm/daily/2026-08-20.md")

    #expect(memory.selection(for: url) == nil)

    memory.remember(NSRange(location: 42, length: 3), for: url)
    #expect(memory.selection(for: url) == NSRange(location: 42, length: 3))

    let other = URL(filePath: "/tmp/petekm/daily/2026-08-19.md")
    #expect(memory.selection(for: other) == nil)
}
