import Foundation

/// The long-lived stores. The app delegate owns the window, so these can't live as scene `@State`.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let folderStore: FolderStore
    let settings: AppSettings

    /// Once-per-process "Changes to sync." check (sync spec §4.3).
    let syncLaunchCheck = SyncLaunchCheck()

    let autoSync: AutoSync

    /// UI tests set this to a scratch folder so the capture loop can be driven
    /// without onboarding and without touching the real PeteKM folder.
    static let uiTestFolderKey = "PETEKM_UITEST_FOLDER"

    private init() {
        if let path = ProcessInfo.processInfo.environment[AppServices.uiTestFolderKey], !path.isEmpty {
            let defaults = UserDefaults(suiteName: "petekm.uitest.\(UUID().uuidString)") ?? .standard
            folderStore = FolderStore(defaults: defaults)
            settings = AppSettings(defaults: defaults)

            let url = URL(filePath: path, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            folderStore.setFolder(url)
            if let folder = folderStore.folder {
                try? FolderInitializer.initialize(folder)
            }
            settings.dailyStartBehavior = .scratch   // no first-open prompt in the loop test
            settings.hasCompletedOnboarding = true
        } else {
            folderStore = FolderStore()
            settings = AppSettings()
        }
        autoSync = AutoSync(settings: settings)
    }
}
