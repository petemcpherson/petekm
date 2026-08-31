import AppKit
import Observation
import SwiftUI

/// Background-resident lifecycle: one sticky window, one global shortcut, one menu-bar item (§8.7).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let services = AppServices.shared
    private let menuBar = MenuBarController()
    private var windowController: StickyWindowController?
    private var settingsKeyMonitor: Any?

    private var settings: AppSettings { services.settings }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = RootView()
            .environment(services.folderStore)
            .environment(services.settings)
            .environment(services.syncLaunchCheck)

        let controller = StickyWindowController(content: root)
        windowController = controller

        GlobalHotKeyMonitor.shared.onFire = { [weak self] in self?.windowController?.toggle() }

        menuBar.onOpenDailySticky = { [weak self] in self?.windowController?.summon() }
        menuBar.onSettings = { [weak self] in self?.openSettings() }
        menuBar.onRevealFolder = { [weak self] in self?.revealFolder() }

        observeSettings()
        observeFolder()
        observeSettingsShortcut()
        UpdateController.shared.apply(settings: settings)

        controller.summon()
    }

    // The app is a capture tool, not a document app: closing the window leaves it running (§8.7).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        windowController?.summon()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyMonitor.shared.unregister()
        if let settingsKeyMonitor { NSEvent.removeMonitor(settingsKeyMonitor) }
    }

    // MARK: - Settings application

    private func observeSettings() {
        withObservationTracking {
            _ = settings.globalShortcut
            _ = settings.floatOnTop
            _ = settings.hideDockIcon
            _ = settings.hideMenuBarItem
        } onChange: {
            Task { @MainActor [weak self] in
                self?.applySettings()
                self?.observeSettings()
            }
        }
        applySettings()
    }

    private func observeFolder() {
        withObservationTracking {
            _ = services.folderStore.state
        } onChange: {
            Task { @MainActor [weak self] in
                self?.updateMenuBarActions()
                self?.observeFolder()
            }
        }
        updateMenuBarActions()
    }

    private func applySettings() {
        GlobalHotKeyMonitor.shared.update(to: settings.globalShortcut)
        windowController?.setFloatsOnTop(settings.floatOnTop)
        NSApp.setActivationPolicy(settings.hideDockIcon ? .accessory : .regular)
        menuBar.setVisible(settings.menuBarItemVisible)
    }

    private func updateMenuBarActions() {
        let hasFolder = services.folderStore.folder != nil
        menuBar.onRevealFolder = hasFolder ? { [weak self] in self?.revealFolder() } : nil
        menuBar.onSearch = hasFolder ? { [weak self] in self?.openSearch() } : nil
        menuBar.refresh()
    }

    // MARK: - Actions

    private func openSearch() {
        windowController?.summon()
        NotificationCenter.default.post(name: .peteKMOpenSearch, object: nil)
    }

    private func revealFolder() {
        guard let folder = services.folderStore.folder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder.root])
    }

    /// The Settings menu item carries ⌘. (PeteKMApp); ⌘, is kept alive here so the
    /// standard macOS preferences key still works.
    private func observeSettingsShortcut() {
        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == ","
            else { return event }
            self?.openSettings()
            return nil
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
