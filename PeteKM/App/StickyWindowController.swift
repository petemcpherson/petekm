import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted when the capture window is summoned — the editor refocuses and rechecks the date (§8.2, §7.7).
    static let peteKMDidSummon = Notification.Name("petekm.didSummon")

    /// Posted by the menu bar's **Search All PeteKM…** — opens the palette in search mode (§10.2).
    static let peteKMOpenSearch = Notification.Name("petekm.openSearch")

    /// Asks the app delegate to bring the capture window forward. Settings lives in its
    /// own window, so an action taken there has to summon the sticky to be seen.
    static let peteKMSummonWindow = Notification.Name("petekm.summonWindow")
}

/// Owns the single sticky capture window: it hides rather than closes, and remembers where it was (§8.6, §8.7).
@MainActor
final class StickyWindowController: NSObject, NSWindowDelegate {

    let window: NSWindow

    private static let frameAutosaveName = "PeteKMStickyWindow"

    init(content: some View) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "PeteKM"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // The content view paints the background (color + opacity settings); the window stays clear.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self

        // Restores size and position from the last summon; centers only on a genuinely first run.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    var isFrontmost: Bool {
        window.isVisible && !window.isMiniaturized && NSApp.isActive && window.isKeyWindow
    }

    /// Global shortcut behavior: showing when hidden, dismissing when already in front (§8.2).
    func toggle() {
        if isFrontmost { hide() } else { summon() }
    }

    func summon() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .peteKMDidSummon, object: nil)
    }

    func hide() {
        window.orderOut(nil)
        NSApp.hide(nil)                       // hand focus back to whatever the user was doing
    }

    func setFloatsOnTop(_ floats: Bool) {
        window.level = floats ? .floating : .normal
    }

    // Red close button and ⌘W hide the window; the app keeps running (§8.7).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        window.saveFrame(usingName: Self.frameAutosaveName)
    }

    func windowDidResize(_ notification: Notification) {
        window.saveFrame(usingName: Self.frameAutosaveName)
    }
}
