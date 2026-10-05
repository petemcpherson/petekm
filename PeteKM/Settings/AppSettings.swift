//
//  AppSettings.swift
//  PeteKM
//
//  User preferences (spec §18). No AI settings exist, now or later (§18.8).
//  The Settings *window* arrives in a later phase; these are the values
//  onboarding needs to record.
//

import AppKit
import Foundation
import Observation

/// Parses user-typed hex colors: `#333`, `333333`, `#FF3030`, `#FF3030CC`.
enum HexColor {

    /// Returns `#RRGGBB` / `#RRGGBBAA` uppercase, or `nil` if the input is not a hex color.
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy(\.isHexDigit) else { return nil }
        switch s.count {
        case 3, 4: s = s.map { "\($0)\($0)" }.joined()
        case 6, 8: break
        default: return nil
        }
        return "#" + s.uppercased()
    }

    static func color(_ input: String) -> NSColor? {
        guard let hex = normalize(input) else { return nil }
        let digits = Array(hex.dropFirst())
        func byte(_ i: Int) -> CGFloat {
            CGFloat(Int(String(digits[i..<i + 2]), radix: 16) ?? 0) / 255
        }
        let alpha: CGFloat = digits.count == 8 ? byte(6) : 1
        return NSColor(srgbRed: byte(0), green: byte(2), blue: byte(4), alpha: alpha)
    }
}

/// How a new day's Daily Sticky starts (§7.2).
enum DailyStartBehavior: String, CaseIterable, Identifiable, Sendable {
    case ask
    case scratch
    case carryForwardHeaders
    case defaultHeaders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Ask each day"
        case .scratch: return "Start from scratch"
        case .carryForwardHeaders: return "Carry forward yesterday's headers"
        case .defaultHeaders: return "Use default headers"
        }
    }

    var detail: String {
        switch self {
        case .ask: return "A small prompt when the first Daily Sticky of the day opens."
        case .scratch: return "Just today's date, then an empty page."
        case .carryForwardHeaders: return "Copies the headings from your last Daily Sticky. Nothing under them."
        case .defaultHeaders: return "Starts every day with the same headings."
        }
    }
}

@Observable
final class AppSettings {

    private enum Keys {
        static let dailyStartBehavior = "petekm.dailyStartBehavior"
        static let defaultHeaders = "petekm.defaultHeaders"
        static let showDateHeading = "petekm.showDateHeading"
        static let globalShortcut = "petekm.globalShortcut"
        static let hasCompletedOnboarding = "petekm.hasCompletedOnboarding"
        /// Template fingerprint the "agent files out of date" notice was last shown for (§6.5).
        static let agentFilesNoticeShownFor = "petekm.agentFilesNoticeShownFor"
        static let editorFontName = "petekm.editorFontName"
        static let editorFontSize = "petekm.editorFontSize"
        static let editorLineSpacing = "petekm.editorLineSpacing"
        static let showTableOfContents = "petekm.showTableOfContents"
        static let autoClosePairs = "petekm.autoClosePairs"
        static let continueListMarkers = "petekm.continueListMarkers"
        static let floatOnTop = "petekm.floatOnTop"
        static let hideDockIcon = "petekm.hideDockIcon"
        static let hideMenuBarItem = "petekm.hideMenuBarItem"
        static let automaticUpdateChecks = "petekm.automaticUpdateChecks"
        static let backgroundHex = "petekm.backgroundHex"
        static let backgroundOpacity = "petekm.backgroundOpacity"
        static let textHex = "petekm.textHex"
        static let scratchVisible = "petekm.scratchVisible"
        static let scratchHeight = "petekm.scratchHeight"
        static let syncAutomatically = "petekm.syncAutomatically"
    }

    /// Opacity floor: the window must stay findable.
    static let backgroundOpacityRange: ClosedRange<Double> = 0.1...1.0

    static let scratchHeightRange: ClosedRange<Double> = 60...600

