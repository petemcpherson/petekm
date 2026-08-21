import AppKit
import Carbon.HIToolbox

/// A global shortcut: a key plus its modifiers (§8.2). Application state, stored in defaults.
struct KeyCombo: Equatable, Sendable {

    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, already narrowed to the device-independent set.
    var modifiers: UInt
    /// Display text for the key itself, captured when the shortcut was recorded ("Space", "K").
    var label: String

    static let suggested = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        label: "Space"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var displayString: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + label
    }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// A global shortcut needs a real modifier; ⇧ alone would swallow ordinary typing.
    var hasUsableModifiers: Bool {
        flags.contains(.control) || flags.contains(.option) || flags.contains(.command)
    }

    /// Warning text for shortcuts known to collide with common system bindings (§8.2).
    var systemConflictWarning: String? {
        let mods = flags.intersection([.command, .option, .control, .shift])
        switch (Int(keyCode), mods) {
        case (kVK_Space, [.command]):
            return "⌘Space is Spotlight."
        case (kVK_Space, [.control]):
            return "⌃Space switches input sources."
        case (kVK_Space, [.command, .option]):
            return "⌥⌘Space opens Finder search."
        case (kVK_Tab, _) where mods.contains(.command):
            return "⌘Tab switches apps."
        case (kVK_ANSI_Q, [.command]):
            return "⌘Q quits the front app."
        case (kVK_ANSI_W, [.command]):
            return "⌘W closes the front window."
        case (kVK_ANSI_H, [.command]):
            return "⌘H hides the front app."
        case (kVK_ANSI_M, [.command]):
            return "⌘M minimizes the front window."
        case (kVK_ANSI_Comma, [.command]):
            return "⌘, opens Settings in most apps."
        case (kVK_Escape, _) where mods.contains(.command):
            return "⌘⌥Esc is Force Quit."
        default:
            return nil
        }
    }

    // MARK: - Recording

    /// Builds a combo from a recorded key-down event, or nil if the event is not a usable shortcut.
    static func from(event: NSEvent) -> KeyCombo? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let combo = KeyCombo(
            keyCode: UInt32(event.keyCode),
            modifiers: mods.rawValue,
            label: label(for: Int(event.keyCode), characters: event.charactersIgnoringModifiers)
        )
        guard combo.hasUsableModifiers || isFunctionKey(Int(event.keyCode)) else { return nil }
        return combo
    }

    private static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    private static func label(for keyCode: Int, characters: String?) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let characters, let first = characters.first, !first.isWhitespace {
            return String(first).uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let namedKeys: [Int: String] = {
        var keys: [Int: String] = [
            kVK_Space: "Space",
            kVK_Return: "Return",
            kVK_Tab: "Tab",
            kVK_Escape: "Esc",
            kVK_Delete: "Delete",
            kVK_ForwardDelete: "Fwd Delete",
            kVK_Home: "Home",
            kVK_End: "End",
            kVK_PageUp: "Page Up",
            kVK_PageDown: "Page Down",
            kVK_LeftArrow: "←",
            kVK_RightArrow: "→",
            kVK_UpArrow: "↑",
            kVK_DownArrow: "↓",
        ]
        keys.merge(functionKeyNames) { current, _ in current }
        return keys
    }()

    // MARK: - Persistence

    /// `keyCode|modifiers|label` — compact and human-inspectable in defaults.
    var storageValue: String { "\(keyCode)|\(modifiers)|\(label)" }

    init(keyCode: UInt32, modifiers: UInt, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt(parts[1]),
              !parts[2].isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, label: String(parts[2]))
    }
}
