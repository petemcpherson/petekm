import AppKit

/// Editor typography knobs (§18.6). Sizes follow the DESIGN.md §49 ramp.
struct MarkdownStyle: Equatable {
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 4
    /// Font family name for the editor, or `nil` for the system font (§18.6).
    var fontName: String?
    /// Body text color, or `nil` for the system label color.
    var textColor: NSColor?

    static let `default` = MarkdownStyle()

    var primaryColor: NSColor { textColor ?? .labelColor }
    /// Markers and quotes: dimmed from the chosen text color so a custom color keeps its tint.
    var secondaryColor: NSColor { textColor?.withAlphaComponent(0.55) ?? .secondaryLabelColor }
    var tertiaryColor: NSColor { textColor?.withAlphaComponent(0.3) ?? .tertiaryLabelColor }

    /// `#` ≈ 22, `##` ≈ 17, `###` ≈ 15, deeper ≈ body + 1.
    func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 9
        case 2: return fontSize + 4
        case 3: return fontSize + 2
        default: return fontSize + 1
        }
    }

    /// Visual width of one list nesting level.
    var listIndent: CGFloat { fontSize * 1.6 }

    var body: NSFont { font(size: fontSize, weight: .regular) }
    var mono: NSFont { .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) }

    /// Heading font at `level` — same family as the body text, heavier.
    func heading(_ level: Int) -> NSFont { font(size: headingSize(level), weight: .semibold) }

    /// Falls back to the system font when the chosen family is missing, so an
    /// uninstalled font can never leave the editor unreadable.
    private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let fontName, !fontName.isEmpty else { return system }
        guard let base = NSFont(name: fontName, size: size) else { return system }
        guard weight >= .semibold else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }
}

/// Applies live styling *on top of* still-visible Markdown syntax (§9.1–9.2).
/// Never rewrites text — attributes only.
enum MarkdownSyntaxHighlighter {

    static let listPattern = "^([ \\t]*)([-*+]|[0-9]+[.)])([ \\t]+)"

    private static let heading = regex("^(#{1,6})([ \\t]+)(.*)$")
    private static let list = regex(listPattern)
    private static let quote = regex("^([ \\t]*>+)([ \\t]*)")
    private static let code = regex("`[^`\\n]+`")
    private static let bold = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = regex("(?<![\\*_\\w])([*_])(?=\\S)([^*_\\n]+?)(?<=\\S)\\1(?![\\*_\\w])")

    /// Styles the whole storage. Callers run this inside `didProcessEditing`, so it must not
    /// call `beginEditing`/`endEditing`.
    static func apply(to storage: NSTextStorage, style: MarkdownStyle) {
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard full.length > 0 else { return }

        storage.setAttributes([
            .font: style.body,
            .foregroundColor: style.primaryColor,
            .paragraphStyle: paragraphStyle(style: style, indentLevels: 0, markerWidth: 0)
        ], range: full)

        var fence: String?

        ns.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                styleCode(storage, lineRange, style)
                if trimmed.hasPrefix(open) { fence = nil }
                return
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                styleCode(storage, lineRange, style)
                return
            }

            styleBlock(storage, line: line, lineRange: lineRange, style: style)
            styleInline(storage, line: line, lineRange: lineRange, style: style)
        }
    }

    // MARK: - Block level

    private static func styleBlock(_ storage: NSTextStorage, line: String, lineRange: NSRange, style: MarkdownStyle) {
        let lineOnly = NSRange(location: 0, length: (line as NSString).length)

        if let match = heading.firstMatch(in: line, range: lineOnly) {
            let level = match.range(at: 1).length
            storage.addAttribute(.font, value: style.heading(level), range: lineRange)
            dim(storage, shift(match.range(at: 1), by: lineRange.location), style)
            return
        }

        if let match = list.firstMatch(in: line, range: lineOnly) {
            let indentColumns = indentWidth(of: (line as NSString).substring(with: match.range(at: 1)))
            let markerWidth = CGFloat(match.range(at: 2).length + match.range(at: 3).length) * style.fontSize * 0.6
            storage.addAttribute(.paragraphStyle,
                                 value: paragraphStyle(style: style,
                                                       indentLevels: indentColumns,
                                                       markerWidth: markerWidth),
                                 range: lineRange)
            storage.addAttribute(.foregroundColor,
                                 value: style.secondaryColor,
                                 range: shift(match.range(at: 2), by: lineRange.location))
            return
        }

        if let match = quote.firstMatch(in: line, range: lineOnly) {
            storage.addAttribute(.foregroundColor, value: style.secondaryColor, range: lineRange)
            dim(storage, shift(match.range(at: 1), by: lineRange.location), style)
        }
    }

    /// Leading whitespace → nesting level. Two spaces or one tab per level, rounded down.
    static func indentWidth(of whitespace: String) -> Int {
        var columns = 0
        for character in whitespace {
            columns += character == "\t" ? 4 : 1
        }
        return columns / 2
    }

    private static func paragraphStyle(style: MarkdownStyle, indentLevels: Int, markerWidth: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.lineSpacing
        let base = CGFloat(indentLevels) * style.listIndent
        paragraph.firstLineHeadIndent = base
        paragraph.headIndent = base + markerWidth
        return paragraph
    }

    // MARK: - Inline level

    private static func styleInline(_ storage: NSTextStorage, line: String, lineRange: NSRange, style: MarkdownStyle) {
        let lineOnly = NSRange(location: 0, length: (line as NSString).length)

        bold.enumerateMatches(in: line, range: lineOnly) { match, _, _ in
            guard let match else { return }
            addTrait(.boldFontMask, storage, shift(match.range, by: lineRange.location))
            dim(storage, shift(match.range(at: 1), by: lineRange.location), style)
            dim(storage, shift(NSRange(location: match.range.upperBound - match.range(at: 1).length,
                                       length: match.range(at: 1).length),
                               by: lineRange.location), style)
        }

        italic.enumerateMatches(in: line, range: lineOnly) { match, _, _ in
            guard let match else { return }
            addTrait(.italicFontMask, storage, shift(match.range, by: lineRange.location))
            dim(storage, shift(match.range(at: 1), by: lineRange.location), style)
            dim(storage, shift(NSRange(location: match.range.upperBound - 1, length: 1), by: lineRange.location), style)
        }

        code.enumerateMatches(in: line, range: lineOnly) { match, _, _ in
            guard let match else { return }
            let range = shift(match.range, by: lineRange.location)
            storage.addAttribute(.font, value: style.mono, range: range)
            storage.addAttribute(.foregroundColor, value: style.secondaryColor, range: range)
        }
    }

    private static func styleCode(_ storage: NSTextStorage, _ range: NSRange, _ style: MarkdownStyle) {
        storage.addAttribute(.font, value: style.mono, range: range)
        storage.addAttribute(.foregroundColor, value: style.secondaryColor, range: range)
    }

    /// Keeps whatever size/weight the block already assigned — a bold span inside an H2 stays H2-sized.
    private static func addTrait(_ trait: NSFontTraitMask, _ storage: NSTextStorage, _ range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
    }

    private static func dim(_ storage: NSTextStorage, _ range: NSRange, _ style: MarkdownStyle) {
        guard range.length > 0 else { return }
        storage.addAttribute(.foregroundColor, value: style.tertiaryColor, range: range)
    }

    private static func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals verified by tests; a failure here is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
}
