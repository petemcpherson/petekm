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
        observeSummonRequests()
        UpdateController.shared.apply(settings: settings)

        controller.summon()
    }

    // The app is a capture tool, not a document app: closing the window leaves it running (§8.7).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌘Q from the keyboard hides instead of quitting, so the global shortcut keeps working.
    /// Every other path still quits: Quit chosen with the mouse (app menu or menu-bar item),
    /// logout/shutdown, and Sparkle relaunching for an update.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let event = NSApp.currentEvent,
              event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers?.lowercased() == "q"
        else { return .terminateNow }
        windowController?.hide()
        return .terminateCancel
    }

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

    private func observeSummonRequests() {
        NotificationCenter.default.addObserver(
            forName: .peteKMSummonWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowController?.summon() }
        }
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
