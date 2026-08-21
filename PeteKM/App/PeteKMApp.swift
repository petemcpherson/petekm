import SwiftUI

@main
struct PeteKMApp: App {
    // The sticky window is created and owned by the delegate so it can outlive being closed (§8.7).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(AppServices.shared.folderStore)
                .environment(AppServices.shared.settings)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { UpdateController.shared.checkForUpdates() }
                    .disabled(!UpdateController.shared.canCheckForUpdates)
            }
        }
    }
}