    static let suggestedShortcut = KeyCombo.suggested

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailyStartBehavior = DailyStartBehavior(
            rawValue: defaults.string(forKey: Keys.dailyStartBehavior) ?? ""
        ) ?? .ask
        defaultHeaders = defaults.string(forKey: Keys.defaultHeaders) ?? AppSettings.starterHeaders
        showDateHeading = defaults.object(forKey: Keys.showDateHeading) as? Bool ?? true
        globalShortcut = defaults.string(forKey: Keys.globalShortcut).flatMap(KeyCombo.init(storageValue:))
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        agentFilesNoticeShownFor = defaults.string(forKey: Keys.agentFilesNoticeShownFor)
        editorFontName = defaults.string(forKey: Keys.editorFontName)
        editorFontSize = defaults.object(forKey: Keys.editorFontSize) as? Double ?? 13
        automaticUpdateChecks = defaults.object(forKey: Keys.automaticUpdateChecks) as? Bool ?? true
        editorLineSpacing = defaults.object(forKey: Keys.editorLineSpacing) as? Double ?? 4
        showTableOfContents = defaults.object(forKey: Keys.showTableOfContents) as? Bool ?? false
        autoClosePairs = defaults.object(forKey: Keys.autoClosePairs) as? Bool ?? true
        continueListMarkers = defaults.object(forKey: Keys.continueListMarkers) as? Bool ?? true
        scratchVisible = defaults.object(forKey: Keys.scratchVisible) as? Bool ?? false
        _scratchHeight = AppSettings.clampScratchHeight(
            defaults.object(forKey: Keys.scratchHeight) as? Double ?? 160
        )
        syncAutomatically = defaults.object(forKey: Keys.syncAutomatically) as? Bool ?? true
        floatOnTop = defaults.object(forKey: Keys.floatOnTop) as? Bool ?? false
        hideDockIcon = defaults.object(forKey: Keys.hideDockIcon) as? Bool ?? false
        hideMenuBarItem = defaults.object(forKey: Keys.hideMenuBarItem) as? Bool ?? false
        _backgroundHex = defaults.string(forKey: Keys.backgroundHex).flatMap(HexColor.normalize)
        _textHex = defaults.string(forKey: Keys.textHex).flatMap(HexColor.normalize)
        _backgroundOpacity = AppSettings.clampOpacity(
            defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 1
        )
        if hideDockIcon { hideMenuBarItem = false }   // §8.7: both entry points may not be hidden
    }

    // MARK: - Window background

    /// Normalized `#RRGGBB` (or `#RRGGBBAA`). `nil` means the default window surface.
    /// Invalid input is dropped, not stored.
    var backgroundHex: String? {
        get { _backgroundHex }
        set {
            _backgroundHex = newValue.flatMap(HexColor.normalize)
            defaults.set(_backgroundHex, forKey: Keys.backgroundHex)
        }
    }
    private var _backgroundHex: String?

    /// Editor text color as `#RRGGBB`. `nil` means the system label color.
    var textHex: String? {
        get { _textHex }
        set {
            _textHex = newValue.flatMap(HexColor.normalize)
            defaults.set(_textHex, forKey: Keys.textHex)
        }
    }
    private var _textHex: String?

    var textColor: NSColor? { textHex.flatMap(HexColor.color) }

    /// 0.1…1.0; 1 is fully opaque. Out-of-range values are clamped.
    var backgroundOpacity: Double {
        get { _backgroundOpacity }
        set {
            _backgroundOpacity = AppSettings.clampOpacity(newValue)
            defaults.set(_backgroundOpacity, forKey: Keys.backgroundOpacity)
        }
    }
    private var _backgroundOpacity: Double

    /// Custom background color, if one is set. Opacity is applied by the caller.
    var backgroundColor: NSColor? {
        backgroundHex.flatMap(HexColor.color)
    }

    /// Whether the window's ground reads as dark, so an overlay knows which way to shift.
    /// A custom background color wins over the system appearance — a light window in Dark
    /// Mode still needs dark ink on it.
    func groundIsDark(systemIsDark: Bool) -> Bool {
        guard let color = backgroundColor?.usingColorSpace(.sRGB) else { return systemIsDark }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance < 0.5
    }

    /// Whether the Scratch pane is expanded. The pane's strip is always visible; this
    /// only decides whether the editor under it is showing.
    var scratchVisible: Bool {
        didSet { defaults.set(scratchVisible, forKey: Keys.scratchVisible) }
    }

    var scratchHeight: Double {
        get { _scratchHeight }
        set {
            _scratchHeight = AppSettings.clampScratchHeight(newValue)
            defaults.set(_scratchHeight, forKey: Keys.scratchHeight)
        }
    }
    private var _scratchHeight: Double

    static func clampScratchHeight(_ value: Double) -> Double {
        guard value.isFinite else { return scratchHeightRange.lowerBound }
        return min(max(value, scratchHeightRange.lowerBound), scratchHeightRange.upperBound)
    }

    private static func clampOpacity(_ value: Double) -> Double {
        min(max(value, backgroundOpacityRange.lowerBound), backgroundOpacityRange.upperBound)
    }

    var dailyStartBehavior: DailyStartBehavior {
        didSet { defaults.set(dailyStartBehavior.rawValue, forKey: Keys.dailyStartBehavior) }
    }

    /// Plain Markdown used when `dailyStartBehavior == .defaultHeaders` (§7.6).
    var defaultHeaders: String {
        didSet { defaults.set(defaultHeaders, forKey: Keys.defaultHeaders) }
    }

    /// Whether a new Daily Sticky opens with an H1 date heading (§7.5).
    var showDateHeading: Bool {
        didSet { defaults.set(showDateHeading, forKey: Keys.showDateHeading) }
    }

    /// None is pre-assigned (§8.2); nil means the user has not set one.
    var globalShortcut: KeyCombo? {
        didSet { defaults.set(globalShortcut?.storageValue, forKey: Keys.globalShortcut) }
    }

    var floatOnTop: Bool {
        didSet { defaults.set(floatOnTop, forKey: Keys.floatOnTop) }
    }

    /// Agent-style app with no Dock icon. Turning it on forces the menu-bar item back on (§8.7).
    var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: Keys.hideDockIcon)
            if hideDockIcon && hideMenuBarItem { hideMenuBarItem = false }
        }
    }

    /// Ignored while the Dock icon is hidden — at least one entry point stays visible (§8.7).
    var hideMenuBarItem: Bool {
        didSet {
            if hideMenuBarItem && hideDockIcon { hideMenuBarItem = false; return }
            defaults.set(hideMenuBarItem, forKey: Keys.hideMenuBarItem)
        }
    }

    var menuBarItemVisible: Bool { hideDockIcon || !hideMenuBarItem }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Template fingerprint the "agent files out of date" notice was last shown for (§6.5).
    var agentFilesNoticeShownFor: String? {
        didSet { defaults.set(agentFilesNoticeShownFor, forKey: Keys.agentFilesNoticeShownFor) }
    }

    // MARK: - Editor (§18.6)

    /// Font family for the editor. `nil` means the system font (§18.6).
    var editorFontName: String? {
        didSet { defaults.set(editorFontName, forKey: Keys.editorFontName) }
    }

    var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: Keys.editorFontSize) }
    }

    /// Background update checks (§20.2). Installing always needs consent.
    /// Sync v2 §4: sync with GitHub on its own. Only has an effect when the folder is
    /// a repository with a remote.
    var syncAutomatically: Bool {
        didSet { defaults.set(syncAutomatically, forKey: Keys.syncAutomatically) }
    }

    var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: Keys.automaticUpdateChecks) }
    }

    var editorLineSpacing: Double {
        didSet { defaults.set(editorLineSpacing, forKey: Keys.editorLineSpacing) }
    }

    /// The table of contents is collapsed by default (§9.4).
    var showTableOfContents: Bool {
        didSet { defaults.set(showTableOfContents, forKey: Keys.showTableOfContents) }
    }

    var autoClosePairs: Bool {
        didSet { defaults.set(autoClosePairs, forKey: Keys.autoClosePairs) }
    }

    var continueListMarkers: Bool {
        didSet { defaults.set(continueListMarkers, forKey: Keys.continueListMarkers) }
    }

    var editorStyle: MarkdownStyle {
        MarkdownStyle(fontSize: CGFloat(editorFontSize),
                      lineSpacing: CGFloat(editorLineSpacing),
                      fontName: editorFontName,
                      textColor: textColor)
    }

    /// Font sizes offered in Settings — a short list beats a stepper here.
    /// Scratch uses the editor's typography one step down — same family, same colors,
    /// visibly a smaller surface.
    var scratchEditorStyle: MarkdownStyle {
        MarkdownStyle(fontSize: CGFloat(max(editorFontSize - 1, 10)),
                      lineSpacing: CGFloat(max(editorLineSpacing - 1, 0)),
                      fontName: editorFontName,
                      textColor: textColor)
    }

    static let editorFontSizes: [Double] = [11, 12, 13, 14, 15, 16, 18, 20]

    static let starterHeaders = """
    ## Work

    ## Personal
    """
}
