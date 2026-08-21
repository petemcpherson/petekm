//
//  AppSettings.swift
//  PeteKM
//
//  User preferences (spec §18). No AI settings exist, now or later (§18.8).
//  The Settings *window* arrives in a later phase; these are the values
//  onboarding needs to record.
//

import Foundation
import Observation

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
        static let editorFontSize = "petekm.editorFontSize"
        static let editorLineSpacing = "petekm.editorLineSpacing"
        static let showTableOfContents = "petekm.showTableOfContents"
        static let autoClosePairs = "petekm.autoClosePairs"
        static let continueListMarkers = "petekm.continueListMarkers"
    }

    static let suggestedShortcut = "⌃⌥Space"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailyStartBehavior = DailyStartBehavior(
            rawValue: defaults.string(forKey: Keys.dailyStartBehavior) ?? ""
        ) ?? .ask
        defaultHeaders = defaults.string(forKey: Keys.defaultHeaders) ?? AppSettings.starterHeaders
        showDateHeading = defaults.object(forKey: Keys.showDateHeading) as? Bool ?? true
        globalShortcut = defaults.string(forKey: Keys.globalShortcut)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        editorFontSize = defaults.object(forKey: Keys.editorFontSize) as? Double ?? 13
        editorLineSpacing = defaults.object(forKey: Keys.editorLineSpacing) as? Double ?? 4
        showTableOfContents = defaults.object(forKey: Keys.showTableOfContents) as? Bool ?? false
        autoClosePairs = defaults.object(forKey: Keys.autoClosePairs) as? Bool ?? true
        continueListMarkers = defaults.object(forKey: Keys.continueListMarkers) as? Bool ?? true
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
    var globalShortcut: String? {
        didSet { defaults.set(globalShortcut, forKey: Keys.globalShortcut) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: - Editor (§18.6)

    var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: Keys.editorFontSize) }
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
        MarkdownStyle(fontSize: CGFloat(editorFontSize), lineSpacing: CGFloat(editorLineSpacing))
    }

    static let starterHeaders = """
    ## Work

    ## Personal
    """
}
