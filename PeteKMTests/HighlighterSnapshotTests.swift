//
//  HighlighterSnapshotTests.swift
//  PeteKMTests
//
//  Guards the iOS port (context/ios/plan.md Phase 0.1, 1.5): moving
//  `MarkdownSyntaxHighlighter` to `Shared/` must leave every attribute run the
//  Mac produces exactly as it was. The baseline is recorded on the dev Mac; a
//  macOS update that changes system font names can need a re-record (delete the
//  fixture and run once).
//

import AppKit
import Foundation
import Testing
@testable import PeteKM

/// One attribute run, reduced to what the highlighter sets.
struct HighlighterRun: Codable, Equatable {
    var location: Int
    var length: Int
    var fontName: String
    var pointSize: Double
    var traits: UInt32
    var color: String
    var firstLineHeadIndent: Double
    var headIndent: Double
    var lineSpacing: Double
}

struct HighlighterSnapshot: Codable, Equatable {
    var style: String
    var runs: [HighlighterRun]
}

/// A sticky using every style the highlighter knows.
let highlighterFixtureText = """
# November 26, 2026

## Work
### Auth
#### Deep heading

Plain text with **bold**, __also bold__, *italic*, _also italic_, and `code`.
Mixed **bold with *italic* inside** and snake_case_words stay plain.

- item
  - nested item
\t- tab-nested item
* star item
+ plus item
1. numbered
2) numbered paren

> quoted line
>> nested quote

```swift
let x = 1 // # not a heading
```

~~~
**not bold in a fence**
~~~

-> library/projects/petekm.md
"""

private func describe(_ color: NSColor?) -> String {
    guard let color else { return "none" }
    if color.type == .catalog { return "catalog:\(color.catalogNameComponent)/\(color.colorNameComponent)" }
    guard let srgb = color.usingColorSpace(.sRGB) else { return color.description }
    let parts = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
    return "srgb:" + parts.map { String(format: "%.4f", Double($0)) }.joined(separator: ",")
}

func highlighterSnapshot(style: MarkdownStyle, label: String) -> HighlighterSnapshot {
    let storage = NSTextStorage(string: highlighterFixtureText)
    MarkdownSyntaxHighlighter.apply(to: storage, style: style)
    var runs: [HighlighterRun] = []
    storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
        let font = attributes[.font] as? NSFont
        let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
        runs.append(HighlighterRun(
            location: range.location,
            length: range.length,
            fontName: font?.fontName ?? "none",
            pointSize: Double(font?.pointSize ?? 0),
            traits: font?.fontDescriptor.symbolicTraits.rawValue ?? 0,
            color: describe(attributes[.foregroundColor] as? NSColor),
            firstLineHeadIndent: Double(paragraph?.firstLineHeadIndent ?? -1),
            headIndent: Double(paragraph?.headIndent ?? -1),
            lineSpacing: Double(paragraph?.lineSpacing ?? -1)))
    }
    return HighlighterSnapshot(style: label, runs: runs)
}

func currentHighlighterSnapshots() -> [HighlighterSnapshot] {
    var custom = MarkdownStyle()
    custom.fontSize = 16
    custom.lineSpacing = 6
    custom.fontName = "Menlo"
    custom.textColor = NSColor(srgbRed: 0.8, green: 0.1, blue: 0.2, alpha: 1)
    return [
        highlighterSnapshot(style: .default, label: "default"),
        highlighterSnapshot(style: custom, label: "menlo-16-red"),
    ]
}

private let baselineURL = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures/highlighter-baseline.json")

@Test @MainActor func highlighterMatchesTheRecordedBaseline() throws {
    let current = currentHighlighterSnapshots()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    guard let data = try? Data(contentsOf: baselineURL) else {
        try encoder.encode(current).write(to: baselineURL, options: .atomic)
        Issue.record("Recorded a new highlighter baseline at \(baselineURL.path()). Run again.")
        return
    }
    let baseline = try JSONDecoder().decode([HighlighterSnapshot].self, from: data)
    #expect(baseline.count == current.count)
    for (old, new) in zip(baseline, current) {
        #expect(old.style == new.style)
        #expect(old.runs.count == new.runs.count, "\(new.style): run count changed")
        for (index, pair) in zip(old.runs, new.runs).enumerated() where pair.0 != pair.1 {
            Issue.record("\(new.style) run \(index): was \(pair.0), now \(pair.1)")
        }
    }
}
