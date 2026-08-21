import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import PeteKM

// MARK: - KeyCombo

@Test func suggestedShortcutDisplaysAsControlOptionSpace() {
    #expect(KeyCombo.suggested.displayString == "⌃⌥Space")
}

@Test func comboRoundTripsThroughStorage() {
    let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                         modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue,
                         label: "K")

    #expect(KeyCombo(storageValue: combo.storageValue) == combo)
    #expect(KeyCombo(storageValue: "nonsense") == nil)
}

@Test func carbonModifiersMatchFlags() {
    let combo = KeyCombo(keyCode: UInt32(kVK_Space),
                         modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
                         label: "Space")

    #expect(combo.carbonModifiers == UInt32(controlKey) | UInt32(optionKey))
}

@Test func knownSystemShortcutsWarn() {
    let spotlight = KeyCombo(keyCode: UInt32(kVK_Space),
                             modifiers: NSEvent.ModifierFlags.command.rawValue,
                             label: "Space")
    #expect(spotlight.systemConflictWarning != nil)
    #expect(KeyCombo.suggested.systemConflictWarning == nil)
}

@Test func shortcutsNeedARealModifier() {
    let shiftOnly = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                             modifiers: NSEvent.ModifierFlags.shift.rawValue,
                             label: "K")

    #expect(!shiftOnly.hasUsableModifiers)
    #expect(KeyCombo.suggested.hasUsableModifiers)
}

// MARK: - Entry-point visibility (§8.7)

private func freshSettings() -> AppSettings {
    let suite = "petekm.tests.\(UUID().uuidString)"
    return AppSettings(defaults: UserDefaults(suiteName: suite)!)
}

@Test func hidingDockIconForcesMenuBarItemBack() {
    let settings = freshSettings()
    settings.hideMenuBarItem = true
    #expect(settings.menuBarItemVisible == false)

    settings.hideDockIcon = true

    #expect(settings.hideMenuBarItem == false)
    #expect(settings.menuBarItemVisible)
}

@Test func menuBarItemCannotBeHiddenWhileDockIconIs() {
    let settings = freshSettings()
    settings.hideDockIcon = true

    settings.hideMenuBarItem = true

    #expect(settings.hideMenuBarItem == false)
    #expect(settings.menuBarItemVisible)
}

@Test func shortcutSurvivesReload() {
    let suite = "petekm.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)

    settings.globalShortcut = KeyCombo.suggested

    #expect(AppSettings(defaults: defaults).globalShortcut == KeyCombo.suggested)
}
