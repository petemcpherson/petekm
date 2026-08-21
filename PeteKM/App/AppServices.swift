import Foundation

/// The long-lived stores. The app delegate owns the window, so these can't live as scene `@State`.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let folderStore = FolderStore()
    let settings = AppSettings()

    private init() {}
}
