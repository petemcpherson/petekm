import AppKit
import Carbon.HIToolbox

/// Registers the configurable global show/hide shortcut with Carbon (§8.2).
///
/// Carbon's `RegisterEventHotKey` is still the only supported way to get a system-wide hotkey
/// without accessibility permissions, so it stays despite the age of the API.
@MainActor
final class GlobalHotKeyMonitor {

    static let shared = GlobalHotKeyMonitor()

    /// Fired on the main actor whenever the registered shortcut is pressed.
    var onFire: (() -> Void)?

    private(set) var registered: KeyCombo?

    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    /// Registers `combo`, replacing any previous registration. Returns false if the system refused it
    /// (usually because another app already owns that combination).
    @discardableResult
    func update(to combo: KeyCombo?) -> Bool {
        guard combo != registered else { return true }
        unregister()
        guard let combo else { return true }

        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x504B_4D31), id: 1)   // 'PKM1'
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.carbonModifiers,
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        registered = combo
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = nil
    }

    fileprivate func fire() {
        onFire?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), peteKMHotKeyHandler, 1, &spec, nil, &handler)
    }
}

/// C callback — no captures allowed, so it hops back to the shared monitor on the main actor.
private nonisolated func peteKMHotKeyHandler(_ callRef: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    Task { @MainActor in GlobalHotKeyMonitor.shared.fire() }
    return noErr
}
