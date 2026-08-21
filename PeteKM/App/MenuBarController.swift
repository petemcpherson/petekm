import AppKit

/// Status-bar item with the pixel-mark glyph and a deliberately small menu (§8.8, DESIGN §25).
@MainActor
final class MenuBarController: NSObject {

    var onOpenDailySticky: () -> Void = {}
    var onSearch: (() -> Void)?          // wired in Phase 5; nil disables the item
    var onRevealFolder: (() -> Void)?    // nil while no PeteKM folder is set
    var onSettings: () -> Void = {}

    private var statusItem: NSStatusItem?

    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = glyph()
            item.button?.image?.isTemplate = true
            item.button?.toolTip = "PeteKM"
            item.menu = buildMenu()
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    /// Rebuilds the menu so enable/disable state tracks what is actually available.
    func refresh() {
        statusItem?.menu = buildMenu()
    }

    private func glyph() -> NSImage? {
        let image = NSImage(named: "PixelMark")
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(item("Open Daily Sticky", #selector(openDailySticky), enabled: true))

        let search = item("Search All PeteKM…", #selector(search), enabled: onSearch != nil)
        menu.addItem(search)

        let reveal = item("Reveal PeteKM Folder in Finder", #selector(revealFolder), enabled: onRevealFolder != nil)
        menu.addItem(reveal)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), enabled: true))
        menu.addItem(.separator())
        menu.addItem(item("Quit PeteKM", #selector(quit), enabled: true))

        return menu
    }

    private func item(_ title: String, _ action: Selector, enabled: Bool) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
        menuItem.target = self
        menuItem.isEnabled = enabled
        return menuItem
    }

    @objc private func openDailySticky() { onOpenDailySticky() }
    @objc private func search() { onSearch?() }
    @objc private func revealFolder() { onRevealFolder?() }
    @objc private func openSettings() { onSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
