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

    static let starterHeaders = """
    ## Work

    ## Personal
    """
}
